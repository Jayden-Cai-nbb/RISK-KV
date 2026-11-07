// 配置级只读启动轨迹：普通功能复位不清除记录，重新配置 FPGA 才重新开始。
module rkv_boot_trace (
    input wire clk,
    input wire event_valid,
    input wire [255:0] event_data,
    input wire [9:0] read_address,
    output reg [303:0] read_data,
    output reg [9:0] read_address_echo,
    output reg read_valid = 1'b0,
    output reg [10:0] count = 11'd0,
    output reg overflow = 1'b0,
    output reg [47:0] ticks = 48'd0
);
    // 1024×304 单时钟简单双端口 RAM；记录不回绕。读延迟一拍。
    // 同址首写与读取发生在同沿时，read_valid=0，下一沿才允许读取新记录。
    (* ram_style = "block" *) reg [303:0] records [0:1023];
    always @(posedge clk) begin
        ticks <= ticks + 48'd1;
        read_data <= records[read_address];
        read_address_echo <= read_address;
        read_valid <= ({1'b0, read_address} < count);
        if (event_valid) begin
            if (count < 11'd1024) begin
                records[count[9:0]] <= {ticks, event_data};
                count <= count + 11'd1;
            end else begin
                overflow <= 1'b1;
            end
        end
    end
endmodule
