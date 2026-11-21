// =============================================================================
// File: eth10g_pcs_64b66b.v
// Module: eth10g_pcs_64b66b
// Project: 10 Gigabit Ethernet (10GbE) MAC Subsystem & 10GBASE-R PCS ASIC
// Description: 10GBASE-R Physical Coding Sublayer (PCS) conforming to
//              IEEE 802.3 Clause 49:
//              - 64b/66b Block Encoder with 2-bit Sync Header (01: Data, 10: Control)
//              - Self-synchronizing Scrambler & Descrambler: 1 + X^39 + X^58
//              - 64b/66b Block Decoder
// =============================================================================

`timescale 1ns / 1ps

module eth10g_pcs_64b66b (
    input  wire        clk,
    input  wire        rst_n,

    // TX XGMII Interface from MAC
    input  wire [63:0] xgmii_txd,
    input  wire [7:0]  xgmii_txc,

    // TX Encoded 66-bit Block to PMA/SerDes
    output reg  [65:0] pcs_tx_block,
    output reg         pcs_tx_valid,

    // RX Encoded 66-bit Block from PMA/SerDes
    input  wire [65:0] pcs_rx_block,
    input  wire        pcs_rx_valid,

    // RX XGMII Interface to MAC
    output reg  [63:0] xgmii_rxd,
    output reg  [7:0]  xgmii_rxc
);

    // 10GBASE-R Block Type Codes
    localparam BLOCK_CTRL_ALL = 8'h1E; // /C/ /C/ /C/ /C/ /C/ /C/ /C/ /C/ (Idle)
    localparam BLOCK_START_0  = 8'h78; // /S/ D1 D2 D3 D4 D5 D6 D7 (Start on Lane 0)
    localparam BLOCK_TERM_4   = 8'hB4; // D0 D1 D2 D3 /T/ /C/ /C/ /C/ (Terminate on Lane 4)

    // 58-bit Scrambler LFSR
    reg [57:0] scrambler_lfsr;
    reg [57:0] descrambler_lfsr;

    // Parallel 64-bit Scrambler: G(X) = 1 + X^39 + X^58
    function [121:0] scramble_64b(input [57:0] state, input [63:0] data_in);
        integer i;
        reg [57:0] cur;
        reg [63:0] out_d;
        reg fb;
        begin
            cur = state;
            for (i = 0; i < 64; i = i + 1) begin
                fb = data_in[i] ^ cur[38] ^ cur[57];
                out_d[i] = fb;
                cur = {cur[56:0], fb};
            end
            scramble_64b = {cur, out_d};
        end
    endfunction

    // Parallel 64-bit Descrambler: G(X) = 1 + X^39 + X^58
    function [121:0] descramble_64b(input [57:0] state, input [63:0] data_in);
        integer i;
        reg [57:0] cur;
        reg [63:0] out_d;
        reg bit_out;
        begin
            cur = state;
            for (i = 0; i < 64; i = i + 1) begin
                bit_out = data_in[i] ^ cur[38] ^ cur[57];
                out_d[i] = bit_out;
                cur = {cur[56:0], data_in[i]};
            end
            descramble_64b = {cur, out_d};
        end
    endfunction

    // 64b/66b TX Encoder & Scrambler
    reg [1:0]   sync_header;
    reg [63:0]  block_payload;
    reg [121:0] scram_res;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scrambler_lfsr <= 58'h3FFFFFFFFFFFFFF;
            pcs_tx_block   <= 66'd0;
            pcs_tx_valid   <= 1'b0;
        end else begin
            pcs_tx_valid <= 1'b1;

            if (xgmii_txc == 8'b00000000) begin
                // All Data: Sync Header = 2'b01
                sync_header   = 2'b01;
                block_payload = xgmii_txd;
            end else if (xgmii_txc[0] && xgmii_txd[7:0] == 8'hFB) begin
                // Start of Packet: Sync Header = 2'b10, Block Type = 0x78
                sync_header   = 2'b10;
                block_payload = {xgmii_txd[63:8], BLOCK_START_0};
            end else if (xgmii_txc[4] && xgmii_txd[39:32] == 8'hFD) begin
                // Terminate on lane 4: Sync Header = 2'b10, Block Type = 0xB4
                sync_header   = 2'b10;
                block_payload = {24'h000000, BLOCK_TERM_4, xgmii_txd[31:0]};
            end else begin
                // All Control / Idle: Sync Header = 2'b10, Block Type = 0x1E
                sync_header   = 2'b10;
                block_payload = {56'h00000000000000, BLOCK_CTRL_ALL};
            end

            scram_res = scramble_64b(scrambler_lfsr, block_payload);
            scrambler_lfsr <= scram_res[121:64];

            // 66-bit block: {Scrambled Data[63:0], Sync[1:0]}
            pcs_tx_block <= {scram_res[63:0], sync_header};
        end
    end

    // 64b/66b RX Descrambler & Decoder
    reg [121:0] descram_res;
    reg [63:0]  recov_payload;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            descrambler_lfsr <= 58'h3FFFFFFFFFFFFFF;
            xgmii_rxd        <= {8{8'h07}}; // Idle
            xgmii_rxc        <= 8'hFF;
        end else begin
            if (pcs_rx_valid) begin
                // Descramble the 64-bit payload
                descram_res = descramble_64b(descrambler_lfsr, pcs_rx_block[65:2]);
                descrambler_lfsr <= descram_res[121:64];
                recov_payload = descram_res[63:0];

                if (pcs_rx_block[1:0] == 2'b01) begin
                    // Data Block
                    xgmii_rxd <= recov_payload;
                    xgmii_rxc <= 8'h00;
                end else if (pcs_rx_block[1:0] == 2'b10) begin
                    // Control Block: examine recovered block type code
                    if (recov_payload[7:0] == BLOCK_START_0) begin
                        xgmii_rxd <= {recov_payload[63:8], 8'hFB};
                        xgmii_rxc <= 8'h01;
                    end else if (recov_payload[39:32] == BLOCK_TERM_4) begin
                        xgmii_rxd <= {24'h070707, 8'hFD, recov_payload[31:0]};
                        xgmii_rxc <= 8'hF0;
                    end else begin
                        xgmii_rxd <= {8{8'h07}}; // Idle
                        xgmii_rxc <= 8'hFF;
                    end
                end else begin
                    // Invalid Sync Header
                    xgmii_rxd <= {8{8'hFE}}; // Error
                    xgmii_rxc <= 8'hFF;
                end
            end
        end
    end

endmodule
