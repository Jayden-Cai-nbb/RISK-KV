`timescale 1ns/1ps
module tb_rkv_boot_trace;
    reg clk = 0;
    always #5 clk = ~clk;
    reg event_valid = 0;
    reg [255:0] event_data = 0;
    reg [9:0] read_address = 0;
    wire [303:0] read_data;
    wire [9:0] read_address_echo;
    wire read_valid;
    wire [10:0] count;
    wire overflow;
    wire [47:0] ticks;
    rkv_boot_trace dut (
        .clk(clk), .event_valid(event_valid), .event_data(event_data),
        .read_address(read_address), .read_data(read_data),
        .read_address_echo(read_address_echo), .read_valid(read_valid),
        .count(count), .overflow(overflow), .ticks(ticks)
    );
    reg [303:0] expected [0:1023];
    integer i;
    task step;
        @(posedge clk); #1;
    endtask
    initial begin
        step();
        if (count != 0 || read_valid || overflow) $fatal(1,"initial ownership");
        // 含空拍的 1024 个事件，每项保留全部位及实际采样时间。
        for (i=0;i<1024;i=i+1) begin
            @(negedge clk);
            event_valid=1;
            event_data={8{32'h9e3779b9 ^ 32'(i)}};
            read_address=10'(i);
            expected[i]={ticks,event_data};
            step();
            if (read_valid) $fatal(1,"same-edge unwritten record advertised");
            if (count != i+1) $fatal(1,"count");
            @(negedge clk); event_valid=0;
            step();
            if (!read_valid || read_data !== expected[i] || read_address_echo != i)
                $fatal(1,"payload/timestamp/echo");
        end
        // 第 1025 项只设置溢出，不覆盖第一项；空拍保持全量记录。
        @(negedge clk); event_valid=1; event_data='1; read_address=0;
        step();
        if (!overflow || count != 1024 || read_data !== expected[0]) $fatal(1,"overflow");
        @(negedge clk); event_valid=0;
        repeat(20) step();
        for(i=1023;i>=0;i=i-1) begin
            @(negedge clk); read_address=10'(i);
            step();
            if (!read_valid || read_data !== expected[i] || read_address_echo != i)
                $fatal(1,"retained history");
        end
        $display("BOOT_TRACE_PASS records=1024 collision=1024 overflow=1 retained=1024");
        $finish;
    end
endmodule
