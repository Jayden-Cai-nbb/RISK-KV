// PicoRV32 + 64 KiB 启动 RAM。主机只访问 0xe000 mailbox，单端口仲裁避免读写冲突。
// 监督与清理不受 CPU 复位；boot_hold 只延迟第一次启动，运行期复位走受控请求。
module rkv_m1_cpu #(
    parameter string FIRMWARE = "",
    parameter logic [31:0] TASK_TIMEOUT = 32'd1000000000,
    parameter logic [31:0] MEMORY_TIMEOUT = 32'd1000000
) (
    input logic clk,
    input logic cold_reset,
    output logic cpu_reset_pulse,
    input logic fabric_idle,
    input logic fabric_error,
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
    input logic npu_halted,
    input logic npu_error,
    input logic loader_busy,
    output logic loader_start,
    output logic [31:0] loader_addr,
    output logic [31:0] loader_count,
    output logic npu_reset,
    output logic [31:0] npu_args [8],
    input logic result_store_valid,
    input logic [31:0] result_store_addr,
    input logic [1023:0] result_store_data,
    input logic [31:0] result_store_mask,
    input logic result_other_write,
    output logic protocol_error,
    output logic launch_pulse,
    output logic [63:0] task_cycles,
    output logic [63:0] loader_cycles,
    output logic flush_req,
    input logic flush_ack,
    output logic req_valid,
    input logic req_ready,
    output logic req_write,
    output logic [31:0] req_addr,
    output logic [1023:0] req_data,
    output logic [127:0] req_mask,
    input logic rsp_valid,
    output logic rsp_ready,
    input logic rsp_error,
    input logic [1023:0] rsp_data,
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
    output logic [31:0] token_trace_data
);
    logic cmd_valid;
    logic [31:0] cmd_op;
    logic [63:0] cmd_session;
    logic [31:0] cmd_epoch;
    logic [63:0] cmd_sequence;
    logic [31:0] cmd_context;
    logic [31:0] cmd_generation;
    logic [31:0] cmd_token0;
    logic [31:0] cmd_token1;
    logic ack_valid;
    logic cancel_valid;
    logic reset_request;
    logic [63:0] receipt_session;
    logic [31:0] receipt_epoch;
    logic [63:0] receipt_sequence;
    logic [31:0] receipt_context;
    logic [31:0] receipt_generation;
    logic cpu_valid;
    logic cpu_instr;
    logic [31:0] cpu_addr;
    logic [31:0] cpu_wdata;
    logic [3:0] cpu_wstrb;
    logic cpu_ready;
    logic [31:0] cpu_rdata;
    logic control_ready;
    logic [31:0] control_rdata;
    logic ram_ready;
    logic [31:0] ram_rdata;
    logic started;
    logic [31:0] ram [16384];
`ifndef SYNTHESIS
    string image; // 仿真路径可由 plusarg 指定；综合不保留运行时字符串变量。
`endif
    wire cpu_reset = cold_reset || !started || cpu_reset_pulse;
    assign boot_waiting = !started;
    wire ram_select = cpu_addr[31:16] == 16'd0;
    wire control_select = cpu_addr[31:12] == 20'h40000;
    assign cpu_ready = control_select ? control_ready : ram_ready;
    assign cpu_rdata = control_select ? control_rdata : ram_rdata;
    initial begin
        for (int i = 0; i < 16384; i++) ram[i] = 32'd0;
`ifdef SYNTHESIS
        // 固件路径在综合展开时确定，保持与仿真一致的 RAM 初始内容。
        if (FIRMWARE != "") $readmemh(FIRMWARE, ram);
`else
        image = FIRMWARE;
        if (image == "") void'($value$plusargs("firmware=%s", image));
        if (image != "") $readmemh(image, ram);
`endif
    end
    always_ff @(posedge clk) begin
        if (cold_reset) started <= 1'b0;
        else if (!boot_hold) started <= 1'b1;
        host_ready <= 1'b0;
        ram_ready <= 1'b0;
        token_trace_valid <= 1'b0;
        if (cold_reset) begin
            host_ready <= 1'b0; host_rdata <= 32'd0; host_error <= 1'b0;
        end else if (host_valid && !host_ready) begin
            host_ready <= 1'b1; host_error <= 1'b0; host_rdata <= 32'd0;
            if (host_addr[15:8] != rkv_m1_layout_pkg::MAILBOX_BASE[15:8] || host_addr[1:0] != 0) host_error <= 1'b1;
            else begin
                host_rdata <= ram[host_addr[15:2]];
                for (int b = 0; b < 4; b++)
                    if (host_wstrb[b]) ram[host_addr[15:2]][b*8 +: 8] <= host_wdata[b*8 +: 8];
            end
        end else if (!host_valid && !cpu_reset && cpu_valid && !control_select && !ram_ready) begin
            ram_ready <= 1'b1; ram_rdata <= 32'd0;
            if (ram_select) begin
                ram_rdata <= ram[cpu_addr[15:2]];
                for (int b = 0; b < 4; b++)
                    if (cpu_wstrb[b]) ram[cpu_addr[15:2]][b*8 +: 8] <= cpu_wdata[b*8 +: 8];
            end else if ((cpu_addr == 32'h50000010 || cpu_addr == 32'h50000014) && cpu_wstrb == 4'hf) begin
                token_trace_valid <= 1'b1; token_trace_row <= cpu_addr[2]; token_trace_data <= cpu_wdata;
            end else if (cpu_addr == 32'h50000000 && cpu_wstrb == 4'hf) begin
                test_done <= 1'b1; test_code <= cpu_wdata;
            end else begin
                test_done <= 1'b1; test_code <= 32'hbad00001;
            end
        end
        if (cpu_reset) begin
            ram_ready <= 1'b0; ram_rdata <= 32'd0; test_done <= 1'b0; test_code <= 32'd0;
            token_trace_valid <= 1'b0; token_trace_row <= 1'b0; token_trace_data <= 32'd0;
        end
    end
    picorv32 #(
        .PROGADDR_RESET(32'd0),
        .STACKADDR(32'h10000),
        .ENABLE_COUNTERS(1),
        .ENABLE_COUNTERS64(1),
        .COMPRESSED_ISA(0),
        .ENABLE_MUL(0),
        .ENABLE_DIV(0),
        .ENABLE_IRQ(0)
    ) cpu (
        .clk(clk),
        .resetn(!cpu_reset),
        .trap(trap),
        .mem_valid(cpu_valid),
        .mem_instr(cpu_instr),
        .mem_ready(cpu_ready),
        .mem_addr(cpu_addr),
        .mem_wdata(cpu_wdata),
        .mem_wstrb(cpu_wstrb),
        .mem_rdata(cpu_rdata),
        .mem_la_read(),
        .mem_la_write(),
        .mem_la_addr(),
        .mem_la_wdata(),
        .mem_la_wstrb(),
        .pcpi_valid(),
        .pcpi_insn(),
        .pcpi_rs1(),
        .pcpi_rs2(),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'b0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
        .irq(32'b0),
        .eoi(),
        .trace_valid(),
        .trace_data()
    );
    rkv_m1_mmio mmio (
        .clk(clk),
        .cpu_reset(cpu_reset),
        .bus_valid(cpu_valid && control_select),
        .bus_addr(cpu_addr[11:0]),
        .bus_wdata(cpu_wdata),
        .bus_wstrb(cpu_wstrb),
        .bus_ready(control_ready),
        .bus_rdata(control_rdata),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_op(cmd_op),
        .cmd_session(cmd_session),
        .cmd_epoch(cmd_epoch),
        .cmd_sequence(cmd_sequence),
        .cmd_context(cmd_context),
        .cmd_generation(cmd_generation),
        .cmd_token0(cmd_token0),
        .cmd_token1(cmd_token1),
        .ack_valid(ack_valid),
        .cancel_valid(cancel_valid),
        .reset_request(reset_request),
        .receipt_session(receipt_session),
        .receipt_epoch(receipt_epoch),
        .receipt_sequence(receipt_sequence),
        .receipt_context(receipt_context),
        .receipt_generation(receipt_generation),
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
        .clear_cleaned_bytes(clear_cleaned_bytes),
        .last_error(last_error)
    );
    rkv_m1_service #(
        .TASK_TIMEOUT(TASK_TIMEOUT),
        .MEMORY_TIMEOUT(MEMORY_TIMEOUT)
    ) service (
        .clk(clk),
        .cold_reset(cold_reset),
        .reset_request(reset_request || host_reset_request),
        .cpu_reset_pulse(cpu_reset_pulse),
        .fabric_idle(fabric_idle),
        .fabric_error(fabric_error),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_op(cmd_op),
        .cmd_session(cmd_session),
        .cmd_epoch(cmd_epoch),
        .cmd_sequence(cmd_sequence),
        .cmd_context(cmd_context),
        .cmd_generation(cmd_generation),
        .cmd_token0(cmd_token0),
        .cmd_token1(cmd_token1),
        .ack_valid(ack_valid),
        .cancel_valid(cancel_valid),
        .receipt_session(receipt_session),
        .receipt_epoch(receipt_epoch),
        .receipt_sequence(receipt_sequence),
        .receipt_context(receipt_context),
        .receipt_generation(receipt_generation),
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
        .npu_error(npu_error),
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
        .clear_cleaned_bytes(clear_cleaned_bytes)
    );
endmodule
