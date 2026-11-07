`timescale 1ns/1ps
module tb_rkv_m1_control;
    import rkv_m1_layout_pkg::*;
    logic clk = '0;
    logic cold_reset = '0;
    logic reset_request = '0;
    logic cpu_reset_pulse;
    logic fabric_idle = '0;
    logic fabric_error = '0;
    logic cmd_valid = '0;
    logic cmd_ready;
    logic [31:0] cmd_op = '0;
    logic [63:0] cmd_session = '0;
    logic [31:0] cmd_epoch = '0;
    logic [63:0] cmd_sequence = '0;
    logic [31:0] cmd_context = '0;
    logic [31:0] cmd_generation = '0;
    logic [31:0] cmd_token0 = '0;
    logic [31:0] cmd_token1 = '0;
    logic ack_valid = '0;
    logic cancel_valid = '0;
    logic [63:0] receipt_session = '0;
    logic [31:0] receipt_epoch = '0;
    logic [63:0] receipt_sequence = '0;
    logic [31:0] receipt_context = '0;
    logic [31:0] receipt_generation = '0;
    logic cq_valid;
    logic [31:0] cq_op;
    logic [31:0] cq_status;
    logic [63:0] cq_session;
    logic [31:0] cq_epoch;
    logic [63:0] cq_sequence;
    logic [31:0] cq_context;
    logic [31:0] cq_generation;
    logic [31:0] cq_token0;
    logic [31:0] cq_token1;
    logic work_valid;
    logic work_ready = '0;
    logic work_decode;
    logic [31:0] work_args [8];
    logic work_done_valid = '0;
    logic work_done_ready;
    logic [31:0] work_status = '0;
    logic [31:0] work_token0 = '0;
    logic [31:0] work_token1 = '0;
    logic clean_valid;
    logic clean_ready = '0;
    logic clean_full;
    logic clean_done_valid = '0;
    logic clean_done_ready;
    logic clean_isolated = '0;
    logic isolated;
    logic reset_pending;
    logic session_valid;
    logic [63:0] session;
    logic [31:0] epoch;
    logic [63:0] next_sequence;
    logic [31:0] generation;
    logic [31:0] object_id;
    logic [2:0] object_state;
    logic bound_pair;
    logic [31:0] built_tokens;
    logic [31:0] decode_steps;
    logic [63:0] accepted_count;
    logic [63:0] rejected_count;
    logic [63:0] committed_tasks;
    logic [31:0] last_error;
    always #5 clk = !clk;
    rkv_m1_control #(.TIMEOUT_CYCLES(32'd128)) dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .reset_request(reset_request),
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
        .work_valid(work_valid),
        .work_ready(work_ready),
        .work_decode(work_decode),
        .work_args(work_args),
        .work_done_valid(work_done_valid),
        .work_done_ready(work_done_ready),
        .work_status(work_status),
        .work_token0(work_token0),
        .work_token1(work_token1),
        .clean_valid(clean_valid),
        .clean_ready(clean_ready),
        .clean_full(clean_full),
        .clean_done_valid(clean_done_valid),
        .clean_done_ready(clean_done_ready),
        .clean_isolated(clean_isolated),
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
        .last_error(last_error)
    );
    integer checks = 0;
    integer command_attempts = 0;
    logic [63:0] host_session = 64'h123456789abcdef0;
    logic [31:0] old_epoch;
    logic [63:0] before_reject;
    logic [63:0] before_commit;

    task automatic tick(input integer n);
        repeat (n) begin @(posedge clk); #1; end
    endtask
    task automatic cold;
        @(negedge clk);
        cold_reset = 1;
        reset_request = 0;
        cmd_valid = 0;
        ack_valid = 0;
        cancel_valid = 0;
        work_done_valid = 0;
        clean_done_valid = 0;
        clean_isolated = 0;
        fabric_error = 0;
        fabric_idle = 1;
        work_ready = 1;
        clean_ready = 1;
        tick(3);
        @(negedge clk); cold_reset = 0;
        tick(3);
    endtask
    task automatic receipt;
        receipt_session = cq_session;
        receipt_epoch = cq_epoch;
        receipt_sequence = cq_sequence;
        receipt_context = cq_context;
        receipt_generation = cq_generation;
    endtask
    task automatic issue(input logic [31:0] op);
        if (!cmd_ready) $fatal(1, "command not ready op=%0d", op);
        @(negedge clk);
        cmd_op = op;
        cmd_session = host_session;
        cmd_epoch = epoch;
        cmd_sequence = next_sequence;
        cmd_context = 32'd7;
        cmd_generation = generation;
        cmd_token0 = 32'd3555;
        cmd_token1 = 32'd8429;
        cmd_valid = 1;
        tick(1);
        @(negedge clk); cmd_valid = 0;
        command_attempts++;
    endtask
    task automatic consume;
        if (!cq_valid) $fatal(1, "completion missing for op %0d", cq_op);
        @(negedge clk); receipt(); ack_valid = 1;
        tick(1);
        @(negedge clk); ack_valid = 0;
        tick(1);
    endtask
    task automatic immediate(input logic [31:0] op);
        issue(op);
        if (!cq_valid || cq_status != 0) $fatal(1, "immediate op failed %0d", op);
        consume();
    endtask
    task automatic finish_work(input logic [31:0] status, input logic cancel_same_edge);
        tick(2);
        if (!work_done_ready) $fatal(1, "executor result not expected");
        @(negedge clk);
        receipt();
        work_status = status;
        work_token0 = 32'd374;
        work_token1 = 32'd28;
        work_done_valid = 1;
        cancel_valid = cancel_same_edge;
        tick(1);
        @(negedge clk); work_done_valid = 0; cancel_valid = 0;
        tick(1);
    endtask
    task automatic finish_clean(input logic expect_full);
        if (!clean_valid || clean_full != expect_full) $fatal(1, "wrong clean mode");
        tick(2);
        if (!clean_done_ready || cmd_ready || cq_valid) $fatal(1, "cleanup not fenced");
        tick(6);
        @(negedge clk); clean_done_valid = 1;
        tick(1);
        @(negedge clk); clean_done_valid = 0;
        tick(1);
    endtask
    task automatic reject_current;
        before_reject = rejected_count;
        @(negedge clk); cmd_valid = 1;
        tick(1);
        @(negedge clk); cmd_valid = 0;
        tick(1);
        if (rejected_count != before_reject + 1 || cq_valid) $fatal(1, "bad command not rejected");
        command_attempts++;
        checks++;
    endtask

    initial begin
        cold();
        immediate(OP_BOOT);
        immediate(OP_REGISTER);
        if (generation != 1 || object_state != 1 || built_tokens != 0) $fatal(1, "register generation");
        issue(OP_BUILD);
        if (work_args[0] != 0 || work_args[2] != KV_BASE || work_args[7] != 0) $fatal(1, "build arguments");
        finish_work(0, 0);
        tick(20);
        if (built_tokens != 0 || !cq_valid) $fatal(1, "commit before consumption");
        @(negedge clk); receipt(); receipt_session ^= 64'd1; ack_valid = 1;
        tick(1);
        @(negedge clk); ack_valid = 0;
        tick(1);
        if (!cq_valid || built_tokens != 0) $fatal(1, "wrong session ACK committed");
        consume();
        if (built_tokens != 4 || committed_tasks != 1) $fatal(1, "success not committed exactly once");
        // 重放刚提交的命令和 ACK；不得重复推进逻辑水位。
        reject_current();
        @(negedge clk); ack_valid = 1;
        tick(1);
        @(negedge clk); ack_valid = 0;
        tick(1);
        if (built_tokens != 4) $fatal(1, "duplicate ACK");
        checks += 5;
        // 当前序号但错误代际、epoch、session、context，各自到达准入边界。
        cmd_sequence = next_sequence; cmd_generation = generation + 1; reject_current();
        cmd_generation = generation; cmd_epoch = epoch + 1; reject_current();
        cmd_epoch = epoch; cmd_session = host_session ^ 64'd1; reject_current();
        cmd_session = host_session; cmd_context = 8; reject_current();
        cmd_context = 7;
        issue(OP_BUILD); finish_work(0, 1);
        if (cq_status != 1 || built_tokens != 4) $fatal(1, "cancel completion race");
        consume();
        if (object_state != 3 || built_tokens != 4) $fatal(1, "cancel committed progress");
        issue(OP_RECOVER); finish_clean(1); consume();
        immediate(OP_REGISTER);
        if (generation != 2 || built_tokens != 0) $fatal(1, "recovery generation");
        issue(OP_BUILD); finish_work(2, 1);
        if (cq_status != 2) $fatal(1, "error must precede cancel");
        consume();
        issue(OP_RECOVER); finish_clean(1); consume();
        checks += 4;

        // 真正反复走完构建、封存、两轮绑定、清理和退役；没有层级强制状态。
        for (int round = 0; round < 140; round++) begin
            immediate(OP_REGISTER);
            for (int build = 0; build < 64; build++) begin
                issue(OP_BUILD);
                if (work_args[1] != (32'd0 - 32'(build * 16)) || work_args[3] != KV_BASE + 32'(build * 4))
                    $fatal(1, "build runtime argument mismatch");
                finish_work(0, 0);
                if (built_tokens != 32'(build * 4)) $fatal(1, "early build watermark");
                consume();
                if (built_tokens != 32'((build + 1) * 4)) $fatal(1, "build watermark");
            end
            immediate(OP_SEAL);
            for (int pair = 0; pair < 2; pair++) begin
                immediate(OP_BIND);
                for (int step = 0; step < 3; step++) begin
                    issue(OP_DECODE);
                    if (!work_decode || work_args[5] != (32'd8429 << 12) || work_args[6] != 32'(step * 256))
                        $fatal(1, "decode arguments");
                    finish_work(0, 0); consume();
                    if (decode_steps != 32'(step+1)) $fatal(1, "decode watermark");
                end
                issue(OP_RELEASE);
                if (!bound_pair || built_tokens != 256) $fatal(1, "released before cleanup");
                finish_clean(0);
                if (!bound_pair) $fatal(1, "released before consume");
                consume();
                if (bound_pair || built_tokens != 256 || decode_steps != 0) $fatal(1, "prefix reuse");
            end
            issue(OP_RETIRE); finish_clean(1); consume();
            if (object_state != 0 || bound_pair || built_tokens != 0) $fatal(1, "retirement");
            checks += 73;
        end
        if (accepted_count < 10000 || command_attempts < 10000) $fatal(1, "lifecycle coverage too small");
        $display("M1_CONTROL_LIFECYCLE accepted=%0d attempts=%0d", accepted_count, command_attempts);

        // 受控复位请求在任务中到达，必须等待任务退休和整区清理。
        immediate(OP_REGISTER);
        issue(OP_BUILD);
        before_commit = committed_tasks;
        old_epoch = epoch;
        @(negedge clk); reset_request = 1;
        tick(1);
        @(negedge clk); reset_request = 0;
        tick(5);
        if (!reset_pending || cpu_reset_pulse || epoch != old_epoch || clean_valid) $fatal(1, "reset before task retirement");
        finish_work(0, 0);
        while (!clean_valid) tick(1);
        finish_clean(1);
        if (epoch != old_epoch + 1 || session_valid || reset_pending || committed_tasks != before_commit)
            $fatal(1, "reset committed old work / did not advance epoch");
        immediate(OP_BOOT);
        immediate(OP_REGISTER);
        checks += 3;

        // 永久停顿与迟到完成，不允许新任务或旧进度进入新对象。
        issue(OP_BUILD); tick(150);
        if (!isolated || cmd_ready || cq_valid || built_tokens != 0) $fatal(1, "stalled work not isolated");
        finish_work(0, 0);
        if (!isolated || cq_valid || built_tokens != 0) $fatal(1, "late result reused slot");
        checks += 2;
        cold();
        @(negedge clk); work_done_valid = 1;
        tick(1);
        @(negedge clk); work_done_valid = 0;
        tick(2);
        if (!isolated) $fatal(1, "orphan result not isolated");
        checks++;
        // 迟到重复结果与成功 ACK 同沿：隔离必须阻止该沿逻辑提交。
        cold();
        immediate(OP_BOOT); immediate(OP_REGISTER);
        issue(OP_BUILD); finish_work(0, 0);
        @(negedge clk); receipt(); ack_valid = 1; work_done_valid = 1;
        tick(1);
        @(negedge clk); ack_valid = 0; work_done_valid = 0;
        tick(1);
        if (!isolated || built_tokens != 0) $fatal(1, "orphan response raced ACK and committed");
        checks++;
        $display("M1_CONTROL_PASS checks=%0d transactions=%0d", checks, command_attempts);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "test timeout");
    end
endmodule
