`timescale 1ns/1ps
module tb_rkv_m1_native_retirement;
    logic clk = '0;
    logic cold_reset = '0;
    logic [1:0] cvalid = '0;
    logic [1:0] cready = '0;
    logic [1:0] cwe = '0;
    logic [1:0] wvalid = '0;
    logic [1:0] wready = '0;
    logic [1:0] rvalid = '0;
    logic [1:0][15:0] wdone = '0;
    logic platform_error = '0;
    logic idle;
    logic error;
    logic [63:0] read_accepted [2];
    logic [63:0] read_retired [2];
    logic [63:0] write_accepted [2];
    logic [63:0] data_accepted [2];
    logic [63:0] write_retired [2];
    always #5 clk = !clk;
    rkv_m1_native_retirement dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .cvalid(cvalid),
        .cready(cready),
        .cwe(cwe),
        .wvalid(wvalid),
        .wready(wready),
        .rvalid(rvalid),
        .wdone(wdone),
        .platform_error(platform_error),
        .idle(idle),
        .error(error),
        .read_accepted(read_accepted),
        .read_retired(read_retired),
        .write_accepted(write_accepted),
        .data_accepted(data_accepted),
        .write_retired(write_retired)
    );
    integer checks = 0;
    task automatic tick(input integer n);
        repeat (n) begin @(posedge clk); #1; end
    endtask
    task automatic cold;
        @(negedge clk); cold_reset = 1;
        cvalid = 0; wvalid = 0; rvalid = 0;
        cready = 3; wready = 3; platform_error = 0;
        tick(3);
        @(negedge clk); cold_reset = 0;
        tick(1);
    endtask
    initial begin
        wdone = {16'hfffc, 16'hfff8};
        cold();
        if (!idle || error) $fatal(1, "initial native retirement");
        // 双通道计数跨过 16-bit 退休计数回绕；每笔写的命令和数据分拍到达。
        for (int i = 0; i < 65540; i++) begin
            @(negedge clk); wvalid = 3;
            tick(1);
            @(negedge clk); wvalid = 0;
            if (idle) $fatal(1, "write data mistaken for retirement");
            cvalid = 3; cwe = 3;
            tick(1);
            @(negedge clk); cvalid = 0;
            tick(1);
            if (idle || error) $fatal(1, "write command mistaken for retirement");
            @(negedge clk); wdone[0] += 16'd1; wdone[1] += 16'd1;
            tick(2);
            if (!idle || error || write_retired[0] != 64'(i+1)) $fatal(1, "write retirement wrap");
            checks++;
        end
        // 预取读即使不被计算端使用也必须实际返回后才算排空。
        @(negedge clk); cvalid = 3; cwe = 0;
        tick(1);
        @(negedge clk); cvalid = 0;
        tick(20);
        if (idle || error) $fatal(1, "unreturned prefetch treated idle");
        @(negedge clk); rvalid = 1;
        tick(1);
        @(negedge clk); rvalid = 0;
        tick(1);
        if (idle) $fatal(1, "one channel still outstanding");
        @(negedge clk); rvalid = 2;
        tick(1);
        @(negedge clk); rvalid = 0;
        tick(1);
        if (!idle || error || read_retired[0] != 1 || read_retired[1] != 1) $fatal(1, "read retirement");
        checks += 3;
        @(negedge clk); wdone[0] += 16'd1;
        tick(2);
        if (!error || idle) $fatal(1, "unearned write retirement accepted");
        cold();
        @(negedge clk); rvalid = 1;
        tick(1);
        @(negedge clk); rvalid = 0;
        tick(2);
        if (!error || idle) $fatal(1, "orphan read ignored");
        checks += 2;
        $display("M1_NATIVE_RETIREMENT_PASS checks=%0d seed=deterministic", checks);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "test timeout");
    end
endmodule
