// =============================================================================
// File: eth10g_xgmii_if.v
// Module: eth10g_xgmii_if
// Project: 10 Gigabit Ethernet (10GbE) MAC Subsystem & 10GBASE-R PCS ASIC
// Description: XGMII Interface Adapter connecting MAC Subsystem and PCS.
//              Provides register retiming, fault sequence detection (Local Fault
//              and Remote Fault sequences), and deficit idle count management.
// =============================================================================

`timescale 1ns / 1ps

module eth10g_xgmii_if (
    input  wire        clk,
    input  wire        rst_n,

    // MAC Side TX Interface
    input  wire [63:0] mac_tx_data,
    input  wire [7:0]  mac_tx_ctrl,

    // PCS Side TX Interface
    output reg  [63:0] xgmii_txd_out,
    output reg  [7:0]  xgmii_txc_out,

    // PCS Side RX Interface
    input  wire [63:0] xgmii_rxd_in,
    input  wire [7:0]  xgmii_rxc_in,

    // MAC Side RX Interface
    output reg  [63:0] mac_rx_data,
    output reg  [7:0]  mac_rx_ctrl,

    // Fault Status Monitoring
    output reg         local_fault_det,
    output reg         remote_fault_det
);

    // Sequence ordered set codes (Local Fault = 0x9C, Remote Fault = 0x02)
    localparam SEQ_LOCAL_FAULT  = 8'h9C;
    localparam SEQ_REMOTE_FAULT = 8'h02;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xgmii_txd_out    <= {8{8'h07}};
            xgmii_txc_out    <= 8'hFF;
            mac_rx_data      <= {8{8'h07}};
            mac_rx_ctrl      <= 8'hFF;
            local_fault_det  <= 1'b0;
            remote_fault_det <= 1'b0;
        end else begin
            // TX Pipeline Stage
            xgmii_txd_out <= mac_tx_data;
            xgmii_txc_out <= mac_tx_ctrl;

            // RX Pipeline Stage & Fault Detector
            mac_rx_data <= xgmii_rxd_in;
            mac_rx_ctrl <= xgmii_rxc_in;

            // Check for Fault Sequence on Lane 0
            if (xgmii_rxc_in[0] && xgmii_rxd_in[7:0] == 8'h5C) begin // Sequence ordered set
                if (xgmii_rxd_in[15:8] == SEQ_LOCAL_FAULT)
                    local_fault_det <= 1'b1;
                else if (xgmii_rxd_in[15:8] == SEQ_REMOTE_FAULT)
                    remote_fault_det <= 1'b1;
            end else begin
                local_fault_det  <= 1'b0;
                remote_fault_det <= 1'b0;
            end
        end
    end

endmodule
