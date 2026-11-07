// 主机门控/native桥＋真实SmartConnect＋异步CDC；控制窗口和完整native缓存另层接入。
// 两主身份在SmartConnect内保存，统一下游ID0；异常ID在丢弃字段前捕获并隔离。
module rkv_m1_shared_axi #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000
) (
    input wire core_clk,
    input wire ddr_clk,
    input wire chain_cold_reset,
    input wire core_locked,
    input wire ddr_locked,
    input wire ddr_calibrated,
    input wire external_fault,
    input wire host_read_grant,
    input wire host_write_grant,
    input wire native_grant,
    output wire control_cold_reset,
    output wire core_cold_reset,
    output wire ddr_axi_aresetn,
    output wire transport_ready,
    output wire admission_enable,
    output wire guard_armed,
    output wire [3:0] fault_causes,
    output wire platform_error,
    output wire host_idle,
    output wire bridge_idle,
    output wire shared_idle,
    output wire host_fault,
    output wire [31:0] host_fault_code,
    output wire bridge_fault,
    output wire [31:0] bridge_fault_code,
    output reg route_fault,
    output wire [63:0] host_verified_beats,
    output wire [63:0] native_verified_writes,
    output wire [63:0] accepted_reads,
    output wire [63:0] accepted_writes,
    output wire [63:0] rejected_requests,
    input wire [3:0] h_awid,
    input wire [31:0] h_awaddr,
    input wire [7:0] h_awlen,
    input wire [2:0] h_awsize,
    input wire [1:0] h_awburst,
    input wire h_awlock,
    input wire [3:0] h_awcache,
    input wire [2:0] h_awprot,
    input wire [3:0] h_awqos,
    input wire h_awvalid,
    output wire h_awready,
    input wire [63:0] h_wdata,
    input wire [7:0] h_wstrb,
    input wire h_wlast,
    input wire h_wvalid,
    output wire h_wready,
    output wire [3:0] h_bid,
    output wire [1:0] h_bresp,
    output wire h_bvalid,
    input wire h_bready,
    input wire [3:0] h_arid,
    input wire [31:0] h_araddr,
    input wire [7:0] h_arlen,
    input wire [2:0] h_arsize,
    input wire [1:0] h_arburst,
    input wire h_arlock,
    input wire [3:0] h_arcache,
    input wire [2:0] h_arprot,
    input wire [3:0] h_arqos,
    input wire h_arvalid,
    output wire h_arready,
    output wire [3:0] h_rid,
    output wire [63:0] h_rdata,
    output wire [1:0] h_rresp,
    output wire h_rlast,
    output wire h_rvalid,
    input wire h_rready,
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
    wire route_error_now;
    wire common_fault;
    wire guard_admission;
    wire [3:0] host_awid;
    wire [31:0] host_awaddr;
    wire [7:0] host_awlen;
    wire [2:0] host_awsize;
    wire [1:0] host_awburst;
    wire host_awlock;
    wire [3:0] host_awcache;
    wire [2:0] host_awprot;
    wire [3:0] host_awqos;
    wire host_awvalid;
    wire host_awready;
    wire [63:0] host_wdata;
    wire [7:0] host_wstrb;
    wire host_wlast;
    wire host_wvalid;
    wire host_wready;
    wire [3:0] host_bid;
    wire [1:0] host_bresp;
    wire host_bvalid;
    wire host_bready;
    wire [3:0] host_arid;
    wire [31:0] host_araddr;
    wire [7:0] host_arlen;
    wire [2:0] host_arsize;
    wire [1:0] host_arburst;
    wire host_arlock;
    wire [3:0] host_arcache;
    wire [2:0] host_arprot;
    wire [3:0] host_arqos;
    wire host_arvalid;
    wire host_arready;
    wire [3:0] host_rid;
    wire [63:0] host_rdata;
    wire [1:0] host_rresp;
    wire host_rlast;
    wire host_rvalid;
    wire host_rready;
    wire [3:0] native_awid;
    wire [32:0] native_awaddr;
    wire [7:0] native_awlen;
    wire [2:0] native_awsize;
    wire [1:0] native_awburst;
    wire native_awlock;
    wire [3:0] native_awcache;
    wire [2:0] native_awprot;
    wire [3:0] native_awqos;
    wire native_awvalid;
    wire native_awready;
    wire [511:0] native_wdata;
    wire [63:0] native_wstrb;
    wire native_wlast;
    wire native_wvalid;
    wire native_wready;
    wire [3:0] native_bid;
    wire [1:0] native_bresp;
    wire native_bvalid;
    wire native_bready;
    wire [3:0] native_arid;
    wire [32:0] native_araddr;
    wire [7:0] native_arlen;
    wire [2:0] native_arsize;
    wire [1:0] native_arburst;
    wire native_arlock;
    wire [3:0] native_arcache;
    wire [2:0] native_arprot;
    wire [3:0] native_arqos;
    wire native_arvalid;
    wire native_arready;
    wire [3:0] native_rid;
    wire [511:0] native_rdata;
    wire [1:0] native_rresp;
    wire native_rlast;
    wire native_rvalid;
    wire native_rready;
    wire [3:0] bus_awid;
    wire [32:0] bus_awaddr;
    wire [7:0] bus_awlen;
    wire [2:0] bus_awsize;
    wire [1:0] bus_awburst;
    wire bus_awlock;
    wire [3:0] bus_awcache;
    wire [2:0] bus_awprot;
    wire [3:0] bus_awqos;
    wire bus_awvalid;
    wire bus_awready;
    wire [511:0] bus_wdata;
    wire [63:0] bus_wstrb;
    wire bus_wlast;
    wire bus_wvalid;
    wire bus_wready;
    wire [3:0] bus_bid;
    wire [1:0] bus_bresp;
    wire bus_bvalid;
    wire bus_bready;
    wire [3:0] bus_arid;
    wire [32:0] bus_araddr;
    wire [7:0] bus_arlen;
    wire [2:0] bus_arsize;
    wire [1:0] bus_arburst;
    wire bus_arlock;
    wire [3:0] bus_arcache;
    wire [2:0] bus_arprot;
    wire [3:0] bus_arqos;
    wire bus_arvalid;
    wire bus_arready;
    wire [3:0] bus_rid;
    wire [511:0] bus_rdata;
    wire [1:0] bus_rresp;
    wire bus_rlast;
    wire bus_rvalid;
    wire bus_rready;

    // 只有整链cold清队列；运行健康撤回经监督隔离，保持既有AXI握手责任。
    rkv_m1_control_reset control_reset (
        .core_clk(core_clk),
        .chain_cold_reset(chain_cold_reset),
        .control_aresetn(),
        .control_cold_reset(control_cold_reset)
    );
    rkv_m1_axi_reset reset_coord (
        .core_clk(core_clk),
        .ddr_clk(ddr_clk),
        .chain_cold_reset(chain_cold_reset),
        .core_aresetn(core_axi_aresetn),
        .ddr_aresetn(ddr_axi_aresetn),
        .core_cold_reset(core_cold_reset),
        .transport_ready(transport_ready)
    );
    rkv_m1_clock_guard guard (
        .core_clk(core_clk),
        .chain_cold_reset(core_cold_reset),
        .core_locked(core_locked),
        .ddr_locked(ddr_locked),
        .ddr_calibrated(ddr_calibrated),
        .transport_ready(transport_ready),
        .fault_causes(fault_causes),
        .admission_enable(guard_admission),
        .fault(clock_fault),
        .armed(guard_armed)
    );
    // 厂商多拍输出必须已打包为64-byte；单拍允许SIZE<=6，后面只为普通DDR扩展。
    assign route_error_now = (bus_bvalid && bus_bid != 4'd0) ||
        (bus_rvalid && bus_rid != 4'd0) ||
        (bus_awvalid && (bus_awsize > 3'd6 || (bus_awlen != 8'd0 && bus_awsize != 3'd6))) ||
        (bus_arvalid && (bus_arsize > 3'd6 || (bus_arlen != 8'd0 && bus_arsize != 3'd6)));
    assign common_fault = external_fault || clock_fault || route_fault || route_error_now || host_fault || bridge_fault;
    assign platform_error = common_fault;
    assign admission_enable = guard_admission && !common_fault;
    assign shared_idle = admission_enable && host_idle && bridge_idle;

    // CDC返回ID尚在core边界可见；同沿错误直接阻断两入口成功，粘滞位保留至cold。
    always @(posedge core_clk) begin
        if (core_cold_reset) route_fault <= 1'b0;
        else if (route_error_now) route_fault <= 1'b1;
    end

    rkv_m1_host_ddr #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) host_gate (
        .clk(core_clk),
        .cold_reset(control_cold_reset),
        .external_fault(common_fault),
        .read_grant(host_read_grant && admission_enable),
        .write_grant(host_write_grant && admission_enable),
        .host_idle(host_idle),
        .fault(host_fault),
        .fault_code(host_fault_code),
        .accepted_reads(accepted_reads),
        .accepted_writes(accepted_writes),
        .rejected_requests(rejected_requests),
        .verified_write_beats(host_verified_beats),
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
        .m_awid(host_awid),
        .m_awaddr(host_awaddr),
        .m_awlen(host_awlen),
        .m_awsize(host_awsize),
        .m_awburst(host_awburst),
        .m_awlock(host_awlock),
        .m_awcache(host_awcache),
        .m_awprot(host_awprot),
        .m_awqos(host_awqos),
        .m_awvalid(host_awvalid),
        .m_awready(host_awready),
        .m_wdata(host_wdata),
        .m_wstrb(host_wstrb),
        .m_wlast(host_wlast),
        .m_wvalid(host_wvalid),
        .m_wready(host_wready),
        .m_bid(host_bid),
        .m_bresp(host_bresp),
        .m_bvalid(host_bvalid),
        .m_bready(host_bready),
        .m_arid(host_arid),
        .m_araddr(host_araddr),
        .m_arlen(host_arlen),
        .m_arsize(host_arsize),
        .m_arburst(host_arburst),
        .m_arlock(host_arlock),
        .m_arcache(host_arcache),
        .m_arprot(host_arprot),
        .m_arqos(host_arqos),
        .m_arvalid(host_arvalid),
        .m_arready(host_arready),
        .m_rid(host_rid),
        .m_rdata(host_rdata),
        .m_rresp(host_rresp),
        .m_rlast(host_rlast),
        .m_rvalid(host_rvalid),
        .m_rready(host_rready)
    );
    rkv_m1_native_axi #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) bridge (
        .clk(core_clk),
        .cold_reset(core_cold_reset),
        .admission_enable(native_grant && admission_enable),
        .external_fault(common_fault),
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
        .verified_writes(native_verified_writes),
        .m_awid(native_awid),
        .m_awaddr(native_awaddr),
        .m_awlen(native_awlen),
        .m_awsize(native_awsize),
        .m_awburst(native_awburst),
        .m_awlock(native_awlock),
        .m_awcache(native_awcache),
        .m_awprot(native_awprot),
        .m_awqos(native_awqos),
        .m_awvalid(native_awvalid),
        .m_awready(native_awready),
        .m_wdata(native_wdata),
        .m_wstrb(native_wstrb),
        .m_wlast(native_wlast),
        .m_wvalid(native_wvalid),
        .m_wready(native_wready),
        .m_bid(native_bid),
        .m_bresp(native_bresp),
        .m_bvalid(native_bvalid),
        .m_bready(native_bready),
        .m_arid(native_arid),
        .m_araddr(native_araddr),
        .m_arlen(native_arlen),
        .m_arsize(native_arsize),
        .m_arburst(native_arburst),
        .m_arlock(native_arlock),
        .m_arcache(native_arcache),
        .m_arprot(native_arprot),
        .m_arqos(native_arqos),
        .m_arvalid(native_arvalid),
        .m_arready(native_arready),
        .m_rid(native_rid),
        .m_rdata(native_rdata),
        .m_rresp(native_rresp),
        .m_rlast(native_rlast),
        .m_rvalid(native_rvalid),
        .m_rready(native_rready)
    );

    // 实际BD导出无MEMORY ID端口；保留SI全部4位身份并由厂商队列还原返回。
    rkv_m1_axi_fabric fabric (
        .core_clk(core_clk),
        .core_aresetn(core_axi_aresetn),
        .HOST_awid(host_awid),
        .HOST_awaddr(host_awaddr),
        .HOST_awlen(host_awlen),
        .HOST_awsize(host_awsize),
        .HOST_awburst(host_awburst),
        .HOST_awlock(host_awlock),
        .HOST_awcache(host_awcache),
        .HOST_awprot(host_awprot),
        .HOST_awqos(host_awqos),
        .HOST_awvalid(host_awvalid),
        .HOST_awready(host_awready),
        .HOST_wdata(host_wdata),
        .HOST_wstrb(host_wstrb),
        .HOST_wlast(host_wlast),
        .HOST_wvalid(host_wvalid),
        .HOST_wready(host_wready),
        .HOST_bid(host_bid),
        .HOST_bresp(host_bresp),
        .HOST_bvalid(host_bvalid),
        .HOST_bready(host_bready),
        .HOST_arid(host_arid),
        .HOST_araddr(host_araddr),
        .HOST_arlen(host_arlen),
        .HOST_arsize(host_arsize),
        .HOST_arburst(host_arburst),
        .HOST_arlock(host_arlock),
        .HOST_arcache(host_arcache),
        .HOST_arprot(host_arprot),
        .HOST_arqos(host_arqos),
        .HOST_arvalid(host_arvalid),
        .HOST_arready(host_arready),
        .HOST_rid(host_rid),
        .HOST_rdata(host_rdata),
        .HOST_rresp(host_rresp),
        .HOST_rlast(host_rlast),
        .HOST_rvalid(host_rvalid),
        .HOST_rready(host_rready),
        .NATIVE_awid(native_awid),
        .NATIVE_awaddr(native_awaddr),
        .NATIVE_awlen(native_awlen),
        .NATIVE_awsize(native_awsize),
        .NATIVE_awburst(native_awburst),
        .NATIVE_awlock(native_awlock),
        .NATIVE_awcache(native_awcache),
        .NATIVE_awprot(native_awprot),
        .NATIVE_awqos(native_awqos),
        .NATIVE_awvalid(native_awvalid),
        .NATIVE_awready(native_awready),
        .NATIVE_wdata(native_wdata),
        .NATIVE_wstrb(native_wstrb),
        .NATIVE_wlast(native_wlast),
        .NATIVE_wvalid(native_wvalid),
        .NATIVE_wready(native_wready),
        .NATIVE_bid(native_bid),
        .NATIVE_bresp(native_bresp),
        .NATIVE_bvalid(native_bvalid),
        .NATIVE_bready(native_bready),
        .NATIVE_arid(native_arid),
        .NATIVE_araddr(native_araddr),
        .NATIVE_arlen(native_arlen),
        .NATIVE_arsize(native_arsize),
        .NATIVE_arburst(native_arburst),
        .NATIVE_arlock(native_arlock),
        .NATIVE_arcache(native_arcache),
        .NATIVE_arprot(native_arprot),
        .NATIVE_arqos(native_arqos),
        .NATIVE_arvalid(native_arvalid),
        .NATIVE_arready(native_arready),
        .NATIVE_rid(native_rid),
        .NATIVE_rdata(native_rdata),
        .NATIVE_rresp(native_rresp),
        .NATIVE_rlast(native_rlast),
        .NATIVE_rvalid(native_rvalid),
        .NATIVE_rready(native_rready),
        .MEMORY_awaddr(bus_awaddr),
        .MEMORY_awlen(bus_awlen),
        .MEMORY_awsize(bus_awsize),
        .MEMORY_awburst(bus_awburst),
        .MEMORY_awlock(bus_awlock),
        .MEMORY_awcache(bus_awcache),
        .MEMORY_awprot(bus_awprot),
        .MEMORY_awqos(bus_awqos),
        .MEMORY_awvalid(bus_awvalid),
        .MEMORY_awready(bus_awready),
        .MEMORY_wdata(bus_wdata),
        .MEMORY_wstrb(bus_wstrb),
        .MEMORY_wlast(bus_wlast),
        .MEMORY_wvalid(bus_wvalid),
        .MEMORY_wready(bus_wready),
        .MEMORY_bresp(bus_bresp),
        .MEMORY_bvalid(bus_bvalid),
        .MEMORY_bready(bus_bready),
        .MEMORY_araddr(bus_araddr),
        .MEMORY_arlen(bus_arlen),
        .MEMORY_arsize(bus_arsize),
        .MEMORY_arburst(bus_arburst),
        .MEMORY_arlock(bus_arlock),
        .MEMORY_arcache(bus_arcache),
        .MEMORY_arprot(bus_arprot),
        .MEMORY_arqos(bus_arqos),
        .MEMORY_arvalid(bus_arvalid),
        .MEMORY_arready(bus_arready),
        .MEMORY_rdata(bus_rdata),
        .MEMORY_rresp(bus_rresp),
        .MEMORY_rlast(bus_rlast),
        .MEMORY_rvalid(bus_rvalid),
        .MEMORY_rready(bus_rready)
    );
    assign bus_awid = 4'd0;
    assign bus_arid = 4'd0;

    // 全宽512-bit/33地址/4ID的真实异步IP；REGION固定0。
    // SmartConnect保留窄单拍SIZE，且多拍首地址可能未按64-byte对齐。
    // 这里的地址只能是普通DDR：向下对齐64-byte并固定SIZE6，LEN和byte-strobe不变。
    // 因而写副作用仍严格由原掩码界定，读可多取同一64-byte块内数据；MMIO禁止接此处。
    rkv_m1_axi_clock_converter crossing (
        .s_axi_aclk(core_clk),
        .s_axi_aresetn(core_axi_aresetn),
        .m_axi_aclk(ddr_clk),
        .m_axi_aresetn(ddr_axi_aresetn),
        .s_axi_awregion(4'd0),
        .s_axi_arregion(4'd0),
        .m_axi_awregion(),
        .m_axi_arregion(),
        .s_axi_awid(bus_awid),
        .s_axi_awaddr({bus_awaddr[32:6], 6'd0}),
        .s_axi_awlen(bus_awlen),
        .s_axi_awsize(3'd6),
        .s_axi_awburst(bus_awburst),
        .s_axi_awlock(bus_awlock),
        .s_axi_awcache(bus_awcache),
        .s_axi_awprot(bus_awprot),
        .s_axi_awqos(bus_awqos),
        .s_axi_awvalid(bus_awvalid),
        .s_axi_awready(bus_awready),
        .s_axi_wdata(bus_wdata),
        .s_axi_wstrb(bus_wstrb),
        .s_axi_wlast(bus_wlast),
        .s_axi_wvalid(bus_wvalid),
        .s_axi_wready(bus_wready),
        .s_axi_bid(bus_bid),
        .s_axi_bresp(bus_bresp),
        .s_axi_bvalid(bus_bvalid),
        .s_axi_bready(bus_bready),
        .s_axi_arid(bus_arid),
        .s_axi_araddr({bus_araddr[32:6], 6'd0}),
        .s_axi_arlen(bus_arlen),
        .s_axi_arsize(3'd6),
        .s_axi_arburst(bus_arburst),
        .s_axi_arlock(bus_arlock),
        .s_axi_arcache(bus_arcache),
        .s_axi_arprot(bus_arprot),
        .s_axi_arqos(bus_arqos),
        .s_axi_arvalid(bus_arvalid),
        .s_axi_arready(bus_arready),
        .s_axi_rid(bus_rid),
        .s_axi_rdata(bus_rdata),
        .s_axi_rresp(bus_rresp),
        .s_axi_rlast(bus_rlast),
        .s_axi_rvalid(bus_rvalid),
        .s_axi_rready(bus_rready),
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
