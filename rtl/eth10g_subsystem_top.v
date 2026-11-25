// =============================================================================
// File: eth10g_subsystem_top.v
// Module: eth10g_subsystem_top
// Project: 10 Gigabit Ethernet (10GbE) MAC Subsystem & 10GBASE-R PCS ASIC
// Description: Full-Flow Synthesizable Top-Level ASIC Subsystem integrating:
//              - 64-bit IEEE 802.3ae 10GbE Transmit MAC with Preamble/SFD/FCS
//              - 64-bit Receive MAC with real-time FCS validation & parsing
//              - IEEE 802.3x PAUSE Flow Control & Priority-Based Flow Control (PFC)
//              - XGMII Retiming & Fault Sequence Monitoring Interface
//              - 10GBASE-R Clause 49 64b/66b Block Encoder/Decoder & PRBS-58 Scrambler
// =============================================================================

`timescale 1ns / 1ps

module eth10g_subsystem_top (
    input  wire        clk,             // 156.25 MHz System Line Clock
    input  wire        rst_n,

    // AXI4-Stream Transmit Interface from System / DMA
    input  wire [63:0] tx_axis_tdata,
    input  wire [7:0]  tx_axis_tkeep,
    input  wire        tx_axis_tvalid,
    input  wire        tx_axis_tlast,
    output wire        tx_axis_tready,

    // AXI4-Stream Receive Interface to System / DMA
    output wire [63:0] rx_axis_tdata,
    output wire [7:0]  rx_axis_tkeep,
    output wire        rx_axis_tvalid,
    output wire        rx_axis_tlast,
    output wire        rx_axis_tuser,

    // Flow Control Hardware Triggers
    input  wire        pause_req,
    input  wire [15:0] pause_quanta_in,
    output wire        tx_pause_active,

    // Status Signals
    output wire        local_fault_det,
    output wire        remote_fault_det,

    // External 66-bit Physical SerDes Interface (PMA)
    output wire [65:0] pcs_tx_block,
    output wire        pcs_tx_valid,
    input  wire [65:0] pcs_rx_block,
    input  wire        pcs_rx_valid
);

    // Internal XGMII Connections between MAC and PCS
    wire [63:0] mac_tx_data;
    wire [7:0]  mac_tx_ctrl;

    wire [63:0] mac_rx_data;
    wire [7:0]  mac_rx_ctrl;

    wire [63:0] xgmii_txd;
    wire [7:0]  xgmii_txc;

    wire [63:0] xgmii_rxd;
    wire [7:0]  xgmii_rxc;

    // Pause Control Signals
    wire        rx_pause_valid;
    wire [15:0] rx_pause_quanta;
    wire        send_pause_frame;
    wire [47:0] pause_dest_mac;
    wire [15:0] pause_opcode;
    wire [15:0] pause_quanta_out;
    wire        pause_frame_done;

    // Flow Control Block
    eth10g_pause_ctrl u_pause_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        .pause_req        (pause_req),
        .pause_quanta_in  (pause_quanta_in),
        .tx_pause_active  (tx_pause_active),
        .send_pause_frame (send_pause_frame),
        .pause_dest_mac   (pause_dest_mac),
        .pause_opcode     (pause_opcode),
        .pause_quanta_out (pause_quanta_out),
        .pause_frame_done (pause_frame_done),
        .rx_pause_valid   (rx_pause_valid),
        .rx_pause_quanta  (rx_pause_quanta)
    );

    // 10G Transmit MAC
    eth10g_mac_tx u_mac_tx (
        .clk              (clk),
        .rst_n            (rst_n),
        .tx_axis_tdata    (tx_axis_tdata),
        .tx_axis_tkeep    (tx_axis_tkeep),
        .tx_axis_tvalid   (tx_axis_tvalid),
        .tx_axis_tlast    (tx_axis_tlast),
        .tx_axis_tready   (tx_axis_tready),
        .tx_pause_inhibit (tx_pause_active),
        .send_pause_frame (send_pause_frame),
        .pause_dest_mac   (pause_dest_mac),
        .pause_opcode     (pause_opcode),
        .pause_quanta     (pause_quanta_out),
        .pause_frame_done (pause_frame_done),
        .xgmii_txd        (mac_tx_data),
        .xgmii_txc        (mac_tx_ctrl)
    );

    // 10G Receive MAC
    eth10g_mac_rx u_mac_rx (
        .clk             (clk),
        .rst_n           (rst_n),
        .xgmii_rxd       (mac_rx_data),
        .xgmii_rxc       (mac_rx_ctrl),
        .rx_axis_tdata   (rx_axis_tdata),
        .rx_axis_tkeep   (rx_axis_tkeep),
        .rx_axis_tvalid  (rx_axis_tvalid),
        .rx_axis_tlast   (rx_axis_tlast),
        .rx_axis_tuser   (rx_axis_tuser),
        .rx_pause_valid  (rx_pause_valid),
        .rx_pause_quanta (rx_pause_quanta)
    );

    // XGMII Interface Adapter
    eth10g_xgmii_if u_xgmii_if (
        .clk              (clk),
        .rst_n            (rst_n),
        .mac_tx_data      (mac_tx_data),
        .mac_tx_ctrl      (mac_tx_ctrl),
        .xgmii_txd_out    (xgmii_txd),
        .xgmii_txc_out    (xgmii_txc),
        .xgmii_rxd_in     (xgmii_rxd),
        .xgmii_rxc_in     (xgmii_rxc),
        .mac_rx_data      (mac_rx_data),
        .mac_rx_ctrl      (mac_rx_ctrl),
        .local_fault_det  (local_fault_det),
        .remote_fault_det (remote_fault_det)
    );

    // 10GBASE-R 64b/66b PCS
    eth10g_pcs_64b66b u_pcs (
        .clk          (clk),
        .rst_n        (rst_n),
        .xgmii_txd    (xgmii_txd),
        .xgmii_txc    (xgmii_txc),
        .pcs_tx_block (pcs_tx_block),
        .pcs_tx_valid (pcs_tx_valid),
        .pcs_rx_block (pcs_rx_block),
        .pcs_rx_valid (pcs_rx_valid),
        .xgmii_rxd    (xgmii_rxd),
        .xgmii_rxc    (xgmii_rxc)
    );

endmodule
