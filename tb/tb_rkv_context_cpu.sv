// Actual RV32I and lifecycle hardware; explicit synthetic NPU control fixture.
`timescale 1ns/1ps
module tb_rkv_context_cpu;
    logic clk=0,reset=1;always #5 clk=~clk;
    logic npu_halted=0,npu_error=0,fabric_idle=1,fabric_error=0,loader_busy=0;
    logic loader_start;logic[31:0]loader_addr,loader_count;
    logic result_store_valid=0,result_other_write=0;logic[31:0]result_store_addr=32'd307322272;
    logic[1023:0]result_store_data=0;logic[31:0]result_store_mask=0;
    logic program_ready,result_valid;logic[31:0]result_token0,result_token1;
    logic token_trace_valid,token_trace_row;logic[31:0]token_trace_data;
    logic npu_reset,trap,test_done,completion_valid,active,launch_pulse;
    logic[31:0]test_code,npu_args[8],completion_status,completion_context,completion_generation,accepted_count,rejected_count;
    logic[63:0]completion_session,completion_sequence;
    int age=0,load_age=0,traces=0,fail_mode=0;
    logic building;
    rkv_npu_context_cpu dut(.*);
    initial void'($value$plusargs("failure=%d",fail_mode));
    always @(posedge clk)begin
        if(!reset)begin
            result_store_valid<=0;fabric_error<=0;
            if(loader_start)begin loader_busy<=1;load_age<=1;fabric_idle<=0;end
            else if(load_age>0&&load_age<50)begin
                load_age<=load_age+1;
                if(load_age==10)loader_busy<=0;
                if(load_age==20)fabric_idle<=1;
            end
            if(launch_pulse)begin
                age<=1;npu_halted<=0;fabric_idle<=0;building<=loader_addr==32'h60000000;
                if(fail_mode==2)fabric_error<=1;
            end else if(age>0&&age<11000)begin
                age<=age+1;
                if(age==6000)begin
                    result_store_valid<=1;result_store_mask<=3;
                    result_store_data[31:0]<=32'h3f800000;
                    result_store_data[63:32]<=building?32'h40800000:32'h40000000;
                end
                if(age==10000)npu_halted<=1;
                if(age==10400)fabric_idle<=1;
            end
            if(npu_reset)npu_halted<=0;
            if(trap)$fatal(1,"RV32I trapped");
            if(token_trace_valid)traces<=traces+1;
            if(test_done)begin
                if(fail_mode==0)begin
                    if(test_code!=32'h600d4003||accepted_count!=67||traces!=6||dut.control.guard.built_tokens!=256||!dut.control.guard.reclaimable)
                        $fatal(1,"Lifecycle positive failed code=%h state=%0d built=%0d accepted=%0d",test_code,dut.control.guard.object_state,dut.control.guard.built_tokens,accepted_count);
                end else begin
                    if(test_code!=(32'h600d3000|32'(fail_mode))||accepted_count!=1||traces!=0||dut.control.guard.built_tokens!=0||!dut.control.guard.reclaimable)
                        $fatal(1,"Failed build was not safely retired code=%h",test_code);
                end
                $display("PASS real RV32I lifecycle fixture failure=%0d accepted=%0d rejected=%0d built=%0d",fail_mode,accepted_count,rejected_count,dut.control.guard.built_tokens);$finish;
            end
        end
    end
    initial begin repeat(3)@(negedge clk);reset=0;end
    initial begin #30000000;$fatal(1,"Lifecycle CPU fixture timeout");end
endmodule
