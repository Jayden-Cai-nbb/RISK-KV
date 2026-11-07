

/******************************************************************************
// (c) Copyright 2013 - 2014 Xilinx, Inc. All rights reserved.
//
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
******************************************************************************/
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor             : Xilinx
// \   \   \/     Version            : 1.0
//  \   \         Application        : MIG
//  /   /         Filename           : example_top.sv
// /___/   /\     Date Last Modified : $Date: 2014/09/03 $
// \   \  /  \    Date Created       : Thu Apr 18 2013
//  \___\/\___\
//
// Device           : UltraScale
// Design Name      : DDR4_SDRAM
// Purpose          :
//                    Top-level  module. This module serves both as an example,
//                    and allows the user to synthesize a self-contained
//                    design, which they can be used to test their hardware.
//                    In addition to the memory controller,
//                    the module instantiates:
//                      1. Synthesizable testbench - used to model
//                      user's backend logic and generate different
//                      traffic patterns
//
// Reference        :
// Revision History :
//*****************************************************************************
`ifdef MODEL_TECH
    `ifndef CALIB_SIM
       `define SIMULATION
     `endif
`elsif INCA
    `ifndef CALIB_SIM
       `define SIMULATION
     `endif
`elsif VCS
    `ifndef CALIB_SIM
       `define SIMULATION
     `endif
`elsif XILINX_SIMULATOR
    `ifndef CALIB_SIM
       `define SIMULATION
     `endif
`elsif _VCP
    `ifndef CALIB_SIM
       `define SIMULATION
     `endif
`endif
`ifdef MODEL_TECH
    `define SIMULATION_MODE
`elsif INCA
    `define SIMULATION_MODE
`elsif VCS
    `define SIMULATION_MODE
`elsif XILINX_SIMULATOR
    `define SIMULATION_MODE
`elsif _VCP
    `define SIMULATION_MODE
`endif


`timescale 1ps/1ps
module rkv_m1_board_memory #
(
    parameter FIRMWARE = "firmware.hex",
    parameter [63:0] EXPERIMENT_ID = 64'd0,
    parameter nCK_PER_CLK           = 4,   // This parameter is controllerwise
    parameter         APP_DATA_WIDTH          = 512, // This parameter is controllerwise
    parameter         APP_MASK_WIDTH          = 64,  // This parameter is controllerwise
    parameter C_AXI_ID_WIDTH                = 4,
                                              // Width of all master and slave ID signals.
                                              // # = >= 1.
    parameter C_AXI_ADDR_WIDTH              = 33,
                                              // Width of S_AXI_AWADDR, S_AXI_ARADDR, M_AXI_AWADDR and
                                              // M_AXI_ARADDR for all SI/MI slots.
                                              // # = 32.
    parameter C_AXI_DATA_WIDTH              = 512,
                                              // Width of WDATA and RDATA on SI slot.
                                              // Must be <= APP_DATA_WIDTH.
                                              // # = 32, 64, 128, 256.
    parameter C_AXI_NBURST_SUPPORT   = 0,

  `ifdef SIMULATION_MODE
    parameter SIMULATION            = "TRUE" 
  `else
    parameter SIMULATION            = "FALSE"
  `endif

  )
   (
    input                 sys_rst, //Common port for all controllers

    output                  c0_init_calib_complete,
    output                  c0_data_compare_error,
    input                   c0_sys_clk_p,
    input                   c0_sys_clk_n,
    output                  c0_ddr4_act_n,
    output [16:0]            c0_ddr4_adr,
    output [1:0]            c0_ddr4_ba,
    output [1:0]            c0_ddr4_bg,
    output [0:0]            c0_ddr4_cke,
    output [0:0]            c0_ddr4_odt,
    output [0:0]            c0_ddr4_cs_n,
    output [0:0]                 c0_ddr4_ck_t,
    output [0:0]                c0_ddr4_ck_c,
    output                  c0_ddr4_reset_n,
    inout  [7:0]            c0_ddr4_dm_dbi_n,
    inout  [63:0]            c0_ddr4_dq,
    inout  [7:0]            c0_ddr4_dqs_t,
    inout  [7:0]            c0_ddr4_dqs_c
    );


  localparam  APP_ADDR_WIDTH = 30;
  localparam  MEM_ADDR_ORDER = "ROW_COLUMN_BANK";
  localparam DBG_WR_STS_WIDTH      = 32;
  localparam DBG_RD_STS_WIDTH      = 32;
  localparam ECC                   = "OFF";

wire prbs_mode_done;



  wire [APP_ADDR_WIDTH-1:0]            c0_ddr4_app_addr;
  wire [2:0]            c0_ddr4_app_cmd;
  wire                  c0_ddr4_app_en;
  wire [APP_DATA_WIDTH-1:0]            c0_ddr4_app_wdf_data;
  wire                  c0_ddr4_app_wdf_end;
  wire [APP_MASK_WIDTH-1:0]            c0_ddr4_app_wdf_mask;
  wire                  c0_ddr4_app_wdf_wren;
  wire [APP_DATA_WIDTH-1:0]            c0_ddr4_app_rd_data;
  wire                  c0_ddr4_app_rd_data_end;
  wire                  c0_ddr4_app_rd_data_valid;
  wire                  c0_ddr4_app_rdy;
  wire                  c0_ddr4_app_wdf_rdy;
  wire                  c0_ddr4_clk;
  wire                  c0_ddr4_rst;
  wire                  dbg_clk;
  wire                  c0_wr_rd_complete;

   // debug ports
  wire [63:0]           dbg_rd_data_cmp;
  wire [63:0]           dbg_expected_data;
  wire [2:0]            dbg_cal_seq;
  wire [31:0]           dbg_cal_seq_cnt;
  wire [7:0]            dbg_cal_seq_rd_cnt;
  wire                  dbg_rd_valid;
  wire [5:0]            dbg_cmp_byte;
  wire [63:0]           dbg_rd_data;
  wire [15:0]           dbg_cplx_config;
  wire [1:0]            dbg_cplx_status;
  wire [27:0]           dbg_io_address;
  wire                  dbg_pllGate;
  wire [19:0]           dbg_phy2clb_fixdly_rdy_low;
  wire [19:0]           dbg_phy2clb_fixdly_rdy_upp;
  wire [19:0]           dbg_phy2clb_phy_rdy_low;
  wire [19:0]           dbg_phy2clb_phy_rdy_upp;
  wire [127:0]          cal_r0_status;
  wire [8:0]            cal_post_status;

  reg                              c0_ddr4_aresetn;
  wire                             c0_ddr4_data_msmatch_err;
  wire                             c0_ddr4_write_err;
  wire                             c0_ddr4_read_err;
  wire                             c0_ddr4_test_cmptd;
  wire                             c0_ddr4_write_cmptd;
  wire                             c0_ddr4_read_cmptd;
  wire                             c0_ddr4_cmptd_one_wr_rd;
  wire                             c0_ddr4_tg_data_err_status_rdy;
  wire [1:0]                       c0_ddr4_tg_data_err_status;

  // Slave Interface Write Address Ports
  wire [3:0]      c0_ddr4_s_axi_awid;
  wire [32:0]    c0_ddr4_s_axi_awaddr;
  wire [7:0]                       c0_ddr4_s_axi_awlen;
  wire [2:0]                       c0_ddr4_s_axi_awsize;
  wire [1:0]                       c0_ddr4_s_axi_awburst;
  wire [3:0]                       c0_ddr4_s_axi_awcache;
  wire [2:0]                       c0_ddr4_s_axi_awprot;
  wire                             c0_ddr4_s_axi_awvalid;
  wire                             c0_ddr4_s_axi_awready;
   // Slave Interface Write Data Ports
  wire [511:0]    c0_ddr4_s_axi_wdata;
  wire [63:0]  c0_ddr4_s_axi_wstrb;
  wire                             c0_ddr4_s_axi_wlast;
  wire                             c0_ddr4_s_axi_wvalid;
  wire                             c0_ddr4_s_axi_wready;
   // Slave Interface Write Response Ports
  wire                             c0_ddr4_s_axi_bready;
  wire [3:0]      c0_ddr4_s_axi_bid;
  wire [1:0]                       c0_ddr4_s_axi_bresp;
  wire                             c0_ddr4_s_axi_bvalid;
   // Slave Interface Read Address Ports
  wire [3:0]      c0_ddr4_s_axi_arid;
  wire [32:0]    c0_ddr4_s_axi_araddr;
  wire [7:0]                       c0_ddr4_s_axi_arlen;
  wire [2:0]                       c0_ddr4_s_axi_arsize;
  wire [1:0]                       c0_ddr4_s_axi_arburst;
  wire [3:0]                       c0_ddr4_s_axi_arcache;
  wire                             c0_ddr4_s_axi_arvalid;
  wire                             c0_ddr4_s_axi_arready;
   // Slave Interface Read Data Ports
  wire                             c0_ddr4_s_axi_rready;
  wire [3:0]      c0_ddr4_s_axi_rid;
  wire [511:0]    c0_ddr4_s_axi_rdata;
  wire [1:0]                       c0_ddr4_s_axi_rresp;
  wire                             c0_ddr4_s_axi_rlast;
  wire                             c0_ddr4_s_axi_rvalid;

  wire                             c0_ddr4_cmp_data_valid;
  wire [511:0]    c0_ddr4_cmp_data;     // Compare data
  wire [511:0]    c0_ddr4_rdata_cmp;      // Read data

  wire                             c0_ddr4_dbg_wr_sts_vld;
  wire [DBG_WR_STS_WIDTH-1:0]      c0_ddr4_dbg_wr_sts;
  wire                             c0_ddr4_dbg_rd_sts_vld;
  wire [DBG_RD_STS_WIDTH-1:0]      c0_ddr4_dbg_rd_sts;
  assign c0_data_compare_error = q_fault || q_reset_fault;


  //HW TG VIO signals
  wire [3:0]                           vio_tg_status_state;
  wire                                 vio_tg_status_err_bit_valid;
  wire [APP_DATA_WIDTH-1:0]            vio_tg_status_err_bit;
  wire [31:0]                          vio_tg_status_err_cnt;
  wire [APP_ADDR_WIDTH-1:0]            vio_tg_status_err_addr;
  wire                                 vio_tg_status_exp_bit_valid;
  wire [APP_DATA_WIDTH-1:0]            vio_tg_status_exp_bit;
  wire                                 vio_tg_status_read_bit_valid;
  wire [APP_DATA_WIDTH-1:0]            vio_tg_status_read_bit;
  wire                                 vio_tg_status_first_err_bit_valid;

  wire [APP_DATA_WIDTH-1:0]            vio_tg_status_first_err_bit;
  wire [APP_ADDR_WIDTH-1:0]            vio_tg_status_first_err_addr;
  wire                                 vio_tg_status_first_exp_bit_valid;
  wire [APP_DATA_WIDTH-1:0]            vio_tg_status_first_exp_bit;
  wire                                 vio_tg_status_first_read_bit_valid;
  wire [APP_DATA_WIDTH-1:0]            vio_tg_status_first_read_bit;
  wire                                 vio_tg_status_err_bit_sticky_valid;
  wire [APP_DATA_WIDTH-1:0]            vio_tg_status_err_bit_sticky;
  wire [31:0]                          vio_tg_status_err_cnt_sticky;
  wire                                 vio_tg_status_err_type_valid;
  wire                                 vio_tg_status_err_type;
  wire                                 vio_tg_status_wr_done;
  wire                                 vio_tg_status_done;
  wire                                 vio_tg_status_watch_dog_hang;
  wire                                 tg_ila_debug;

  // Debug Bus
  wire [511:0]                         dbg_bus;        




// debug port wire declarations
`ifdef SIMULATION
`else
 (*mark_debug  = "TRUE" *) wire dbg_init_calib_complete;
 (*mark_debug  = "TRUE" *) wire dbg_data_compare_error;
`endif
// end of  debug port wire declarations

wire reference_clock, ddr_mmcm_locked;
wire service_mode, switch_fault, release_service;
wire [1:0] loss_control;
wire core_clk;
wire fast_clk;
wire core_locked;
wire [3:0] h_awid;
wire [31:0] h_awaddr;
wire [7:0] h_awlen;
wire [2:0] h_awsize;
wire [1:0] h_awburst;
wire h_awlock;
wire [3:0] h_awcache;
wire [2:0] h_awprot;
wire [3:0] h_awqos;
wire h_awvalid;
wire h_awready;
wire [63:0] h_wdata;
wire [7:0] h_wstrb;
wire h_wlast;
wire h_wvalid;
wire h_wready;
wire [3:0] h_bid;
wire [1:0] h_bresp;
wire h_bvalid;
wire h_bready;
wire [3:0] h_arid;
wire [31:0] h_araddr;
wire [7:0] h_arlen;
wire [2:0] h_arsize;
wire [1:0] h_arburst;
wire h_arlock;
wire [3:0] h_arcache;
wire [2:0] h_arprot;
wire [3:0] h_arqos;
wire h_arvalid;
wire h_arready;
wire [3:0] h_rid;
wire [63:0] h_rdata;
wire [1:0] h_rresp;
wire h_rlast;
wire h_rvalid;
wire h_rready;
wire [3:0] m_awid;
wire [32:0] m_awaddr;
wire [7:0] m_awlen;
wire [2:0] m_awsize;
wire [1:0] m_awburst;
wire m_awlock;
wire [3:0] m_awcache;
wire [2:0] m_awprot;
wire [3:0] m_awqos;
wire m_awvalid;
wire m_awready;
wire [511:0] m_wdata;
wire [63:0] m_wstrb;
wire m_wlast;
wire m_wvalid;
wire m_wready;
wire [3:0] m_bid;
wire [1:0] m_bresp;
wire m_bvalid;
wire m_bready;
wire [3:0] m_arid;
wire [32:0] m_araddr;
wire [7:0] m_arlen;
wire [2:0] m_arsize;
wire [1:0] m_arburst;
wire m_arlock;
wire [3:0] m_arcache;
wire [2:0] m_arprot;
wire [3:0] m_arqos;
wire m_arvalid;
wire m_arready;
wire [3:0] m_rid;
wire [511:0] m_rdata;
wire [1:0] m_rresp;
wire m_rlast;
wire m_rvalid;
wire m_rready;
wire control_cold_reset;
wire core_cold_reset;
wire ddr_axi_aresetn;
wire admission_enable;
wire [3:0] fault_causes;
wire platform_error;
wire [63:0] host_verified_beats;
wire [63:0] native_verified_writes;
wire cpu_reset_pulse;
wire cq_valid;
wire isolated;
wire reset_pending;
wire [31:0] epoch;
wire [31:0] generation;
wire [31:0] built_tokens;
wire [63:0] committed_tasks;
wire [31:0] last_error;
wire boot_waiting;
wire trap;
wire test_done;
wire [31:0] test_code;
wire boot_hold;
wire [1279:0] observation_data;
wire c0_ddr4_s_axi_awlock;
wire [3:0] c0_ddr4_s_axi_awqos;
wire c0_ddr4_s_axi_arlock;
wire [2:0] c0_ddr4_s_axi_arprot;
wire [3:0] c0_ddr4_s_axi_arqos;
wire [3:0] q_axi_awid;
wire [32:0] q_axi_awaddr;
wire [7:0] q_axi_awlen;
wire [2:0] q_axi_awsize;
wire [1:0] q_axi_awburst;
wire q_axi_awlock;
wire [3:0] q_axi_awcache;
wire [2:0] q_axi_awprot;
wire [3:0] q_axi_awqos;
wire q_axi_awvalid;
wire q_axi_awready;
wire [511:0] q_axi_wdata;
wire [63:0] q_axi_wstrb;
wire q_axi_wlast;
wire q_axi_wvalid;
wire q_axi_wready;
wire [3:0] q_axi_bid;
wire [1:0] q_axi_bresp;
wire q_axi_bvalid;
wire q_axi_bready;
wire [3:0] q_axi_arid;
wire [32:0] q_axi_araddr;
wire [7:0] q_axi_arlen;
wire [2:0] q_axi_arsize;
wire [1:0] q_axi_arburst;
wire q_axi_arlock;
wire [3:0] q_axi_arcache;
wire [2:0] q_axi_arprot;
wire [3:0] q_axi_arqos;
wire q_axi_arvalid;
wire q_axi_arready;
wire [3:0] q_axi_rid;
wire [511:0] q_axi_rdata;
wire [1:0] q_axi_rresp;
wire q_axi_rlast;
wire q_axi_rvalid;
wire q_axi_rready;
wire ddr_bvalid, ddr_bready, ddr_rvalid, ddr_rready;

wire c0_ddr4_reset_n_int;
  assign c0_ddr4_reset_n = c0_ddr4_reset_n_int;

//***************************************************************************
// The User design is instantiated below. The memory interface ports are
// connected to the top-level and the application interface ports are
// connected to the traffic generator module. This provides a reference
// for connecting the memory controller to system.
//***************************************************************************

  // user design top is one instance for all controllers
rkv_ddr_candidate u_rkv_ddr_candidate
(
   .rkv_ref_clock (reference_clock),
   .rkv_mmcm_locked (ddr_mmcm_locked),
   .sys_rst           (sys_rst),

   .c0_sys_clk_p                   (c0_sys_clk_p),
   .c0_sys_clk_n                   (c0_sys_clk_n),
   .c0_init_calib_complete (c0_init_calib_complete),
   .c0_ddr4_act_n          (c0_ddr4_act_n),
   .c0_ddr4_adr            (c0_ddr4_adr),
   .c0_ddr4_ba             (c0_ddr4_ba),
   .c0_ddr4_bg             (c0_ddr4_bg),
   .c0_ddr4_cke            (c0_ddr4_cke),
   .c0_ddr4_odt            (c0_ddr4_odt),
   .c0_ddr4_cs_n           (c0_ddr4_cs_n),
   .c0_ddr4_ck_t           (c0_ddr4_ck_t),
   .c0_ddr4_ck_c           (c0_ddr4_ck_c),
   .c0_ddr4_reset_n        (c0_ddr4_reset_n_int),

   .c0_ddr4_dm_dbi_n       (c0_ddr4_dm_dbi_n),
   .c0_ddr4_dq             (c0_ddr4_dq),
   .c0_ddr4_dqs_c          (c0_ddr4_dqs_c),
   .c0_ddr4_dqs_t          (c0_ddr4_dqs_t),

   .c0_ddr4_ui_clk                (c0_ddr4_clk),
   .c0_ddr4_ui_clk_sync_rst       (c0_ddr4_rst),
   .dbg_clk                                    (dbg_clk),
   .dbg_rd_data_cmp                            (dbg_rd_data_cmp),
   .dbg_expected_data                          (dbg_expected_data),
   .dbg_cal_seq                                (dbg_cal_seq               ),
   .dbg_cal_seq_cnt                            (dbg_cal_seq_cnt           ),
   .dbg_cal_seq_rd_cnt                         (dbg_cal_seq_rd_cnt        ),
   .dbg_rd_valid                               (dbg_rd_valid              ),
   .dbg_cmp_byte                               (dbg_cmp_byte              ),
   .dbg_rd_data                                (dbg_rd_data               ),
   .dbg_cplx_config                            (dbg_cplx_config           ),
   .dbg_cplx_status                            (dbg_cplx_status           ),
   .dbg_io_address                             (dbg_io_address            ),
   .dbg_pllGate                                (dbg_pllGate               ),
   .dbg_phy2clb_fixdly_rdy_low                 (dbg_phy2clb_fixdly_rdy_low),
   .dbg_phy2clb_fixdly_rdy_upp                 (dbg_phy2clb_fixdly_rdy_upp),
   .dbg_phy2clb_phy_rdy_low                    (dbg_phy2clb_phy_rdy_low   ),
   .dbg_phy2clb_phy_rdy_upp                    (dbg_phy2clb_phy_rdy_upp   ),
   .cal_r0_status                              (cal_r0_status),
   .cal_post_status                            (cal_post_status),
  // Slave Interface Write Address Ports
  .c0_ddr4_aresetn                     (c0_ddr4_aresetn),
  .c0_ddr4_s_axi_awid                  (c0_ddr4_s_axi_awid),
  .c0_ddr4_s_axi_awaddr                (c0_ddr4_s_axi_awaddr),
  .c0_ddr4_s_axi_awlen                 (c0_ddr4_s_axi_awlen),
  .c0_ddr4_s_axi_awsize                (c0_ddr4_s_axi_awsize),
  .c0_ddr4_s_axi_awburst               (c0_ddr4_s_axi_awburst),
  .c0_ddr4_s_axi_awlock                (c0_ddr4_s_axi_awlock),
  .c0_ddr4_s_axi_awcache               (c0_ddr4_s_axi_awcache),
  .c0_ddr4_s_axi_awprot                (c0_ddr4_s_axi_awprot),
  .c0_ddr4_s_axi_awqos                 (c0_ddr4_s_axi_awqos),
  .c0_ddr4_s_axi_awvalid               (c0_ddr4_s_axi_awvalid),
  .c0_ddr4_s_axi_awready               (c0_ddr4_s_axi_awready),
  // Slave Interface Write Data Ports
  .c0_ddr4_s_axi_wdata                 (c0_ddr4_s_axi_wdata),
  .c0_ddr4_s_axi_wstrb                 (c0_ddr4_s_axi_wstrb),
  .c0_ddr4_s_axi_wlast                 (c0_ddr4_s_axi_wlast),
  .c0_ddr4_s_axi_wvalid                (c0_ddr4_s_axi_wvalid),
  .c0_ddr4_s_axi_wready                (c0_ddr4_s_axi_wready),
  // Slave Interface Write Response Ports
  .c0_ddr4_s_axi_bid                   (c0_ddr4_s_axi_bid),
  .c0_ddr4_s_axi_bresp                 (c0_ddr4_s_axi_bresp),
  .c0_ddr4_s_axi_bvalid                (ddr_bvalid),
  .c0_ddr4_s_axi_bready                (ddr_bready),
  // Slave Interface Read Address Ports
  .c0_ddr4_s_axi_arid                  (c0_ddr4_s_axi_arid),
  .c0_ddr4_s_axi_araddr                (c0_ddr4_s_axi_araddr),
  .c0_ddr4_s_axi_arlen                 (c0_ddr4_s_axi_arlen),
  .c0_ddr4_s_axi_arsize                (c0_ddr4_s_axi_arsize),
  .c0_ddr4_s_axi_arburst               (c0_ddr4_s_axi_arburst),
  .c0_ddr4_s_axi_arlock                (c0_ddr4_s_axi_arlock),
  .c0_ddr4_s_axi_arcache               (c0_ddr4_s_axi_arcache),
  .c0_ddr4_s_axi_arprot                (c0_ddr4_s_axi_arprot),
  .c0_ddr4_s_axi_arqos                 (c0_ddr4_s_axi_arqos),
  .c0_ddr4_s_axi_arvalid               (c0_ddr4_s_axi_arvalid),
  .c0_ddr4_s_axi_arready               (c0_ddr4_s_axi_arready),
  // Slave Interface Read Data Ports
  .c0_ddr4_s_axi_rid                   (c0_ddr4_s_axi_rid),
  .c0_ddr4_s_axi_rdata                 (c0_ddr4_s_axi_rdata),
  .c0_ddr4_s_axi_rresp                 (c0_ddr4_s_axi_rresp),
  .c0_ddr4_s_axi_rlast                 (c0_ddr4_s_axi_rlast),
  .c0_ddr4_s_axi_rvalid                (ddr_rvalid),
  .c0_ddr4_s_axi_rready                (ddr_rready),
  
  // Debug Port
  .dbg_bus         (dbg_bus)                                             

  );
   always @(posedge c0_ddr4_clk) begin
     c0_ddr4_aresetn <= ~c0_ddr4_rst;
   end



//***************************************************************************
// The AXI testbench module instantiated below drives traffic (patterns)
// on the application interface of the memory controller
//***************************************************************************

// UI域独立验收批次；配置级guard仍限制一次启动，不提供局部reset。
wire q_start, q_launch, q_launched, q_reset_fault, q_busy, q_done, q_fault;
wire q_peek_toggle, q_peek_ack;
wire [31:0] q_base, q_seed, q_peek_address;
wire [25:0] q_blocks, q_index;
wire [15:0] q_min_seconds;
wire [3:0] q_code, q_phase;
wire [2:0] q_pass;
wire [31:0] q_rounds, q_elapsed, q_seconds;
wire [47:0] q_cycles;
wire [511:0] q_expected, q_observed;
wire [47:0] q_aw, q_w, q_b, q_ar, q_r;
reg [31:0] q_heartbeat = 32'd0;
always @(posedge c0_ddr4_clk) q_heartbeat <= q_heartbeat + 32'd1;
wire q_cold = c0_ddr4_rst || !c0_ddr4_aresetn;
wire [3:0] q_report_code = q_reset_fault ? 4'd7 : q_code;
wire [31:0] q_status = {18'd0, q_report_code, q_phase, q_start,
    (q_fault || q_reset_fault), (q_done && !q_reset_fault), q_busy,
    c0_ddr4_rst, c0_init_calib_complete};
assign q_axi_awid = 4'd0;
assign q_axi_awlen = 8'd0;
assign q_axi_awsize = 3'd6;
assign q_axi_awburst = 2'b01;
assign q_axi_awcache = 4'd0;
assign q_axi_awprot = 3'd0;
assign q_axi_wlast = 1'b1;
assign q_axi_arid = 4'd0;
assign q_axi_arlen = 8'd0;
assign q_axi_arsize = 3'd6;
assign q_axi_arburst = 2'b01;
assign q_axi_arcache = 4'd0;
rkv_ddr_first_guard configuration_guard (
    .clk(c0_ddr4_clk),
    .ui_reset(q_cold),
    .start_level(q_start),
    .launch(q_launch),
    .launched(q_launched),
    .reset_fault(q_reset_fault)
);
rkv_ddr_qualifier qualification (
    .clk(c0_ddr4_clk),
    .cold_reset(q_cold),
    .calibrated(c0_init_calib_complete),
    .start(q_launch),
    .base_address(q_base),
    .block_count(q_blocks),
    .seed(q_seed),
    .min_seconds(q_min_seconds),
    .peek_toggle(service_mode ? q_peek_ack : q_peek_toggle),
    .peek_address(q_peek_address),
    .peek_ack(q_peek_ack),
    .busy(q_busy),
    .done(q_done),
    .fault(q_fault),
    .fault_code(q_code),
    .phase(q_phase),
    .rounds(q_rounds),
    .block_index(q_index),
    .elapsed(q_elapsed),
    .cycles(q_cycles),
    .seconds(q_seconds),
    .expected_data(q_expected),
    .observed_data(q_observed),
    .aw_count(q_aw),
    .w_count(q_w),
    .b_count(q_b),
    .ar_count(q_ar),
    .r_count(q_r),
    .pass(q_pass),
    .axi_awaddr(q_axi_awaddr),
    .axi_awvalid(q_axi_awvalid),
    .axi_awready(q_axi_awready),
    .axi_wdata(q_axi_wdata),
    .axi_wstrb(q_axi_wstrb),
    .axi_wvalid(q_axi_wvalid),
    .axi_wready(q_axi_wready),
    .axi_bid(q_axi_bid),
    .axi_bresp(q_axi_bresp),
    .axi_bvalid(q_axi_bvalid),
    .axi_bready(q_axi_bready),
    .axi_araddr(q_axi_araddr),
    .axi_arvalid(q_axi_arvalid),
    .axi_arready(q_axi_arready),
    .axi_rid(q_axi_rid),
    .axi_rresp(q_axi_rresp),
    .axi_rdata(q_axi_rdata),
    .axi_rlast(q_axi_rlast),
    .axi_rvalid(q_axi_rvalid),
    .axi_rready(q_axi_rready)
);
ddr_qualifier_vio qualification_diagnosis (
    .clk(c0_ddr4_clk),
    .probe_in0(32'h44445251),
    .probe_in1(q_heartbeat),
    .probe_in2(q_status),
    .probe_in3(q_elapsed),
    .probe_in4(q_axi_awaddr),
    .probe_in5({q_aw,q_w,q_b,q_ar}),
    .probe_in6(q_r),
    .probe_in7(q_cycles),
    .probe_in8(q_rounds),
    .probe_in9(q_pass),
    .probe_in10(q_expected[127:0]),
    .probe_in11(q_expected[255:128]),
    .probe_in12(q_expected[383:256]),
    .probe_in13(q_expected[511:384]),
    .probe_in14(q_observed[127:0]),
    .probe_in15(q_observed[255:128]),
    .probe_in16(q_observed[383:256]),
    .probe_in17(q_observed[511:384]),
    .probe_in18(q_peek_ack),
    .probe_in19(q_index),
    .probe_in20(q_seconds),
    .probe_out0(q_start),
    .probe_out1(q_base),
    .probe_out2(q_blocks),
    .probe_out3(q_seed),
    .probe_out4(q_min_seconds),
    .probe_out5(q_peek_toggle),
    .probe_out6(q_peek_address),
    .probe_out7(release_service),
    .probe_out8(loss_control)
);

assign q_axi_awlock = 1'd0;
assign q_axi_awqos = 4'd0;
assign q_axi_arlock = 1'd0;
assign q_axi_arprot = 3'd0;
assign q_axi_arqos = 4'd0;
assign c0_ddr4_s_axi_bvalid = ddr_bvalid && !(service_mode && loss_control[1]);
assign ddr_bready = c0_ddr4_s_axi_bready && !(service_mode && loss_control[1]);
assign c0_ddr4_s_axi_rvalid = ddr_rvalid && !(service_mode && loss_control[0]);
assign ddr_rready = c0_ddr4_s_axi_rready && !(service_mode && loss_control[0]);
rkv_m1_boot_mux boot_selection (
    .clk(c0_ddr4_clk),
    .release_request(release_service),
    .qualified(q_done && !q_fault && !q_reset_fault && c0_init_calib_complete),
    .qualification_idle(!q_busy && q_peek_toggle == q_peek_ack && q_aw == q_b && q_w == q_b && q_ar == q_r),
    .health_fault(q_reset_fault || q_fault),
    .service_mode(service_mode),
    .switch_fault(switch_fault),
    .q_awid(q_axi_awid),
    .q_awaddr(q_axi_awaddr),
    .q_awlen(q_axi_awlen),
    .q_awsize(q_axi_awsize),
    .q_awburst(q_axi_awburst),
    .q_awlock(q_axi_awlock),
    .q_awcache(q_axi_awcache),
    .q_awprot(q_axi_awprot),
    .q_awqos(q_axi_awqos),
    .q_awvalid(q_axi_awvalid),
    .q_awready(q_axi_awready),
    .q_wdata(q_axi_wdata),
    .q_wstrb(q_axi_wstrb),
    .q_wlast(q_axi_wlast),
    .q_wvalid(q_axi_wvalid),
    .q_wready(q_axi_wready),
    .q_bid(q_axi_bid),
    .q_bresp(q_axi_bresp),
    .q_bvalid(q_axi_bvalid),
    .q_bready(q_axi_bready),
    .q_arid(q_axi_arid),
    .q_araddr(q_axi_araddr),
    .q_arlen(q_axi_arlen),
    .q_arsize(q_axi_arsize),
    .q_arburst(q_axi_arburst),
    .q_arlock(q_axi_arlock),
    .q_arcache(q_axi_arcache),
    .q_arprot(q_axi_arprot),
    .q_arqos(q_axi_arqos),
    .q_arvalid(q_axi_arvalid),
    .q_arready(q_axi_arready),
    .q_rid(q_axi_rid),
    .q_rdata(q_axi_rdata),
    .q_rresp(q_axi_rresp),
    .q_rlast(q_axi_rlast),
    .q_rvalid(q_axi_rvalid),
    .q_rready(q_axi_rready),
    .s_awid(m_awid),
    .s_awaddr(m_awaddr),
    .s_awlen(m_awlen),
    .s_awsize(m_awsize),
    .s_awburst(m_awburst),
    .s_awlock(m_awlock),
    .s_awcache(m_awcache),
    .s_awprot(m_awprot),
    .s_awqos(m_awqos),
    .s_awvalid(m_awvalid),
    .s_awready(m_awready),
    .s_wdata(m_wdata),
    .s_wstrb(m_wstrb),
    .s_wlast(m_wlast),
    .s_wvalid(m_wvalid),
    .s_wready(m_wready),
    .s_bid(m_bid),
    .s_bresp(m_bresp),
    .s_bvalid(m_bvalid),
    .s_bready(m_bready),
    .s_arid(m_arid),
    .s_araddr(m_araddr),
    .s_arlen(m_arlen),
    .s_arsize(m_arsize),
    .s_arburst(m_arburst),
    .s_arlock(m_arlock),
    .s_arcache(m_arcache),
    .s_arprot(m_arprot),
    .s_arqos(m_arqos),
    .s_arvalid(m_arvalid),
    .s_arready(m_arready),
    .s_rid(m_rid),
    .s_rdata(m_rdata),
    .s_rresp(m_rresp),
    .s_rlast(m_rlast),
    .s_rvalid(m_rvalid),
    .s_rready(m_rready),
    .m_awid(c0_ddr4_s_axi_awid),
    .m_awaddr(c0_ddr4_s_axi_awaddr),
    .m_awlen(c0_ddr4_s_axi_awlen),
    .m_awsize(c0_ddr4_s_axi_awsize),
    .m_awburst(c0_ddr4_s_axi_awburst),
    .m_awlock(c0_ddr4_s_axi_awlock),
    .m_awcache(c0_ddr4_s_axi_awcache),
    .m_awprot(c0_ddr4_s_axi_awprot),
    .m_awqos(c0_ddr4_s_axi_awqos),
    .m_awvalid(c0_ddr4_s_axi_awvalid),
    .m_awready(c0_ddr4_s_axi_awready),
    .m_wdata(c0_ddr4_s_axi_wdata),
    .m_wstrb(c0_ddr4_s_axi_wstrb),
    .m_wlast(c0_ddr4_s_axi_wlast),
    .m_wvalid(c0_ddr4_s_axi_wvalid),
    .m_wready(c0_ddr4_s_axi_wready),
    .m_bid(c0_ddr4_s_axi_bid),
    .m_bresp(c0_ddr4_s_axi_bresp),
    .m_bvalid(c0_ddr4_s_axi_bvalid),
    .m_bready(c0_ddr4_s_axi_bready),
    .m_arid(c0_ddr4_s_axi_arid),
    .m_araddr(c0_ddr4_s_axi_araddr),
    .m_arlen(c0_ddr4_s_axi_arlen),
    .m_arsize(c0_ddr4_s_axi_arsize),
    .m_arburst(c0_ddr4_s_axi_arburst),
    .m_arlock(c0_ddr4_s_axi_arlock),
    .m_arcache(c0_ddr4_s_axi_arcache),
    .m_arprot(c0_ddr4_s_axi_arprot),
    .m_arqos(c0_ddr4_s_axi_arqos),
    .m_arvalid(c0_ddr4_s_axi_arvalid),
    .m_arready(c0_ddr4_s_axi_arready),
    .m_rid(c0_ddr4_s_axi_rid),
    .m_rdata(c0_ddr4_s_axi_rdata),
    .m_rresp(c0_ddr4_s_axi_rresp),
    .m_rlast(c0_ddr4_s_axi_rlast),
    .m_rvalid(c0_ddr4_s_axi_rvalid),
    .m_rready(c0_ddr4_s_axi_rready)
);
// UI域移交电平只翻转一次；core域双触发同步，不能由普通服务复位撤销。
(* ASYNC_REG = "TRUE" *) reg [1:0] service_sync = 2'b00;
(* ASYNC_REG = "TRUE" *) reg [1:0] switch_fault_sync = 2'b00;
always @(posedge core_clk) begin
    service_sync <= {service_sync[0],service_mode};
    switch_fault_sync <= {switch_fault_sync[0],switch_fault};
end
wire [31:0] board_control;
reg [31:0] board_heartbeat = 32'd0;
reg [31:0] snapshot_sequence = 32'd0;
reg snapshot_ack = 1'b0;
reg [1535:0] snapshot_data = 1536'd0;
reg [63:0] board_cycles = 64'd0;
reg [63:0] board_reset_count = 64'd0;
wire mask_active;
wire j_awvalid, j_awready, j_wvalid, j_wready;
wire [7:0] j_wstrb;
always @(posedge core_clk) begin
    board_heartbeat <= board_heartbeat + 32'd1;
    board_cycles <= board_cycles + 64'd1;
    if (cpu_reset_pulse) board_reset_count <= board_reset_count + 64'd1;
    if (board_control[0] != snapshot_ack) begin
        snapshot_data <= {128'd0,board_cycles,board_reset_count,observation_data};
        snapshot_sequence <= snapshot_sequence + 32'd1;
        snapshot_ack <= board_control[0];
    end
end
clock_48_to_100_50 clocks (
    .clk_in1(reference_clock),
    .reset(1'b0),
    .clk_out1(fast_clk),
    .clk_out2(core_clk),
    .locked(core_locked)
);
rkv_m1_platform #(
    .FIRMWARE(FIRMWARE),
    .EXPERIMENT_ID(EXPERIMENT_ID)
) platform (
    .core_clk(core_clk),
    .fast_clk(fast_clk),
    .ddr_clk(c0_ddr4_clk),
    .chain_cold_reset(!service_sync[1]),
    .core_locked(core_locked),
    .ddr_locked(ddr_mmcm_locked),
    .ddr_calibrated(c0_init_calib_complete),
    .external_fault(switch_fault_sync[1]),
    .inject_task_error(board_control[1]),
    .h_awid(h_awid),
    .h_awaddr(h_awaddr),
    .h_awlen(h_awlen),
    .h_awsize(h_awsize),
    .h_awburst(h_awburst),
    .h_awlock(h_awlock),
    .h_awcache(h_awcache),
    .h_awprot(h_awprot),
    .h_awqos(h_awqos),
    .h_awvalid(h_awvalid),
    .h_awready(h_awready),
    .h_wdata(h_wdata),
    .h_wstrb(h_wstrb),
    .h_wlast(h_wlast),
    .h_wvalid(h_wvalid),
    .h_wready(h_wready),
    .h_bid(h_bid),
    .h_bresp(h_bresp),
    .h_bvalid(h_bvalid),
    .h_bready(h_bready),
    .h_arid(h_arid),
    .h_araddr(h_araddr),
    .h_arlen(h_arlen),
    .h_arsize(h_arsize),
    .h_arburst(h_arburst),
    .h_arlock(h_arlock),
    .h_arcache(h_arcache),
    .h_arprot(h_arprot),
    .h_arqos(h_arqos),
    .h_arvalid(h_arvalid),
    .h_arready(h_arready),
    .h_rid(h_rid),
    .h_rdata(h_rdata),
    .h_rresp(h_rresp),
    .h_rlast(h_rlast),
    .h_rvalid(h_rvalid),
    .h_rready(h_rready),
    .m_awid(m_awid),
    .m_awaddr(m_awaddr),
    .m_awlen(m_awlen),
    .m_awsize(m_awsize),
    .m_awburst(m_awburst),
    .m_awlock(m_awlock),
    .m_awcache(m_awcache),
    .m_awprot(m_awprot),
    .m_awqos(m_awqos),
    .m_awvalid(m_awvalid),
    .m_awready(m_awready),
    .m_wdata(m_wdata),
    .m_wstrb(m_wstrb),
    .m_wlast(m_wlast),
    .m_wvalid(m_wvalid),
    .m_wready(m_wready),
    .m_bid(m_bid),
    .m_bresp(m_bresp),
    .m_bvalid(m_bvalid),
    .m_bready(m_bready),
    .m_arid(m_arid),
    .m_araddr(m_araddr),
    .m_arlen(m_arlen),
    .m_arsize(m_arsize),
    .m_arburst(m_arburst),
    .m_arlock(m_arlock),
    .m_arcache(m_arcache),
    .m_arprot(m_arprot),
    .m_arqos(m_arqos),
    .m_arvalid(m_arvalid),
    .m_arready(m_arready),
    .m_rid(m_rid),
    .m_rdata(m_rdata),
    .m_rresp(m_rresp),
    .m_rlast(m_rlast),
    .m_rvalid(m_rvalid),
    .m_rready(m_rready),
    .control_cold_reset(control_cold_reset),
    .core_cold_reset(core_cold_reset),
    .ddr_axi_aresetn(ddr_axi_aresetn),
    .admission_enable(admission_enable),
    .fault_causes(fault_causes),
    .platform_error(platform_error),
    .host_verified_beats(host_verified_beats),
    .native_verified_writes(native_verified_writes),
    .cpu_reset_pulse(cpu_reset_pulse),
    .cq_valid(cq_valid),
    .isolated(isolated),
    .reset_pending(reset_pending),
    .epoch(epoch),
    .generation(generation),
    .built_tokens(built_tokens),
    .committed_tasks(committed_tasks),
    .last_error(last_error),
    .boot_waiting(boot_waiting),
    .trap(trap),
    .test_done(test_done),
    .test_code(test_code),
    .boot_hold(boot_hold),
    .observation_data(observation_data)
);
// JTAG只负责全字传输，字节使能由真实AW沿绑定，避免配置变化破坏阻塞W。
rkv_m1_jtag_mask host_byte_mask (
    .clk(core_clk),
    .cold_reset(control_cold_reset),
    .mask_enable(board_control[2]),
    .byte_mask(board_control[15:8]),
    .awaddr(h_awaddr),
    .j_awvalid(j_awvalid),
    .j_awready(j_awready),
    .h_awvalid(h_awvalid),
    .h_awready(h_awready),
    .j_wvalid(j_wvalid),
    .j_wlast(h_wlast),
    .j_wstrb(j_wstrb),
    .j_wready(j_wready),
    .h_wvalid(h_wvalid),
    .h_wstrb(h_wstrb),
    .h_wready(h_wready),
    .bvalid(h_bvalid),
    .bready(h_bready),
    .active(mask_active)
);

rkv_m1_jtag_axi host_jtag (
    .aclk(core_clk),
    .aresetn(!control_cold_reset),
    .m_axi_awid(h_awid),
    .m_axi_awaddr(h_awaddr),
    .m_axi_awlen(h_awlen),
    .m_axi_awsize(h_awsize),
    .m_axi_awburst(h_awburst),
    .m_axi_awlock(h_awlock),
    .m_axi_awcache(h_awcache),
    .m_axi_awprot(h_awprot),
    .m_axi_awqos(h_awqos),
    .m_axi_awvalid(j_awvalid),
    .m_axi_awready(j_awready),
    .m_axi_wdata(h_wdata),
    .m_axi_wstrb(j_wstrb),
    .m_axi_wlast(h_wlast),
    .m_axi_wvalid(j_wvalid),
    .m_axi_wready(j_wready),
    .m_axi_bid(h_bid),
    .m_axi_bresp(h_bresp),
    .m_axi_bvalid(h_bvalid),
    .m_axi_bready(h_bready),
    .m_axi_arid(h_arid),
    .m_axi_araddr(h_araddr),
    .m_axi_arlen(h_arlen),
    .m_axi_arsize(h_arsize),
    .m_axi_arburst(h_arburst),
    .m_axi_arlock(h_arlock),
    .m_axi_arcache(h_arcache),
    .m_axi_arprot(h_arprot),
    .m_axi_arqos(h_arqos),
    .m_axi_arvalid(h_arvalid),
    .m_axi_arready(h_arready),
    .m_axi_rid(h_rid),
    .m_axi_rdata(h_rdata),
    .m_axi_rresp(h_rresp),
    .m_axi_rlast(h_rlast),
    .m_axi_rvalid(h_rvalid),
    .m_axi_rready(h_rready)
);
rkv_m1_board_vio board_diagnosis (
    .clk(core_clk),
    .probe_in0(32'h4d314231),
    .probe_in1(board_heartbeat),
    .probe_in2(snapshot_sequence),
    .probe_in3({26'd0,mask_active,switch_fault_sync[1],service_sync[1],core_locked,snapshot_ack,boot_hold}),
    .probe_in4(snapshot_data[255:0]),
    .probe_in5(snapshot_data[511:256]),
    .probe_in6(snapshot_data[767:512]),
    .probe_in7(snapshot_data[1023:768]),
    .probe_in8(snapshot_data[1279:1024]),
    .probe_in9(snapshot_data[1535:1280]),
    .probe_out0(board_control)
);

`ifdef SIMULATION
`else
 // Debug cores instantiation

   assign dbg_init_calib_complete = c0_init_calib_complete;
   assign dbg_data_compare_error  = c0_data_compare_error;


 ila_ddrx u_ila_ddrx (                              // Refer to PG150 for the usage of the Below probes 

    .clk (c0_ddr4_clk),                           
    .probe0  (dbg_init_calib_complete),             // Signifies the status of calibration
    .probe1  (dbg_data_compare_error),              // Signifies the status of Traffic Error from The TG 
    .probe2  (dbg_expected_data),                   // Displays the expected data during calibration stages that use fabric-based data pattern comparison such as Read per-bit deskew or read DQS centering (complex).
    .probe3  (dbg_rd_data_cmp),                     // Comparison of dbg_rd_data and dbg_expected_data
    .probe4  (dbg_cal_seq),                         // Calibration sequence indicator, when RTL is issuing commands to the DRAM. 
    .probe5  (dbg_cal_seq_cnt),                     // Calibration command sequence count used when RTL is issuing commands to the DRAM.
    .probe6  (dbg_cal_seq_rd_cnt),                  // Calibration read data burst count
    .probe7  (dbg_rd_valid),                        // Read data valid
    .probe8  (dbg_cmp_byte),                        // Calibration byte selection 
    .probe9  (dbg_rd_data),                         // Read data from input FIFOs
    .probe10 (dbg_cplx_config),                     // Complex cal configuration
    .probe11 (dbg_cplx_status),                     // Complex cal status
    .probe12 (dbg_io_address),                      // MicroBlaze I/O address bus 
    .probe13 (dbg_pllGate),                         // PLL lock indicator
    .probe14 (dbg_phy2clb_fixdly_rdy_low),          // Xiphy fixed delay ready signal (lower nibble) 
    .probe15 (dbg_phy2clb_fixdly_rdy_upp),          // Xiphy fixed delay ready signal (upper nibble)
    .probe16 (dbg_phy2clb_phy_rdy_low),             // Xiphy phy ready signal (lower nibble)
    .probe17 (dbg_phy2clb_phy_rdy_upp),             // Xiphy phy ready signal (upper nibble)
    .probe18 (cal_r0_status),                        // Signifies the status of each stage of calibration.
    //.probe18 (win_status),                          // Margin Status 
    .probe19 (cal_post_status)                        // Signifies the status of calibration.                                                                                                                      

    );
`endif

 //End of Debug cores instantiation


`ifdef VIO_ATG_EN

`endif

endmodule





































