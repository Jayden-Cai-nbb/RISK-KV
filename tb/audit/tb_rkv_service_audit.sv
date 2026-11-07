`timescale 1ns/1ps
// 独立协议审计：外部 NPU/访存由明确夹具驱动，不作为模型数值证据。
module tb_rkv_service_audit;
    localparam logic [31:0] KV_BASE = 32'd1233223680;
    localparam logic [31:0] RESULT_ADDR = 32'd1229289088;
    localparam logic [63:0] SESSION = 64'h1122334455667788;
    localparam logic [63:0] NEW_SESSION = 64'h8877665544332211;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic bus_valid = 1'b0;
    logic [11:0] bus_addr = 12'b0;
    logic [31:0] bus_wdata = 32'b0;
    logic [3:0] bus_wstrb = 4'b0;
    logic bus_ready;
    logic [31:0] bus_rdata;
    logic npu_halted = 1'b0;
    logic npu_error = 1'b0;
    logic fabric_idle = 1'b1;
    logic fabric_error = 1'b0;
    logic loader_busy = 1'b0;
    logic loader_start;
    logic [31:0] loader_addr;
    logic [31:0] loader_count;
    logic result_store_valid = 1'b0;
    logic result_other_write = 1'b0;
    logic [31:0] result_store_addr = 32'b0;
    logic [1023:0] result_store_data = 1024'b0;
    logic [31:0] result_store_mask = 32'b0;
    logic npu_reset;
    logic [31:0] npu_args [8];
    logic completion_valid;
    logic active;
    logic launch_pulse;
    logic program_ready;
    logic result_valid;
    logic [31:0] completion_status;
    logic [31:0] completion_context;
    logic [31:0] completion_generation;
    logic [63:0] completion_session;
    logic [63:0] completion_sequence;
    logic [31:0] accepted_count;
    logic [31:0] rejected_count;
    logic [31:0] result_token0;
    logic [31:0] result_token1;
    // 此字表示不受控制复位驱动的外部存储。没有向 DUT 内部注入状态。
    logic [31:0] retained_memory = 32'h7fc01234;
    // 保存第一笔合法回执的两个 FP32 字，控制复位不修改此夹具存储。
    logic [63:0] retained_receipt = 64'b0;
    logic [31:0] replay_status;
    integer checks = 0;
    logic [31:0] value;

    always #5 clk = ~clk;

    rkv_npu_context_service #(
        .RESULT_ADDR(RESULT_ADDR)
    ) dut (
        .clk(clk),
        .reset(reset),
        .bus_valid(bus_valid),
        .bus_addr(bus_addr),
        .bus_wdata(bus_wdata),
        .bus_wstrb(bus_wstrb),
        .bus_ready(bus_ready),
        .bus_rdata(bus_rdata),
        .npu_halted(npu_halted),
        .npu_error(npu_error),
        .fabric_idle(fabric_idle),
        .fabric_error(fabric_error),
        .loader_busy(loader_busy),
        .loader_start(loader_start),
        .loader_addr(loader_addr),
        .loader_count(loader_count),
        .result_store_valid(result_store_valid),
        .result_other_write(result_other_write),
        .result_store_addr(result_store_addr),
        .result_store_data(result_store_data),
        .result_store_mask(result_store_mask),
        .npu_reset(npu_reset),
        .npu_args(npu_args),
        .completion_valid(completion_valid),
        .active(active),
        .launch_pulse(launch_pulse),
        .program_ready(program_ready),
        .result_valid(result_valid),
        .completion_status(completion_status),
        .completion_context(completion_context),
        .completion_generation(completion_generation),
        .completion_session(completion_session),
        .completion_sequence(completion_sequence),
        .accepted_count(accepted_count),
        .rejected_count(rejected_count),
        .result_token0(result_token0),
        .result_token1(result_token1)
    );

    // 下降沿驱动和采样，所检查值来自前一个上升沿的 NBA 更新。
    task automatic tick(input integer count);
        repeat(count) @(negedge clk);
    endtask
    task automatic verify(input logic condition, input string label_text);
        if (!condition) $fatal(1, "AUDIT_FAIL %s", label_text);
        checks = checks + 1;
    endtask
    task automatic wr(input logic [11:0] address, input logic [31:0] data);
        @(negedge clk);
        bus_addr = address;
        bus_wdata = data;
        bus_wstrb = 4'hf;
        bus_valid = 1'b1;
        do @(negedge clk); while (!bus_ready);
        bus_valid = 1'b0;
        bus_wstrb = 4'b0;
        @(negedge clk);
    endtask
    task automatic rd(input logic [11:0] address, output logic [31:0] data);
        @(negedge clk);
        bus_addr = address;
        bus_wstrb = 4'b0;
        bus_valid = 1'b1;
        do @(negedge clk); while (!bus_ready);
        data = bus_rdata;
        bus_valid = 1'b0;
        @(negedge clk);
    endtask
    task automatic expect_error(input logic [31:0] expected);
        rd(12'h008, value);
        verify(value == expected, "core error code");
    endtask
    task automatic args_build(input logic [31:0] progress);
        wr(12'h040, 32'b0);
        // 地址偏移按无符号 32 位模运算，保持原生编译器的八参数编码。
        wr(12'h044, 32'b0 - (progress << 2));
        wr(12'h048, KV_BASE);
        wr(12'h04c, KV_BASE + progress);
        wr(12'h050, KV_BASE + (progress << 2));
        wr(12'h054, KV_BASE + (progress << 7));
        wr(12'h058, progress << 2);
        wr(12'h05c, progress << 8);
    endtask
    task automatic setup_session(input logic [63:0] session_value);
        @(negedge clk);
        reset = 1'b1;
        bus_valid = 1'b0;
        bus_wstrb = 4'b0;
        npu_halted = 1'b0;
        npu_error = 1'b0;
        fabric_idle = 1'b1;
        fabric_error = 1'b0;
        loader_busy = 1'b0;
        result_store_valid = 1'b0;
        result_other_write = 1'b0;
        tick(3);
        reset = 1'b0;
        tick(3);
        wr(12'h010, session_value[31:0]);
        wr(12'h014, session_value[63:32]);
        wr(12'h00c, 32'd1);
        wr(12'h020, session_value[31:0]);
        wr(12'h024, session_value[63:32]);
        wr(12'h028, 32'd1);
        wr(12'h02c, 32'd0);
        wr(12'h030, 32'd1);
        wr(12'h034, 32'd7);
        wr(12'h200, 32'd1);
        rd(12'h208, value);
        verify(value == 32'b0, "register clean logical slot");
        wr(12'h100, 32'h60000000);
        wr(12'h104, 32'd1026);
        wr(12'h108, 32'd1);
        // loader 先确认 busy，再排空；busy 下降不立即等于 program_ready。
        loader_busy = 1'b1;
        fabric_idle = 1'b0;
        tick(3);
        loader_busy = 1'b0;
        tick(2);
        verify(!program_ready, "loader waits for fabric drain");
        fabric_idle = 1'b1;
        tick(4);
        verify(program_ready, "loader ready after drain");
        args_build(32'b0);
        wr(12'h00c, 32'd2);
        expect_error(32'b0);
        tick(5);
        verify(active && !npu_reset && accepted_count == 32'd1, "accepted build runs");
    endtask
    task automatic setup;
        setup_session(SESSION);
    endtask
    task automatic receipt;
        @(negedge clk);
        result_store_addr = RESULT_ADDR >> 2;
        result_store_data = 1024'b0;
        result_store_data[31:0] = 32'h3f800000;
        result_store_data[63:32] = 32'h40800000;
        result_store_mask = 32'd3;
        result_store_valid = 1'b1;
        tick(1);
        result_store_valid = 1'b0;
        tick(2);
    endtask
    task automatic finish_success;
        npu_halted = 1'b1;
        fabric_idle = 1'b1;
        tick(4);
        verify(completion_valid && completion_status == 32'b0 && result_valid, "visible successful receipt");
    endtask
    task automatic cancel_at_completion(input logic with_error);
        // quiet_previous 已经稳定；在同一接受沿送 CANCEL、halt 和可选执行错误。
        @(negedge clk);
        bus_addr = 12'h00c;
        bus_wdata = 32'd4;
        bus_wstrb = 4'hf;
        bus_valid = 1'b1;
        npu_halted = 1'b1;
        npu_error = with_error;
        tick(1);
        verify(bus_ready && completion_valid, "cancel and completion accepted together");
        bus_valid = 1'b0;
        bus_wstrb = 4'b0;
        npu_error = 1'b0;
        tick(3);
        verify(completion_status == (with_error ? 32'd2 : 32'd1), "execution error precedes cancel precedes success");
        wr(12'h00c, 32'd3);
        tick(3);
        rd(12'h20c, value);
        verify(value == 32'b0, "failed/cancelled completion never commits");
    endtask

    initial begin
        setup();
        receipt();
        retained_receipt = result_store_data[63:0];
        finish_success();
        tick(64);
        rd(12'h20c, value);
        verify(value == 32'b0, "completion held until ACK");
        wr(12'h028, 32'd2);
        wr(12'h00c, 32'd3);
        expect_error(32'd7);
        verify(completion_valid, "wrong ACK identity leaves result pending");
        wr(12'h028, 32'd1);
        wr(12'h020, SESSION[31:0] ^ 32'd1);
        wr(12'h00c, 32'd3);
        expect_error(32'd7);
        verify(completion_valid, "wrong ACK session leaves result pending");
        wr(12'h020, SESSION[31:0]);
        wr(12'h00c, 32'd3);
        tick(3);
        rd(12'h20c, value);
        verify(value == 32'd4, "exactly one four-token commit");
        wr(12'h00c, 32'd3);
        expect_error(32'd7);
        args_build(32'd4);
        wr(12'h00c, 32'd2);
        expect_error(32'd5);
        verify(accepted_count == 32'd1, "duplicate sequence not accepted");
        $display("AUDIT_CASE delayed_ack_and_duplicate_identity passed");

        // 只改变外部暂存寄存器，逐一隔离 session、对象、代际和参数校验。
        wr(12'h028, 32'd2);
        wr(12'h020, SESSION[31:0] ^ 32'd1);
        wr(12'h00c, 32'd2);
        expect_error(32'd5);
        wr(12'h020, SESSION[31:0]);
        wr(12'h030, 32'd2);
        wr(12'h00c, 32'd2);
        expect_error(32'd9);
        wr(12'h030, 32'd1);
        wr(12'h034, 32'd8);
        wr(12'h00c, 32'd2);
        expect_error(32'd9);
        wr(12'h034, 32'd7);
        wr(12'h048, KV_BASE + 32'd4);
        wr(12'h00c, 32'd2);
        expect_error(32'd9);
        verify(accepted_count == 32'd1, "wrong identities and address cannot launch");
        $display("AUDIT_CASE wrong_identity_and_address passed");

        setup();
        receipt();
        cancel_at_completion(1'b0);
        $display("AUDIT_CASE cancel_same_edge passed");
        setup();
        receipt();
        cancel_at_completion(1'b1);
        $display("AUDIT_CASE error_cancel_same_edge passed");

        setup();
        fabric_idle = 1'b0;
        wr(12'h00c, 32'd4);
        tick(128);
        verify(active && !completion_valid, "cancel remains active without halt/drain");
        $display("AUDIT_OBSERVATION lost_response active=1 completion=0 observed_cycles=128");

        setup();
        receipt();
        receipt();
        npu_halted = 1'b1;
        tick(5);
        verify(completion_valid && completion_status == 32'd2 && !result_valid, "duplicate write faults task");
        wr(12'h00c, 32'd3);
        tick(3);
        rd(12'h20c, value);
        verify(value == 32'b0, "duplicate result does not commit");
        $display("AUDIT_CASE duplicate_result_before_completion passed");

        setup();
        receipt();
        finish_success();
        // 故意违反已排空边界：完成发布以后又到达重复写。记录行为，不伪装成合法总线序列。
        receipt();
        verify(!result_valid && !program_ready, "late result invalidates mailbox and program");
        wr(12'h00c, 32'd3);
        tick(3);
        rd(12'h20c, value);
        $display("AUDIT_OBSERVATION late_write_after_publish committed_tokens=%0d assumption=fabric_retirement_violated", value);

        // 重置控制不重置外部存储，也不强制改变 session：暴露平台必须承担的启动义务。
        setup();
        verify(retained_memory == 32'h7fc01234, "external memory survives controller reset");
        verify(completion_session == SESSION && completion_sequence == 64'd1, "session and sequence can repeat after reset");
        $display("AUDIT_OBSERVATION reset_retained_memory accepted=1 repeated_identity=1 memory=%h", retained_memory);
        // 外部平台没有隔离旧通道时，将复位前保存的回执经实际输入端口重放。
        // 这是跨复位退休前提缺失的观察，不把旧回执提交列为正常合同要求。
        verify(retained_receipt == 64'h408000003f800000, "old accepted receipt survives reset");
        @(negedge clk);
        result_store_addr = RESULT_ADDR >> 2;
        result_store_data = 1024'b0;
        result_store_data[63:0] = retained_receipt;
        result_store_mask = 32'd3;
        result_store_valid = 1'b1;
        tick(1);
        result_store_valid = 1'b0;
        tick(2);
        npu_halted = 1'b1;
        fabric_idle = 1'b1;
        tick(4);
        verify(completion_valid, "reset replay fixture reaches completion publication");
        replay_status = completion_status;
        wr(12'h00c, 32'd3);
        tick(3);
        rd(12'h20c, value);
        $display("AUDIT_OBSERVATION reset_old_receipt status=%0d committed_tokens=%0d receipt=%h assumption=no_cross_reset_fence", replay_status, value, retained_receipt);
        // 更换 MMIO 身份但仍不隔离旧物理通道，单独检查身份更新是否足够。
        // 旧回执来自前一 session；输入写回端口本身没有 session 字段。
        setup_session(NEW_SESSION);
        verify(completion_session == NEW_SESSION && NEW_SESSION != SESSION,
            "new task uses a different MMIO session");
        @(negedge clk);
        result_store_addr = RESULT_ADDR >> 2;
        result_store_data = 1024'b0;
        result_store_data[63:0] = retained_receipt;
        result_store_mask = 32'd3;
        result_store_valid = 1'b1;
        tick(1);
        result_store_valid = 1'b0;
        tick(2);
        npu_halted = 1'b1;
        fabric_idle = 1'b1;
        tick(4);
        verify(completion_valid, "new-session replay fixture reaches completion publication");
        replay_status = completion_status;
        wr(12'h00c, 32'd3);
        tick(3);
        rd(12'h20c, value);
        $display("AUDIT_OBSERVATION reset_old_receipt_new_session status=%0d committed_tokens=%0d old_session=%h new_session=%h assumption=no_cross_reset_fence", replay_status, value, SESSION, completion_session);
        $display("PASS service audit checks=%0d contract_cases=5 boundary_observations=5", checks);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "audit timeout");
    end
endmodule
