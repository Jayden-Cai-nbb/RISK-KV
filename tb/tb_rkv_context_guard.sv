// Lifecycle unit: accepted/completion events are explicit fixtures, not model runs.
`timescale 1ns/1ps
module tb_rkv_context_guard;
    logic clk=0,reset=1;always #5 clk=~clk;
    logic bus_valid=0;logic[11:0]bus_addr=0;logic[31:0]bus_wdata=0,bus_rdata;logic[3:0]bus_wstrb=0;logic bus_ready;
    logic session_valid=1;logic[63:0]session_value=64'h1122334455667788,request_session=64'h1122334455667788;
    logic[31:0]proposed_context=1,proposed_generation=7,proposed_args[8]='{default:0};
    logic[31:0]loaded_addr=32'h60000000,loaded_count=1026;
    logic active=0,completion_valid=0,accepted_event=0,consumed_event=0,fabric_idle=1,loader_busy=0;
    logic[31:0]completion_status=0,completion_context=1,completion_generation=7;
    logic[63:0]completion_session=64'h1122334455667788,completion_sequence=0;
    logic result_valid=0;logic[31:0]result_word0=32'h3f800000,result_word1=32'h40800000;
    logic submit_allowed,reclaimable,bound_pair,task_reference;logic[2:0]object_state;
    logic[8:0]built_tokens,decode_steps;logic[31:0]object_id,object_generation;
    localparam[31:0] BASE=1233223680;
    int checks=0;logic[31:0]q;
    rkv_context_guard dut(.*);
    task tick(input int n);repeat(n)@(negedge clk);endtask
    task verify(input logic okay,input string label_text);if(!okay)$fatal(1,"FAIL %s",label_text);checks++;endtask
    task wr(input logic[11:0]addr,input logic[31:0]value);
        @(negedge clk);bus_addr=addr;bus_wdata=value;bus_wstrb=15;bus_valid=1;
        do @(negedge clk);while(!bus_ready);
        bus_valid=0;bus_wstrb=0;@(negedge clk);
    endtask
    task rd(input logic[11:0]addr,output logic[31:0]value);
        @(negedge clk);bus_addr=addr;bus_wstrb=0;bus_valid=1;
        do @(negedge clk);while(!bus_ready);
        value=bus_rdata;bus_valid=0;@(negedge clk);
    endtask
    task command(input int cmd,input int error);
        wr('h200,32'(cmd));rd('h208,q);verify(q==32'(error),"object command result");
    endtask
    task args_build(input int p);
        proposed_args[0]=0;proposed_args[1]=0-(32'(p)<<2);proposed_args[2]=BASE;proposed_args[3]=BASE+32'(p);
        proposed_args[4]=BASE+(32'(p)<<2);proposed_args[5]=BASE+(32'(p)<<7);proposed_args[6]=32'(p)<<2;proposed_args[7]=32'(p)<<8;
        loaded_addr=32'h60000000;loaded_count=1026;tick(1);
    endtask
    task args_decode(input int p);
        proposed_args[0]=0-(32'(p)<<2);proposed_args[1]=BASE;proposed_args[2]=BASE+32'(p);proposed_args[3]=BASE+(32'(p)<<2);
        proposed_args[4]=BASE+(32'(p)<<7);proposed_args[5]=8*4096;proposed_args[6]=32'(p)<<8;proposed_args[7]=7*4096;
        loaded_addr=32'h60010000;loaded_count=1004;tick(1);
    endtask
    task accept;
        verify(submit_allowed,"admit legal task");completion_sequence++;accepted_event=1;active=1;fabric_idle=0;tick(1);accepted_event=0;
        verify(task_reference,"actual acceptance pins object");
    endtask
    task completed(input int status,input bit valid_payload=1);
        active=0;fabric_idle=1;completion_status=32'(status);completion_valid=1;result_valid=valid_payload;tick(2);
    endtask
    task consume;
        completion_valid=0;result_valid=0;consumed_event=1;tick(1);consumed_event=0;tick(2);
        verify(!task_reference,"consumption releases task reference");
    endtask
    task cold;
        reset=1;active=0;completion_valid=0;accepted_event=0;consumed_event=0;fabric_idle=1;result_valid=0;
        request_session=session_value;proposed_context=1;proposed_generation=7;completion_context=1;completion_generation=7;
        completion_session=session_value;result_word0=32'h3f800000;result_word1=32'h40800000;
        tick(3);reset=0;tick(2);command(1,0);
    endtask
    initial begin
        tick(3);reset=0;tick(2);
        request_session=0;command(1,1);verify(object_state==0,"wrong session cannot register");request_session=session_value;
        proposed_generation=0;command(1,1);proposed_generation=7;command(1,0);
        wr('h20c,256);rd('h208,q);verify(q==8&&built_tokens==0,"cursor is read-only");
        command(2,4);command(3,2);args_decode(0);verify(!submit_allowed,"unsealed read denied");
        args_build(0);proposed_generation=8;tick(1);verify(!submit_allowed,"stale generation denied");proposed_generation=7;
        proposed_args[2]=BASE+128;tick(1);verify(!submit_allowed,"wrong base denied");args_build(0);
        loaded_count=1025;tick(1);verify(!submit_allowed,"wrong program identity denied");loaded_count=1026;tick(1);
        accept();command(5,0);verify(object_state==3&&!reclaimable,"retirement waits on live build");
        completed(0);verify(built_tokens==0,"completion alone cannot commit");tick(300);
        verify(task_reference&&!reclaimable,"unconsumed completion pins retirement");consume();
        verify(object_state==0&&reclaimable&&built_tokens==4,"retire after consumed success");command(1,2);
        cold();args_build(0);accept();completed(1,0);consume();verify(object_state==4&&built_tokens==0,"cancelled build not committed");command(2,2);command(3,2);
        cold();args_build(0);accept();completed(2,0);consume();verify(object_state==4&&built_tokens==0,"failed build not committed");
        cold();args_build(0);accept();result_word1=32'h40400000;completed(0);consume();verify(object_state==4&&built_tokens==0,"wrong build acknowledgement not committed");
        cold();args_build(0);accept();completion_sequence++;completed(0);consume();verify(object_state==4&&built_tokens==0,"wrong completion identity not committed");
        cold();
        for(int p=0;p<256;p+=4)begin
            args_build(p);accept();command(2,3);completed(0);verify(built_tokens==9'(p),"not committed before consume");
            if(p==252)command(2,3);consume();verify(built_tokens==9'(p+4),"exact four-token commit");
        end
        command(2,0);verify(object_state==2,"sealed exactly full page");command(2,2);
        args_decode(0);verify(!submit_allowed,"sealed but unbound denied");command(3,0);command(3,2);
        args_build(256);verify(!submit_allowed,"sealed prefix cannot be rebuilt");args_decode(0);
        proposed_args[5]=1;tick(1);verify(!submit_allowed,"malformed token offset denied");args_decode(0);accept();
        command(5,0);command(4,3);verify(!reclaimable,"bound in-flight decode pins object");completed(0);consume();
        verify(object_state==3&&bound_pair&&!reclaimable&&decode_steps==1,"binding remains after task consumption");
        command(4,0);tick(2);verify(object_state==0&&reclaimable,"release allows retirement");command(1,2);
        $display("PASS context guard checks=%0d full_page_build_tasks=64",checks);$finish;
    end
    initial begin #10000000;$fatal(1,"guard unit timeout");end
endmodule
