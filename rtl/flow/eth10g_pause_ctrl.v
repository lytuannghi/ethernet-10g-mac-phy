// =============================================================================
// File: eth10g_pause_ctrl.v
// Module: eth10g_pause_ctrl
// Project: 10 Gigabit Ethernet (10GbE) MAC Subsystem & 10GBASE-R PCS ASIC
// Description: IEEE 802.3x MAC Flow Control & Priority-Based Flow Control (PFC)
//              - Transmits Standard Pause Frames (EtherType 0x8808, Opcode 0x0001)
//              - Decrements Pause Quanta timer upon reception of Pause frames
// =============================================================================

`timescale 1ns / 1ps

module eth10g_pause_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Flow Control Triggers from Local Buffer Watermark
    input  wire        pause_req,
    input  wire [15:0] pause_quanta_in,

    // TX Flow Inhibit Signal to TX MAC
    output reg         tx_pause_active,

    // Pause Frame Generator Interface
    output reg         send_pause_frame,
    output wire [47:0] pause_dest_mac,
    output wire [15:0] pause_opcode,
    output reg  [15:0] pause_quanta_out,
    input  wire        pause_frame_done,

    // Pause Frame Receiver Interface (from RX MAC parser)
    input  wire        rx_pause_valid,
    input  wire [15:0] rx_pause_quanta
);

    // Reserved Multicast Destination MAC: 01:80:C2:00:00:01
    assign pause_dest_mac = 48'h0180C2000001;
    assign pause_opcode   = 16'h0001; // Standard PAUSE

    // TX Inhibit Timer (1 quantum = 512 bit times @ 10 Gbps = 8 cycles of 64-bit @ 156.25 MHz)
    reg [15:0] quanta_timer;
    reg [2:0]  cycle_in_quantum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            quanta_timer     <= 16'd0;
            cycle_in_quantum <= 3'd0;
            tx_pause_active  <= 1'b0;
        end else begin
            if (rx_pause_valid) begin
                quanta_timer     <= rx_pause_quanta;
                cycle_in_quantum <= 3'd0;
                tx_pause_active  <= (rx_pause_quanta > 0);
            end else if (quanta_timer > 0) begin
                tx_pause_active <= 1'b1;
                cycle_in_quantum <= cycle_in_quantum + 3'd1;
                if (cycle_in_quantum == 3'd7) begin
                    quanta_timer <= quanta_timer - 16'd1;
                end
            end else begin
                tx_pause_active <= 1'b0;
            end
        end
    end

    // Pause Frame Transmission Strobe
    reg pause_req_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pause_req_d      <= 1'b0;
            send_pause_frame <= 1'b0;
            pause_quanta_out <= 16'd0;
        end else begin
            pause_req_d <= pause_req;
            if (pause_req && !pause_req_d) begin
                send_pause_frame <= 1'b1;
                pause_quanta_out <= pause_quanta_in;
            end else if (pause_frame_done) begin
                send_pause_frame <= 1'b0;
            end
        end
    end

endmodule
