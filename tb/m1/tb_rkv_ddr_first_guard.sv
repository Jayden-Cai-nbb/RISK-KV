`timescale 1ns/1ps
module tb_rkv_ddr_first_guard;
    logic clk=0;
    always #5 clk=!clk;
    logic ui_reset=1;
    logic start_level=1;
    wire launch;
    wire launched;
    wire reset_fault;
    integer accepted=0;
    integer checks=0;
    rkv_ddr_first_guard dut (
        .clk(clk),
        .ui_reset(ui_reset),
        .start_level(start_level),
        .launch(launch),
        .launched(launched),
        .reset_fault(reset_fault)
    );
    always @(posedge clk) if(launch) accepted++;
    task automatic tick;
        @(posedge clk); #1;
    endtask
    task automatic check(input bit ok,input string label);
        if(!ok) $fatal(1,"%s",label);
        checks++;
    endtask
    initial begin
        repeat(5) tick();
        check(accepted==0 && !launched && !reset_fault,"initial UI reset blocks start");
        @(negedge clk); ui_reset=0;
        tick();
        check(accepted==1 && launched && !launch && !reset_fault,"first eligible edge accepted once");
        repeat(5) tick();
        check(accepted==1,"held start cannot repeat");
        @(negedge clk); ui_reset=1;
        tick();
        check(reset_fault && launched && !launch,"automatic MIG reset retains ownership and sets fault");
        @(negedge clk); ui_reset=0;
        repeat(5) tick();
        check(reset_fault && accepted==1,"recalibration cannot restart held start");
        repeat(10) begin
            @(negedge clk); start_level=0; tick();
            @(negedge clk); start_level=1; tick();
            check(accepted==1 && reset_fault && !launch,"new start cannot bypass configuration lifetime");
        end
        $display("DDR_FIRST_GUARD_PASS checks=%0d accepted=%0d",checks,accepted);
        $finish;
    end
    initial begin #10000; $fatal(1,"watchdog"); end
endmodule
