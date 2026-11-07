// 实际native桥＋异步AXI IP＋冷复位/故障监督；MIG/主机尚在此模块之外。
// native向量按bit低位为channel0展平，与原packed端口一一对应。
module rkv_m1_native_axi_cdc #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000
) (
    input wire core_clk,
    input wire ddr_clk,
    input wire chain_cold_reset,
    input wire core_locked,
    input wire ddr_locked,
    input wire ddr_calibrated,
    output wire core_cold_reset,
    output wire ddr_axi_aresetn,
    output wire transport_ready,
    output wire admission_enable,
    output wire guard_armed,
    output wire [3:0] fault_causes,
    output wire platform_error,
    output wire bridge_idle,
    output wire bridge_fault,
    output wire [31:0] bridge_fault_code,
    output wire [63:0] verified_writes,
    input wire [1:0] n_cvalid,
    output wire [1:0] n_cready,
    input wire [1:0] n_cwe,
    input wire [49:0] n_caddr,
    input wire [1:0] n_wvalid,
    output wire [1:0] n_wready,
    input wire [1023:0] n_wdata,
    input wire [127:0] n_wmask,
    output wire [1:0] n_rvalid,
    output wire [1023:0] n_rdata,
    output wire [31:0] n_wdone,
    output wire [3:0] m_awid,
    output wire [32:0] m_awaddr,
    output wire [7:0] m_awlen,
    output wire [2:0] m_awsize,
    output wire [1:0] m_awburst,
    output wire m_awlock,
    output wire [3:0] m_awcache,
    output wire [2:0] m_awprot,
    output wire [3:0] m_awqos,
    output wire m_awvalid,
    input wire m_awready,
    output wire [511:0] m_wdata,
    output wire [63:0] m_wstrb,
    output wire m_wlast,
    output wire m_wvalid,
    input wire m_wready,
    input wire [3:0] m_bid,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    output wire m_bready,
    output wire [3:0] m_arid,
    output wire [32:0] m_araddr,
    output wire [7:0] m_arlen,
    output wire [2:0] m_arsize,
    output wire [1:0] m_arburst,
    output wire m_arlock,
    output wire [3:0] m_arcache,
    output wire [2:0] m_arprot,
    output wire [3:0] m_arqos,
    output wire m_arvalid,
    input wire m_arready,
    input wire [3:0] m_rid,
    input wire [511:0] m_rdata,
    input wire [1:0] m_rresp,
    input wire m_rlast,
    input wire m_rvalid,
    output wire m_rready
);
    wire core_axi_aresetn;
    wire clock_fault;
    wire [3:0] s_awid;
    wire [32:0] s_awaddr;
    wire [7:0] s_awlen;
    wire [2:0] s_awsize;
    wire [1:0] s_awburst;
    wire s_awlock;
    wire [3:0] s_awcache;
    wire [2:0] s_awprot;
    wire [3:0] s_awqos;
    wire s_awvalid;
    wire s_awready;
    wire [511:0] s_wdata;
    wire [63:0] s_wstrb;
    wire s_wlast;
    wire s_wvalid;
    wire s_wready;
    wire [3:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    wire s_bready;
    wire [3:0] s_arid;
    wire [32:0] s_araddr;
    wire [7:0] s_arlen;
    wire [2:0] s_arsize;
    wire [1:0] s_arburst;
    wire s_arlock;
    wire [3:0] s_arcache;
    wire [2:0] s_arprot;
    wire [3:0] s_arqos;
    wire s_arvalid;
    wire s_arready;
    wire [3:0] s_rid;
    wire [511:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    wire s_rready;

    // 整链冷复位覆盖CDC两端；普通任务/CPU复位不进入此路径。
    rkv_m1_axi_reset reset_coord (
        .core_clk(core_clk),
        .ddr_clk(ddr_clk),
        .chain_cold_reset(chain_cold_reset),
        .core_aresetn(core_axi_aresetn),
        .ddr_aresetn(ddr_axi_aresetn),
        .core_cold_reset(core_cold_reset),
        .transport_ready(transport_ready)
    );

    // 实际锁定/校准撤回只锁存隔离，绝不自动复位CDC或计数。
    rkv_m1_clock_guard guard (
        .core_clk(core_clk),
        .chain_cold_reset(core_cold_reset),
        .core_locked(core_locked),
        .ddr_locked(ddr_locked),
        .ddr_calibrated(ddr_calibrated),
        .transport_ready(transport_ready),
        .admission_enable(admission_enable),
        .fault(clock_fault),
        .fault_causes(fault_causes),
        .armed(guard_armed)
    );
    assign platform_error = clock_fault || bridge_fault;

    // 退休与单在途事务仍属于core域桥接；AXI master端在DDR时钟域。
    rkv_m1_native_axi #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) bridge (
        .clk(core_clk),
        .cold_reset(core_cold_reset),
        .admission_enable(admission_enable),
        .external_fault(clock_fault),
        .n_cvalid(n_cvalid),
        .n_cready(n_cready),
        .n_cwe(n_cwe),
        .n_caddr(n_caddr),
        .n_wvalid(n_wvalid),
        .n_wready(n_wready),
        .n_wdata(n_wdata),
        .n_wmask(n_wmask),
        .n_rvalid(n_rvalid),
        .n_rdata(n_rdata),
        .n_wdone(n_wdone),
        .idle(bridge_idle),
        .fault(bridge_fault),
        .fault_code(bridge_fault_code),
        .verified_writes(verified_writes),
        .m_awid(s_awid),
        .m_awaddr(s_awaddr),
        .m_awlen(s_awlen),
        .m_awsize(s_awsize),
        .m_awburst(s_awburst),
        .m_awlock(s_awlock),
        .m_awcache(s_awcache),
        .m_awprot(s_awprot),
        .m_awqos(s_awqos),
        .m_awvalid(s_awvalid),
        .m_awready(s_awready),
        .m_wdata(s_wdata),
        .m_wstrb(s_wstrb),
        .m_wlast(s_wlast),
        .m_wvalid(s_wvalid),
        .m_wready(s_wready),
        .m_bid(s_bid),
        .m_bresp(s_bresp),
        .m_bvalid(s_bvalid),
        .m_bready(s_bready),
        .m_arid(s_arid),
        .m_araddr(s_araddr),
        .m_arlen(s_arlen),
        .m_arsize(s_arsize),
        .m_arburst(s_arburst),
        .m_arlock(s_arlock),
        .m_arcache(s_arcache),
        .m_arprot(s_arprot),
        .m_arqos(s_arqos),
        .m_arvalid(s_arvalid),
        .m_arready(s_arready),
        .m_rid(s_rid),
        .m_rdata(s_rdata),
        .m_rresp(s_rresp),
        .m_rlast(s_rlast),
        .m_rvalid(s_rvalid),
        .m_rready(s_rready)
    );

    // 固定512/33/4-bit、异步模式；REGION固定0且不参与本2GiB线性映射。
    rkv_m1_axi_clock_converter crossing (
        .s_axi_aclk(core_clk),
        .s_axi_aresetn(core_axi_aresetn),
        .m_axi_aclk(ddr_clk),
        .m_axi_aresetn(ddr_axi_aresetn),
        .s_axi_awregion(4'd0),
        .s_axi_arregion(4'd0),
        .m_axi_awregion(),
        .m_axi_arregion(),
        .s_axi_awid(s_awid),
        .s_axi_awaddr(s_awaddr),
        .s_axi_awlen(s_awlen),
        .s_axi_awsize(s_awsize),
        .s_axi_awburst(s_awburst),
        .s_axi_awlock(s_awlock),
        .s_axi_awcache(s_awcache),
        .s_axi_awprot(s_awprot),
        .s_axi_awqos(s_awqos),
        .s_axi_awvalid(s_awvalid),
        .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata),
        .s_axi_wstrb(s_wstrb),
        .s_axi_wlast(s_wlast),
        .s_axi_wvalid(s_wvalid),
        .s_axi_wready(s_wready),
        .s_axi_bid(s_bid),
        .s_axi_bresp(s_bresp),
        .s_axi_bvalid(s_bvalid),
        .s_axi_bready(s_bready),
        .s_axi_arid(s_arid),
        .s_axi_araddr(s_araddr),
        .s_axi_arlen(s_arlen),
        .s_axi_arsize(s_arsize),
        .s_axi_arburst(s_arburst),
        .s_axi_arlock(s_arlock),
        .s_axi_arcache(s_arcache),
        .s_axi_arprot(s_arprot),
        .s_axi_arqos(s_arqos),
        .s_axi_arvalid(s_arvalid),
        .s_axi_arready(s_arready),
        .s_axi_rid(s_rid),
        .s_axi_rdata(s_rdata),
        .s_axi_rresp(s_rresp),
        .s_axi_rlast(s_rlast),
        .s_axi_rvalid(s_rvalid),
        .s_axi_rready(s_rready),
        .m_axi_awid(m_awid),
        .m_axi_awaddr(m_awaddr),
        .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst),
        .m_axi_awlock(m_awlock),
        .m_axi_awcache(m_awcache),
        .m_axi_awprot(m_awprot),
        .m_axi_awqos(m_awqos),
        .m_axi_awvalid(m_awvalid),
        .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata),
        .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast),
        .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),
        .m_axi_bid(m_bid),
        .m_axi_bresp(m_bresp),
        .m_axi_bvalid(m_bvalid),
        .m_axi_bready(m_bready),
        .m_axi_arid(m_arid),
        .m_axi_araddr(m_araddr),
        .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize),
        .m_axi_arburst(m_arburst),
        .m_axi_arlock(m_arlock),
        .m_axi_arcache(m_arcache),
        .m_axi_arprot(m_arprot),
        .m_axi_arqos(m_arqos),
        .m_axi_arvalid(m_arvalid),
        .m_axi_arready(m_arready),
        .m_axi_rid(m_rid),
        .m_axi_rdata(m_rdata),
        .m_axi_rresp(m_rresp),
        .m_axi_rlast(m_rlast),
        .m_axi_rvalid(m_rvalid),
        .m_axi_rready(m_rready)
    );
endmodule
