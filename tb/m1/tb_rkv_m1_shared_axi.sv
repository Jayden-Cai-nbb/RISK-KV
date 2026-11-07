`timescale 1ns/1ps
module tb_rkv_m1_shared_axi;
    logic chain_cold_reset='0;
    logic core_locked='0;
    logic ddr_locked='0;
    logic ddr_calibrated='0;
    logic native_grant='0;
    wire core_cold_reset;
    wire ddr_axi_aresetn;
    wire transport_ready;
    wire admission_enable;
    wire guard_armed;
    wire [3:0] fault_causes;
    wire platform_error;
    wire host_idle;
    wire bridge_idle;
    wire shared_idle;
    wire host_fault;
    wire [31:0] host_fault_code;
    wire bridge_fault;
    wire [31:0] bridge_fault_code;
    wire route_fault;
    wire [63:0] host_verified_beats;
    wire [63:0] native_verified_writes;
    wire [63:0] accepted_reads;
    wire [63:0] accepted_writes;
    wire [63:0] rejected_requests;
    logic [3:0] h_awid='0;
    logic [31:0] h_awaddr='0;
    logic [7:0] h_awlen='0;
    logic [2:0] h_awsize='0;
    logic [1:0] h_awburst='0;
    logic h_awlock='0;
    logic [3:0] h_awcache='0;
    logic [2:0] h_awprot='0;
    logic [3:0] h_awqos='0;
    logic h_awvalid='0;
    wire h_awready;
    logic [63:0] h_wdata='0;
    logic [7:0] h_wstrb='0;
    logic h_wlast='0;
    logic h_wvalid='0;
    wire h_wready;
    wire [3:0] h_bid;
    wire [1:0] h_bresp;
    wire h_bvalid;
    logic h_bready='0;
    logic [3:0] h_arid='0;
    logic [31:0] h_araddr='0;
    logic [7:0] h_arlen='0;
    logic [2:0] h_arsize='0;
    logic [1:0] h_arburst='0;
    logic h_arlock='0;
    logic [3:0] h_arcache='0;
    logic [2:0] h_arprot='0;
    logic [3:0] h_arqos='0;
    logic h_arvalid='0;
    wire h_arready;
    wire [3:0] h_rid;
    wire [63:0] h_rdata;
    wire [1:0] h_rresp;
    wire h_rlast;
    wire h_rvalid;
    logic h_rready='0;
    logic [1:0] n_cvalid='0;
    wire [1:0] n_cready;
    logic [1:0] n_cwe='0;
    logic [49:0] n_caddr='0;
    logic [1:0] n_wvalid='0;
    wire [1:0] n_wready;
    logic [1023:0] n_wdata='0;
    logic [127:0] n_wmask='0;
    wire [1:0] n_rvalid;
    wire [1023:0] n_rdata;
    wire [31:0] n_wdone;
    wire [3:0] m_awid;
    wire [32:0] m_awaddr;
    wire [7:0] m_awlen;
    wire [2:0] m_awsize;
    wire [1:0] m_awburst;
    wire m_awlock;
    wire [3:0] m_awcache;
    wire [2:0] m_awprot;
    wire [3:0] m_awqos;
    wire m_awvalid;
    logic m_awready='0;
    wire [511:0] m_wdata;
    wire [63:0] m_wstrb;
    wire m_wlast;
    wire m_wvalid;
    logic m_wready='0;
    logic [3:0] m_bid='0;
    logic [1:0] m_bresp='0;
    logic m_bvalid='0;
    wire m_bready;
    wire [3:0] m_arid;
    wire [32:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire m_arlock;
    wire [3:0] m_arcache;
    wire [2:0] m_arprot;
    wire [3:0] m_arqos;
    wire m_arvalid;
    logic m_arready='0;
    logic [3:0] m_rid='0;
    logic [511:0] m_rdata='0;
    logic [1:0] m_rresp='0;
    logic m_rlast='0;
    logic m_rvalid='0;
    wire m_rready;
    logic clk=0,ui_clk=0;
    bit core_running=1,ui_running=1;
    always #10 if(core_running) clk=~clk;
    int ui_phase_ps=3333;
    initial begin if(!$value$plusargs("ui_phase_ps=%d",ui_phase_ps))ui_phase_ps=3333; #(ui_phase_ps*0.001); forever #2.604 if(ui_running) ui_clk=~ui_clk;end
    bit permit_read=1,permit_write=1;
    logic [3:0] write_id=10,read_id=5;
    rkv_m1_shared_axi #(.TIMEOUT_CYCLES(32'd256)) dut (
        .core_clk(clk),
        .ddr_clk(ui_clk),
        .chain_cold_reset(chain_cold_reset),
        .core_locked(core_locked),
        .ddr_locked(ddr_locked),
        .ddr_calibrated(ddr_calibrated),
        .external_fault(1'b0),
        .host_read_grant(permit_read && host_idle),
        .host_write_grant(permit_write && host_idle),
        .native_grant(native_grant),
        .control_cold_reset(),
        .core_cold_reset(core_cold_reset),
        .ddr_axi_aresetn(ddr_axi_aresetn),
        .transport_ready(transport_ready),
        .admission_enable(admission_enable),
        .guard_armed(guard_armed),
        .fault_causes(fault_causes),
        .platform_error(platform_error),
        .host_idle(host_idle),
        .bridge_idle(bridge_idle),
        .shared_idle(shared_idle),
        .host_fault(host_fault),
        .host_fault_code(host_fault_code),
        .bridge_fault(bridge_fault),
        .bridge_fault_code(bridge_fault_code),
        .route_fault(route_fault),
        .host_verified_beats(host_verified_beats),
        .native_verified_writes(native_verified_writes),
        .accepted_reads(accepted_reads),
        .accepted_writes(accepted_writes),
        .rejected_requests(rejected_requests),
        .h_awid(h_awid),
        .h_awaddr(h_awaddr),
        .h_awlen(h_awlen),
        .h_awsize(h_awsize),
        .h_awburst(h_awburst),
        .h_awlock(h_awlock),
        .h_awcache(h_awcache),
        .h_awprot(h_awprot),
        .h_awqos(h_awqos),
        .h_awvalid(h_awvalid),
        .h_awready(h_awready),
        .h_wdata(h_wdata),
        .h_wstrb(h_wstrb),
        .h_wlast(h_wlast),
        .h_wvalid(h_wvalid),
        .h_wready(h_wready),
        .h_bid(h_bid),
        .h_bresp(h_bresp),
        .h_bvalid(h_bvalid),
        .h_bready(h_bready),
        .h_arid(h_arid),
        .h_araddr(h_araddr),
        .h_arlen(h_arlen),
        .h_arsize(h_arsize),
        .h_arburst(h_arburst),
        .h_arlock(h_arlock),
        .h_arcache(h_arcache),
        .h_arprot(h_arprot),
        .h_arqos(h_arqos),
        .h_arvalid(h_arvalid),
        .h_arready(h_arready),
        .h_rid(h_rid),
        .h_rdata(h_rdata),
        .h_rresp(h_rresp),
        .h_rlast(h_rlast),
        .h_rvalid(h_rvalid),
        .h_rready(h_rready),
        .n_cvalid(n_cvalid),
        .n_cready(n_cready),
        .n_cwe(n_cwe),
        .n_caddr(n_caddr),
        .n_wvalid(n_wvalid),
        .n_wready(n_wready),
        .n_wdata(n_wdata),
        .n_wmask(n_wmask),
        .n_rvalid(n_rvalid),
        .n_rdata(n_rdata),
        .n_wdone(n_wdone),
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
    bit block_aw=0, block_ar=0;
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
        if (!condition) $fatal(1,"SHARED_AXI_FAIL seed=%0d check=%0d %s t=%0t fault=%0b/%0d",seed,checks,message,$time,platform_error,host_fault_code);
    endtask
    task automatic tick(input int count=1);
        repeat(count) begin @(posedge clk); #1; end
    endtask


    task automatic send_aw(input logic [31:0] address,input int beats,input logic [2:0] size=3,input logic [1:0] burst=1,input bit locked=0);
        @(negedge clk);h_awid=write_id;h_awaddr=address;h_awlen=8'(beats-1);h_awsize=size;h_awburst=burst;h_awlock=locked;h_awvalid=1;
        for(int t=0;;t++) begin @(posedge clk);if(h_awready) break;if(t>5000)$fatal(1,"AW source timeout");end
        @(negedge clk);h_awvalid=0;
    endtask
    task automatic send_w(input logic [31:0] address,input int beats,input int tag,input bit partial=0,input bit wrong_last=0);
        for(int i=0;i<beats;i++) begin
            repeat($urandom_range(0,2)) tick();
            @(negedge clk);h_wdata=data_value(address,i,tag);h_wstrb=byte_mask(i,tag,partial);h_wlast=wrong_last ? i!=beats-1 : i==beats-1;h_wvalid=1;
            for(int t=0;;t++) begin @(posedge clk);if(h_wready) break;if(t>5000)$fatal(1,"W source timeout");end
            @(negedge clk);h_wvalid=0;
        end
    endtask
    task automatic take_b(input logic [1:0] response,input int stall=4);
        for(int t=0;!h_bvalid;t++) begin tick();if(t>20000)$fatal(1,"B timeout");end
        ck(!host_idle,"B pending retains ownership");tick(stall);
        @(negedge clk);h_bready=1;@(posedge clk);
        ck(h_bvalid && h_bid==write_id && h_bresp==response,"host B response");
        @(negedge clk);h_bready=0;tick();
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
        if(response==0) begin expect_write(address,beats,tag,partial);ck(host_idle&&!platform_error,"write retired and eligible");end
    endtask
    task automatic send_ar(input logic [31:0] address,input int beats,input logic [2:0] size=3,input logic [1:0] burst=1,input bit locked=0);
        @(negedge clk);h_arid=read_id;h_araddr=address;h_arlen=8'(beats-1);h_arsize=size;h_arburst=burst;h_arlock=locked;h_arvalid=1;
        for(int t=0;;t++) begin @(posedge clk);if(h_arready) break;if(t>5000)$fatal(1,"AR source timeout");end
        @(negedge clk);h_arvalid=0;
    endtask
    task automatic take_r(input logic [31:0] address,input int beats,input logic [1:0] response=0,input int initial_stall=4);
        tick(initial_stall);
        for(int i=0;i<beats;i++) begin
            for(int t=0;;t++) begin
                @(negedge clk);h_rready=$urandom_range(0,3)!=0;
                @(posedge clk);
                if(h_rvalid&&h_rready) begin
                    ck(h_rid==read_id && h_rresp==response && h_rlast==(i==beats-1),"host R ID/response/last");
                    if(response==0) ck(h_rdata===expected(64'(address)+64'(i)*8),"host read full data");
                    break;
                end
                if(t>20000)$fatal(1,"R timeout");
            end
        end
        @(negedge clk);h_rready=0;tick();
    endtask
    task automatic read_tx(input logic [31:0] address,input int beats,input logic [1:0] response=0);
        send_ar(address,beats);take_r(address,beats,response);
    endtask

    // 独立DDR UI目标，线性64-byte AXI；主机/nativ​​e共同参考同一逐64-bit字黄金。
    // 只验证有限地址，不是全2GiB存储测试；目标对读写可独立背压。
    bit have_aw=0,b_pending=0,read_active=0,w_complete=0;
    int w_before_aw=0,blocked_next_w=0;
    logic [32:0] aw_address=0,ar_address=0;
    logic [3:0] aw_id=0,ar_id=0;
    int aw_length=0,ar_length=0,write_count=0,read_count=0,b_delay=0,r_delay=0;
    logic [511:0] write_buffer [256];
    logic [63:0] strobe_buffer [256];
    logic last_buffer [256];
    int native_reads[2]='{0,0};
    logic [511:0] native_last[2];
    always @(negedge ui_clk) begin
        m_awready = ddr_axi_aresetn && !have_aw && !b_pending && !block_aw && $urandom_range(0,3)!=0;
        m_wready = ddr_axi_aresetn && !b_pending && !w_complete && write_count<256 && $urandom_range(0,3)!=0;
        m_arready = ddr_axi_aresetn && !read_active && !m_rvalid && !block_ar && $urandom_range(0,3)!=0;
    end
    always @(posedge ui_clk) begin
        if (!ddr_axi_aresetn) begin
            have_aw<=0;b_pending<=0;read_active<=0;w_complete<=0;write_count<=0;read_count<=0;
            m_bvalid<=0;m_rvalid<=0;b_delay<=0;r_delay<=0;
        end else begin
            if (m_awvalid && m_awready) begin
                ck(m_awsize==6 && m_awburst==1 && !m_awlock && m_awid==0 && m_awaddr[5:0]==0,"UI AW format/ID0");
                ck(m_awaddr+33'(int'(m_awlen)+1)*64<=33'h80000000,"UI write within 2GiB");
                have_aw<=1;aw_address<=m_awaddr;aw_length<=int'(m_awlen)+1;aw_id<=m_awid;bus_writes++;
            end
            if (m_wvalid && m_wready) begin
                ck(write_count<256,"write overflow");
                if(!have_aw)w_before_aw++;
                write_buffer[write_count]<=m_wdata;strobe_buffer[write_count]<=m_wstrb;last_buffer[write_count]<=m_wlast;
                write_count<=write_count+1;write_beats++;
                if(m_wlast)w_complete<=1;
            end
            if(w_complete&&m_wvalid&&!m_wready)blocked_next_w++;
            if (have_aw && write_count==aw_length && !b_pending) begin
                ck(!(m_wvalid && m_wready), "BFM must not erase a newly accepted next-burst W during commit");
                for(int i=0;i<aw_length;i++) begin
                    ck(last_buffer[i]==(i==aw_length-1),"UI WLAST matches expanded burst");
                    for(int j=0;j<8;j++) begin
                        logic [63:0] value;
                        longint unsigned address;
                        address=64'(aw_address)+64'(i)*64+64'(j)*8;value=peek(address);
                        for(int b=0;b<8;b++) if(strobe_buffer[i][8*j+b]) value[b*8+:8]=write_buffer[i][(8*j+b)*8+:8];
                        memory[address>>3]=value;
                    end
                end
                have_aw<=0;write_count<=0;w_complete<=0;b_pending<=1;b_delay<=$urandom_range(1,10);
            end
            if(b_pending && !m_bvalid && mode!=8) begin
                if(b_delay!=0)b_delay<=b_delay-1;
                else begin m_bvalid<=1;m_bid<=mode==7 ? 4'd1 : aw_id;m_bresp<=mode==1 ? 2'b10 : 2'b00;end
            end
            if(m_bvalid&&m_bready)begin m_bvalid<=0;b_pending<=0;end
            if(m_arvalid&&m_arready)begin
                ck(m_arsize==6 && m_arburst==1 && !m_arlock && m_arid==0 && m_araddr[5:0]==0,"UI AR format/ID0");
                ck(m_araddr+33'(int'(m_arlen)+1)*64<=33'h80000000,"UI read within 2GiB");
                read_active<=1;ar_address<=m_araddr;ar_length<=int'(m_arlen)+1;ar_id<=m_arid;
                read_count<=0;r_delay<=$urandom_range(1,10);bus_reads++;
            end
            if(read_active&&!m_rvalid&&mode!=6) begin
                if(r_delay!=0)r_delay<=r_delay-1;
                else begin
                    m_rvalid<=1;m_rid<=mode==3 ? 4'd1 : ar_id;
                    for(int j=0;j<8;j++)m_rdata[j*64+:64]<=peek(64'(ar_address)+64'(read_count)*64+64'(j)*8) ^ (mode==5?64'd1:64'd0);
                    m_rresp<=mode==2 ? 2'b10:2'b00;m_rlast<=read_count==ar_length-1;
                end
            end
            if(m_rvalid&&m_rready)begin
                m_rvalid<=0;read_beats++;
                if(read_count==ar_length-1)read_active<=0;
                else begin read_count<=read_count+1;r_delay<=$urandom_range(0,7);end
            end
        end
    end
    always @(posedge clk) begin
        if(core_cold_reset)begin native_reads[0]=0;native_reads[1]=0;end
        else for(int c=0;c<2;c++)if(n_rvalid[c])begin native_reads[c]++;native_last[c]=n_rdata[c*512+:512];end
    end
    task automatic ready_chain;
        for(int t=0;!admission_enable;t++)begin tick();if(t>500)$fatal(1,"admission timeout");end
        tick(30);ck(shared_idle&&!platform_error,"whole chain ready");
    endtask
    task automatic reset_chain;
        @(negedge clk);chain_cold_reset=1;n_cvalid=0;n_wvalid=0;h_awvalid=0;h_wvalid=0;h_arvalid=0;h_bready=0;h_rready=0;
        mode=0;block_aw=0;block_ar=0;core_locked=1;ddr_locked=1;ddr_calibrated=1;native_grant=1;permit_read=1;permit_write=1;
        tick(4);@(negedge clk);chain_cold_reset=0;ready_chain();
    endtask
    task automatic native_command(input bit c,input bit write,input logic [24:0] beat);
        @(negedge clk);n_cwe[c]=write;n_caddr[c*25+:25]=beat;n_cvalid[c]=1;
        for(int t=0;;t++)begin @(posedge clk);if(n_cready[c])break;if(t>5000)$fatal(1,"native command timeout");end
        @(negedge clk);n_cvalid[c]=0;
    endtask
    task automatic native_data(input bit c,input logic[511:0] value,input logic[63:0] mask);
        @(negedge clk);n_wdata[c*512+:512]=value;n_wmask[c*64+:64]=mask;n_wvalid[c]=1;
        for(int t=0;;t++)begin @(posedge clk);if(n_wready[c])break;if(t>5000)$fatal(1,"native data timeout");end
        @(negedge clk);n_wvalid[c]=0;
    endtask
    task automatic native_write(input logic[31:0] address,input int tag);
        logic[24:0] beat;bit c;logic[511:0] value;logic[63:0] mask;logic[15:0] before_count;
        beat=25'(address>>7);c=address[6]^(^beat);before_count=n_wdone[c*16+:16];
        for(int i=0;i<8;i++)begin value[i*64+:64]=data_value(address,i,tag);mask[i*8+:8]=byte_mask(i,tag,1);end
        fork native_command(c,1,beat);native_data(c,value,mask);join
        for(int t=0;n_wdone[c*16+:16]==before_count;t++)begin tick();if(t>5000)$fatal(1,"native write retirement timeout");end
        ck(n_wdone[c*16+:16]==before_count+16'd1&&!platform_error,"native retirement exactly once");
        expect_write(address,8,tag,1);
    endtask
    task automatic native_read(input logic[31:0] address);
        logic[24:0] beat;bit c;int before_count;
        beat=25'(address>>7);c=address[6]^(^beat);before_count=native_reads[c];native_command(c,0,beat);
        for(int t=0;native_reads[c]==before_count;t++)begin tick();if(t>5000)$fatal(1,"native read timeout");end
        for(int i=0;i<8;i++)ck(native_last[c][i*64+:64]===expected(64'(address)+64'(i)*8),"host/native linear bytes agree");
        ck(!platform_error,"native read no fault");
    endtask
    task automatic wait_isolation;
        for(int t=0;!platform_error;t++)begin tick();if(t>1000)$fatal(1,"fault timeout");end
        tick(4);ck(host_fault&&bridge_fault&&!admission_enable&&!shared_idle,"common isolation reaches both sources");
    endtask
    // 对真实厂商互连的输出及主机返回做RV背压稳定性核对。
    bit held_aw=0,held_ar=0,held_w=0,held_b=0,held_r=0;
    logic[61:0] old_aw,old_ar;logic[576:0] old_w;logic[5:0] old_b;logic[70:0] old_r;
    always @(posedge ui_clk)begin
        if(!ddr_axi_aresetn)begin held_aw=0;held_ar=0;held_w=0;end
        else begin
            if(held_aw)ck(m_awvalid&&{m_awid,m_awaddr,m_awlen,m_awsize,m_awburst,m_awlock,m_awcache,m_awprot,m_awqos}===old_aw,"UI AW stability");
            if(held_ar)ck(m_arvalid&&{m_arid,m_araddr,m_arlen,m_arsize,m_arburst,m_arlock,m_arcache,m_arprot,m_arqos}===old_ar,"UI AR stability");
            if(held_w)ck(m_wvalid&&{m_wdata,m_wstrb,m_wlast}===old_w,"UI W stability");
            held_aw=m_awvalid&&!m_awready;held_ar=m_arvalid&&!m_arready;held_w=m_wvalid&&!m_wready;
            old_aw={m_awid,m_awaddr,m_awlen,m_awsize,m_awburst,m_awlock,m_awcache,m_awprot,m_awqos};
            old_ar={m_arid,m_araddr,m_arlen,m_arsize,m_arburst,m_arlock,m_arcache,m_arprot,m_arqos};
            old_w={m_wdata,m_wstrb,m_wlast};
        end
    end
    always @(posedge clk)begin
        if(core_cold_reset)begin held_b=0;held_r=0;end
        else begin
            if(held_b)ck(h_bvalid&&{h_bid,h_bresp}===old_b,"host B stable");
            if(held_r)ck(h_rvalid&&{h_rid,h_rdata,h_rresp,h_rlast}===old_r,"host R stable");
            held_b=h_bvalid&&!h_bready;held_r=h_rvalid&&!h_rready;
            old_b={h_bid,h_bresp};old_r={h_rid,h_rdata,h_rresp,h_rlast};
        end
    end
    initial begin
        if(!$value$plusargs("seed=%d",seed))seed=1;random_state=seed;random_state=$urandom(random_state);
        reset_chain();
        // 明确制造W先到而AW被阻塞，不能仅依赖随机READY碰巧覆盖。
        block_aw=1;
        fork
            write_tx(32'h2000,8,40,1);
            native_write(32'h3000,41);
            begin
                for(int t=0;!w_complete;t++)begin tick();if(t>200)$fatal(1,"W-before-AW coverage timeout");end
                tick(40);block_aw=0;
            end
        join
        read_tx(32'h2000,8);read_tx(32'h3000,8);
        ck(w_before_aw>0,"explicit W-before-AW case exercised");
        reset_chain();
        // 8个64-bit lane、部分mask、字序、full-width对齐和非64-byte对齐。
        for(int i=0;i<32;i++)begin
            logic[31:0] address;int beats;
            address=32'h10000+32'(i)*4096+32'(i%8)*8;beats=i+1;
            write_id=4'(i);read_id=4'(15-i);h_awcache=i%2 ? 4'd2:4'd0;h_arcache=h_awcache;
            write_tx(address,beats,i,1,0,(i%7)-3);read_tx(address,beats);
            native_read(address&32'hffffffc0);
        end
        write_tx(32'h7ffff800,256,55,1);read_tx(32'h7ffff800,256);native_read(32'h7fffffc0);
        write_tx(32'h7ffff7f8,255,56,1);read_tx(32'h7ffff7f8,255);
        native_write(32'h7fffffc0,57);read_tx(32'h7fffffc0,8);
        // 并发仅为路由压力测试，地址不相交；不是运行阶段允许主机改模型的合同。
        write_id=0;read_id=0;
        fork
            begin
                for(int i=0;i<12;i++)begin
                    write_tx(32'h400000+32'(i)*4096,40+i,i+60,1);read_tx(32'h400000+32'(i)*4096,40+i);
                end
            end
            begin
                for(int i=0;i<24;i++)begin native_write(32'h600000+32'(i)*64,i+100);native_read(32'h600000+32'(i)*64);end
            end
        join
        for(int i=0;i<24;i++)read_tx(32'h600000+32'(i)*64,8);
        ck(native_verified_writes==25,"native aggregate retirement");
        // 无权限以及控制地址不能走DDR；不允许互连地址扩展后产生别名。
        begin
            longint unsigned wb,rb;wb=bus_writes;rb=bus_reads;
            permit_write=0;write_tx(0,1,1,0,3);permit_read=0;read_tx(0,1,3);
            permit_write=1;permit_read=1;write_tx(32'h80000000,1,1,0,3);read_tx(32'h80000000,1,3);
            ck(bus_writes==wb&&bus_reads==rb&&!platform_error,"rejected host requests never reach DDR");
        end
        // 错误ID不能在无ID出口被静默丢弃，正确身份也不可掩盖读回差异。
        for(int e=1;e<=3;e++)begin
            reset_chain();mode=e;
            write_tx(32'h8000,8,200+e,0,2);wait_isolation();
            ck(host_verified_beats==0&&native_verified_writes==0,"failed host write no retirement");
            if(e==3)ck(route_fault,"wrong RID latched before ID stripping");
        end
        reset_chain();mode=7;write_tx(32'h8000,1,207,0,2);wait_isolation();ck(route_fault,"wrong BID isolated");
        reset_chain();mode=5;write_tx(32'h8000,8,205,0,2);wait_isolation();ck(host_fault_code==8,"readback mismatch detected through packing");
        // 丢失响应必须占有并隔离；迟到返回无成功，不能伪造完成或自动开闸。
        reset_chain();mode=6;send_ar(32'h10000,8);wait_isolation();ck(!h_rvalid,"lost response not fabricated");
        mode=0;take_r(32'h10000,8,2);ck(!shared_idle&&platform_error,"late response cannot restore service");
        // 运行失锁不复位CDC/互连。冷恢复保留物理存储，黄金改为实际已发生写的状态。
        reset_chain();mode=6;send_ar(32'h10000,1);
        while(!read_active)tick();@(negedge clk);core_locked=0;tick();core_locked=1;
        wait_isolation();ck(!core_cold_reset&&ddr_axi_aresetn,"runtime loss does not reset transaction queues");
        mode=0;take_r(32'h10000,1,2);
        reset_chain();write_tx(32'h8000,8,208);read_tx(32'h8000,8);native_read(32'h8000);
        // 未确认响应时进行整链冷复位，旧结果不得在新身份出现。
        mode=6;send_ar(32'h8000,8);while(!read_active)tick();reset_chain();tick(40);ck(!h_rvalid&&!h_bvalid,"old responses absent after whole-chain reset");
        read_tx(32'h8000,8);native_read(32'h8000);
        // 后续burst的随机背压跨三个种子汇总覆盖；每种子仍执行不丢W断言。
        ck(w_before_aw>0,"AW/W independence exercised");
        $display("M1_SHARED_AXI_PASS seed=%0d checks=%0d ui_writes=%0d ui_reads=%0d write_beats=%0d read_beats=%0d w_before_aw=%0d blocked_next_w=%0d",seed,checks,bus_writes,bus_reads,write_beats,read_beats,w_before_aw,blocked_next_w);$finish;
    end
    initial begin #20000000;$fatal(1,"global watchdog");end
endmodule
