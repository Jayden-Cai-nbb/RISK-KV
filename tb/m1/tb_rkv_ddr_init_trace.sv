`timescale 1ns/1ps
module ddr_init_trace_vio (
    input wire clk,
    input wire [31:0] probe_in0,
    input wire [31:0] probe_in1,
    input wire [127:0] probe_in2,
    input wire [127:0] probe_in3,
    input wire [47:0] probe_in4,
    input wire [47:0] probe_in5,
    output wire [9:0] probe_out0
);
    assign probe_out0=10'd0;
endmodule
module tb_rkv_ddr_init_trace;
    reg clk=0;
    always #5 clk=~clk;
    reg [135:0] address=0;
    reg [15:0] bank=0;
    reg [15:0] group_bits=0;
    reg [7:0] act_n=8'hff;
    reg [7:0] cs_n=8'hff;
    reg [7:0] cke=0;
    reg [7:0] reset_n=0;
    reg [7:0] odt=0;
    reg [7:0] status=8'h02;
    rkv_ddr_init_trace dut (
        .clk(clk),
        .command_address(address),
        .command_bank(bank),
        .command_group(group_bits),
        .command_act_n(act_n),
        .command_cs_n(cs_n),
        .command_cke(cke),
        .command_reset_n(reset_n),
        .command_odt(odt),
        .status(status)
    );
    task settle;
        repeat(3) begin @(posedge clk); #1; end
    endtask
    initial begin
        settle();
        if (dut.count != 1) $fatal(1,"first snapshot");
        if (dut.read_data[255:0] !== {40'd0,8'h02,8'h00,8'h00,8'h00,8'hff,8'hff,16'd0,16'd0,136'd0})
            $fatal(1,"field packing");
        repeat(100) @(negedge clk);
        if (dut.count != 1) $fatal(1,"idle filled history");
        // 复位中选中命令不记录；控制变化仍需保留。
        cs_n=8'he7; settle();
        if (dut.count != 1) $fatal(1,"command during reset");
        @(negedge clk); cs_n=8'hff; status=0; settle();
        if (dut.count != 2) $fatal(1,"reset release");
        @(negedge clk); reset_n=8'hff; settle();
        if (dut.count != 3) $fatal(1,"dram reset release");
        @(negedge clk); cke=8'hff; settle();
        if (dut.count != 4) $fatal(1,"cke release");
        // 连续两拍两个命令，不用去重逻辑误删相同命令。
        @(negedge clk); cs_n=8'he7; address='1;
        repeat(2) @(negedge clk);
        cs_n=8'hff; settle();
        if (dut.count != 6) $fatal(1,"back-to-back commands");
        @(negedge clk); status=8'h02; reset_n=0; cke=0; settle();
        if (dut.count != 7 || !dut.read_valid) $fatal(1,"functional reset erased history");
        if (dut.read_data[199:192] !== 8'd0 || dut.read_data[215:208] !== 8'h02)
            $fatal(1,"first history not retained");
        $display("DDR_INIT_TRACE_PASS initial idle reset commands packing retention");
        $finish;
    end
endmodule
