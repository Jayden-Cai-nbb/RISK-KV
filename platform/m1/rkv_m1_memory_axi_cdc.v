// 实际openTPU原生适配器接AXI异步传输；DDR/主机仲裁在本模块之外。
// 普通run_flush只失效缓存；所有在途、退休、CDC只由可信整链cold清除。
module rkv_m1_memory_axi_cdc #(
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
    output wire m_rready,
    input wire run_flush,
    input wire cache_flush,
    output wire cache_flush_ack,
    output wire transport_idle,
    output wire transport_error,
    output wire mem_wr_idle,
    output wire mem_rd_idle,
    input wire mem_a_req,
    input wire mem_a_we,
    input wire [31:0] mem_a_addr,
    input wire [31:0] mem_a_wdata,
    input wire [3:0] mem_a_be,
    output wire mem_a_rdy,
    output wire mem_a_rvalid,
    output wire [255:0] mem_a_rdata,
    input wire mem_sw_req,
    input wire [31:0] mem_sw_addr,
    input wire [31:0] mem_sw_wdata,
    input wire [3:0] mem_sw_be,
    output wire mem_sw_rdy,
    input wire mem_b_req,
    input wire mem_b_we,
    input wire mem_b_tag,
    input wire mem_b_par,
    input wire [31:0] mem_b_addr,
    input wire [1023:0] mem_b_wdata,
    input wire [31:0] mem_b_wmask,
    output wire mem_b_rdy,
    output wire mem_b_rvalid,
    output wire mem_b_rtag,
    output wire [1023:0] mem_b_rdata
);
    wire [1:0] n_cvalid;
    wire [1:0] n_cready;
    wire [1:0] n_cwe;
    wire [49:0] n_caddr;
    wire [1:0] n_wvalid;
    wire [1:0] n_wready;
    wire [1023:0] n_wdata;
    wire [127:0] n_wmask;
    wire [1:0] n_rvalid;
    wire [1023:0] n_rdata;
    wire [31:0] n_wdone;
    wire native_transport_idle;
    wire native_transport_error;
    wire native_flush_ack;
    wire native_a_rdy;
    wire native_b_rdy;
    wire native_sw_rdy;
    wire request_enable;

    // 新请求和返回是不同边界；只阻止新请求，已有数据/事务不因运行复位丢弃。
    assign request_enable = admission_enable && !native_transport_error;
    assign transport_error = native_transport_error;
    assign transport_idle = native_transport_idle && bridge_idle && request_enable;
    assign cache_flush_ack = native_flush_ack && transport_idle;
    assign mem_a_rdy = native_a_rdy && request_enable;
    assign mem_b_rdy = native_b_rdy && request_enable;
    assign mem_sw_rdy = native_sw_rdy && request_enable;

    // 缓存、预取、聚合以及原生接受/退休监督都保持原实现与core时钟。
    rkv_m1_native_memory native_memory (
        .clk(core_clk),
        .cold_reset(core_cold_reset),
        .run_flush(run_flush),
        .cache_flush(cache_flush),
        .cache_flush_ack(native_flush_ack),
        .transport_idle(native_transport_idle),
        .transport_error(native_transport_error),
        .platform_error(platform_error),
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
        .mem_wr_idle(mem_wr_idle),
        .mem_rd_idle(mem_rd_idle),
        .mem_a_req(mem_a_req && request_enable),
        .mem_a_we(mem_a_we),
        .mem_a_addr(mem_a_addr),
        .mem_a_wdata(mem_a_wdata),
        .mem_a_be(mem_a_be),
        .mem_a_rdy(native_a_rdy),
        .mem_a_rvalid(mem_a_rvalid),
        .mem_a_rdata(mem_a_rdata),
        .mem_sw_req(mem_sw_req && request_enable),
        .mem_sw_addr(mem_sw_addr),
        .mem_sw_wdata(mem_sw_wdata),
        .mem_sw_be(mem_sw_be),
        .mem_sw_rdy(native_sw_rdy),
        .mem_b_req(mem_b_req && request_enable),
        .mem_b_we(mem_b_we),
        .mem_b_tag(mem_b_tag),
        .mem_b_par(mem_b_par),
        .mem_b_addr(mem_b_addr),
        .mem_b_wdata(mem_b_wdata),
        .mem_b_wmask(mem_b_wmask),
        .mem_b_rdy(native_b_rdy),
        .mem_b_rvalid(mem_b_rvalid),
        .mem_b_rtag(mem_b_rtag),
        .mem_b_rdata(mem_b_rdata)
    );

    // 双域复位协调提供core冷复位，桥接返回只在校验完成后推进写退休。
    rkv_m1_native_axi_cdc #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) transport (
        .core_clk(core_clk),
        .ddr_clk(ddr_clk),
        .chain_cold_reset(chain_cold_reset),
        .core_locked(core_locked),
        .ddr_locked(ddr_locked),
        .ddr_calibrated(ddr_calibrated),
        .core_cold_reset(core_cold_reset),
        .ddr_axi_aresetn(ddr_axi_aresetn),
        .transport_ready(transport_ready),
        .admission_enable(admission_enable),
        .guard_armed(guard_armed),
        .fault_causes(fault_causes),
        .platform_error(platform_error),
        .bridge_idle(bridge_idle),
        .bridge_fault(bridge_fault),
        .bridge_fault_code(bridge_fault_code),
        .verified_writes(verified_writes),
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
        .m_rready(m_rready)
    );
endmodule
