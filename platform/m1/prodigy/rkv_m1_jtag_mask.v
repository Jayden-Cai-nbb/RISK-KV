// 将软件配置锁存在AW接收沿；只改变DDR写的WSTRB，不改变数据或返回语义。
module rkv_m1_jtag_mask (
    input wire clk,
    input wire cold_reset,
    input wire mask_enable,
    input wire [7:0] byte_mask,
    input wire [31:0] awaddr,
    input wire j_awvalid,
    output wire j_awready,
    output wire h_awvalid,
    input wire h_awready,
    input wire j_wvalid,
    input wire j_wlast,
    input wire [7:0] j_wstrb,
    output wire j_wready,
    output wire h_wvalid,
    output wire [7:0] h_wstrb,
    input wire h_wready,
    input wire bvalid,
    input wire bready,
    output reg active
);
    reg [7:0] saved_mask;
    reg data_finished;
    // 一个写责任覆盖AW到B消费；新AW不越过旧B，故无需多项mask队列。
    assign h_awvalid = j_awvalid && !active && !cold_reset;
    assign j_awready = h_awready && !active && !cold_reset;
    assign h_wvalid = j_wvalid && active && !data_finished && !cold_reset;
    assign j_wready = h_wready && active && !data_finished && !cold_reset;
    assign h_wstrb = j_wstrb & saved_mask;
    always @(posedge clk) begin
        if (cold_reset) begin
            active <= 1'b0;
            saved_mask <= 8'hff;
            data_finished <= 1'b0;
        end else begin
            if (h_awvalid && h_awready) begin
                active <= 1'b1;
                data_finished <= 1'b0;
                // [31]=1是独立控制地址窗口，不能被DDR字节mask影响。
                saved_mask <= mask_enable && !awaddr[31] ? byte_mask : 8'hff;
            end
            if (h_wvalid && h_wready && j_wlast) data_finished <= 1'b1;
            if (bvalid && bready) active <= 1'b0;
        end
    end
endmodule
