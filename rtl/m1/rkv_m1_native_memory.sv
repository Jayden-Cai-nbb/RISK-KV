// 复用 openTPU 两路 512-bit 原生适配器；外部平台负责真实 DDR/AXI/CDC。
// 两路是逻辑通道，不假设目标板必须有两组物理 DDR。
module rkv_m1_native_memory (
    input logic clk,
    input logic cold_reset,
    input logic run_flush,
    input logic cache_flush,
    output logic cache_flush_ack,
    output logic transport_idle,
    output logic transport_error,
    input logic platform_error,
    output logic [1:0] n_cvalid,
    input logic [1:0] n_cready,
    output logic [1:0] n_cwe,
    output logic [1:0][24:0] n_caddr,
    output logic [1:0] n_wvalid,
    input logic [1:0] n_wready,
    output logic [1:0][511:0] n_wdata,
    output logic [1:0][63:0] n_wmask,
    input logic [1:0] n_rvalid,
    input logic [1:0][511:0] n_rdata,
    input logic [1:0][15:0] n_wdone,
    output logic mem_wr_idle,
    output logic mem_rd_idle,
    input logic mem_a_req,
    input logic mem_a_we,
    input logic [31:0] mem_a_addr,
    input logic [31:0] mem_a_wdata,
    input logic [3:0] mem_a_be,
    output logic mem_a_rdy,
    output logic mem_a_rvalid,
    output logic [255:0] mem_a_rdata,
    input logic mem_sw_req,
    input logic [31:0] mem_sw_addr,
    input logic [31:0] mem_sw_wdata,
    input logic [3:0] mem_sw_be,
    output logic mem_sw_rdy,
    input logic mem_b_req,
    input logic mem_b_we,
    input logic mem_b_tag,
    input logic mem_b_par,
    input logic [31:0] mem_b_addr,
    input logic [1023:0] mem_b_wdata,
    input logic [31:0] mem_b_wmask,
    output logic mem_b_rdy,
    output logic mem_b_rvalid,
    output logic mem_b_rtag,
    output logic [1023:0] mem_b_rdata
);
    logic flush_previous;
    logic idle_previous;
    logic [63:0] read_accepted [2];
    logic [63:0] read_retired [2];
    logic [63:0] write_accepted [2];
    logic [63:0] data_accepted [2];
    logic [63:0] write_retired [2];
    always_ff @(posedge clk) begin
        if (cold_reset) begin flush_previous <= 1'b0; idle_previous <= 1'b0; end
        else begin
            flush_previous <= cache_flush;
            idle_previous <= transport_idle && mem_wr_idle && mem_rd_idle;
        end
    end
    assign cache_flush_ack = cache_flush && flush_previous && idle_previous && transport_idle &&
                             mem_wr_idle && mem_rd_idle && !transport_error;
    otpu_native_dram #(
        .D(128),
        .CHASH(1'b1)
    ) adapter (
        .clk(clk),
        .rst(cold_reset),
        .a_flush(cache_flush || run_flush),
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
        .wr_idle(mem_wr_idle),
        .rd_idle(mem_rd_idle),
        .a_req_x(mem_a_req),
        .a_we_x(mem_a_we),
        .a_addr_x(mem_a_addr),
        .a_wdata_x(mem_a_wdata),
        .a_be_x(mem_a_be),
        .a_rdy_x(mem_a_rdy),
        .a_rvalid(mem_a_rvalid),
        .a_rdata(mem_a_rdata),
        .sw_req(mem_sw_req),
        .sw_addr(mem_sw_addr),
        .sw_wdata(mem_sw_wdata),
        .sw_be(mem_sw_be),
        .sw_rdy(mem_sw_rdy),
        .b_req(mem_b_req),
        .b_we(mem_b_we),
        .b_tag(mem_b_tag),
        .b_addr(mem_b_addr),
        .b_wdata(mem_b_wdata),
        .b_wmask(mem_b_wmask),
        .b_rdy(mem_b_rdy),
        .b_rvalid(mem_b_rvalid),
        .b_rtag(mem_b_rtag),
        .b_rdata(mem_b_rdata),
        .b_par(mem_b_par)
    );
    rkv_m1_native_retirement retirement (
        .clk(clk),
        .cold_reset(cold_reset),
        .cvalid(n_cvalid),
        .cready(n_cready),
        .cwe(n_cwe),
        .wvalid(n_wvalid),
        .wready(n_wready),
        .rvalid(n_rvalid),
        .wdone(n_wdone),
        .platform_error(platform_error),
        .idle(transport_idle),
        .error(transport_error),
        .read_accepted(read_accepted),
        .read_retired(read_retired),
        .write_accepted(write_accepted),
        .data_accepted(data_accepted),
        .write_retired(write_retired)
    );
endmodule
