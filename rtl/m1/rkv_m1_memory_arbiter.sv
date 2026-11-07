// 在 openTPU 原生 A/B/SW 与存储适配器之间加入串行清理通路。
// mem_* 就绪来自适配器寄存状态；真实退休由 wr_idle/rd_idle/transport_idle 联合定义。
module rkv_m1_memory_arbiter (
    input logic clk,
    input logic cold_reset,
    input logic npu_reset,
    input logic loader_busy,
    input logic a_req,
    input logic a_we,
    input logic [31:0] a_addr,
    input logic [31:0] a_wdata,
    input logic [3:0] a_be,
    output logic a_rdy,
    output logic a_rvalid,
    output logic [255:0] a_rdata,
    input logic sw_req,
    input logic [31:0] sw_addr,
    input logic [31:0] sw_wdata,
    input logic [3:0] sw_be,
    output logic sw_rdy,
    input logic b_req,
    input logic b_we,
    input logic b_tag,
    input logic b_par,
    input logic [31:0] b_addr,
    input logic [1023:0] b_wdata,
    input logic [31:0] b_wmask,
    output logic b_rdy,
    output logic b_rvalid,
    output logic b_rtag,
    output logic [1023:0] b_rdata,
    input logic clean_req_valid,
    output logic clean_req_ready,
    input logic clean_req_write,
    input logic [31:0] clean_req_addr,
    input logic [1023:0] clean_req_data,
    input logic [127:0] clean_req_mask,
    output logic clean_rsp_valid,
    input logic clean_rsp_ready,
    output logic clean_rsp_error,
    output logic [1023:0] clean_rsp_data,
    input logic flush_req,
    output logic flush_ack,
    output logic cache_flush,
    input logic cache_flush_ack,
    input logic transport_idle,
    input logic transport_error,
    input logic mem_wr_idle,
    input logic mem_rd_idle,
    output logic fabric_idle,
    output logic fabric_error,
    output logic mem_a_req,
    output logic mem_a_we,
    output logic [31:0] mem_a_addr,
    output logic [31:0] mem_a_wdata,
    output logic [3:0] mem_a_be,
    input logic mem_a_rdy,
    input logic mem_a_rvalid,
    input logic [255:0] mem_a_rdata,
    output logic mem_sw_req,
    output logic [31:0] mem_sw_addr,
    output logic [31:0] mem_sw_wdata,
    output logic [3:0] mem_sw_be,
    input logic mem_sw_rdy,
    output logic mem_b_req,
    output logic mem_b_we,
    output logic mem_b_tag,
    output logic mem_b_par,
    output logic [31:0] mem_b_addr,
    output logic [1023:0] mem_b_wdata,
    output logic [31:0] mem_b_wmask,
    input logic mem_b_rdy,
    input logic mem_b_rvalid,
    input logic mem_b_rtag,
    input logic [1023:0] mem_b_rdata
);
    typedef enum logic [2:0] {NPU, SEND, WAIT_READ, WAIT_WRITE, RESPONSE} state_t;
    state_t state;
    logic saved_write;
    logic [31:0] saved_addr;
    logic [1023:0] saved_data;
    logic [31:0] saved_mask;
    logic write_previous;
    logic bvalid_previous;
    logic memory_idle_previous;
    logic sticky_error;
    logic mask_supported;
    logic [31:0] word_mask;
    logic [1:0] write_wait_cycles;
    wire ports_quiet = !a_req && !sw_req && !b_req && !mem_a_rvalid && !mem_b_rvalid;
    wire memory_idle = mem_wr_idle && mem_rd_idle && transport_idle && !write_previous && !bvalid_previous;
    wire collision = state != NPU && (a_req || sw_req || b_req);

    always_comb begin
        mask_supported = 1'b1;
        word_mask = 32'd0;
        for (int i = 0; i < 32; i++) begin
            word_mask[i] = &clean_req_mask[i*4 +: 4];
            if (clean_req_mask[i*4 +: 4] != 4'h0 && clean_req_mask[i*4 +: 4] != 4'hf)
                mask_supported = 1'b0;
        end
    end
    assign fabric_error = sticky_error || transport_error || collision;
    assign fabric_idle = state == NPU && memory_idle && ports_quiet && !fabric_error;
    assign cache_flush = flush_req;
    assign flush_ack = flush_req && cache_flush_ack && fabric_idle && memory_idle_previous;
    assign clean_req_ready = state == NPU && npu_reset && !loader_busy && memory_idle &&
                             memory_idle_previous && ports_quiet && !fabric_error && !flush_req;
    assign clean_rsp_valid = state == RESPONSE;
    // NPU 的 ready 不依赖当前请求；清理请求只能在 NPU 排空且保持复位时接受。
    assign a_rdy = state == NPU && mem_a_rdy;
    assign sw_rdy = state == NPU && mem_sw_rdy;
    assign b_rdy = state == NPU && mem_b_rdy;
    assign a_rvalid = state == NPU && mem_a_rvalid;
    assign a_rdata = mem_a_rdata;
    assign b_rvalid = state == NPU && mem_b_rvalid;
    assign b_rtag = mem_b_rtag;
    assign b_rdata = mem_b_rdata;
    assign mem_a_req = state == NPU && a_req;
    assign mem_a_we = a_we;
    assign mem_a_addr = a_addr;
    assign mem_a_wdata = a_wdata;
    assign mem_a_be = a_be;
    assign mem_sw_req = state == NPU && sw_req;
    assign mem_sw_addr = sw_addr;
    assign mem_sw_wdata = sw_wdata;
    assign mem_sw_be = sw_be;
    assign mem_b_req = state == NPU ? b_req : state == SEND;
    assign mem_b_we = state == NPU ? b_we : saved_write;
    assign mem_b_tag = state == NPU ? b_tag : 1'b0;
    assign mem_b_par = state == NPU ? b_par : ^saved_addr[31:7];
    assign mem_b_addr = state == NPU ? b_addr : saved_addr >> 2;
    assign mem_b_wdata = state == NPU ? b_wdata : saved_data;
    assign mem_b_wmask = state == NPU ? b_wmask : saved_mask;

    always_ff @(posedge clk) begin
        if (cold_reset) begin
            state <= NPU;
            saved_write <= 1'b0;
            saved_addr <= 32'd0;
            saved_data <= 1024'd0;
            saved_mask <= 32'd0;
            write_previous <= 1'b0;
            bvalid_previous <= 1'b0;
            memory_idle_previous <= 1'b0;
            sticky_error <= 1'b0;
            write_wait_cycles <= 2'd0;
            clean_rsp_error <= 1'b0;
            clean_rsp_data <= 1024'd0;
        end else begin
            write_previous <= (mem_a_req && mem_a_we && mem_a_rdy) ||
                              (mem_sw_req && mem_sw_rdy) || (mem_b_req && mem_b_we && mem_b_rdy);
            bvalid_previous <= mem_b_rvalid;
            memory_idle_previous <= memory_idle && ports_quiet;
            if (transport_error || collision) sticky_error <= 1'b1;
            if (state != NPU && mem_a_rvalid) sticky_error <= 1'b1;
            if (state != NPU && state != WAIT_READ && mem_b_rvalid) sticky_error <= 1'b1;
            case (state)
                NPU: begin
                    if (clean_req_valid && clean_req_ready) begin
                        saved_write <= clean_req_write;
                        saved_addr <= clean_req_addr;
                        saved_data <= clean_req_data;
                        saved_mask <= word_mask;
                        clean_rsp_data <= 1024'd0;
                        clean_rsp_error <= 1'b0;
                        write_wait_cycles <= 2'd0;
                        // M1 清理通路只用整字掩码。标量字节掩码由 A/SW 原生通路完整保留。
                        if (clean_req_addr[6:0] != 0 || clean_req_addr[31] || (clean_req_write && !mask_supported)) begin
                            clean_rsp_error <= 1'b1;
                            state <= RESPONSE;
                        end else state <= SEND;
                    end
                end
                SEND: if (mem_b_req && mem_b_rdy) state <= saved_write ? WAIT_WRITE : WAIT_READ;
                WAIT_READ: begin
                    if (mem_b_rvalid) begin
                        clean_rsp_data <= mem_b_rdata;
                        clean_rsp_error <= fabric_error || mem_b_rtag;
                        state <= RESPONSE;
                    end
                end
                WAIT_WRITE: begin
                    if (write_wait_cycles != 2'd2) write_wait_cycles <= write_wait_cycles + 2'd1;
                    if (write_wait_cycles == 2'd2 && memory_idle && memory_idle_previous) begin
                        clean_rsp_error <= fabric_error;
                        state <= RESPONSE;
                    end
                end
                RESPONSE: if (clean_rsp_valid && clean_rsp_ready) state <= NPU;
                default: sticky_error <= 1'b1;
            endcase
        end
    end
endmodule
