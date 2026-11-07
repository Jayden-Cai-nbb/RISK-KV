`timescale 1ns/1ps
module tb_rkv_m1_executor;
    import rkv_m1_layout_pkg::*;
    logic clk = '0;
    logic cold_reset = '0;
    logic work_valid = '0;
    logic work_ready;
    logic work_decode = '0;
    logic [31:0] work_args [8] = '{default: '0};
    logic work_done_valid;
    logic work_done_ready = '0;
    logic [31:0] work_status;
    logic [31:0] work_token0;
    logic [31:0] work_token1;
    logic npu_halted = '0;
    logic npu_error = '0;
    logic fabric_idle = '0;
    logic fabric_error = '0;
    logic loader_busy = '0;
    logic loader_start;
    logic [31:0] loader_addr;
    logic [31:0] loader_count;
    logic npu_reset;
    logic [31:0] npu_args [8];
    logic result_store_valid = '0;
    logic [31:0] result_store_addr = '0;
    logic [1023:0] result_store_data = '0;
    logic [31:0] result_store_mask = '0;
    logic result_other_write = '0;
    logic protocol_error;
    logic launch_pulse;
    logic [63:0] task_cycles;
    logic [63:0] loader_cycles;
    always #5 clk = !clk;
    rkv_m1_executor dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .work_valid(work_valid),
        .work_ready(work_ready),
        .work_decode(work_decode),
        .work_args(work_args),
        .work_done_valid(work_done_valid),
        .work_done_ready(work_done_ready),
        .work_status(work_status),
        .work_token0(work_token0),
        .work_token1(work_token1),
        .npu_halted(npu_halted),
        .npu_error(npu_error),
        .fabric_idle(fabric_idle),
        .fabric_error(fabric_error),
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
        .loader_cycles(loader_cycles)
    );
    integer checks = 0;
    integer loads = 0;
    integer load_delay = 0;
    always @(posedge clk) begin
        if (cold_reset) begin
            loader_busy <= 0;
            load_delay <= 0;
        end else if (loader_start) begin
            loads <= loads + 1;
            if ((loader_addr == BUILD_ADDR && loader_count != BUILD_INSNS) ||
                (loader_addr == DECODE_ADDR && loader_count != DECODE_INSNS) ||
                (loader_addr != BUILD_ADDR && loader_addr != DECODE_ADDR)) $fatal(1, "untrusted loader descriptor");
            load_delay <= 4;
            loader_busy <= 1;
        end else if (load_delay > 0) begin
            load_delay <= load_delay - 1;
            if (load_delay == 1) loader_busy <= 0;
        end
    end
    task automatic tick(input integer n);
        repeat (n) begin @(posedge clk); #1; end
    endtask
    task automatic start(input logic decode);
        @(negedge clk);
        work_decode = decode;
        work_valid = 1;
        npu_halted = 0;
        for (int i = 0; i < 8; i++) work_args[i] = 32'd100 + 32'(i);
        do begin @(posedge clk); end while (!work_ready);
        @(negedge clk); work_valid = 0;
        for (int i = 0; i < 8; i++) work_args[i] = 32'hbad00000;
        while (!launch_pulse) tick(1);
        if (npu_reset) $fatal(1, "reset at launch");
        for (int i = 0; i < 8; i++) if (npu_args[i] != 32'd100 + 32'(i)) $fatal(1, "argument snapshot");
        checks++;
    endtask
    task automatic result_write(input logic [31:0] a, input logic [31:0] b);
        @(negedge clk);
        fabric_idle = 0;
        result_store_valid = 1;
        result_store_addr = RESULT_ADDRESS >> 2;
        result_store_mask = 32'd3;
        result_store_data = 1024'd0;
        result_store_data[31:0] = a;
        result_store_data[63:32] = b;
        tick(1);
        @(negedge clk); result_store_valid = 0;
    endtask
    task automatic finish(input logic [31:0] expected);
        @(negedge clk); npu_halted = 1; fabric_idle = 0;
        tick(5);
        if (work_done_valid) $fatal(1, "HALT before DDR retirement published");
        @(negedge clk); fabric_idle = 1;
        tick(1);
        if (work_done_valid) $fatal(1, "missing previous quiet cycle");
        tick(2);
        if (!work_done_valid || work_status != expected || !npu_reset) $fatal(1, "wrong task completion status %0d", work_status);
        tick(7);
        if (!work_done_valid || work_ready) $fatal(1, "completion not retained");
        checks += 4;
    endtask
    task automatic consume;
        @(negedge clk); work_done_ready = 1;
        tick(1);
        @(negedge clk); work_done_ready = 0;
        tick(2);
    endtask
    initial begin
        cold_reset = 1; fabric_idle = 1;
        tick(3);
        @(negedge clk); cold_reset = 0;
        tick(3);
        start(0); result_write(32'h3f800000, 32'h40800000); finish(0); consume();
        start(0); result_write(32'h3f800000, 32'h40800000); finish(0); consume();
        if (loads != 1) $fatal(1, "build program reloaded each task");
        start(1); result_write(32'h43bb0000, 32'h41e00000); finish(0);
        if (work_token0 != 374 || work_token1 != 28) $fatal(1, "FP32 tokens decoded incorrectly");
        consume();
        if (loads != 2) $fatal(1, "program kind change not loaded");
        // NaN、Inf、负数和小数分别不能成为可提交的 token。
        start(1); result_write(32'h7fc00000, 32'h41e00000); finish(2); consume();
        start(1); result_write(32'h7f800000, 32'h41e00000); finish(2); consume();
        start(1); result_write(32'hbf800000, 32'h41e00000); finish(2); consume();
        start(1); result_write(32'h3fc00000, 32'h41e00000); finish(2); consume();
        // 缺失回执和重复回执必须报错；错误任务后可用清理后的新任务恢复。
        start(0); finish(2); consume();
        start(0); result_write(32'h3f800000, 32'h40800000);
        result_write(32'h3f800000, 32'h40800000); finish(2); consume();
        start(0); result_write(32'h3f800000, 32'h40800000); finish(0);
        // CQ 已发布后的旧写，不属于任何当前任务；交给监督器隔离。
        result_write(32'h3f800000, 32'h40800000);
        tick(1);
        if (!protocol_error) $fatal(1, "late mailbox store accepted");
        checks += 3;
        $display("M1_EXECUTOR_PASS checks=%0d loads=%0d", checks, loads);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "test timeout");
    end
endmodule
