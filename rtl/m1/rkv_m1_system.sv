// 无 DPI 的 M1 可移植系统核心；真实 DDR、CDC、时钟 IP、主机传输由平台绑定。
module rkv_m1_system #(
    parameter string FIRMWARE = ""
) (
    input logic clk,
    input logic cold_reset,
    output logic cpu_reset_pulse,
    output logic cmd_ready,
    output logic cq_valid,
    output logic [31:0] cq_op,
    output logic [31:0] cq_status,
    output logic [63:0] cq_session,
    output logic [31:0] cq_epoch,
    output logic [63:0] cq_sequence,
    output logic [31:0] cq_context,
    output logic [31:0] cq_generation,
    output logic [31:0] cq_token0,
    output logic [31:0] cq_token1,
    output logic isolated,
    output logic reset_pending,
    output logic session_valid,
    output logic [63:0] session,
    output logic [31:0] epoch,
    output logic [63:0] next_sequence,
    output logic [31:0] generation,
    output logic [31:0] object_id,
    output logic [2:0] object_state,
    output logic bound_pair,
    output logic [31:0] built_tokens,
    output logic [31:0] decode_steps,
    output logic [63:0] accepted_count,
    output logic [63:0] rejected_count,
    output logic [63:0] committed_tasks,
    output logic [31:0] last_error,
    output logic loader_start,
    output logic [31:0] loader_addr,
    output logic [31:0] loader_count,
    output logic npu_reset,
    output logic [31:0] npu_args [8],
    output logic protocol_error,
    output logic launch_pulse,
    output logic [63:0] task_cycles,
    output logic [63:0] loader_cycles,
    output logic flush_req,
    output logic req_valid,
    output logic req_write,
    output logic [31:0] req_addr,
    output logic [1023:0] req_data,
    output logic [127:0] req_mask,
    output logic rsp_ready,
    output logic [31:0] clear_fault_code,
    output logic [63:0] clear_reads_accepted,
    output logic [63:0] clear_reads_retired,
    output logic [63:0] clear_writes_accepted,
    output logic [63:0] clear_writes_retired,
    output logic [63:0] clear_cleaned_bytes,
    input logic boot_hold,
    output logic boot_waiting,
    input logic host_reset_request,
    input logic host_valid,
    input logic [15:0] host_addr,
    input logic [31:0] host_wdata,
    input logic [3:0] host_wstrb,
    output logic host_ready,
    output logic [31:0] host_rdata,
    output logic host_error,
    output logic trap,
    output logic test_done,
    output logic [31:0] test_code,
    output logic token_trace_valid,
    output logic token_trace_row,
    output logic [31:0] token_trace_data,
    output logic cache_flush,
    input logic cache_flush_ack,
    input logic transport_idle,
    input logic transport_error,
    input logic mem_wr_idle,
    input logic mem_rd_idle,
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
    input logic [1023:0] mem_b_rdata,
    input logic clk_f,
    input logic inject_task_error,
    output logic [31:0] injected_errors,
    output logic a_inval,
    input logic host_idle,
    input logic host_accept_now,
    output logic host_read_grant,
    output logic host_write_grant,
    input logic dump,
    output logic [31:0] icount
);
    logic fabric_idle;
    logic fabric_error;
    logic npu_halted;
    logic npu_error;
    logic loader_busy;
    logic result_store_valid;
    logic [31:0] result_store_addr;
    logic [1023:0] result_store_data;
    logic [31:0] result_store_mask;
    logic result_other_write;
    logic flush_ack;
    logic req_ready;
    logic rsp_valid;
    logic rsp_error;
    logic [1023:0] rsp_data;
    logic a_req;
    logic a_we;
    logic [31:0] a_addr;
    logic [31:0] a_wdata;
    logic [3:0] a_be;
    logic a_rdy;
    logic a_rvalid;
    logic [255:0] a_rdata;
    logic sw_req;
    logic [31:0] sw_addr;
    logic [31:0] sw_wdata;
    logic [3:0] sw_be;
    logic sw_rdy;
    logic b_req;
    logic b_we;
    logic b_tag;
    logic b_par;
    logic [31:0] b_addr;
    logic [1023:0] b_wdata;
    logic [31:0] b_wmask;
    logic b_rdy;
    logic b_rvalid;
    logic b_rtag;
    logic [1023:0] b_rdata;
    logic arbiter_idle;
    logic injection_previous;
    wire injection_event = inject_task_error && !injection_previous && !npu_reset;
    // 特权验收注入只使当前任务失败，计算仍自然结束，逻辑进度由监督器拒绝提交。
    always_ff @(posedge clk) begin
        if (cold_reset) begin
            injection_previous <= 1'b0;
            injected_errors <= 32'd0;
        end else begin
            injection_previous <= inject_task_error;
            if (injection_event) injected_errors <= injected_errors + 32'd1;
        end
    end
    // 权限取接收前静止状态；CPU准入另外看本拍根入口接收，避免权限自拒绝组合环。
    assign fabric_idle = arbiter_idle && host_idle && !host_accept_now;
    assign result_store_valid = b_req && b_we && b_rdy;
    assign result_store_addr = b_addr;
    assign result_store_data = b_wdata;
    assign result_store_mask = b_wmask;
    assign result_other_write = (a_req && a_we && a_rdy &&
        (a_addr == rkv_m1_layout_pkg::RESULT_ADDRESS/4 || a_addr == rkv_m1_layout_pkg::RESULT_ADDRESS/4 + 1)) ||
        (sw_req && sw_rdy && (sw_addr == rkv_m1_layout_pkg::RESULT_ADDRESS/4 || sw_addr == rkv_m1_layout_pkg::RESULT_ADDRESS/4 + 1));
    assign host_write_grant = boot_waiting && npu_reset && arbiter_idle && host_idle && !loader_busy;
    assign host_read_grant = host_write_grant || (cq_valid && npu_reset && arbiter_idle && host_idle && !loader_busy && !reset_pending && !isolated);
    rkv_m1_cpu #(
        .FIRMWARE(FIRMWARE)
    ) cpu (
        .clk(clk),
        .cold_reset(cold_reset),
        .cpu_reset_pulse(cpu_reset_pulse),
        .fabric_idle(fabric_idle),
        .fabric_error(fabric_error),
        .cmd_ready(cmd_ready),
        .cq_valid(cq_valid),
        .cq_op(cq_op),
        .cq_status(cq_status),
        .cq_session(cq_session),
        .cq_epoch(cq_epoch),
        .cq_sequence(cq_sequence),
        .cq_context(cq_context),
        .cq_generation(cq_generation),
        .cq_token0(cq_token0),
        .cq_token1(cq_token1),
        .isolated(isolated),
        .reset_pending(reset_pending),
        .session_valid(session_valid),
        .session(session),
        .epoch(epoch),
        .next_sequence(next_sequence),
        .generation(generation),
        .object_id(object_id),
        .object_state(object_state),
        .bound_pair(bound_pair),
        .built_tokens(built_tokens),
        .decode_steps(decode_steps),
        .accepted_count(accepted_count),
        .rejected_count(rejected_count),
        .committed_tasks(committed_tasks),
        .last_error(last_error),
        .npu_halted(npu_halted),
        .npu_error(npu_error || injection_event),
        .loader_busy(loader_busy),
        .loader_start(loader_start),
        .loader_addr(loader_addr),
        .loader_count(loader_count),
        .npu_reset(npu_reset),
        .npu_args(npu_args),
        .result_store_valid(result_store_valid),
        .result_store_addr(result_store_addr),
        .result_store_data(result_store_data),
        .result_store_mask(result_store_mask),
        .result_other_write(result_other_write),
        .protocol_error(protocol_error),
        .launch_pulse(launch_pulse),
        .task_cycles(task_cycles),
        .loader_cycles(loader_cycles),
        .flush_req(flush_req),
        .flush_ack(flush_ack),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_data(req_data),
        .req_mask(req_mask),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_error(rsp_error),
        .rsp_data(rsp_data),
        .clear_fault_code(clear_fault_code),
        .clear_reads_accepted(clear_reads_accepted),
        .clear_reads_retired(clear_reads_retired),
        .clear_writes_accepted(clear_writes_accepted),
        .clear_writes_retired(clear_writes_retired),
        .clear_cleaned_bytes(clear_cleaned_bytes),
        .boot_hold(boot_hold),
        .boot_waiting(boot_waiting),
        .host_reset_request(host_reset_request),
        .host_valid(host_valid),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_wstrb(host_wstrb),
        .host_ready(host_ready),
        .host_rdata(host_rdata),
        .host_error(host_error),
        .trap(trap),
        .test_done(test_done),
        .test_code(test_code),
        .token_trace_valid(token_trace_valid),
        .token_trace_row(token_trace_row),
        .token_trace_data(token_trace_data)
    );
    rkv_m1_compute compute (
        .clk(clk),
        .clk_f(clk_f),
        .cold_reset(cold_reset),
        .npu_reset(npu_reset),
        .npu_args(npu_args),
        .loader_start(loader_start),
        .loader_addr(loader_addr),
        .loader_count(loader_count),
        .loader_busy(loader_busy),
        .wr_idle(mem_wr_idle),
        .rd_idle(mem_rd_idle),
        .halted(npu_halted),
        .error(npu_error),
        .a_inval(a_inval),
        .icount(icount),
        .dump(dump),
        .a_req(a_req),
        .a_we(a_we),
        .a_addr(a_addr),
        .a_wdata(a_wdata),
        .a_be(a_be),
        .a_rdy(a_rdy),
        .a_rvalid(a_rvalid),
        .a_rdata(a_rdata),
        .sw_req(sw_req),
        .sw_addr(sw_addr),
        .sw_wdata(sw_wdata),
        .sw_be(sw_be),
        .sw_rdy(sw_rdy),
        .b_req(b_req),
        .b_we(b_we),
        .b_tag(b_tag),
        .b_par(b_par),
        .b_addr(b_addr),
        .b_wdata(b_wdata),
        .b_wmask(b_wmask),
        .b_rdy(b_rdy),
        .b_rvalid(b_rvalid),
        .b_rtag(b_rtag),
        .b_rdata(b_rdata)
    );
    rkv_m1_memory_arbiter memory_arbiter (
        .clk(clk),
        .cold_reset(cold_reset),
        .npu_reset(npu_reset),
        .loader_busy(loader_busy),
        .a_req(a_req),
        .a_we(a_we),
        .a_addr(a_addr),
        .a_wdata(a_wdata),
        .a_be(a_be),
        .a_rdy(a_rdy),
        .a_rvalid(a_rvalid),
        .a_rdata(a_rdata),
        .sw_req(sw_req),
        .sw_addr(sw_addr),
        .sw_wdata(sw_wdata),
        .sw_be(sw_be),
        .sw_rdy(sw_rdy),
        .b_req(b_req),
        .b_we(b_we),
        .b_tag(b_tag),
        .b_par(b_par),
        .b_addr(b_addr),
        .b_wdata(b_wdata),
        .b_wmask(b_wmask),
        .b_rdy(b_rdy),
        .b_rvalid(b_rvalid),
        .b_rtag(b_rtag),
        .b_rdata(b_rdata),
        .clean_req_valid(req_valid),
        .clean_req_ready(req_ready),
        .clean_req_write(req_write),
        .clean_req_addr(req_addr),
        .clean_req_data(req_data),
        .clean_req_mask(req_mask),
        .clean_rsp_valid(rsp_valid),
        .clean_rsp_ready(rsp_ready),
        .clean_rsp_error(rsp_error),
        .clean_rsp_data(rsp_data),
        .flush_req(flush_req),
        .flush_ack(flush_ack),
        .cache_flush(cache_flush),
        .cache_flush_ack(cache_flush_ack),
        .transport_idle(transport_idle),
        .transport_error(transport_error),
        .mem_wr_idle(mem_wr_idle),
        .mem_rd_idle(mem_rd_idle),
        .fabric_idle(arbiter_idle),
        .fabric_error(fabric_error),
        .mem_a_req(mem_a_req),
        .mem_a_we(mem_a_we),
        .mem_a_addr(mem_a_addr),
        .mem_a_wdata(mem_a_wdata),
        .mem_a_be(mem_a_be),
        .mem_a_rdy(mem_a_rdy),
        .mem_a_rvalid(mem_a_rvalid),
        .mem_a_rdata(mem_a_rdata),
        .mem_sw_req(mem_sw_req),
        .mem_sw_addr(mem_sw_addr),
        .mem_sw_wdata(mem_sw_wdata),
        .mem_sw_be(mem_sw_be),
        .mem_sw_rdy(mem_sw_rdy),
        .mem_b_req(mem_b_req),
        .mem_b_we(mem_b_we),
        .mem_b_tag(mem_b_tag),
        .mem_b_par(mem_b_par),
        .mem_b_addr(mem_b_addr),
        .mem_b_wdata(mem_b_wdata),
        .mem_b_wmask(mem_b_wmask),
        .mem_b_rdy(mem_b_rdy),
        .mem_b_rvalid(mem_b_rvalid),
        .mem_b_rtag(mem_b_rtag),
        .mem_b_rdata(mem_b_rdata)
    );
endmodule
