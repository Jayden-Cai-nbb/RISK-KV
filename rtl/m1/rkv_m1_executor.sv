// 可信固定程序执行器；实际装载握手、三拍 ARM、结果收集和两拍排空。
module rkv_m1_executor (
    input logic clk,
    input logic cold_reset,
    input logic work_valid,
    output logic work_ready,
    input logic work_decode,
    input logic [31:0] work_args [8],
    output logic work_done_valid,
    input logic work_done_ready,
    output logic [31:0] work_status,
    output logic [31:0] work_token0,
    output logic [31:0] work_token1,
    input logic npu_halted,
    input logic npu_error,
    input logic fabric_idle,
    input logic fabric_error,
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
    output logic [63:0] loader_cycles
);
    import rkv_m1_layout_pkg::*;
    typedef enum logic [3:0] {IDLE, LOAD_START, LOAD_WAIT, LOAD_ACTIVE, LOAD_DRAIN, ARM, RUN, DONE} state_t;
    state_t state;
    logic loaded;
    logic loaded_decode;
    logic task_decode;
    logic [1:0] arm_count;
    logic quiet_previous;
    logic task_error;
    logic [1:0] seen;
    logic [31:0] raw_result0;
    logic [31:0] raw_result1;
    logic [32:0] converted0;
    logic [32:0] converted1;
    logic result_bad_now;
    localparam logic [31:0] RESULT_WORD = RESULT_ADDRESS >> 2;

    // Argmax 写出 FP32 整数。只接受词表范围内的精确非负整数，拒绝 NaN/Inf/小数。
    function automatic logic [32:0] token_integer(input logic [31:0] raw);
        logic [31:0] mantissa;
        logic [31:0] value;
        logic [7:0] shift_count;
        mantissa = {8'd0, 1'b1, raw[22:0]};
        shift_count = 8'd150 - raw[30:23];
        value = mantissa >> shift_count;
        if (raw == 32'd0) token_integer = {1'b1, 32'd0};
        else token_integer = {(!raw[31] && raw[30:23] >= 8'd127 && raw[30:23] <= 8'd144 &&
                              value < VOCAB && (value << shift_count) == mantissa), value};
    endfunction
    always_comb begin
        converted0 = token_integer(raw_result0);
        converted1 = token_integer(raw_result1);
        result_bad_now = result_other_write;
        for (int w = 0; w < 32; w++) begin
            if (result_store_valid && result_store_mask[w] &&
                (result_store_addr + 32'(w) == RESULT_WORD || result_store_addr + 32'(w) == RESULT_WORD + 32'd1)) begin
                if (state != RUN || seen[result_store_addr + 32'(w) == RESULT_WORD + 32'd1]) result_bad_now = 1'b1;
            end
        end
    end
    assign work_ready = state == IDLE && fabric_idle && quiet_previous && !loader_busy && !protocol_error;
    assign work_done_valid = state == DONE;
    assign npu_reset = cold_reset || state != RUN;

    always_ff @(posedge clk) begin
        if (cold_reset) begin
            state <= IDLE;
            loaded <= 1'b0;
            loaded_decode <= 1'b0;
            task_decode <= 1'b0;
            arm_count <= 2'd0;
            quiet_previous <= 1'b0;
            task_error <= 1'b0;
            seen <= 2'd0;
            raw_result0 <= 32'd0;
            raw_result1 <= 32'd0;
            work_status <= 32'd0;
            work_token0 <= 32'd0;
            work_token1 <= 32'd0;
            loader_start <= 1'b0;
            loader_addr <= 32'd0;
            loader_count <= 32'd0;
            protocol_error <= 1'b0;
            launch_pulse <= 1'b0;
            task_cycles <= 64'd0;
            loader_cycles <= 64'd0;
            for (int i = 0; i < 8; i++) npu_args[i] <= 32'd0;
        end else begin
            loader_start <= 1'b0;
            launch_pulse <= 1'b0;
            quiet_previous <= fabric_idle && !loader_busy;
            if (state == RUN) task_cycles <= task_cycles + 64'd1;
            if (state == LOAD_WAIT || state == LOAD_ACTIVE || state == LOAD_DRAIN)
                loader_cycles <= loader_cycles + 64'd1;
            if (fabric_error) protocol_error <= 1'b1;
            if (state == RUN && (npu_error || result_bad_now)) task_error <= 1'b1;
            if (result_bad_now && state != RUN) protocol_error <= 1'b1;

            // 只观察 NPU 被接受的 B 写；清理 / 主机写不得接到此结果观察端。
            for (int w = 0; w < 32; w++) begin
                if (state == RUN && result_store_valid && result_store_mask[w]) begin
                    if (result_store_addr + 32'(w) == RESULT_WORD) begin
                        raw_result0 <= result_store_data[w*32 +: 32];
                        seen[0] <= 1'b1;
                    end
                    if (result_store_addr + 32'(w) == RESULT_WORD + 32'd1) begin
                        raw_result1 <= result_store_data[w*32 +: 32];
                        seen[1] <= 1'b1;
                    end
                end
            end
            case (state)
                IDLE: begin
                    if (work_valid && work_ready) begin
                        for (int i = 0; i < 8; i++) npu_args[i] <= work_args[i];
                        task_decode <= work_decode;
                        seen <= 2'd0;
                        task_error <= 1'b0;
                        raw_result0 <= 32'd0;
                        raw_result1 <= 32'd0;
                        work_status <= 32'd0;
                        arm_count <= 2'd0;
                        if (loaded && loaded_decode == work_decode) state <= ARM;
                        else begin
                            loader_addr <= work_decode ? DECODE_ADDR : BUILD_ADDR;
                            loader_count <= work_decode ? DECODE_INSNS : BUILD_INSNS;
                            state <= LOAD_START;
                        end
                    end
                end
                LOAD_START: begin
                    loader_start <= 1'b1;
                    loaded <= 1'b0;
                    state <= LOAD_WAIT;
                end
                LOAD_WAIT: if (loader_busy) state <= LOAD_ACTIVE;
                LOAD_ACTIVE: if (!loader_busy) state <= LOAD_DRAIN;
                LOAD_DRAIN: begin
                    if (fabric_idle && quiet_previous && !loader_busy) begin
                        loaded <= 1'b1;
                        loaded_decode <= task_decode;
                        state <= ARM;
                    end
                end
                ARM: begin
                    if (arm_count == 2'd2) begin
                        state <= RUN;
                        launch_pulse <= 1'b1;
                    end else arm_count <= arm_count + 2'd1;
                end
                RUN: begin
                    // 结果到达不能当作完成；HALT、真实退休、前拍退休必须同时满足。
                    if (npu_halted && fabric_idle && quiet_previous && !loader_busy) begin
                        state <= DONE;
                        work_token0 <= task_decode ? converted0[31:0] : 32'd0;
                        work_token1 <= task_decode ? converted1[31:0] : 32'd0;
                        if (task_error || npu_error || fabric_error || result_bad_now || seen != 2'b11 ||
                            (task_decode && (!converted0[32] || !converted1[32])) ||
                            (!task_decode && (raw_result0 != 32'h3f800000 || raw_result1 != 32'h40800000)))
                            work_status <= 32'd2;
                        else work_status <= 32'd0;
                    end
                end
                DONE: if (work_done_valid && work_done_ready) state <= IDLE;
                default: protocol_error <= 1'b1;
            endcase
        end
    end
endmodule
