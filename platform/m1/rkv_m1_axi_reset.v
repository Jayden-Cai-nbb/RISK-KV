// AXI两域冷复位协调：各域先观察16个有效沿，再交叉确认，最后同步释放。
// 只接整链cold请求；运行失锁不得借此抹掉在途请求和退休责任。
module rkv_m1_axi_reset (
    input wire core_clk,
    input wire ddr_clk,
    input wire chain_cold_reset,
    output reg core_aresetn = 1'b0,
    output reg ddr_aresetn = 1'b0,
    output wire core_cold_reset,
    output wire transport_ready
);
    // 外部cold不直接释放业务状态的异步CLR。每域三级同步后才开始16拍等待。
    (* ASYNC_REG = "TRUE" *) reg [2:0] core_reset_release = 3'b000;
    (* ASYNC_REG = "TRUE" *) reg [2:0] ddr_reset_release = 3'b000;
    wire core_entry_reset = !core_reset_release[2];
    wire ddr_entry_reset = !ddr_reset_release[2];
    always @(posedge core_clk or posedge chain_cold_reset) begin
        if (chain_cold_reset) core_reset_release <= 3'b000;
        else core_reset_release <= {core_reset_release[1:0], 1'b1};
    end
    always @(posedge ddr_clk or posedge chain_cold_reset) begin
        if (chain_cold_reset) ddr_reset_release <= 3'b000;
        else ddr_reset_release <= {ddr_reset_release[1:0], 1'b1};
    end

    reg [15:0] core_hold = 16'd0;
    reg [15:0] ddr_hold = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [2:0] ddr_done_in_core = 3'b000;
    (* ASYNC_REG = "TRUE" *) reg [2:0] core_done_in_ddr = 3'b000;
    (* ASYNC_REG = "TRUE" *) reg [2:0] ddr_release_in_core = 3'b000;

    assign core_cold_reset = !core_aresetn;
    assign transport_ready = core_aresetn && ddr_release_in_core[2];

    // 插入1延展16拍；跨域done是单调状态，下一次cold同时清两边握手。
    // 一侧停钟时其hold不会走满，另一侧必须保持复位，不能单侧提前恢复。
    always @(posedge core_clk or posedge core_entry_reset) begin
        if (core_entry_reset) begin
            core_hold <= 16'd0;
            ddr_done_in_core <= 3'b000;
            ddr_release_in_core <= 3'b000;
            core_aresetn <= 1'b0;
        end else begin
            core_hold <= {core_hold[14:0], 1'b1};
            ddr_done_in_core <= {ddr_done_in_core[1:0], ddr_hold[15]};
            ddr_release_in_core <= {ddr_release_in_core[1:0], ddr_aresetn};
            core_aresetn <= core_hold[15] && ddr_done_in_core[2];
        end
    end

    // DDR侧独立计拍与同步释放；不假设192/50是整数比或边沿对齐。
    always @(posedge ddr_clk or posedge ddr_entry_reset) begin
        if (ddr_entry_reset) begin
            ddr_hold <= 16'd0;
            core_done_in_ddr <= 3'b000;
            ddr_aresetn <= 1'b0;
        end else begin
            ddr_hold <= {ddr_hold[14:0], 1'b1};
            core_done_in_ddr <= {core_done_in_ddr[1:0], core_hold[15]};
            ddr_aresetn <= ddr_hold[15] && core_done_in_ddr[2];
        end
    end
endmodule
