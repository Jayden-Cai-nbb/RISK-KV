// 可综合主机连接：最早责任记录→实际根SmartConnect→控制/DDR两个独立出口。
// 无主机/NPU/DDR行为目标。cold统一来自平台控制域，普通CPU复位只作为请求输出。
module rkv_m1_host_link #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000,
    parameter [63:0] EXPERIMENT_ID = 64'd0
) (
    input wire  clk,
    input wire  cold_reset,
    input wire  platform_ready,
    input wire  platform_error,
    input wire  ddr_idle,
    input wire  ddr_accept_now,
    input wire [31:0] status_flags,
    input wire [31:0] epoch,
    input wire [31:0] generation,
    input wire [31:0] error_code,
    input wire [63:0] host_verified,
    input wire [63:0] native_verified,
    input wire [63:0] accepted_reads,
    input wire [63:0] accepted_writes,
    input wire [63:0] rejected_requests,
    output wire  boot_hold,
    output wire  reset_request,
    output wire  control_idle,
    output wire [63:0] control_requests,
    output wire  host_valid,
    output wire [15:0] host_addr,
    output wire [31:0] host_wdata,
    output wire [3:0] host_wstrb,
    input wire  host_ready,
    input wire [31:0] host_rdata,
    input wire  host_error,
    input wire  read_grant,
    input wire  write_grant,
    output wire  memory_idle,
    output wire  memory_accept_now,
    output wire  saved_read_grant,
    output wire  saved_write_grant,
    output wire  fault,
    output wire [31:0] fault_code,
    output wire [1:0] memory_outstanding,
    input wire [3:0] h_awid,
    input wire [31:0] h_awaddr,
    input wire [7:0] h_awlen,
    input wire [2:0] h_awsize,
    input wire [1:0] h_awburst,
    input wire  h_awlock,
    input wire [3:0] h_awcache,
    input wire [2:0] h_awprot,
    input wire [3:0] h_awqos,
    input wire  h_awvalid,
    output wire  h_awready,
    input wire [63:0] h_wdata,
    input wire [7:0] h_wstrb,
    input wire  h_wlast,
    input wire  h_wvalid,
    output wire  h_wready,
    output wire [3:0] h_bid,
    output wire [1:0] h_bresp,
    output wire  h_bvalid,
    input wire  h_bready,
    input wire [3:0] h_arid,
    input wire [31:0] h_araddr,
    input wire [7:0] h_arlen,
    input wire [2:0] h_arsize,
    input wire [1:0] h_arburst,
    input wire  h_arlock,
    input wire [3:0] h_arcache,
    input wire [2:0] h_arprot,
    input wire [3:0] h_arqos,
    input wire  h_arvalid,
    output wire  h_arready,
    output wire [3:0] h_rid,
    output wire [63:0] h_rdata,
    output wire [1:0] h_rresp,
    output wire  h_rlast,
    output wire  h_rvalid,
    input wire  h_rready,
    output wire [31:0] d_awaddr,
    output wire [7:0] d_awlen,
    output wire [2:0] d_awsize,
    output wire [1:0] d_awburst,
    output wire  d_awlock,
    output wire [3:0] d_awcache,
    output wire [2:0] d_awprot,
    output wire [3:0] d_awqos,
    output wire  d_awvalid,
    input wire  d_awready,
    output wire [63:0] d_wdata,
    output wire [7:0] d_wstrb,
    output wire  d_wlast,
    output wire  d_wvalid,
    input wire  d_wready,
    input wire [1:0] d_bresp,
    input wire  d_bvalid,
    output wire  d_bready,
    output wire [31:0] d_araddr,
    output wire [7:0] d_arlen,
    output wire [2:0] d_arsize,
    output wire [1:0] d_arburst,
    output wire  d_arlock,
    output wire [3:0] d_arcache,
    output wire [2:0] d_arprot,
    output wire [3:0] d_arqos,
    output wire  d_arvalid,
    input wire  d_arready,
    input wire [63:0] d_rdata,
    input wire [1:0] d_rresp,
    input wire  d_rlast,
    input wire  d_rvalid,
    output wire  d_rready
);
    wire [3:0] root_awid;
    wire [31:0] root_awaddr;
    wire [7:0] root_awlen;
    wire [2:0] root_awsize;
    wire [1:0] root_awburst;
    wire  root_awlock;
    wire [3:0] root_awcache;
    wire [2:0] root_awprot;
    wire [3:0] root_awqos;
    wire  root_awvalid;
    wire  root_awready;
    wire [63:0] root_wdata;
    wire [7:0] root_wstrb;
    wire  root_wlast;
    wire  root_wvalid;
    wire  root_wready;
    wire [3:0] root_bid;
    wire [1:0] root_bresp;
    wire  root_bvalid;
    wire  root_bready;
    wire [3:0] root_arid;
    wire [31:0] root_araddr;
    wire [7:0] root_arlen;
    wire [2:0] root_arsize;
    wire [1:0] root_arburst;
    wire  root_arlock;
    wire [3:0] root_arcache;
    wire [2:0] root_arprot;
    wire [3:0] root_arqos;
    wire  root_arvalid;
    wire  root_arready;
    wire [3:0] root_rid;
    wire [63:0] root_rdata;
    wire [1:0] root_rresp;
    wire  root_rlast;
    wire  root_rvalid;
    wire  root_rready;
    wire [31:0] CONTROL_araddr;
    wire [1:0] CONTROL_arburst;
    wire [3:0] CONTROL_arcache;
    wire [7:0] CONTROL_arlen;
    wire [0:0] CONTROL_arlock;
    wire [2:0] CONTROL_arprot;
    wire [3:0] CONTROL_arqos;
    wire  CONTROL_arready;
    wire [2:0] CONTROL_arsize;
    wire  CONTROL_arvalid;
    wire [31:0] CONTROL_awaddr;
    wire [1:0] CONTROL_awburst;
    wire [3:0] CONTROL_awcache;
    wire [7:0] CONTROL_awlen;
    wire [0:0] CONTROL_awlock;
    wire [2:0] CONTROL_awprot;
    wire [3:0] CONTROL_awqos;
    wire  CONTROL_awready;
    wire [2:0] CONTROL_awsize;
    wire  CONTROL_awvalid;
    wire  CONTROL_bready;
    wire [1:0] CONTROL_bresp;
    wire  CONTROL_bvalid;
    wire [63:0] CONTROL_rdata;
    wire  CONTROL_rlast;
    wire  CONTROL_rready;
    wire [1:0] CONTROL_rresp;
    wire  CONTROL_rvalid;
    wire [63:0] CONTROL_wdata;
    wire  CONTROL_wlast;
    wire  CONTROL_wready;
    wire [7:0] CONTROL_wstrb;
    wire  CONTROL_wvalid;
    rkv_m1_host_ingress #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) ingress (
        .clk(clk),
        .cold_reset(cold_reset),
        .read_grant(read_grant),
        .write_grant(write_grant),
        .memory_idle(memory_idle),
        .memory_accept_now(memory_accept_now),
        .saved_read_grant(saved_read_grant),
        .saved_write_grant(saved_write_grant),
        .fault(fault),
        .fault_code(fault_code),
        .memory_outstanding(memory_outstanding),
        .s_awid(h_awid),
        .s_awaddr(h_awaddr),
        .s_awlen(h_awlen),
        .s_awsize(h_awsize),
        .s_awburst(h_awburst),
        .s_awlock(h_awlock),
        .s_awcache(h_awcache),
        .s_awprot(h_awprot),
        .s_awqos(h_awqos),
        .s_awvalid(h_awvalid),
        .s_awready(h_awready),
        .s_wdata(h_wdata),
        .s_wstrb(h_wstrb),
        .s_wlast(h_wlast),
        .s_wvalid(h_wvalid),
        .s_wready(h_wready),
        .s_bid(h_bid),
        .s_bresp(h_bresp),
        .s_bvalid(h_bvalid),
        .s_bready(h_bready),
        .s_arid(h_arid),
        .s_araddr(h_araddr),
        .s_arlen(h_arlen),
        .s_arsize(h_arsize),
        .s_arburst(h_arburst),
        .s_arlock(h_arlock),
        .s_arcache(h_arcache),
        .s_arprot(h_arprot),
        .s_arqos(h_arqos),
        .s_arvalid(h_arvalid),
        .s_arready(h_arready),
        .s_rid(h_rid),
        .s_rdata(h_rdata),
        .s_rresp(h_rresp),
        .s_rlast(h_rlast),
        .s_rvalid(h_rvalid),
        .s_rready(h_rready),
        .m_awid(root_awid),
        .m_awaddr(root_awaddr),
        .m_awlen(root_awlen),
        .m_awsize(root_awsize),
        .m_awburst(root_awburst),
        .m_awlock(root_awlock),
        .m_awcache(root_awcache),
        .m_awprot(root_awprot),
        .m_awqos(root_awqos),
        .m_awvalid(root_awvalid),
        .m_awready(root_awready),
        .m_wdata(root_wdata),
        .m_wstrb(root_wstrb),
        .m_wlast(root_wlast),
        .m_wvalid(root_wvalid),
        .m_wready(root_wready),
        .m_bid(root_bid),
        .m_bresp(root_bresp),
        .m_bvalid(root_bvalid),
        .m_bready(root_bready),
        .m_arid(root_arid),
        .m_araddr(root_araddr),
        .m_arlen(root_arlen),
        .m_arsize(root_arsize),
        .m_arburst(root_arburst),
        .m_arlock(root_arlock),
        .m_arcache(root_arcache),
        .m_arprot(root_arprot),
        .m_arqos(root_arqos),
        .m_arvalid(root_arvalid),
        .m_arready(root_arready),
        .m_rid(root_rid),
        .m_rdata(root_rdata),
        .m_rresp(root_rresp),
        .m_rlast(root_rlast),
        .m_rvalid(root_rvalid),
        .m_rready(root_rready)
    );
    rkv_m1_host_router router (
        .CONTROL_araddr(CONTROL_araddr),
        .CONTROL_arburst(CONTROL_arburst),
        .CONTROL_arcache(CONTROL_arcache),
        .CONTROL_arlen(CONTROL_arlen),
        .CONTROL_arlock(CONTROL_arlock),
        .CONTROL_arprot(CONTROL_arprot),
        .CONTROL_arqos(CONTROL_arqos),
        .CONTROL_arready(CONTROL_arready),
        .CONTROL_arsize(CONTROL_arsize),
        .CONTROL_arvalid(CONTROL_arvalid),
        .CONTROL_awaddr(CONTROL_awaddr),
        .CONTROL_awburst(CONTROL_awburst),
        .CONTROL_awcache(CONTROL_awcache),
        .CONTROL_awlen(CONTROL_awlen),
        .CONTROL_awlock(CONTROL_awlock),
        .CONTROL_awprot(CONTROL_awprot),
        .CONTROL_awqos(CONTROL_awqos),
        .CONTROL_awready(CONTROL_awready),
        .CONTROL_awsize(CONTROL_awsize),
        .CONTROL_awvalid(CONTROL_awvalid),
        .CONTROL_bready(CONTROL_bready),
        .CONTROL_bresp(CONTROL_bresp),
        .CONTROL_bvalid(CONTROL_bvalid),
        .CONTROL_rdata(CONTROL_rdata),
        .CONTROL_rlast(CONTROL_rlast),
        .CONTROL_rready(CONTROL_rready),
        .CONTROL_rresp(CONTROL_rresp),
        .CONTROL_rvalid(CONTROL_rvalid),
        .CONTROL_wdata(CONTROL_wdata),
        .CONTROL_wlast(CONTROL_wlast),
        .CONTROL_wready(CONTROL_wready),
        .CONTROL_wstrb(CONTROL_wstrb),
        .CONTROL_wvalid(CONTROL_wvalid),
        .DDR_araddr(d_araddr),
        .DDR_arburst(d_arburst),
        .DDR_arcache(d_arcache),
        .DDR_arlen(d_arlen),
        .DDR_arlock(d_arlock),
        .DDR_arprot(d_arprot),
        .DDR_arqos(d_arqos),
        .DDR_arready(d_arready),
        .DDR_arsize(d_arsize),
        .DDR_arvalid(d_arvalid),
        .DDR_awaddr(d_awaddr),
        .DDR_awburst(d_awburst),
        .DDR_awcache(d_awcache),
        .DDR_awlen(d_awlen),
        .DDR_awlock(d_awlock),
        .DDR_awprot(d_awprot),
        .DDR_awqos(d_awqos),
        .DDR_awready(d_awready),
        .DDR_awsize(d_awsize),
        .DDR_awvalid(d_awvalid),
        .DDR_bready(d_bready),
        .DDR_bresp(d_bresp),
        .DDR_bvalid(d_bvalid),
        .DDR_rdata(d_rdata),
        .DDR_rlast(d_rlast),
        .DDR_rready(d_rready),
        .DDR_rresp(d_rresp),
        .DDR_rvalid(d_rvalid),
        .DDR_wdata(d_wdata),
        .DDR_wlast(d_wlast),
        .DDR_wready(d_wready),
        .DDR_wstrb(d_wstrb),
        .DDR_wvalid(d_wvalid),
        .HOST_araddr(root_araddr),
        .HOST_arburst(root_arburst),
        .HOST_arcache(root_arcache),
        .HOST_arid(root_arid),
        .HOST_arlen(root_arlen),
        .HOST_arlock(root_arlock),
        .HOST_arprot(root_arprot),
        .HOST_arqos(root_arqos),
        .HOST_arready(root_arready),
        .HOST_arsize(root_arsize),
        .HOST_arvalid(root_arvalid),
        .HOST_awaddr(root_awaddr),
        .HOST_awburst(root_awburst),
        .HOST_awcache(root_awcache),
        .HOST_awid(root_awid),
        .HOST_awlen(root_awlen),
        .HOST_awlock(root_awlock),
        .HOST_awprot(root_awprot),
        .HOST_awqos(root_awqos),
        .HOST_awready(root_awready),
        .HOST_awsize(root_awsize),
        .HOST_awvalid(root_awvalid),
        .HOST_bid(root_bid),
        .HOST_bready(root_bready),
        .HOST_bresp(root_bresp),
        .HOST_bvalid(root_bvalid),
        .HOST_rdata(root_rdata),
        .HOST_rid(root_rid),
        .HOST_rlast(root_rlast),
        .HOST_rready(root_rready),
        .HOST_rresp(root_rresp),
        .HOST_rvalid(root_rvalid),
        .HOST_wdata(root_wdata),
        .HOST_wlast(root_wlast),
        .HOST_wready(root_wready),
        .HOST_wstrb(root_wstrb),
        .HOST_wvalid(root_wvalid),
        .core_aresetn(!cold_reset),
        .core_clk(clk)
    );

    rkv_m1_host_control #(
        .EXPERIMENT_ID(EXPERIMENT_ID)
    ) control (
        .clk(clk),
        .cold_reset(cold_reset),
        .platform_ready(platform_ready),
        .platform_error(platform_error),
        .ddr_idle(ddr_idle && memory_idle),
        .ddr_accept_now(ddr_accept_now || memory_accept_now),
        .status_flags(status_flags),
        .epoch(epoch),
        .generation(generation),
        .error_code(error_code),
        .host_verified(host_verified),
        .native_verified(native_verified),
        .accepted_reads(accepted_reads),
        .accepted_writes(accepted_writes),
        .rejected_requests(rejected_requests),
        .boot_hold(boot_hold),
        .reset_request(reset_request),
        .control_idle(control_idle),
        .control_requests(control_requests),
        .host_valid(host_valid),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_wstrb(host_wstrb),
        .host_ready(host_ready),
        .host_rdata(host_rdata),
        .host_error(host_error),
        .s_awid(4'd0),
        .s_awaddr(CONTROL_awaddr),
        .s_awlen(CONTROL_awlen),
        .s_awsize(CONTROL_awsize),
        .s_awburst(CONTROL_awburst),
        .s_awlock(CONTROL_awlock),
        .s_awvalid(CONTROL_awvalid),
        .s_awready(CONTROL_awready),
        .s_wdata(CONTROL_wdata),
        .s_wstrb(CONTROL_wstrb),
        .s_wlast(CONTROL_wlast),
        .s_wvalid(CONTROL_wvalid),
        .s_wready(CONTROL_wready),
        .s_bid(),
        .s_bresp(CONTROL_bresp),
        .s_bvalid(CONTROL_bvalid),
        .s_bready(CONTROL_bready),
        .s_arid(4'd0),
        .s_araddr(CONTROL_araddr),
        .s_arlen(CONTROL_arlen),
        .s_arsize(CONTROL_arsize),
        .s_arburst(CONTROL_arburst),
        .s_arlock(CONTROL_arlock),
        .s_arvalid(CONTROL_arvalid),
        .s_arready(CONTROL_arready),
        .s_rid(),
        .s_rdata(CONTROL_rdata),
        .s_rresp(CONTROL_rresp),
        .s_rlast(CONTROL_rlast),
        .s_rvalid(CONTROL_rvalid),
        .s_rready(CONTROL_rready)
    );
endmodule
