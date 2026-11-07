`timescale 1ns/1ps
module tb_rkv_m1_host_ddr;
    logic clk=0;
    always #10 clk=~clk;
    logic cold_reset=1, external_fault=0;
    logic permit_read=1, permit_write=1;
    wire host_idle, fault;
    wire read_grant=permit_read && host_idle;
    wire write_grant=permit_write && host_idle;
    wire [31:0] fault_code;
    wire [63:0] accepted_reads,accepted_writes,rejected_requests,verified_write_beats;
    logic [3:0] s_awid=0;
    logic [31:0] s_awaddr=0;
    logic [7:0] s_awlen=0;
    logic [2:0] s_awsize=0;
    logic [1:0] s_awburst=0;
    logic s_awlock=0;
    logic [3:0] s_awcache=0;
    logic [2:0] s_awprot=0;
    logic [3:0] s_awqos=0;
    logic s_awvalid=0;
    wire s_awready;
    logic [63:0] s_wdata=0;
    logic [7:0] s_wstrb=0;
    logic s_wlast=0;
    logic s_wvalid=0;
    wire s_wready;
    wire [3:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    logic s_bready=0;
    logic [3:0] s_arid=0;
    logic [31:0] s_araddr=0;
    logic [7:0] s_arlen=0;
    logic [2:0] s_arsize=0;
    logic [1:0] s_arburst=0;
    logic s_arlock=0;
    logic [3:0] s_arcache=0;
    logic [2:0] s_arprot=0;
    logic [3:0] s_arqos=0;
    logic s_arvalid=0;
    wire s_arready;
    wire [3:0] s_rid;
    wire [63:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    logic s_rready=0;
    wire [3:0] m_awid;
    wire [31:0] m_awaddr;
    wire [7:0] m_awlen;
    wire [2:0] m_awsize;
    wire [1:0] m_awburst;
    wire m_awlock;
    wire [3:0] m_awcache;
    wire [2:0] m_awprot;
    wire [3:0] m_awqos;
    wire m_awvalid;
    logic m_awready=0;
    wire [63:0] m_wdata;
    wire [7:0] m_wstrb;
    wire m_wlast;
    wire m_wvalid;
    logic m_wready=0;
    logic [3:0] m_bid=0;
    logic [1:0] m_bresp=0;
    logic m_bvalid=0;
    wire m_bready;
    wire [3:0] m_arid;
    wire [31:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire m_arlock;
    wire [3:0] m_arcache;
    wire [2:0] m_arprot;
    wire [3:0] m_arqos;
    wire m_arvalid;
    logic m_arready=0;
    logic [3:0] m_rid=0;
    logic [63:0] m_rdata=0;
    logic [1:0] m_rresp=0;
    logic m_rlast=0;
    logic m_rvalid=0;
    wire m_rready;
    rkv_m1_host_ddr #(.TIMEOUT_CYCLES(32'd64)) dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .external_fault(external_fault),
        .read_grant(read_grant),
        .write_grant(write_grant),
        .host_idle(host_idle),
        .fault(fault),
        .fault_code(fault_code),
        .accepted_reads(accepted_reads),
        .accepted_writes(accepted_writes),
        .rejected_requests(rejected_requests),
        .verified_write_beats(verified_write_beats),
        .s_awid(s_awid),
        .s_awaddr(s_awaddr),
        .s_awlen(s_awlen),
        .s_awsize(s_awsize),
        .s_awburst(s_awburst),
        .s_awlock(s_awlock),
        .s_awcache(s_awcache),
        .s_awprot(s_awprot),
        .s_awqos(s_awqos),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_wdata(s_wdata),
        .s_wstrb(s_wstrb),
        .s_wlast(s_wlast),
        .s_wvalid(s_wvalid),
        .s_wready(s_wready),
        .s_bid(s_bid),
        .s_bresp(s_bresp),
        .s_bvalid(s_bvalid),
        .s_bready(s_bready),
        .s_arid(s_arid),
        .s_araddr(s_araddr),
        .s_arlen(s_arlen),
        .s_arsize(s_arsize),
        .s_arburst(s_arburst),
        .s_arlock(s_arlock),
        .s_arcache(s_arcache),
        .s_arprot(s_arprot),
        .s_arqos(s_arqos),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_rid(s_rid),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .s_rvalid(s_rvalid),
        .s_rready(s_rready),
        .m_awid(m_awid),
        .m_awaddr(m_awaddr),
        .m_awlen(m_awlen),
        .m_awsize(m_awsize),
        .m_awburst(m_awburst),
        .m_awlock(m_awlock),
        .m_awcache(m_awcache),
        .m_awprot(m_awprot),
        .m_awqos(m_awqos),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_wlast(m_wlast),
        .m_wvalid(m_wvalid),
        .m_wready(m_wready),
        .m_bid(m_bid),
        .m_bresp(m_bresp),
        .m_bvalid(m_bvalid),
        .m_bready(m_bready),
        .m_arid(m_arid),
        .m_araddr(m_araddr),
        .m_arlen(m_arlen),
        .m_arsize(m_arsize),
        .m_arburst(m_arburst),
        .m_arlock(m_arlock),
        .m_arcache(m_arcache),
        .m_arprot(m_arprot),
        .m_arqos(m_arqos),
        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_rid(m_rid),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_rlast(m_rlast),
        .m_rvalid(m_rvalid),
        .m_rready(m_rready)
    );
    int seed=1, random_state, checks=0;
    int mode=0;
    bit block_aw=0, block_ar=0, inject_r=0, inject_b=0;
    longint unsigned bus_writes=0,bus_reads=0,write_beats=0,read_beats=0;
    logic [63:0] memory [longint unsigned];
    logic [63:0] golden [longint unsigned];
    function automatic logic [63:0] initial_word(input longint unsigned address);
        return 64'hfedcba9801234567 ^ (address>>3);
    endfunction
    function automatic logic [63:0] peek(input longint unsigned address);
        return (memory.exists(address>>3)!=0) ? memory[address>>3] : initial_word(address);
    endfunction
    function automatic logic [63:0] expected(input longint unsigned address);
        return (golden.exists(address>>3)!=0) ? golden[address>>3] : initial_word(address);
    endfunction
    function automatic logic [63:0] data_value(input logic [31:0] address,input int index,input int tag);
        return 64'h123456789abcdef0 ^ {32'(tag),address} ^ (64'(index)*64'h0102040810204081);
    endfunction
    function automatic logic [7:0] byte_mask(input int index,input int tag,input bit partial);
        return partial ? 8'((index*37+tag*13) & 255) : 8'hff;
    endfunction
    task automatic ck(input bit condition,input string message);
        checks++;
        if (!condition) $fatal(1,"HOST_DDR_FAIL seed=%0d check=%0d %s t=%0t fault=%0b/%0d",seed,checks,message,$time,fault,fault_code);
    endtask
    task automatic tick(input int count=1);
        repeat(count) begin @(posedge clk); #1; end
    endtask

    // 独立AXI行为目标：AW/W可以任意先后，真实修改按字节使能发生在B之前。
    bit have_aw=0,b_pending=0,read_active=0;
    logic [31:0] aw_address=0,ar_address=0;
    logic [3:0] aw_id=0,ar_id=0;
    int aw_length=0,ar_length=0,write_count=0,read_count=0,b_delay=0,r_delay=0;
    logic [63:0] write_buffer [256];
    logic [7:0] strobe_buffer [256];
    always @(negedge clk) begin
        m_awready = !cold_reset && !have_aw && !b_pending && !block_aw && $urandom_range(0,3)!=0;
        m_wready = !cold_reset && !b_pending && write_count<256 && $urandom_range(0,3)!=0;
        m_arready = !cold_reset && !read_active && !m_rvalid && !block_ar && $urandom_range(0,3)!=0;
    end
    always @(posedge clk) begin
        if (cold_reset) begin
            have_aw<=0;b_pending<=0;read_active<=0;write_count<=0;read_count<=0;
            m_bvalid<=0;m_rvalid<=0;b_delay<=0;r_delay<=0;
        end else begin
            if (m_awvalid && m_awready) begin
                ck(m_awsize==3 && m_awburst==1 && !m_awlock,"downstream AW format");
                have_aw<=1;aw_address<=m_awaddr;aw_length<=int'(m_awlen)+1;aw_id<=m_awid;bus_writes++;
            end
            if (m_wvalid && m_wready) begin
                ck(write_count<256,"write overflow");
                write_buffer[write_count]<=m_wdata;strobe_buffer[write_count]<=m_wstrb;
                write_count<=write_count+1;write_beats++;
            end
            if (have_aw && write_count==aw_length && !b_pending) begin
                for (int i=0;i<aw_length;i++) begin
                    logic [63:0] value;
                    value=peek(64'(aw_address)+64'(i)*8);
                    for (int b=0;b<8;b++) if (strobe_buffer[i][b]) value[b*8+:8]=write_buffer[i][b*8+:8];
                    memory[(64'(aw_address)+64'(i)*8)>>3]=value;
                end
                have_aw<=0;write_count<=0;b_pending<=1;b_delay<=$urandom_range(1,7);
            end
            if (b_pending && !m_bvalid && mode!=8) begin
                if (b_delay!=0) b_delay<=b_delay-1;
                else begin m_bvalid<=1;m_bid<=mode==7 ? aw_id^4'd1 : aw_id;m_bresp<=mode==1 ? 2'b10 : 2'b00;end
            end
            if (inject_b && !b_pending && !m_bvalid) begin m_bvalid<=1;m_bid<=4'ha;m_bresp<=0;end
            if (m_bvalid && m_bready) begin m_bvalid<=0;b_pending<=0;end
            if (m_arvalid && m_arready) begin
                ck(m_arsize==3 && m_arburst==1 && !m_arlock,"downstream AR format");
                read_active<=1;ar_address<=m_araddr;ar_length<=int'(m_arlen)+1;ar_id<=m_arid;
                read_count<=0;r_delay<=$urandom_range(1,6);bus_reads++;
            end
            if (read_active && !m_rvalid && mode!=6) begin
                if (r_delay!=0) r_delay<=r_delay-1;
                else begin
                    m_rvalid<=1;m_rid<=mode==3 ? ar_id^4'd1 : ar_id;
                    m_rdata<=peek(64'(ar_address)+64'(read_count)*8) ^ (mode==5 ? 64'd1 : 64'd0);
                    m_rresp<=mode==2 ? 2'b10 : 2'b00;
                    m_rlast<=mode==4 ? read_count!=ar_length-1 : read_count==ar_length-1;
                end
            end
            if (inject_r && !read_active && !m_rvalid) begin m_rvalid<=1;m_rid<=4'ha;m_rdata<=0;m_rresp<=0;m_rlast<=1;end
            if (m_rvalid && m_rready) begin
                read_beats++;m_rvalid<=0;
                if (read_count==ar_length-1) read_active<=0;
                else begin read_count<=read_count+1;r_delay<=$urandom_range(0,5);end
            end
        end
    end

    // 既有VALID在背压、权限撤回与外部故障中都必须保持负载。
    bit held_aw=0,held_ar=0,held_w=0,held_b=0,held_r=0;
    logic [60:0] old_aw,old_ar;
    logic [72:0] old_w;
    logic [5:0] old_b;
    logic [70:0] old_r;
    always @(posedge clk) begin
        if(cold_reset) begin held_aw=0;held_ar=0;held_w=0;held_b=0;held_r=0;end
        else begin
            if(held_aw) ck(m_awvalid && {m_awid,m_awaddr,m_awlen,m_awsize,m_awburst,m_awlock,m_awcache,m_awprot,m_awqos}==old_aw,"AW stability");
            if(held_ar) ck(m_arvalid && {m_arid,m_araddr,m_arlen,m_arsize,m_arburst,m_arlock,m_arcache,m_arprot,m_arqos}==old_ar,"AR stability");
            if(held_w) ck(m_wvalid && {m_wdata,m_wstrb,m_wlast}==old_w,"W stability");
            if(held_b) ck(s_bvalid && {s_bid,s_bresp}==old_b,"B stability");
            if(held_r) ck(s_rvalid && {s_rid,s_rdata,s_rresp,s_rlast}==old_r,"R stability");
            held_aw=m_awvalid&&!m_awready;held_ar=m_arvalid&&!m_arready;held_w=m_wvalid&&!m_wready;
            held_b=s_bvalid&&!s_bready;held_r=s_rvalid&&!s_rready;
            old_aw={m_awid,m_awaddr,m_awlen,m_awsize,m_awburst,m_awlock,m_awcache,m_awprot,m_awqos};
            old_ar={m_arid,m_araddr,m_arlen,m_arsize,m_arburst,m_arlock,m_arcache,m_arprot,m_arqos};
            old_w={m_wdata,m_wstrb,m_wlast};old_b={s_bid,s_bresp};old_r={s_rid,s_rdata,s_rresp,s_rlast};
        end
    end

    task automatic reset_chain;
        @(negedge clk);cold_reset=1;external_fault=0;mode=0;block_aw=0;block_ar=0;inject_r=0;inject_b=0;
        permit_read=1;permit_write=1;s_awvalid=0;s_wvalid=0;s_arvalid=0;s_bready=0;s_rready=0;
        tick(4);@(negedge clk);cold_reset=0;tick(2);
        ck(host_idle&&!fault,"cold chain ready (memory retained)");
    endtask
    task automatic send_aw(input logic [31:0] address,input int beats,input logic [2:0] size=3,input logic [1:0] burst=1,input bit locked=0);
        @(negedge clk);s_awid=4'ha;s_awaddr=address;s_awlen=8'(beats-1);s_awsize=size;s_awburst=burst;s_awlock=locked;s_awvalid=1;
        for(int t=0;;t++) begin @(posedge clk);if(s_awready) break;if(t>5000)$fatal(1,"AW source timeout");end
        @(negedge clk);s_awvalid=0;
    endtask
    task automatic send_w(input logic [31:0] address,input int beats,input int tag,input bit partial=0,input bit wrong_last=0);
        for(int i=0;i<beats;i++) begin
            repeat($urandom_range(0,2)) tick();
            @(negedge clk);s_wdata=data_value(address,i,tag);s_wstrb=byte_mask(i,tag,partial);s_wlast=wrong_last ? i!=beats-1 : i==beats-1;s_wvalid=1;
            for(int t=0;;t++) begin @(posedge clk);if(s_wready) break;if(t>5000)$fatal(1,"W source timeout");end
            @(negedge clk);s_wvalid=0;
        end
    endtask
    task automatic take_b(input logic [1:0] response,input int stall=4);
        for(int t=0;!s_bvalid;t++) begin tick();if(t>20000)$fatal(1,"B timeout");end
        ck(!host_idle,"B pending retains ownership");tick(stall);
        @(negedge clk);s_bready=1;@(posedge clk);
        ck(s_bvalid && s_bid==4'ha && s_bresp==response,"host B response");
        @(negedge clk);s_bready=0;tick();
    endtask
    task automatic expect_write(input logic [31:0] address,input int beats,input int tag,input bit partial);
        for(int i=0;i<beats;i++) begin
            logic [63:0] value,data;
            logic [7:0] mask;
            value=expected(64'(address)+64'(i)*8);data=data_value(address,i,tag);mask=byte_mask(i,tag,partial);
            for(int b=0;b<8;b++) if(mask[b]) value[b*8+:8]=data[b*8+:8];
            golden[(64'(address)+64'(i)*8)>>3]=value;
        end
    endtask
    task automatic write_tx(input logic [31:0] address,input int beats,input int tag,input bit partial=0,input logic [1:0] response=0,input int skew=0);
        fork
            begin if(skew>0) tick(skew);send_aw(address,beats);end
            begin if(skew<0) tick(-skew);send_w(address,beats,tag,partial);end
        join
        take_b(response);
        if(response==0) begin expect_write(address,beats,tag,partial);ck(host_idle&&!fault,"write retired and eligible");end
    endtask
    task automatic send_ar(input logic [31:0] address,input int beats,input logic [2:0] size=3,input logic [1:0] burst=1,input bit locked=0);
        @(negedge clk);s_arid=4'h5;s_araddr=address;s_arlen=8'(beats-1);s_arsize=size;s_arburst=burst;s_arlock=locked;s_arvalid=1;
        for(int t=0;;t++) begin @(posedge clk);if(s_arready) break;if(t>5000)$fatal(1,"AR source timeout");end
        @(negedge clk);s_arvalid=0;
    endtask
    task automatic take_r(input logic [31:0] address,input int beats,input logic [1:0] response=0,input int initial_stall=4);
        tick(initial_stall);
        for(int i=0;i<beats;i++) begin
            for(int t=0;;t++) begin
                @(negedge clk);s_rready=$urandom_range(0,3)!=0;
                @(posedge clk);
                if(s_rvalid&&s_rready) begin
                    ck(s_rid==5 && s_rresp==response && s_rlast==(i==beats-1),"host R ID/response/last");
                    if(response==0) ck(s_rdata===expected(64'(address)+64'(i)*8),"host read full data");
                    break;
                end
                if(t>20000)$fatal(1,"R timeout");
            end
        end
        @(negedge clk);s_rready=0;tick();
    endtask
    task automatic read_tx(input logic [31:0] address,input int beats,input logic [1:0] response=0);
        send_ar(address,beats);take_r(address,beats,response);
    endtask
    task automatic wait_fault(input int code);
        for(int t=0;!fault;t++) begin tick();if(t>1000)$fatal(1,"fault timeout");end
        ck(fault_code==32'(code)&&!host_idle,"sticky fault reason");
    endtask
    task automatic isolated;
        tick(5);ck(fault&&!host_idle&&!s_awready&&!s_arready,"fault blocks new transactions");
    endtask

    initial begin
        void'($value$plusargs("seed=%d",seed));random_state=seed;void'($urandom(random_state));
        if($test$plusargs("unexpected_only")) begin
            reset_chain();block_aw=1;
            fork send_aw(32'h12000,1);send_w(32'h12000,1,36);join
            inject_r=1;wait_fault(9);ck(!s_bvalid&&verified_write_beats==0,"unsolicited R cannot verify a write");
            $display("M1_HOST_DDR_UNEXPECTED_PASS");$finish;
        end
        reset_chain();
        // 地址和字节黄金独立于DUT内部；含0/2GiB末端/256-beat整段与全零掩码。
        write_tx(0,1,0,1,0,4);read_tx(0,1);
        write_tx(32'h7ffff800,256,3,1,0,-5);read_tx(32'h7ffff800,256);
        for(int i=0;i<60;i++) begin
            int beats,skew;logic [31:0] address;
            beats=$urandom_range(1,48);skew=int'($urandom_range(0,12))-6;address=32'h10000+32'(i)*4096;
            write_tx(address,beats,i,1,0,skew);read_tx(address,beats);
        end
        // 拒绝的DDR请求既不触发读写，也不改变内存；等待grant的VALID不挂住idle。
        begin
            longint unsigned wb,rb;wb=bus_writes;rb=bus_reads;
            permit_write=0;write_tx(32'h4000,4,11,0,3);permit_read=0;read_tx(32'h4000,3,3);
            ck(host_idle&&!fault && bus_writes==wb && bus_reads==rb,"permission reject has no DDR side effect");
            permit_write=1;permit_read=1;
            fork send_aw(32'h80000000,2);send_w(32'h80000000,2,1);join take_b(3);
            read_tx(32'h80000000,2,3);
            fork send_aw(32'hff8,2);send_w(32'hff8,2,1);join take_b(3);
            send_ar(32'hff8,2);take_r(32'hff8,2,3);
            fork send_aw(32'h1001,2);send_w(32'h1001,2,1);join take_b(3);
            send_ar(32'h1001,2);take_r(32'h1001,2,3);
            fork send_aw(32'h2000,1,2);send_w(32'h2000,1,1);join take_b(3);
            send_ar(32'h2000,1,3,2);take_r(32'h2000,1,3);
            fork send_aw(32'h2000,1,3,1,1);send_w(32'h2000,1,1);join take_b(3);
            send_ar(32'h2000,1,3,1,1);take_r(32'h2000,1,3);
            ck(!fault && bus_writes==wb && bus_reads==rb,"format and bounds reject without target access");
        end
        // B之前已经物理写入，读回未到前不能交付成功；grant因idle下降而撤回不死锁。
        reset_chain();mode=6;
        fork send_aw(32'h6000,8);send_w(32'h6000,8,16);join
        tick(30);ck(!s_bvalid&&verified_write_beats==0&&!host_idle,"write needs verification read");
        mode=0;take_b(0);expect_write(32'h6000,8,16,0);read_tx(32'h6000,8);
        // 每类错误有独立cold，首次错误码保留；错误之后恢复响应不自动解隔离。
        for(int e=1;e<=5;e++) begin
            reset_chain();mode=e;
            write_tx(32'h8000,4,20+e,0,2);wait_fault(e==5 ? 8 : e==1 ? 1 : e==2 ? 2 : e==3 ? 3 : 4);isolated();
        end
        reset_chain();mode=7;write_tx(32'h8000,4,27,0,2);wait_fault(3);isolated();
        reset_chain();mode=2;read_tx(32'h6000,4,2);wait_fault(2);isolated();
        // 响应丢失不合成B/R；迟到后返回错误，仍需要整链cold。
        reset_chain();mode=6;send_ar(32'h6000,4);wait_fault(5);ck(!s_rvalid,"lost R is not fabricated");
        mode=0;take_r(32'h6000,4,2);isolated();
        reset_chain();mode=8;
        fork send_aw(32'h9000,2);send_w(32'h9000,2,9);join
        wait_fault(5);ck(!s_bvalid,"lost B is not fabricated");mode=0;take_b(2);isolated();
        // 已发AR/AW不能因故障撤回；主机背压中的已可见响应必须保持原负载。
        reset_chain();block_ar=1;send_ar(32'h6000,2);tick(6);external_fault=1;tick();wait_fault(7);tick(5);
        ck(m_arvalid&&!host_idle,"fault holds issued AR");block_ar=0;external_fault=0;take_r(32'h6000,2,2);isolated();
        reset_chain();block_aw=1;
        fork send_aw(32'ha000,2);send_w(32'ha000,2,30);join
        tick(6);external_fault=1;tick();wait_fault(7);ck(m_awvalid,"fault holds issued AW");block_aw=0;external_fault=0;take_b(2);isolated();
        reset_chain();send_ar(32'h6000,1);
        while(!s_rvalid) tick();external_fault=1;tick(8);ck(s_rvalid&&s_rresp==0,"visible response cannot change under backpressure");
        take_r(32'h6000,1,0,0);wait_fault(7);isolated();
        // 主机接收端停顿超过DDR超时阈值也不应被误判为下游失联。
        reset_chain();send_ar(32'h6000,1);
        while(!s_rvalid) tick();tick(100);ck(!fault&&!host_idle,"host R backpressure is not DDR timeout");take_r(32'h6000,1,0,0);
        fork send_aw(32'hc000,1);send_w(32'hc000,1,33);join
        take_b(0,100);expect_write(32'hc000,1,33,0);ck(!fault&&host_idle,"host B backpressure is not DDR timeout");
        // 全零mask的字节不参与读回比较；独立读确认物理内容确实未改变。
        mode=5;write_tx(32'hd000,1,0,1);mode=0;read_tx(32'hd000,1);
        // 地址通道永久背压：保持已发VALID；恢复后只排空并返回失败。
        reset_chain();block_ar=1;send_ar(32'h6000,1);wait_fault(5);ck(m_arvalid&&!s_rvalid,"AR timeout retains request");
        block_ar=0;take_r(32'h6000,1,2);isolated();
        reset_chain();block_aw=1;fork send_aw(32'he000,1);send_w(32'he000,1,34);join
        wait_fault(5);ck(m_awvalid&&!s_bvalid,"AW timeout retains request");block_aw=0;take_b(2);isolated();
        // 外部错误与最后一个核验R同拍，禁止增加verified_write_beats。
        reset_chain();fork send_aw(32'hf000,1);send_w(32'hf000,1,35);join
        while(!m_rvalid) @(negedge clk);
        external_fault=1;take_b(2);wait_fault(7);ck(verified_write_beats==0,"fault wins final verification beat");isolated();
        // 上游坏WLAST不能成为成功；下游按已接受长度接收，允许部分物理副作用。
        reset_chain();fork send_aw(32'hb000,3);send_w(32'hb000,3,31,0,1);join take_b(2);wait_fault(4);isolated();
        reset_chain();block_aw=1;
        fork send_aw(32'h12000,1);send_w(32'h12000,1,36);join
        inject_r=1;wait_fault(9);ck(!s_bvalid&&verified_write_beats==0,"unexpected R cannot verify write");
        inject_r=0;block_aw=0;take_b(2);isolated();
        reset_chain();block_ar=1;send_ar(32'h6000,1);inject_b=1;wait_fault(9);
        inject_b=0;block_ar=0;take_r(32'h6000,1,2);isolated();
        reset_chain();write_tx(32'hb000,3,32);read_tx(32'hb000,3);ck(host_idle&&!fault,"whole-chain recovery reuses retained memory safely");
        $display("M1_HOST_DDR_PASS seed=%0d checks=%0d target_writes=%0d target_reads=%0d write_beats=%0d read_beats=%0d",seed,checks,bus_writes,bus_reads,write_beats,read_beats);
        $finish;
    end
    initial begin #20000000;$fatal(1,"global watchdog");end
endmodule
