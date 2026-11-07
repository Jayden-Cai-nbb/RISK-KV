// 仅用于独立 DDR 初始化诊断；所有观测输入均来自同一 div_clk 域。
module rkv_ddr_init_trace (
    input wire clk,
    input wire [135:0] command_address,
    input wire [15:0] command_bank,
    input wire [15:0] command_group,
    input wire [7:0] command_act_n,
    input wire [7:0] command_cs_n,
    input wire [7:0] command_cke,
    input wire [7:0] command_reset_n,
    input wire [7:0] command_odt,
    input wire [7:0] status
);
    // 保存全部八个串行槽，保留 DDR4 ADR[16:14] 复用的 RAS/CAS/WE。
    // cal_RESET_n 未经过 mcal 命令寄存级，解码时分别解释，不伪装成管脚波形。
    wire [255:0] payload = {40'd0, status, command_odt, command_reset_n,
        command_cke, command_cs_n, command_act_n, command_group,
        command_bank, command_address};
    reg seen = 1'b0;
    reg [23:0] previous_control = 24'd0;
    wire [23:0] control = {status, command_reset_n, command_cke};
    wire command_selected = !status[1] && (&command_reset_n) &&
        (command_cs_n != 8'hff);
    wire event_valid = !seen || (control != previous_control) || command_selected;
    // 独立输入寄存级隔离 RAM 的使能组合路径；时间戳对应此采样的后一沿。
    reg pending_valid = 1'b0;
    reg [255:0] pending_data;
    always @(posedge clk) begin
        seen <= 1'b1;
        previous_control <= control;
        pending_valid <= event_valid;
        pending_data <= payload;
    end

    wire [9:0] read_address;
    wire [9:0] read_address_echo;
    wire [303:0] read_data;
    wire read_valid;
    wire [10:0] count;
    wire overflow;
    wire [47:0] ticks;
    rkv_boot_trace trace_storage (
        .clk(clk),
        .event_valid(pending_valid),
        .event_data(pending_data),
        .read_address(read_address),
        .read_data(read_data),
        .read_address_echo(read_address_echo),
        .read_valid(read_valid),
        .count(count),
        .overflow(overflow),
        .ticks(ticks)
    );

    // VIO 唯一输出是读索引，无法复位、重启校准或改变 DDR 命令。
    ddr_init_trace_vio trace_readout (
        .clk(clk),
        .probe_in0(32'h54524331),
        .probe_in1({9'd0, overflow, read_valid, count, read_address_echo}),
        .probe_in2(read_data[127:0]),
        .probe_in3(read_data[255:128]),
        .probe_in4(read_data[303:256]),
        .probe_in5(ticks),
        .probe_out0(read_address)
    );
endmodule
