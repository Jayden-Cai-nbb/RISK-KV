// M1 唯一生命周期 / 监督状态所有者。CPU 复位请求不能清除本模块。
module rkv_m1_control #(
    parameter logic [31:0] TIMEOUT_CYCLES = 32'd1000000000
) (
    input logic clk,
    input logic cold_reset,
    input logic reset_request,
    output logic cpu_reset_pulse,
    input logic fabric_idle,
    input logic fabric_error,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [31:0] cmd_op,
    input logic [63:0] cmd_session,
    input logic [31:0] cmd_epoch,
    input logic [63:0] cmd_sequence,
    input logic [31:0] cmd_context,
    input logic [31:0] cmd_generation,
    input logic [31:0] cmd_token0,
    input logic [31:0] cmd_token1,
    input logic ack_valid,
    input logic cancel_valid,
    input logic [63:0] receipt_session,
    input logic [31:0] receipt_epoch,
    input logic [63:0] receipt_sequence,
    input logic [31:0] receipt_context,
    input logic [31:0] receipt_generation,
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
    output logic work_valid,
    input logic work_ready,
    output logic work_decode,
    output logic [31:0] work_args [8],
    input logic work_done_valid,
    output logic work_done_ready,
    input logic [31:0] work_status,
    input logic [31:0] work_token0,
    input logic [31:0] work_token1,
    output logic clean_valid,
    input logic clean_ready,
    output logic clean_full,
    input logic clean_done_valid,
    output logic clean_done_ready,
    input logic clean_isolated,
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
    output logic [31:0] last_error
);
    import rkv_m1_layout_pkg::*;
    localparam logic [2:0] EMPTY = 3'd0;
    localparam logic [2:0] BUILDING = 3'd1;
    localparam logic [2:0] SEALED = 3'd2;
    localparam logic [2:0] FAILED = 3'd3;
    typedef enum logic [3:0] {
        IDLE, WORK_REQUEST, WORK_WAIT, CLEAN_REQUEST, CLEAN_WAIT,
        COMPLETION, RESET_DRAIN, RESET_CLEAN_REQUEST, RESET_CLEAN_WAIT, QUARANTINE
    } state_t;
    state_t state;
    logic cancelled;
    logic idle_previous;
    logic reset_previous;
    logic [31:0] wait_cycles;
    logic [31:0] admission_error;
    wire reset_now = reset_request && !reset_previous;
    wire same_receipt = receipt_session == cq_session && receipt_epoch == cq_epoch &&
                        receipt_sequence == cq_sequence && receipt_context == cq_context &&
                        receipt_generation == cq_generation;
    wire active_work = state == WORK_REQUEST || state == WORK_WAIT;
    wire cancelling_now = cancel_valid && same_receipt && active_work;
    wire waiting = active_work || state == CLEAN_REQUEST || state == CLEAN_WAIT ||
                   state == RESET_DRAIN || state == RESET_CLEAN_REQUEST || state == RESET_CLEAN_WAIT;
    wire timeout_now = waiting && wait_cycles >= TIMEOUT_CYCLES - 32'd1;
    wire orphan_result = (work_done_valid && !work_done_ready) || (clean_done_valid && !clean_done_ready);
    wire unsafe_now = fabric_error || clean_isolated || isolated || timeout_now || orphan_result;

    // CQ 是身份匹配消费协议；受控复位撤销旧 CQ，永不把它提交到新身份。
    assign cmd_ready = state == IDLE && !unsafe_now && !reset_pending && !reset_now;
    assign cq_valid = state == COMPLETION && !unsafe_now && !reset_pending && !reset_now;
    assign work_valid = state == WORK_REQUEST;
    assign work_done_ready = state == WORK_WAIT;
    assign clean_valid = state == CLEAN_REQUEST || state == RESET_CLEAN_REQUEST;
    assign clean_full = state == RESET_CLEAN_REQUEST || cq_op != OP_RELEASE;
    assign clean_done_ready = state == CLEAN_WAIT || state == RESET_CLEAN_WAIT;

    // 准入只查看消费后逻辑状态；八个运行参数由硬件根据冻结布局产生。
    always_comb begin
        admission_error = 32'd0;
        if (cmd_epoch != epoch || cmd_sequence != next_sequence || &next_sequence)
            admission_error = 32'd1;
        else if (cmd_op == OP_BOOT) begin
            if (session_valid || cmd_session == 64'd0 || object_state != EMPTY)
                admission_error = 32'd2;
        end else if (!session_valid || cmd_session != session || cmd_generation != generation)
            admission_error = 32'd1;
        else if (cmd_op == OP_REGISTER) begin
            if (object_state != EMPTY || cmd_context == 32'd0 || &generation)
                admission_error = 32'd3;
        end else if (cmd_context != object_id) admission_error = 32'd1;
        else begin
            case (cmd_op)
                OP_BUILD: if (object_state != BUILDING || built_tokens >= PREFIX_TOKENS)
                    admission_error = 32'd3;
                OP_SEAL: if (object_state != BUILDING || built_tokens != PREFIX_TOKENS)
                    admission_error = 32'd3;
                OP_BIND: if (object_state != SEALED || bound_pair)
                    admission_error = 32'd3;
                OP_DECODE: begin
                    if (object_state != SEALED || !bound_pair || decode_steps >= DECODE_STEPS)
                        admission_error = 32'd3;
                    else if (cmd_token0 >= VOCAB || cmd_token1 >= VOCAB) admission_error = 32'd4;
                end
                OP_RELEASE: if (object_state != SEALED || !bound_pair) admission_error = 32'd3;
                OP_RETIRE: if (object_state == EMPTY || object_state == FAILED) admission_error = 32'd3;
                OP_RECOVER: if (object_state != FAILED) admission_error = 32'd3;
                default: admission_error = 32'd5;
            endcase
        end
        if (!fabric_idle || !idle_previous) admission_error = 32'd6;
    end

    always_ff @(posedge clk) begin
        if (cold_reset) begin
            state <= IDLE;
            cancelled <= 1'b0;
            idle_previous <= 1'b0;
            reset_previous <= 1'b0;
            wait_cycles <= 32'd0;
            isolated <= 1'b0;
            reset_pending <= 1'b0;
            cpu_reset_pulse <= 1'b0;
            session_valid <= 1'b0;
            session <= 64'd0;
            epoch <= 32'd1;
            next_sequence <= 64'd1;
            generation <= 32'd0;
            object_id <= 32'd0;
            object_state <= EMPTY;
            bound_pair <= 1'b0;
            built_tokens <= 32'd0;
            decode_steps <= 32'd0;
            accepted_count <= 64'd0;
            rejected_count <= 64'd0;
            committed_tasks <= 64'd0;
            last_error <= 32'd0;
            cq_op <= 32'd0;
            cq_status <= 32'd0;
            cq_session <= 64'd0;
            cq_epoch <= 32'd0;
            cq_sequence <= 64'd0;
            cq_context <= 32'd0;
            cq_generation <= 32'd0;
            cq_token0 <= 32'd0;
            cq_token1 <= 32'd0;
            work_decode <= 1'b0;
            for (int i = 0; i < 8; i++) work_args[i] <= 32'd0;
        end else begin
            cpu_reset_pulse <= 1'b0;
            reset_previous <= reset_request;
            idle_previous <= fabric_idle;
            if (waiting && !timeout_now) wait_cycles <= wait_cycles + 32'd1;
            else if (!waiting) wait_cycles <= 32'd0;

            if (reset_now) reset_pending <= 1'b1;
            if (unsafe_now) begin
                isolated <= 1'b1;
                if (!isolated) last_error <= timeout_now ? 32'd16 : 32'd17;
            end
            // 多余结果或清理完成没有可消费的对应事务，必须隔离旧返回。
            if (orphan_result) begin
                isolated <= 1'b1;
                last_error <= 32'd18;
            end
            if (cancel_valid) begin
                if (cancelling_now) cancelled <= 1'b1;
                else begin
                    last_error <= 32'd7;
                    rejected_count <= rejected_count + 64'd1;
                end
            end
            if (ack_valid && (!cq_valid || !same_receipt)) begin
                last_error <= 32'd8;
                rejected_count <= rejected_count + 64'd1;
            end

            case (state)
                IDLE: begin
                    if (unsafe_now) state <= QUARANTINE;
                    else if (reset_pending || reset_now) state <= RESET_DRAIN;
                    else if (cmd_valid && cmd_ready) begin
                        if (admission_error != 32'd0) begin
                            last_error <= admission_error;
                            rejected_count <= rejected_count + 64'd1;
                        end else begin
                            cq_op <= cmd_op;
                            cq_status <= 32'd0;
                            cq_session <= cmd_session;
                            cq_epoch <= cmd_epoch;
                            cq_sequence <= cmd_sequence;
                            cq_context <= cmd_context;
                            cq_generation <= cmd_generation;
                            cq_token0 <= 32'd0;
                            cq_token1 <= 32'd0;
                            next_sequence <= next_sequence + 64'd1;
                            accepted_count <= accepted_count + 64'd1;
                            last_error <= 32'd0;
                            cancelled <= 1'b0;
                            if (cmd_op == OP_BUILD || cmd_op == OP_DECODE) begin
                                work_decode <= cmd_op == OP_DECODE;
                                if (cmd_op == OP_BUILD) begin
                                    work_args[0] <= 32'd0;
                                    work_args[1] <= 32'd0 - (built_tokens << 2);
                                    work_args[2] <= KV_BASE;
                                    work_args[3] <= KV_BASE + built_tokens;
                                    work_args[4] <= KV_BASE + (built_tokens << 2);
                                    work_args[5] <= KV_BASE + (built_tokens << 7);
                                    work_args[6] <= built_tokens << 2;
                                    work_args[7] <= built_tokens << 8;
                                end else begin
                                    // 词表索引小于 151936，乘 4096 在无符号 32 bit 内精确。
                                    work_args[0] <= 32'd0 - (decode_steps << 2);
                                    work_args[1] <= KV_BASE;
                                    work_args[2] <= KV_BASE + decode_steps;
                                    work_args[3] <= KV_BASE + (decode_steps << 2);
                                    work_args[4] <= KV_BASE + (decode_steps << 7);
                                    work_args[5] <= cmd_token1 << 12;
                                    work_args[6] <= decode_steps << 8;
                                    work_args[7] <= cmd_token0 << 12;
                                end
                                state <= WORK_REQUEST;
                            end else if (cmd_op == OP_RELEASE || cmd_op == OP_RETIRE || cmd_op == OP_RECOVER)
                                state <= CLEAN_REQUEST;
                            else state <= COMPLETION;
                        end
                    end
                end
                WORK_REQUEST: begin
                    // 已呈现的请求保持至接受；取消 / 受控复位不撤回 valid。
                    if (work_valid && work_ready) state <= WORK_WAIT;
                end
                WORK_WAIT: begin
                    if (work_done_valid && work_done_ready) begin
                        cq_token0 <= work_token0;
                        cq_token1 <= work_token1;
                        cq_status <= work_status != 32'd0 ? 32'd2 :
                                     ((cancelled || cancelling_now) ? 32'd1 : 32'd0);
                        if (unsafe_now) state <= QUARANTINE;
                        else if (reset_pending || reset_now) state <= RESET_DRAIN;
                        else state <= COMPLETION;
                    end
                end
                CLEAN_REQUEST: if (clean_valid && clean_ready) state <= CLEAN_WAIT;
                CLEAN_WAIT: begin
                    if (clean_done_valid && clean_done_ready) begin
                        if (unsafe_now) state <= QUARANTINE;
                        else if (reset_pending || reset_now) state <= RESET_DRAIN;
                        else state <= COMPLETION;
                    end
                end
                COMPLETION: begin
                    if (unsafe_now) state <= QUARANTINE;
                    else if (reset_pending || reset_now) state <= RESET_DRAIN;
                    else if (ack_valid && cq_valid && same_receipt) begin
                        // 唯一提交沿；成功消费之前不更新可见逻辑水位和引用。
                        state <= IDLE;
                        last_error <= 32'd0;
                        if (cq_status != 32'd0) object_state <= FAILED;
                        else begin
                            case (cq_op)
                                OP_BOOT: begin
                                    session <= cq_session;
                                    session_valid <= 1'b1;
                                end
                                OP_REGISTER: begin
                                    object_id <= cq_context;
                                    generation <= generation + 32'd1;
                                    object_state <= BUILDING;
                                    built_tokens <= 32'd0;
                                    decode_steps <= 32'd0;
                                    bound_pair <= 1'b0;
                                end
                                OP_BUILD: begin
                                    built_tokens <= built_tokens + ROWS_PER_BUILD;
                                    committed_tasks <= committed_tasks + 64'd1;
                                end
                                OP_SEAL: object_state <= SEALED;
                                OP_BIND: begin
                                    bound_pair <= 1'b1;
                                    decode_steps <= 32'd0;
                                end
                                OP_DECODE: begin
                                    decode_steps <= decode_steps + 32'd1;
                                    committed_tasks <= committed_tasks + 64'd1;
                                end
                                OP_RELEASE: begin
                                    bound_pair <= 1'b0;
                                    decode_steps <= 32'd0;
                                end
                                OP_RETIRE, OP_RECOVER: begin
                                    object_state <= EMPTY;
                                    bound_pair <= 1'b0;
                                    built_tokens <= 32'd0;
                                    decode_steps <= 32'd0;
                                end
                                default: begin
                                    isolated <= 1'b1;
                                    last_error <= 32'd19;
                                    state <= QUARANTINE;
                                end
                            endcase
                        end
                    end
                end
                RESET_DRAIN: begin
                    if (unsafe_now || &epoch) state <= QUARANTINE;
                    else if (fabric_idle && idle_previous && work_ready && clean_ready)
                        state <= RESET_CLEAN_REQUEST;
                end
                RESET_CLEAN_REQUEST: if (clean_valid && clean_ready) state <= RESET_CLEAN_WAIT;
                RESET_CLEAN_WAIT: begin
                    if (clean_done_valid && clean_done_ready) begin
                        if (unsafe_now || &epoch) state <= QUARANTINE;
                        else begin
                            // 新 epoch 只在完整清理成功后建立；旧 CQ 被丢弃而非提交。
                            epoch <= epoch + 32'd1;
                            next_sequence <= 64'd1;
                            session_valid <= 1'b0;
                            session <= 64'd0;
                            object_state <= EMPTY;
                            bound_pair <= 1'b0;
                            built_tokens <= 32'd0;
                            decode_steps <= 32'd0;
                            reset_pending <= 1'b0;
                            cpu_reset_pulse <= 1'b1;
                            last_error <= 32'd0;
                            state <= IDLE;
                        end
                    end
                end
                QUARANTINE: isolated <= 1'b1;
                default: begin
                    isolated <= 1'b1;
                    last_error <= 32'd20;
                    state <= QUARANTINE;
                end
            endcase
        end
    end
endmodule
