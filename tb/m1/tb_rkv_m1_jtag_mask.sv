`timescale 1ns/1ps
module tb_rkv_m1_jtag_mask;
    logic clk=0,cold_reset=1,mask_enable=0;
    logic [7:0] byte_mask=0,j_wstrb=8'hff,h_wstrb;
    logic [31:0] awaddr=0;
    logic j_awvalid=0,j_awready,h_awvalid,h_awready=0;
    logic j_wvalid=0,j_wlast=1,j_wready,h_wvalid,h_wready=0;
    logic bvalid=0,bready=0,active;
    rkv_m1_jtag_mask dut (
        .clk(clk),.cold_reset(cold_reset),.mask_enable(mask_enable),.byte_mask(byte_mask),.awaddr(awaddr),
        .j_awvalid(j_awvalid),.j_awready(j_awready),.h_awvalid(h_awvalid),.h_awready(h_awready),
        .j_wvalid(j_wvalid),.j_wlast(j_wlast),.j_wstrb(j_wstrb),.j_wready(j_wready),
        .h_wvalid(h_wvalid),.h_wstrb(h_wstrb),.h_wready(h_wready),.bvalid(bvalid),.bready(bready),.active(active)
    );
    always #5 clk=!clk;
    task tick; @(posedge clk); #1; endtask
    integer i;
    initial begin
        tick(); @(negedge clk); cold_reset=0;
        // W先到时必须等AW，不可使用前一个事务的mask。
        j_wvalid=1; h_wready=1; mask_enable=1; byte_mask=8'haa;
        tick(); if(h_wvalid || j_wready || active) $fatal(1,"W accepted before AW");
        @(negedge clk);j_awvalid=1;h_awready=1;h_wready=0; tick();
        if(!active || h_wstrb!=8'haa) $fatal(1,"AW mask capture");
        @(negedge clk); byte_mask=8'h55;
        repeat(3) begin tick(); if(h_wstrb!=8'haa || !h_wvalid || j_awready) $fatal(1,"backpressure stability");end
        @(negedge clk);h_wready=1; tick();
        if(h_wvalid || j_wready || !active || j_awready) $fatal(1,"WLAST did not stop extra data");
        @(negedge clk);bvalid=1;tick();if(!active) $fatal(1,"B not consumed yet");
        @(negedge clk);bready=1;tick();if(active) $fatal(1,"B retirement");
        @(negedge clk);bvalid=0;awaddr=32'h80000000; byte_mask=0;tick();
        if(!active || h_wstrb!=8'hff) $fatal(1,"control write incorrectly masked");
        @(negedge clk);j_awvalid=0;tick();
        @(negedge clk);bvalid=1;tick();
        // 零mask仍发真实AW/W/B；不在主机假造完成。
        @(negedge clk);bvalid=0;awaddr=32'h100;j_awvalid=1;tick();
        if(h_wstrb!=0 || !h_wvalid) $fatal(1,"zero mask missing real transaction");
        $display("JTAG_MASK_PASS");$finish;
    end
    initial begin #10000;$fatal(1,"timeout");end
endmodule
