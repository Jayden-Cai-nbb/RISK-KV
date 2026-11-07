`timescale 1ns/1ps
module tb_rkv_ddr_qualifier;
    reg clk=0; always #5 clk=~clk;
    reg cold_reset=1, calibrated=1, start=0, peek_toggle=0;
    reg [31:0] base_address=0,seed=32'h12345678,peek_address=0;
    reg [25:0] block_count=4;
    reg [15:0] min_seconds=0;
    wire peek_ack,busy,done,fault;
    wire [3:0] fault_code,phase;
    wire [2:0] pass;
    wire [31:0] rounds,elapsed,seconds;
    wire [47:0] aw_count,w_count,b_count,ar_count,r_count;
    wire [25:0] block_index;
    wire [47:0] cycles;
    wire [511:0] expected_data,observed_data,axi_wdata;
    wire [63:0] axi_wstrb;
    wire [32:0] axi_awaddr,axi_araddr;
    wire axi_awvalid,axi_wvalid,axi_arvalid,axi_bready,axi_rready;
    reg axi_awready=0,axi_wready=0,axi_arready=0;
    reg [3:0] axi_bid=0,axi_rid=0;
    reg [1:0] axi_bresp=0,axi_rresp=0;
    reg axi_bvalid=0,axi_rvalid=0,axi_rlast=1;
    reg [511:0] axi_rdata=0;
    rkv_ddr_qualifier #(.TIMEOUT_CYCLES(32'd150),.CYCLES_PER_SECOND(32'd2000)) dut (.*);
    reg [511:0] memory [0:255];
    reg aw_pending=0,w_pending=0,ar_pending=0;
    reg [31:0] saved_aw,saved_ar;
    reg [511:0] saved_w;
    reg [63:0] saved_mask;
    integer mode=0,checks=0,tests=0,seed_arg=1,j,location;
    integer aw_total,w_total,b_total,ar_total,r_total;
    reg [31:0] captured_base,captured_seed;
    reg [32:0] prev_aw,prev_ar;
    reg [511:0] prev_w;
    reg [63:0] prev_mask;
    reg stall_aw=0,stall_ar=0,stall_w=0;
    task check(input bit ok,input string msg);
        if(!ok) $fatal(1,"%s phase=%d pass=%d fault=%d counts=%d/%d/%d/%d/%d",msg,phase,pass,fault_code,aw_count,w_count,b_count,ar_count,r_count);
        checks++;
    endtask
    // 独立存储模型只保存AXI写数据；别名模式故意截掉一个实际地址位。
    always @(posedge clk) begin
        if(cold_reset) begin
            aw_pending<=0;w_pending<=0;ar_pending<=0;axi_bvalid<=0;axi_rvalid<=0;
            aw_total<=0;w_total<=0;b_total<=0;ar_total<=0;r_total<=0;
            stall_aw<=0;stall_ar<=0;stall_w<=0;
        end else begin
            if(stall_aw) check(axi_awvalid && axi_awaddr==prev_aw,"AW changed during backpressure");
            if(stall_ar) check(axi_arvalid && axi_araddr==prev_ar,"AR changed during backpressure");
            if(stall_w) check(axi_wvalid && axi_wdata==prev_w && axi_wstrb==prev_mask,"W changed during backpressure");
            stall_aw<=axi_awvalid&&!axi_awready;prev_aw<=axi_awaddr;
            stall_ar<=axi_arvalid&&!axi_arready;prev_ar<=axi_araddr;
            stall_w<=axi_wvalid&&!axi_wready;prev_w<=axi_wdata;prev_mask<=axi_wstrb;
            if(axi_awvalid&&axi_awready) begin
                check(!aw_pending,"duplicate AW");saved_aw<=axi_awaddr[31:0];aw_pending<=1;aw_total<=aw_total+1;
            end
            if(axi_wvalid&&axi_wready) begin
                check(!w_pending,"duplicate W");saved_w<=axi_wdata;saved_mask<=axi_wstrb;w_pending<=1;w_total<=w_total+1;
            end
            if(aw_pending&&w_pending&&!axi_bvalid && mode!=5 && ($urandom_range(0,3)==0)) begin
                location=((saved_aw-captured_base)>>6)&(mode==7 ? 127:255);
                for(j=0;j<64;j++) if(saved_mask[j]||mode==9) memory[location][8*j+:8]<=saved_w[8*j+:8];
                axi_bid<=mode==11?1:0;axi_bresp<=mode==2?2:0;axi_bvalid<=1;
            end
            if(axi_bvalid&&axi_bready) begin axi_bvalid<=0;aw_pending<=0;w_pending<=0;b_total<=b_total+1;end
            if(axi_arvalid&&axi_arready) begin
                check(!ar_pending,"duplicate AR");saved_ar<=axi_araddr[31:0];ar_pending<=1;ar_total<=ar_total+1;
            end
            if(ar_pending&&!axi_rvalid&&mode!=6&&($urandom_range(0,3)==0)) begin
                location=((saved_ar-captured_base)>>6)&(mode==7?127:255);
                axi_rdata<=memory[location]^(mode==1?512'd1:512'd0);
                axi_rresp<=mode==3?2:0;axi_rid<=mode==4?1:0;axi_rlast<=mode!=10;axi_rvalid<=1;
            end
            if(axi_rvalid&&axi_rready) begin axi_rvalid<=0;if(axi_rlast) ar_pending<=0;r_total<=r_total+1;end
        end
    end
    always @(negedge clk) begin
        axi_awready=(mode!=8)&&!aw_pending&&($urandom_range(0,2)!=0);
        axi_wready=!w_pending&&($urandom_range(0,2)!=0);
        axi_arready=!ar_pending&&($urandom_range(0,2)!=0);
    end
    function automatic [511:0] reference(input [31:0] addr,input [31:0] s,input [31:0] r);
        reg [31:0] x;
        for(int i=0;i<16;i++) begin
            x=addr^s^r^(32'h9e3779b9*32'(i));
            x^=x<<13;x^=x>>17;x^=x<<5;
            reference[32*i+:32]=x;
        end
    endfunction
    task begin_test(input integer m,input [31:0] base,input [25:0] blocks,input [15:0] duration);
        @(negedge clk);cold_reset=1;start=0;mode=m;calibrated=1;peek_toggle=0;
        base_address=base;block_count=blocks;min_seconds=duration;seed=32'h12345678;
        captured_base=base;captured_seed=seed;
        repeat(4) @(negedge clk);
        cold_reset=0;start=1;
        @(negedge clk);start=0;tests++;
    endtask
    task await_result;
        integer budget;
        budget=0;
        while(!done&&!fault&&budget<100000) begin @(negedge clk);budget++;end
        check(done||fault,"bounded completion");
    endtask
    task check_counts;
        check(aw_count==aw_total&&w_count==w_total&&b_count==b_total&&ar_count==ar_total&&r_count==r_total,"handshake counters independently agree");
    endtask
    initial begin
        if($value$plusargs("seed=%d",seed_arg)) begin end
        j=$urandom(seed_arg);
        begin_test(0,32'h00000fc0,26'd128,0); // 覆盖4KiB前后的相邻单beat。
        // 接受后主机乱改配置不得串入本批次。
        base_address=32'h7fffffc0;block_count=1;seed=0;min_seconds=3600;
        await_result;check(done&&!fault&&rounds==1,"range pass");
        check(aw_count==384&&b_count==384&&ar_count==384&&r_count==384,"six complete sweeps");check_counts;
        for(int n=0;n<128;n++) check(memory[n]===reference(captured_base+32'(n*64),captured_seed,0),"independent final data");
        peek_address=captured_base+32'd4096;peek_toggle=1;
        while(!peek_ack&&!fault) @(negedge clk);
        check(!fault&&observed_data===reference(peek_address,captured_seed,0),"independent host peek");
        check(aw_count==384&&r_count==385,"peek is read only");
        start=1;repeat(20) @(negedge clk);check(aw_count==384,"duplicate batch start rejected");
        calibrated=0;repeat(3) @(negedge clk);check(fault&&!done,"post-success calibration loss invalidates result");
        begin_test(0,32'h7fffffc0,1,0);await_result;check(done&&!fault,"last64B within2GiB");check_counts;
        begin_test(0,0,4,4);await_result;check(done&&rounds>1&&seconds>=4,"minimum duration ends only after full round");
        check(memory[0]===reference(0,captured_seed,rounds-1),"last round identity");
        begin_test(7,0,256,0);await_result;check(fault&&fault_code==6&&!done,"fill then read detects address alias");
        for(int m=1;m<=6;m++) begin
            begin_test(m,0,4,0);await_result;
            check(fault&&!done,"fault rejects success");check_counts;
            if(m==5||m==6) begin
                mode=0;repeat(40) @(negedge clk);
                check(fault&&!done&&phase==6,"late response drains without recovery");check_counts;
            end
        end
        begin_test(9,0,4,0);await_result;check(fault_code==6&&pass==3,"mask violation independently detected");
        begin_test(10,0,4,0);await_result;check(fault_code==5&&phase==3,"missing RLAST remains in flight");
        mode=0;repeat(40) @(negedge clk);check(fault&&!done&&phase==6,"drain to late RLAST without success");
        begin_test(11,0,4,0);await_result;check(fault_code==4,"wrong BID rejected");
        begin_test(8,0,4,0);await_result;check(fault&&axi_awvalid,"timeout retains stalled AW");
        mode=0;repeat(40) @(negedge clk);check(fault&&!done&&phase==6,"late AW/B retires no next transaction");
        begin_test(0,0,4,0);while(phase!=2) @(negedge clk);calibrated=0;
        await_result;check(fault&&fault_code==2,"calibration withdrawal");
        repeat(40) @(negedge clk);check(aw_count==1&&!done,"withdrawal prevents new transactions");
        begin_test(8,0,1,0);while(!axi_awvalid) @(negedge clk);
        dut.aw_count=48'h0000ffffffff;mode=0;
        while(aw_count==48'h0000ffffffff) @(negedge clk);
        check(aw_count==48'h000100000000,"48-bit counter carries across former32-bit limit");
        await_result;check(done&&!fault,"wide counter case completes");
        begin_test(0,32'h7fffffc0,2,0);await_result;check(fault_code==1&&aw_count==0,"range overflow rejected");
        begin_test(0,1,1,0);await_result;check(fault_code==1&&aw_count==0,"misalignment rejected");
        begin_test(0,0,0,0);await_result;check(fault_code==1&&aw_count==0,"zero blocks rejected");
        begin_test(0,0,1,3601);await_result;check(fault_code==1&&aw_count==0,"unbounded duration rejected");
        $display("DDR_QUALIFIER_PASS tests=%0d checks=%0d",tests,checks);$finish;
    end
    initial begin #10000000;$fatal(1,"TB global timeout");end
endmodule
