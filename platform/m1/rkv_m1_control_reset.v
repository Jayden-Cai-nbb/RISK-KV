// 主机控制仅等待core时钟，DDR UI未启动时仍可读取状态并拒绝DDR访问。
// 只接整链cold；普通受控复位、运行失锁都不能清掉主机/存储在途责任。
module rkv_m1_control_reset (
    input wire core_clk,
    input wire chain_cold_reset,
    output reg control_aresetn = 1'b0,
    output wire control_cold_reset
);
    reg [15:0] hold = 16'd0;
    assign control_cold_reset = !control_aresetn;

    // 异步断言，core本地移入16个1后下一沿释放；停钟不会提前解除复位。
    always @(posedge core_clk or posedge chain_cold_reset) begin
        if (chain_cold_reset) begin
            hold <= 16'd0;
            control_aresetn <= 1'b0;
        end else begin
            hold <= {hold[14:0], 1'b1};
            control_aresetn <= hold[15];
        end
    end
endmodule
