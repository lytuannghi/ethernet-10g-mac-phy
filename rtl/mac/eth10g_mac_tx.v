// =============================================================================
// File: eth10g_mac_tx.v
// Module: eth10g_mac_tx
// Project: 10 Gigabit Ethernet (10GbE) MAC Subsystem & 10GBASE-R PCS ASIC
// Description: 64-bit Transmit MAC Engine operating at 156.25 MHz line clock.
//              - Preamble (0x55) & SFD (0xD5) insertion
//              - Parallel CRC-32 calculation & FCS append
//              - Minimum 96-bit (12-byte) Inter-Packet Gap (IPG) enforcement
//              - XGMII framing: /S/ (0xFB) Start, /T/ (0xFD) Terminate, /I/ (0x07) Idle
// =============================================================================

`timescale 1ns / 1ps

module eth10g_mac_tx (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Stream Transmit Interface from User Logic / DMA
    input  wire [63:0] tx_axis_tdata,
    input  wire [7:0]  tx_axis_tkeep,
    input  wire        tx_axis_tvalid,
    input  wire        tx_axis_tlast,
    output reg         tx_axis_tready,

    // Flow Control Inhibit & PAUSE Frame Generation Interface
    input  wire        tx_pause_inhibit,
    input  wire        send_pause_frame,
    input  wire [47:0] pause_dest_mac,
    input  wire [15:0] pause_opcode,
    input  wire [15:0] pause_quanta,
    output reg         pause_frame_done,

    // XGMII Physical Interface to PCS
    output reg  [63:0] xgmii_txd,
    output reg  [7:0]  xgmii_txc
);

    // XGMII Control Characters
    localparam C_IDLE  = 8'h07;
    localparam C_START = 8'hFB; // /S/ Start character
    localparam C_TERM  = 8'hFD; // /T/ Terminate character

    // 8-byte Preamble + SFD: 7 bytes 0x55 + 1 byte 0xD5
    localparam [63:0] PREAMBLE_SFD = 64'hD555555555555555;

    // FSM States
    localparam S_IDLE     = 3'd0;
    localparam S_PREAMBLE = 3'd1;
    localparam S_PAYLOAD  = 3'd2;
    localparam S_FCS      = 3'd3;
    localparam S_PAUSE_1  = 3'd4;
    localparam S_IPG      = 3'd5;
    localparam S_PAUSE_2  = 3'd6;

    reg [2:0] state;
    reg [1:0] ipg_counter;

    // CRC-32 Engine
    reg        crc_init;
    reg        crc_en;
    reg [63:0] crc_data;
    reg [7:0]  crc_keep;
    wire [31:0] crc_out;

    eth10g_crc32 u_crc (
        .clk     (clk),
        .rst_n   (rst_n),
        .init    (crc_init),
        .en      (crc_en),
        .data_in (crc_data),
        .keep    (crc_keep),
        .crc_out (crc_out)
    );

    reg [63:0] last_tdata;
    reg [7:0]  last_tkeep;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            tx_axis_tready   <= 1'b0;
            xgmii_txd        <= {8{C_IDLE}};
            xgmii_txc        <= 8'hFF; // All 8 bytes are control Idle
            crc_init         <= 1'b1;
            crc_en           <= 1'b0;
            crc_data         <= 64'd0;
            crc_keep         <= 8'd0;
            ipg_counter      <= 2'd0;
            last_tdata       <= 64'd0;
            last_tkeep       <= 8'd0;
            pause_frame_done <= 1'b0;
        end else begin
            crc_init         <= 1'b0;
            crc_en           <= 1'b0;
            pause_frame_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    xgmii_txd <= {8{C_IDLE}};
                    xgmii_txc <= 8'hFF;
                    if (tx_axis_tvalid && !tx_pause_inhibit) begin
                        // Transmit /S/ on lane 0, followed by 7 bytes preamble
                        xgmii_txd      <= {56'h55555555555555, C_START};
                        xgmii_txc      <= 8'h01; // Lane 0 is control /S/, Lanes 1..7 are data
                        crc_init       <= 1'b1;
                        tx_axis_tready <= 1'b1;
                        state          <= S_PREAMBLE;
                    end else if (send_pause_frame) begin
                        // Transmit IEEE 802.3x PAUSE /S/ + Preamble
                        xgmii_txd      <= {56'h55555555555555, C_START};
                        xgmii_txc      <= 8'h01;
                        crc_init       <= 1'b1;
                        tx_axis_tready <= 1'b0;
                        state          <= S_PAUSE_1;
                    end else begin
                        tx_axis_tready <= 1'b0;
                    end
                end

                S_PAUSE_1: begin
                    // SFD (0xD5) + 6-byte Reserved Multicast MAC (01:80:C2:00:00:01) + Src MAC byte 0
                    xgmii_txd <= {8'h00, pause_dest_mac, 8'hD5};
                    xgmii_txc <= 8'h00;
                    crc_en    <= 1'b1;
                    crc_data  <= {8'h00, pause_dest_mac, 8'hD5};
                    crc_keep  <= 8'hFF;
                    state     <= S_PAUSE_2;
                end

                S_PAUSE_2: begin
                    // EtherType 0x8808 at [31:16], Opcode 0x0001 at [47:32], Pause Quanta at [63:48]
                    xgmii_txd        <= {pause_quanta, pause_opcode, 16'h8808, 16'h0000};
                    xgmii_txc        <= 8'h00;
                    crc_en           <= 1'b1;
                    crc_data         <= {pause_quanta, pause_opcode, 16'h8808, 16'h0000};
                    crc_keep         <= 8'hFF;
                    pause_frame_done <= 1'b1;
                    state            <= S_FCS;
                end

                S_PREAMBLE: begin
                    // Emit 1 byte SFD (0xD5) + first 7 bytes of payload
                    if (tx_axis_tvalid) begin
                        xgmii_txd  <= {tx_axis_tdata[55:0], 8'hD5};
                        xgmii_txc  <= 8'h00;
                        crc_en     <= 1'b1;
                        crc_data   <= tx_axis_tdata;
                        crc_keep   <= tx_axis_tkeep;
                        last_tdata <= tx_axis_tdata;
                        last_tkeep <= tx_axis_tkeep;

                        if (tx_axis_tlast) begin
                            tx_axis_tready <= 1'b0;
                            state          <= S_FCS;
                        end else begin
                            state <= S_PAYLOAD;
                        end
                    end
                end

                S_PAYLOAD: begin
                    if (tx_axis_tvalid) begin
                        xgmii_txd  <= tx_axis_tdata;
                        xgmii_txc  <= 8'h00;
                        crc_en     <= 1'b1;
                        crc_data   <= tx_axis_tdata;
                        crc_keep   <= tx_axis_tkeep;
                        last_tdata <= tx_axis_tdata;
                        last_tkeep <= tx_axis_tkeep;

                        if (tx_axis_tlast) begin
                            tx_axis_tready <= 1'b0;
                            state          <= S_FCS;
                        end
                    end else begin
                        // Underrun bubble
                        xgmii_txd <= {8{C_IDLE}};
                        xgmii_txc <= 8'hFF;
                    end
                end

                S_FCS: begin
                    // Emit 32-bit CRC-32 (FCS) followed by /T/ Terminate and Idle
                    xgmii_txd <= {{3{C_IDLE}}, C_TERM, crc_out};
                    xgmii_txc <= 8'hF0; // Upper 4 bytes are control (/T/, /I/), Lower 4 bytes are FCS
                    state     <= S_IPG;
                    ipg_counter <= 2'd0;
                end

                S_IPG: begin
                    // Transmit Idle (IPG enforcement)
                    xgmii_txd <= {8{C_IDLE}};
                    xgmii_txc <= 8'hFF;
                    ipg_counter <= ipg_counter + 2'd1;
                    if (ipg_counter == 2'd2) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
