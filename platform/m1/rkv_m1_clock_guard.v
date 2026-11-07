// 平台准入监督：异步故障捕获只置位，整链冷复位才允许清除。
// 不生成时钟或直接复位AXI队列；原始健康信号必须满足目标器件异步置位脉宽。
module rkv_m1_clock_guard (
    input wire core_clk,
    input wire chain_cold_reset,
    input wire core_locked,
    input wire ddr_locked,
    input wire ddr_calibrated,
    input wire transport_ready,
    output wire admission_enable,
    output wire fault,
    output wire [3:0] fault_causes,
    output reg armed = 1'b0
);
    // 四位为独立健康条件，不是需要原子传递的数据总线：bit0至3依次对应四个输入。
    wire [3:0] healthy_raw;
    (* ASYNC_REG = "TRUE" *) reg [3:0] healthy_meta = 4'b0000;
    (* ASYNC_REG = "TRUE" *) reg [3:0] healthy_sync = 4'b0000;
    (* ASYNC_REG = "TRUE" *) reg [3:0] healthy_stable = 4'b0000;
    reg [3:0] stable_count = 4'd0;
    wire [3:0] fault_event;
    genvar cause;

    assign healthy_raw = {transport_ready, ddr_calibrated, ddr_locked, core_locked};
    assign fault_event = {4{armed}} & ~healthy_raw;
    assign fault = |fault_causes;
    assign admission_enable = armed && !fault && !chain_cold_reset;

    // 冷复位异步关闭准入，释放须重新经过三级同步和连续16个有效core沿。
    // 计数从0到15共16次合格采样；armed一经置位，普通健康恢复不能重新建资格。
    always @(posedge core_clk or posedge chain_cold_reset) begin
        if (chain_cold_reset) begin
            healthy_meta <= 4'b0000;
            healthy_sync <= 4'b0000;
            healthy_stable <= 4'b0000;
            stable_count <= 4'd0;
            armed <= 1'b0;
        end else begin
            healthy_meta <= healthy_raw;
            healthy_sync <= healthy_meta;
            healthy_stable <= healthy_sync;
            if (!armed) begin
                if (&healthy_stable) begin
                    if (stable_count == 4'd15) armed <= 1'b1;
                    else stable_count <= stable_count + 4'd1;
                end else stable_count <= 4'd0;
            end
        end
    end

    // 每个原因独占一个异步置位FF。故障优先于同步清除；没有时钟时仍保留事件。
    // chain_cold_reset须保持到core恢复并至少采样一次；最终平台应按整链复位序列延展。
    generate
        for (cause = 0; cause < 4; cause = cause + 1) begin : capture
            reg sticky = 1'b0;
            assign fault_causes[cause] = sticky;
            always @(posedge core_clk or posedge fault_event[cause]) begin
                if (fault_event[cause]) sticky <= 1'b1;
                else if (chain_cold_reset) sticky <= 1'b0;
            end
        end
    endgenerate
endmodule
