`timescale 1ns/1ps
// 实际CPU/缓存/AXI/CDC；仅compute为显式协议夹具，UI为独立行为目标。
module tb_rkv_m1_platform_lifecycle;
    import rkv_m1_layout_pkg::*;
    logic  chain_cold_reset=0;
    logic  core_locked=0;
    logic  ddr_locked=0;
    logic  ddr_calibrated=0;
    logic  external_fault=0;
    logic  inject_task_error=0;
    logic [3:0] h_awid=0;
    logic [31:0] h_awaddr=0;
    logic [7:0] h_awlen=0;
    logic [2:0] h_awsize=0;
    logic [1:0] h_awburst=0;
    logic  h_awlock=0;
    logic [3:0] h_awcache=0;
    logic [2:0] h_awprot=0;
    logic [3:0] h_awqos=0;
    logic  h_awvalid=0;
    wire  h_awready;
    logic [63:0] h_wdata=0;
    logic [7:0] h_wstrb=0;
    logic  h_wlast=0;
    logic  h_wvalid=0;
    wire  h_wready;
    wire [3:0] h_bid;
    wire [1:0] h_bresp;
    wire  h_bvalid;
    logic  h_bready=0;
    logic [3:0] h_arid=0;
    logic [31:0] h_araddr=0;
    logic [7:0] h_arlen=0;
    logic [2:0] h_arsize=0;
    logic [1:0] h_arburst=0;
    logic  h_arlock=0;
    logic [3:0] h_arcache=0;
    logic [2:0] h_arprot=0;
    logic [3:0] h_arqos=0;
    logic  h_arvalid=0;
    wire  h_arready;
    wire [3:0] h_rid;
    wire [63:0] h_rdata;
    wire [1:0] h_rresp;
    wire  h_rlast;
    wire  h_rvalid;
    logic  h_rready=0;
    wire [3:0] m_awid;
    wire [32:0] m_awaddr;
    wire [7:0] m_awlen;
    wire [2:0] m_awsize;
    wire [1:0] m_awburst;
    wire  m_awlock;
    wire [3:0] m_awcache;
    wire [2:0] m_awprot;
    wire [3:0] m_awqos;
    wire  m_awvalid;
    logic  m_awready=0;
    wire [511:0] m_wdata;
    wire [63:0] m_wstrb;
    wire  m_wlast;
    wire  m_wvalid;
    logic  m_wready=0;
    logic [3:0] m_bid=0;
    logic [1:0] m_bresp=0;
    logic  m_bvalid=0;
    wire  m_bready;
    wire [3:0] m_arid;
    wire [32:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire  m_arlock;
    wire [3:0] m_arcache;
    wire [2:0] m_arprot;
    wire [3:0] m_arqos;
    wire  m_arvalid;
    logic  m_arready=0;
    logic [3:0] m_rid=0;
    logic [511:0] m_rdata=0;
    logic [1:0] m_rresp=0;
    logic  m_rlast=0;
    logic  m_rvalid=0;
    wire  m_rready;
    wire  control_cold_reset;
    wire  core_cold_reset;
    wire  ddr_axi_aresetn;
    wire  admission_enable;
    wire [3:0] fault_causes;
    wire  platform_error;
    wire [63:0] host_verified_beats;
    wire [63:0] native_verified_writes;
    wire  cpu_reset_pulse;
    wire  cq_valid;
    wire  isolated;
    wire  reset_pending;
    wire [31:0] epoch;
    wire [31:0] generation;
    wire [31:0] built_tokens;
    wire [63:0] committed_tasks;
    wire [31:0] last_error;
    wire  boot_waiting;
    wire  trap;
    wire  test_done;
    wire [31:0] test_code;
    wire  boot_hold;
    logic clk=0,clk_f=0,ui_clk=0;
    bit ui_running=0;
    always #10 clk=~clk;
    always #5 clk_f=~clk_f;
    int ui_phase_ps=3333;
    initial begin if(!$value$plusargs("ui_phase_ps=%d",ui_phase_ps))ui_phase_ps=3333; #(ui_phase_ps*0.001); forever #2.604 if(ui_running)ui_clk=~ui_clk;end
    logic [3:0] write_id=10,read_id=5;
    rkv_m1_platform #(.TIMEOUT_CYCLES(32'd4096)) dut (
        .core_clk(clk),
        .fast_clk(clk_f),
        .ddr_clk(ui_clk),
        .chain_cold_reset(chain_cold_reset),
        .core_locked(core_locked),
        .ddr_locked(ddr_locked),
        .ddr_calibrated(ddr_calibrated),
        .external_fault(external_fault),
        .inject_task_error(inject_task_error),
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
        .m_rready(m_rready),
        .control_cold_reset(control_cold_reset),
        .core_cold_reset(core_cold_reset),
        .ddr_axi_aresetn(ddr_axi_aresetn),
        .admission_enable(admission_enable),
        .fault_causes(fault_causes),
        .platform_error(platform_error),
        .host_verified_beats(host_verified_beats),
        .native_verified_writes(native_verified_writes),
        .cpu_reset_pulse(cpu_reset_pulse),
        .cq_valid(cq_valid),
        .isolated(isolated),
        .reset_pending(reset_pending),
        .epoch(epoch),
        .generation(generation),
        .built_tokens(built_tokens),
        .committed_tasks(committed_tasks),
        .last_error(last_error),
        .boot_waiting(boot_waiting),
        .trap(trap),
        .test_done(test_done),
        .test_code(test_code),
        .boot_hold(boot_hold)
    );
    wire  host_idle = dut.host_idle;
    wire  shared_idle = dut.shared_idle;
    wire  bridge_idle = dut.bridge_idle;
    wire  host_fault = dut.host_fault;
    wire  bridge_fault = dut.bridge_fault;
    wire [31:0] host_fault_code = dut.host_fault_code;
    wire  memory_idle = dut.memory_idle;
    wire [1:0] memory_outstanding = dut.memory_outstanding;
    wire  ingress_fault = dut.ingress_fault;
    wire  memory_accept_now = dut.memory_accept_now;
    wire  saved_read_grant = dut.saved_read_grant;
    wire  reset_request = dut.reset_request;
    wire [1:0] n_rvalid = dut.n_rvalid;
    wire [1023:0] n_rdata = dut.n_rdata;
    wire  transport_ready = dut.transport_ready;
    wire  guard_armed = dut.guard_armed;
    wire  sys_cq_valid = dut.native.cq_valid;
    wire [63:0] sys_next_sequence = dut.native.next_sequence;
    wire [31:0] sys_last_error = dut.native.last_error;
    wire  sys_launch_pulse = dut.native.launch_pulse;
    wire [31:0] sys_epoch = dut.native.epoch;
    wire [31:0] sys_generation = dut.native.generation;
    wire  sys_boot_waiting = dut.native.boot_waiting;
    wire  sys_host_write_grant = dut.native.host_write_grant;
    wire  sys_host_read_grant = dut.native.host_read_grant;
    wire [31:0] sys_built_tokens = dut.native.built_tokens;
    wire [63:0] sys_committed_tasks = dut.native.committed_tasks;
    wire  sys_npu_reset = dut.native.npu_reset;
    wire [63:0] sys_rejected_count = dut.native.rejected_count;
    wire  sys_cmd_ready = dut.native.cmd_ready;
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
        if (!condition) $fatal(1,"FULL_PLATFORM_FAIL seed=%0d check=%0d %s t=%0t fault=%0b/%0d",seed,checks,message,$time,platform_error,host_fault_code);
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
        tick(stall); // 根互连可缓存B；DDR门控退休不等于外部主机已消费。
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
        tick(30);ck(shared_idle&&!platform_error,"chain healthy");
    endtask
    task automatic reset_chain;
        @(negedge clk);chain_cold_reset=1;h_awvalid=0;h_wvalid=0;h_arvalid=0;h_bready=0;h_rready=0;
        mode=0;block_aw=0;block_ar=0;inject_task_error=0;core_locked=1;ddr_locked=1;ddr_calibrated=1;
        tick(4);@(negedge clk);chain_cold_reset=0;ready_chain();
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
        if(control_cold_reset)begin held_b=0;held_r=0;end
        else begin
            if(held_b)ck(h_bvalid&&{h_bid,h_bresp}===old_b,"host B stable");
            if(held_r)ck(h_rvalid&&{h_rid,h_rdata,h_rresp,h_rlast}===old_r,"host R stable");
            held_b=h_bvalid&&!h_bready;held_r=h_rvalid&&!h_rready;
            old_b={h_bid,h_bresp};old_r={h_rid,h_rdata,h_rresp,h_rlast};
        end
    end

    int reset_pulses=0;
    always @(posedge clk) if(reset_request) reset_pulses++;
    task automatic csr_read(input logic[31:0] address,input logic[63:0] expected_value,input logic[63:0] mask=64'hffffffffffffffff);
        send_ar(address,1);tick(4);
        @(negedge clk);h_rready=1;
        for(int t=0;;t++)begin
            @(posedge clk);
            if(h_rvalid)begin
                ck(h_rid==read_id&&h_rresp==0&&h_rlast,"CSR response identity");
                if ((h_rdata&mask)!=(expected_value&mask)) $display("CSR_MISMATCH address=%h actual=%h expected=%h mask=%h",address,h_rdata,expected_value,mask);
                ck((h_rdata&mask)==(expected_value&mask),"CSR data");break;
            end
            if(t>500)$fatal(1,"CSR read timeout");
        end
        @(negedge clk);h_rready=0;tick();
    endtask
    task automatic csr_write(input logic[31:0] address,input logic[31:0] value,input logic[1:0] response=0);
        send_aw(address,1);
        @(negedge clk);h_wdata={32'd0,value};h_wstrb=8'h0f;h_wlast=1;h_wvalid=1;
        for(int t=0;;t++)begin @(posedge clk);if(h_wready)break;if(t>500)$fatal(1,"CSR W timeout");end
        @(negedge clk);h_wvalid=0;take_b(response);
    endtask
    integer serial=0,launches=0;
    logic [31:0] hvalue,saved[11];
    logic [63:0] host_session=64'h1234567812345678;
    always @(posedge clk) if(!control_cold_reset && sys_launch_pulse) launches++;
    task automatic hword(input integer word_index,input logic write_op,input logic[31:0] value);
        if(write_op) csr_write(32'h80010000+32'(word_index)*8,value);
        else begin
            send_ar(32'h80010000+32'(word_index)*8,1);
            @(negedge clk);h_rready=1;
            for(int t=0;;t++)begin
                @(posedge clk);
                if(h_rvalid)begin
                    ck(h_rresp==0 && h_rlast && h_rid==read_id && h_rdata[63:32]==0,"mailbox AXI response");
                    hvalue=h_rdata[31:0];
                    break;
                end
                if(t>1000)$fatal(1,"mailbox AXI timeout");
            end
            @(negedge clk);h_rready=0;tick();
        end
    endtask
    task automatic ready_epoch(input logic [31:0] expected);
        hword(MB_READY_EPOCH,0,0);
        for(int poll=0;hvalue!==expected;poll++)begin
            if(poll>2000)$fatal(1,"ready epoch timeout");
            hword(MB_READY_EPOCH,0,0);
        end
        ck(hvalue===expected,"ready epoch positively observed");
    endtask
    task automatic stage(input logic [31:0] action, input logic [31:0] op);
        hword(MB_ACTION,1,action); hword(MB_OP,1,op);
        hword(MB_SESSION0,1,host_session[31:0]); hword(MB_SESSION1,1,host_session[63:32]);
        hword(MB_EPOCH,1,sys_epoch); hword(MB_SEQUENCE0,1,sys_next_sequence[31:0]);
        hword(MB_SEQUENCE1,1,sys_next_sequence[63:32]); hword(MB_CONTEXT,1,7);
        hword(MB_GENERATION,1,sys_generation); hword(MB_TOKEN0,1,3555); hword(MB_TOKEN1,1,8429);
    endtask
    task automatic ring;
        serial++; hword(MB_DOORBELL,1,32'(serial));
    endtask
    task automatic response(input logic [31:0] expected);
        logic [31:0] expected_serial;
        expected_serial=32'(serial);
        hword(MB_RESPONSE,0,0);
        for(int poll=0;hvalue!==expected_serial;poll++)begin
            if(poll>2000)$fatal(1,"mailbox response timeout");
            hword(MB_RESPONSE,0,0);
        end
        ck(hvalue===expected_serial,"response serial positively observed before reading payload");
        hword(MB_RESULT,0,0);
        if (hvalue !== expected) $fatal(1,"mailbox result got=%h expected=%h serial=%0d",hvalue,expected,serial);
        for (int i=0;i<11;i++) begin hword(MB_CQ0+i,0,0); saved[i]=hvalue; end
        checks++;
    endtask
    task automatic submit(input logic [31:0] op);
        stage(1,op); ring(); response(0);
    endtask
    task automatic acknowledge(input logic corrupt_identity, input logic [31:0] expected);
        hword(MB_ACTION,1,2);
        for (int i=0;i<7;i++) hword(MB_SESSION0+i,1,saved[2+i] ^ ((corrupt_identity && i==0)?32'd1:32'd0));
        ring(); response(expected);
    endtask
    // 读取数据独立按主机事先写入的字计算；不以DUT内部结果反作黄金。
    task automatic check_native;
        for(int j=0;j<4;j++)ck(dut.native.system.compute.last_load[j*64+:64]===expected(32'h10000+j*8),"real A cache sees host-written bytes");
        ck(dut.native.system.compute.load_returns==1,"same program loaded once across repeated tasks");
        for(int c=0;c<2;c++)begin
            ck(dut.native.native_memory.read_accepted[c]==dut.native.native_memory.read_retired[c],"all native reads including prefetch retired");
            ck(dut.native.native_memory.write_accepted[c]==dut.native.native_memory.write_retired[c],"native write commands retired");
            ck(dut.native.native_memory.data_accepted[c]==dut.native.native_memory.write_retired[c],"native write data retired");
        end
        ck(native_verified_writes>0 && dut.native.transport_idle && shared_idle,"native verification and shared drain agree");
    endtask
    // 这些轨迹故意在清理开头注入故障；不缩布局，也不声称完成整个对象清理。
    int cpu_reset_events=0,cancel_events=0,clean_starts=0,clean_request_checks=0;
    always @(posedge clk) if(!core_cold_reset)begin
        if(cpu_reset_pulse)cpu_reset_events++;
        if(dut.native.system.cpu.cancel_valid)cancel_events++;
        if(dut.native.system.cpu.service.clean_valid && dut.native.system.cpu.service.clean_ready)begin
            clean_starts++;
            ck(dut.native.system.cpu.service.clean_full,"recovery uses actual full-object mode");
            ck(dut.native.transport_idle && shared_idle && dut.native.npu_reset,"clean starts only after physical retirement");
        end
        if(dut.native.req_valid && dut.native.system.req_ready)begin
            ck(dut.native.npu_reset && !dut.native.host_write_grant && !dut.native.host_read_grant,"cleaning excludes compute/host DDR");
            ck(dut.native.req_write && dut.native.req_mask=={128{1'b1}} && dut.native.req_data==0,"early full-object zero writes use full masks");
            ck(dut.native.req_addr==KV_BASE+32'(dut.native.clear_writes_accepted)*128,"early clean addresses strictly increase");
            clean_request_checks++;
        end
    end
    task automatic boot_service;
        hword(MB_READY_EPOCH,1,0);hword(MB_DOORBELL,1,0);hword(MB_CANCEL_SERIAL,1,0);
        csr_write(32'h80000010,32'h52554e31);ready_epoch(1);
        submit(OP_BOOT);acknowledge(0,0);submit(OP_REGISTER);acknowledge(0,0);
    endtask
    task automatic wait_write_pending;
        for(int t=0;!b_pending;t++)begin tick();if(t>20000)$fatal(1,"expected real UI write");end
    endtask
    task automatic wait_clean_prefix;
        for(int t=0;dut.native.clear_writes_retired<4;t++)begin tick();if(t>30000)$fatal(1,"first four clean blocks not retired");end
        ck(dut.native.clear_cleaned_bytes>=512 && !cq_valid,"partial physical cleaning is not completion");
        for(int i=0;i<64;i++)ck(peek(64'(KV_BASE)+64'(i)*8)==0,"retired clean prefix zero in physical target");
    endtask
    task automatic wait_fault;
        for(int t=0;!platform_error;t++)begin tick();if(t>6000)$fatal(1,"injected error not isolated");end
        tick(20);ck(isolated && dut.native.transport_error && !admission_enable && !cq_valid,"platform error closes all success paths");
    endtask
    initial begin
        logic [63:0] sw_expected;
        int before_resets;
        logic [63:0] accepted_at_fault;
        if(!$value$plusargs("seed=%d",seed))seed=1;random_state=seed;random_state=$urandom(random_state);
        ui_running=1;reset_chain();boot_service();
        stage(1,OP_BUILD);mode=8;ring();wait_write_pending();
        hword(MB_CANCEL_SERIAL,1,1);tick(200);
        ck(cancel_events==1 && built_tokens==0 && committed_tasks==0 && !cq_valid,"cancel accepted but physical B still pending");
        ck(dut.native.clear_writes_accepted==0 && clean_starts==0,"cancel cannot start clearing before task drains");
        @(negedge clk);mode=0;response(1);
        ck(dut.native.transport_idle && shared_idle && native_verified_writes>=2,"cancelled physical SW/B writes really retire");
        sw_expected=initial_word(32'h20000);sw_expected[7:0]=8'h45;sw_expected[15:8]=8'h23;sw_expected[31:24]=8'h7f;
        golden[32'h20000>>3]=sw_expected;golden[RESULT_ADDRESS>>3]=64'h408000003f800000;
        read_tx(32'h20000,1);read_tx(RESULT_ADDRESS,1);
        ck(peek(32'h20000)===sw_expected,"real scalar aggregation preserves unmasked byte and neighbor word");
        acknowledge(0,0);ck(built_tokens==0 && committed_tasks==0 && dut.native.object_state==3,"cancel ACK yields failed object with zero commit");
        stage(1,OP_RECOVER);ring();wait_clean_prefix();
        // readback SLVERR during actual cleaning prevents success and generation change.
        @(negedge clk);mode=2;wait_fault();
        accepted_at_fault=dut.native.clear_writes_accepted;before_resets=cpu_reset_events;
        csr_write(32'h80000018,32'h52535431);tick(100);
        ck(epoch==1 && generation==1 && cpu_reset_events==before_resets,"reset cannot bypass failed cleaning or change epoch");
        ck(dut.native.clear_writes_accepted==accepted_at_fault && !cq_valid,"faulted cleaner stops issuing new work");
        $display("LIFECYCLE_CANCEL_CLEAN_ERROR clean_requests=%0d cleaned_bytes=%0d",clean_request_checks,dut.native.clear_cleaned_bytes);

        // 独立任务错误仍自然停机和排空；正确ACK也不得推进逻辑水位。
        reset_chain();host_session++;boot_service();stage(1,OP_BUILD);ring();
        for(int t=0;dut.native.npu_reset;t++)begin tick();if(t>20000)$fatal(1,"task did not launch");end
        @(negedge clk);inject_task_error=1;tick();@(negedge clk);inject_task_error=0;
        response(2);ck(!platform_error && dut.native.transport_idle,"task error drains without transport quarantine");
        acknowledge(0,0);ck(built_tokens==0 && committed_tasks==0 && dut.native.object_state==3,"failed task no logical increment");

        // 受控reset先等旧计算真实退休；清理期间丢响应，不能用复位清掉责任。
        reset_chain();host_session++;boot_service();stage(1,OP_BUILD);mode=8;ring();wait_write_pending();
        before_resets=cpu_reset_events;csr_write(32'h80000018,32'h52535431);tick(100);
        ck(reset_pending && epoch==1 && cpu_reset_events==before_resets && dut.native.clear_writes_accepted==0,"controlled reset waits old physical write");
        @(negedge clk);mode=0;wait_clean_prefix();
        ck(epoch==1 && reset_pending && cpu_reset_events==before_resets && committed_tasks==0,"partial reset cleaning cannot announce new epoch");
        @(negedge clk);mode=6;wait_fault();
        ck(read_active && !dut.native.transport_idle,"clean readback loss retains real memory responsibility");
        csr_write(32'h80000018,32'h52535431);tick(30);
        ck(read_active && epoch==1 && cpu_reset_events==before_resets,"repeated ordinary reset cannot erase missing read");
        @(negedge clk);mode=0;tick(1000);
        ck(!read_active && isolated && platform_error && epoch==1 && cpu_reset_events==before_resets,"late memory return drains while quarantine persists");
        ck(clean_starts==2 && cancel_events==1 && launches==3,"all independent lifecycle paths really executed");
        $display("M1_PLATFORM_LIFECYCLE_PASS seed=%0d checks=%0d ui_writes=%0d ui_reads=%0d cancel_events=%0d clean_starts=%0d clean_request_checks=%0d launches=%0d full_clean_completions=0",seed,checks,bus_writes,bus_reads,cancel_events,clean_starts,clean_request_checks,launches);$finish;
    end
    initial begin #20000000;$fatal(1,"global watchdog");end
endmodule
