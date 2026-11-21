// =============================================================================
// File: eth10g_crc32.v
// Module: eth10g_crc32
// Project: 10 Gigabit Ethernet (10GbE) MAC Subsystem & 10GBASE-R PCS ASIC
// Description: Parallel 64-bit IEEE 802.3 Ethernet FCS CRC-32 calculation engine.
//              Polynomial: G(X) = X^32 + X^26 + X^23 + X^22 + X^16 + X^12 +
//                                 X^11 + X^10 + X^8 + X^7 + X^5 + X^4 + X^2 + X + 1
// =============================================================================

`timescale 1ns / 1ps

module eth10g_crc32 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        init,
    input  wire        en,
    input  wire [63:0] data_in,
    input  wire [7:0]  keep,      // Byte enable mask for partial end words
    output wire [31:0] crc_out
);

    reg [31:0] crc_reg;

    // Single-byte CRC-32 update function
    function [31:0] step_crc8(input [31:0] cur, input [7:0] d);
        integer i;
        reg [31:0] c;
        reg fb;
        begin
            c = cur;
            for (i = 0; i < 8; i = i + 1) begin
                fb = c[31] ^ d[i];
                c = {c[30:0], 1'b0};
                if (fb) begin
                    c = c ^ 32'h04C11DB7;
                end
            end
            step_crc8 = c;
        end
    endfunction

    // 64-bit CRC update with keep mask
    function [31:0] step_crc64(input [31:0] cur, input [63:0] d, input [7:0] k);
        integer b;
        reg [31:0] c;
        begin
            c = cur;
            for (b = 0; b < 8; b = b + 1) begin
                if (k[b]) begin
                    c = step_crc8(c, d[b*8 +: 8]);
                end
            end
            step_crc64 = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= 32'hFFFFFFFF;
        end else begin
            if (init) begin
                crc_reg <= 32'hFFFFFFFF;
            end else if (en) begin
                crc_reg <= step_crc64(crc_reg, data_in, keep);
            end
        end
    end

    // Inverted final CRC result
    assign crc_out = ~crc_reg;

endmodule
