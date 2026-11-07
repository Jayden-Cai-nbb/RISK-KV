`timescale 1ns/1ps
// 实际生成根路由的有限失联观察；目标仅为协议夹具，不是DDR。
module tb_rkv_m1_host_router;
    wire [31:0] CONTROL_araddr;
    wire [1:0] CONTROL_arburst;
    wire [3:0] CONTROL_arcache;
    wire [7:0] CONTROL_arlen;
    wire [0:0] CONTROL_arlock;
    wire [2:0] CONTROL_arprot;
    wire [3:0] CONTROL_arqos;
    wire  CONTROL_arready;
    wire [2:0] CONTROL_arsize;
    wire  CONTROL_arvalid;
    wire [31:0] CONTROL_awaddr;
    wire [1:0] CONTROL_awburst;
    wire [3:0] CONTROL_awcache;
    wire [7:0] CONTROL_awlen;
    wire [0:0] CONTROL_awlock;
    wire [2:0] CONTROL_awprot;
    wire [3:0] CONTROL_awqos;
    wire  CONTROL_awready;
    wire [2:0] CONTROL_awsize;
    wire  CONTROL_awvalid;
    wire  CONTROL_bready;
    wire [1:0] CONTROL_bresp;
    wire  CONTROL_bvalid;
    wire [63:0] CONTROL_rdata;
    wire  CONTROL_rlast;
    wire  CONTROL_rready;
    wire [1:0] CONTROL_rresp;
    wire  CONTROL_rvalid;
    wire [63:0] CONTROL_wdata;
    wire  CONTROL_wlast;
    wire  CONTROL_wready;
    wire [7:0] CONTROL_wstrb;
    wire  CONTROL_wvalid;
    wire [31:0] DDR_araddr;
    wire [1:0] DDR_arburst;
    wire [3:0] DDR_arcache;
    wire [7:0] DDR_arlen;
    wire [0:0] DDR_arlock;
    wire [2:0] DDR_arprot;
    wire [3:0] DDR_arqos;
    wire  DDR_arready;
    wire [2:0] DDR_arsize;
    wire  DDR_arvalid;
    wire [31:0] DDR_awaddr;
    wire [1:0] DDR_awburst;
    wire [3:0] DDR_awcache;
    wire [7:0] DDR_awlen;
    wire [0:0] DDR_awlock;
    wire [2:0] DDR_awprot;
    wire [3:0] DDR_awqos;
    wire  DDR_awready;
    wire [2:0] DDR_awsize;
    wire  DDR_awvalid;
    wire  DDR_bready;
    wire [1:0] DDR_bresp;
    wire  DDR_bvalid;
    wire [63:0] DDR_rdata;
    wire  DDR_rlast;
    wire  DDR_rready;
    wire [1:0] DDR_rresp;
    wire  DDR_rvalid;
    wire [63:0] DDR_wdata;
    wire  DDR_wlast;
    wire  DDR_wready;
    wire [7:0] DDR_wstrb;
    wire  DDR_wvalid;
    reg [31:0] HOST_araddr = 0;
    reg [1:0] HOST_arburst = 0;
    reg [3:0] HOST_arcache = 0;
    reg [3:0] HOST_arid = 0;
    reg [7:0] HOST_arlen = 0;
    reg [0:0] HOST_arlock = 0;
    reg [2:0] HOST_arprot = 0;
    reg [3:0] HOST_arqos = 0;
    wire  HOST_arready;
    reg [2:0] HOST_arsize = 0;
    reg  HOST_arvalid = 0;
    reg [31:0] HOST_awaddr = 0;
    reg [1:0] HOST_awburst = 0;
    reg [3:0] HOST_awcache = 0;
    reg [3:0] HOST_awid = 0;
    reg [7:0] HOST_awlen = 0;
    reg [0:0] HOST_awlock = 0;
    reg [2:0] HOST_awprot = 0;
    reg [3:0] HOST_awqos = 0;
    wire  HOST_awready;
    reg [2:0] HOST_awsize = 0;
    reg  HOST_awvalid = 0;
    wire [3:0] HOST_bid;
    reg  HOST_bready = 0;
    wire [1:0] HOST_bresp;
    wire  HOST_bvalid;
    wire [63:0] HOST_rdata;
    wire [3:0] HOST_rid;
    wire  HOST_rlast;
    reg  HOST_rready = 0;
    wire [1:0] HOST_rresp;
    wire  HOST_rvalid;
    reg [63:0] HOST_wdata = 0;
    reg  HOST_wlast = 0;
    wire  HOST_wready;
    reg [7:0] HOST_wstrb = 0;
    reg  HOST_wvalid = 0;
    reg  core_aresetn = 0;
    reg  core_clk = 0;
    always #10 core_clk = ~core_clk;
    rkv_m1_host_router router (
        .CONTROL_araddr(CONTROL_araddr),
        .CONTROL_arburst(CONTROL_arburst),
        .CONTROL_arcache(CONTROL_arcache),
        .CONTROL_arlen(CONTROL_arlen),
        .CONTROL_arlock(CONTROL_arlock),
        .CONTROL_arprot(CONTROL_arprot),
        .CONTROL_arqos(CONTROL_arqos),
        .CONTROL_arready(CONTROL_arready),
        .CONTROL_arsize(CONTROL_arsize),
        .CONTROL_arvalid(CONTROL_arvalid),
        .CONTROL_awaddr(CONTROL_awaddr),
        .CONTROL_awburst(CONTROL_awburst),
        .CONTROL_awcache(CONTROL_awcache),
        .CONTROL_awlen(CONTROL_awlen),
        .CONTROL_awlock(CONTROL_awlock),
        .CONTROL_awprot(CONTROL_awprot),
        .CONTROL_awqos(CONTROL_awqos),
        .CONTROL_awready(CONTROL_awready),
        .CONTROL_awsize(CONTROL_awsize),
        .CONTROL_awvalid(CONTROL_awvalid),
        .CONTROL_bready(CONTROL_bready),
        .CONTROL_bresp(CONTROL_bresp),
        .CONTROL_bvalid(CONTROL_bvalid),
        .CONTROL_rdata(CONTROL_rdata),
        .CONTROL_rlast(CONTROL_rlast),
        .CONTROL_rready(CONTROL_rready),
        .CONTROL_rresp(CONTROL_rresp),
        .CONTROL_rvalid(CONTROL_rvalid),
        .CONTROL_wdata(CONTROL_wdata),
        .CONTROL_wlast(CONTROL_wlast),
        .CONTROL_wready(CONTROL_wready),
        .CONTROL_wstrb(CONTROL_wstrb),
        .CONTROL_wvalid(CONTROL_wvalid),
        .DDR_araddr(DDR_araddr),
        .DDR_arburst(DDR_arburst),
        .DDR_arcache(DDR_arcache),
        .DDR_arlen(DDR_arlen),
        .DDR_arlock(DDR_arlock),
        .DDR_arprot(DDR_arprot),
        .DDR_arqos(DDR_arqos),
        .DDR_arready(DDR_arready),
        .DDR_arsize(DDR_arsize),
        .DDR_arvalid(DDR_arvalid),
        .DDR_awaddr(DDR_awaddr),
        .DDR_awburst(DDR_awburst),
        .DDR_awcache(DDR_awcache),
        .DDR_awlen(DDR_awlen),
        .DDR_awlock(DDR_awlock),
        .DDR_awprot(DDR_awprot),
        .DDR_awqos(DDR_awqos),
        .DDR_awready(DDR_awready),
        .DDR_awsize(DDR_awsize),
        .DDR_awvalid(DDR_awvalid),
        .DDR_bready(DDR_bready),
        .DDR_bresp(DDR_bresp),
        .DDR_bvalid(DDR_bvalid),
        .DDR_rdata(DDR_rdata),
        .DDR_rlast(DDR_rlast),
        .DDR_rready(DDR_rready),
        .DDR_rresp(DDR_rresp),
        .DDR_rvalid(DDR_rvalid),
        .DDR_wdata(DDR_wdata),
        .DDR_wlast(DDR_wlast),
        .DDR_wready(DDR_wready),
        .DDR_wstrb(DDR_wstrb),
        .DDR_wvalid(DDR_wvalid),
        .HOST_araddr(HOST_araddr),
        .HOST_arburst(HOST_arburst),
        .HOST_arcache(HOST_arcache),
        .HOST_arid(HOST_arid),
        .HOST_arlen(HOST_arlen),
        .HOST_arlock(HOST_arlock),
        .HOST_arprot(HOST_arprot),
        .HOST_arqos(HOST_arqos),
        .HOST_arready(HOST_arready),
        .HOST_arsize(HOST_arsize),
        .HOST_arvalid(HOST_arvalid),
        .HOST_awaddr(HOST_awaddr),
        .HOST_awburst(HOST_awburst),
        .HOST_awcache(HOST_awcache),
        .HOST_awid(HOST_awid),
        .HOST_awlen(HOST_awlen),
        .HOST_awlock(HOST_awlock),
        .HOST_awprot(HOST_awprot),
        .HOST_awqos(HOST_awqos),
        .HOST_awready(HOST_awready),
        .HOST_awsize(HOST_awsize),
        .HOST_awvalid(HOST_awvalid),
        .HOST_bid(HOST_bid),
        .HOST_bready(HOST_bready),
        .HOST_bresp(HOST_bresp),
        .HOST_bvalid(HOST_bvalid),
        .HOST_rdata(HOST_rdata),
        .HOST_rid(HOST_rid),
        .HOST_rlast(HOST_rlast),
        .HOST_rready(HOST_rready),
        .HOST_rresp(HOST_rresp),
        .HOST_rvalid(HOST_rvalid),
        .HOST_wdata(HOST_wdata),
        .HOST_wlast(HOST_wlast),
        .HOST_wready(HOST_wready),
        .HOST_wstrb(HOST_wstrb),
        .HOST_wvalid(HOST_wvalid),
        .core_aresetn(core_aresetn),
        .core_clk(core_clk)
    );
    wire reset_request;
    rkv_m1_host_control control (
        .clk(core_clk),
        .cold_reset(!core_aresetn),
        .platform_ready(1'b1),
        .platform_error(1'b0),
        .ddr_idle(!read_pending && !write_pending),
        .ddr_accept_now(DDR_arvalid || DDR_awvalid),
        .status_flags(32'h12345678),
        .epoch(32'd7),
        .generation(32'd3),
        .error_code(32'd0),
        .host_verified(64'd0),
        .native_verified(64'd0),
        .accepted_reads(64'd0),
        .accepted_writes(64'd0),
        .rejected_requests(64'd0),
        .boot_hold(),
        .reset_request(reset_request),
        .control_idle(),
        .control_requests(),
        .host_valid(),
        .host_addr(),
        .host_wdata(),
        .host_wstrb(),
        .host_ready(1'b0),
        .host_rdata(32'd0),
        .host_error(1'b0),
        .s_awid(4'd0),
        .s_awaddr(CONTROL_awaddr),
        .s_awlen(CONTROL_awlen),
        .s_awsize(CONTROL_awsize),
        .s_awburst(CONTROL_awburst),
        .s_awlock(CONTROL_awlock),
        .s_awvalid(CONTROL_awvalid),
        .s_awready(CONTROL_awready),
        .s_wdata(CONTROL_wdata),
        .s_wstrb(CONTROL_wstrb),
        .s_wlast(CONTROL_wlast),
        .s_wvalid(CONTROL_wvalid),
        .s_wready(CONTROL_wready),
        .s_bid(),
        .s_bresp(CONTROL_bresp),
        .s_bvalid(CONTROL_bvalid),
        .s_bready(CONTROL_bready),
        .s_arid(4'd0),
        .s_araddr(CONTROL_araddr),
        .s_arlen(CONTROL_arlen),
        .s_arsize(CONTROL_arsize),
        .s_arburst(CONTROL_arburst),
        .s_arlock(CONTROL_arlock),
        .s_arvalid(CONTROL_arvalid),
        .s_arready(CONTROL_arready),
        .s_rid(),
        .s_rdata(CONTROL_rdata),
        .s_rresp(CONTROL_rresp),
        .s_rlast(CONTROL_rlast),
        .s_rvalid(CONTROL_rvalid),
        .s_rready(CONTROL_rready)
    );

    reg read_pending = 0;
    reg write_pending = 0;
    reg write_data_pending = 0;
    reg release_read = 1;
    reg release_write = 1;
    integer cycle = 0;
    integer reset_pulses = 0;
    integer control_reads = 0;
    integer control_writes = 0;
    integer ddr_reads = 0;
    integer ddr_writes = 0;
    integer host_responses = 0;
    integer before_reads;
    integer before_writes;
    integer before_responses;
    integer checks = 0;
    reg [63:0] result;
    assign DDR_arready = !read_pending;
    assign DDR_awready = !write_pending;
    assign DDR_wready = !write_data_pending;
    assign DDR_rvalid = read_pending && release_read;
    assign DDR_rdata = 64'h123456789abcdef0;
    assign DDR_rresp = 2'd0;
    assign DDR_rlast = 1'b1;
    assign DDR_bvalid = write_pending && write_data_pending && release_write;
    assign DDR_bresp = 2'd0;
    // 仅真实返回握手或整链cold清目标责任，故障观察期间不发假响应。
    always @(posedge core_clk) begin
        cycle <= cycle + 1;
        if (!core_aresetn) begin
            read_pending <= 0;
            write_pending <= 0;
            write_data_pending <= 0;
        end else begin
            if (DDR_arvalid && DDR_arready) begin read_pending <= 1; ddr_reads <= ddr_reads+1; end
            if (DDR_rvalid && DDR_rready) read_pending <= 0;
            if (DDR_awvalid && DDR_awready) begin write_pending <= 1; ddr_writes <= ddr_writes+1; end
            if (DDR_wvalid && DDR_wready) write_data_pending <= 1;
            if (DDR_bvalid && DDR_bready) begin write_pending <= 0; write_data_pending <= 0; end
            if (CONTROL_arvalid && CONTROL_arready) control_reads <= control_reads+1;
            if (CONTROL_awvalid && CONTROL_awready) control_writes <= control_writes+1;
            if (HOST_rvalid && HOST_rready) host_responses <= host_responses+1;
            if (reset_request) reset_pulses <= reset_pulses+1;
        end
    end
    task check(input bit condition, input string message);
        begin
            checks=checks+1;
            if (!condition) $fatal(1,"cycle=%0d %s",cycle,message);
        end
    endtask
    task send_read(input [31:0] address, input [3:0] identity);
        integer count;
        begin
            @(negedge core_clk); HOST_araddr=address; HOST_arid=identity; HOST_arvalid=1;
            count=0;
            do begin @(posedge core_clk); count=count+1; if(count>1000) $fatal(1,"AR timeout"); end while(!HOST_arready);
            @(negedge core_clk); HOST_arvalid=0;
        end
    endtask
    task receive_read(input [3:0] identity, output [63:0] data);
        integer count;
        begin
            @(negedge core_clk); HOST_rready=1; count=0;
            do begin @(posedge core_clk); count=count+1; if(count>1000) $fatal(1,"R timeout"); end while(!HOST_rvalid);
            check(HOST_rid==identity && HOST_rresp==0 && HOST_rlast,"read identity/status"); data=HOST_rdata;
            @(negedge core_clk); HOST_rready=0;
        end
    endtask
    task send_write(input [31:0] address, input [63:0] data);
        integer count;
        begin
            @(negedge core_clk); HOST_awaddr=address; HOST_awid=4'hb; HOST_awvalid=1; count=0;
            do begin @(posedge core_clk); count=count+1; if(count>1000) $fatal(1,"AW timeout"); end while(!HOST_awready);
            @(negedge core_clk); HOST_awvalid=0; HOST_wdata=data; HOST_wvalid=1; count=0;
            do begin @(posedge core_clk); count=count+1; if(count>1000) $fatal(1,"W timeout"); end while(!HOST_wready);
            @(negedge core_clk); HOST_wvalid=0;
        end
    endtask
    task receive_write;
        integer count;
        begin
            @(negedge core_clk); HOST_bready=1; count=0;
            do begin @(posedge core_clk); count=count+1; if(count>1000) $fatal(1,"B timeout"); end while(!HOST_bvalid);
            check(HOST_bid==4'hb && HOST_bresp==0,"write identity/status");
            @(negedge core_clk); HOST_bready=0;
        end
    endtask
    // 同向第二请求保持VALID；只观察有限256拍，恢复真实旧返回后才等待其接收。
    // 这超过当前JTAG队列1的并发能力，是对根互连的额外测试，不冒充JTAG发起轨迹。
    initial begin
        HOST_arsize=3; HOST_arburst=1; HOST_awsize=3; HOST_awburst=1; HOST_wstrb=8'h0f; HOST_wlast=1;
        repeat(32) @(negedge core_clk); core_aresetn=1;
        repeat(64) @(negedge core_clk);
        send_read(32'h80000000,4'h3); receive_read(4'h3,result);
        check(result==64'h0000000152564b50,"CSR identity baseline");
        send_read(32'h100,4'h5); receive_read(4'h5,result);
        check(result==64'h123456789abcdef0,"DDR baseline");
        release_read=0; send_read(32'h100,4'h5);
        wait(read_pending); @(negedge core_clk);
        before_reads=control_reads; before_responses=host_responses;
        fork
            send_read(32'h80000000,4'h6);
            begin
                repeat(256) @(negedge core_clk);
                $display("ROUTER_LOST_R cycles=256 csr_delta=%0d response_delta=%0d second_arvalid=%0d second_arready=%0d",control_reads-before_reads,host_responses-before_responses,HOST_arvalid,HOST_arready);
                check(control_reads==before_reads && host_responses==before_responses,"lost R did not block later CSR as expected");
                send_write(32'h80000018,64'h0000000052535431); receive_write();
                check(reset_pulses==1 && read_pending,"independent reset write must not clear pending read");
                $display("ROUTER_RESET_WRITE_DURING_LOST_R pulses=%0d read_pending=%0d",reset_pulses,read_pending);
                release_read=1;
                receive_read(4'h5,result); check(result==64'h123456789abcdef0,"late original R");
            end
        join
        receive_read(4'h6,result); check(result==64'h0000000152564b50,"CSR after late R");
        release_write=0; send_write(32'h108,64'h00000000abcdef01);
        wait(write_pending && write_data_pending); @(negedge core_clk);
        before_writes=control_writes;
        fork
            send_write(32'h80000018,64'h0000000052535431);
            begin
                repeat(256) @(negedge core_clk);
                $display("ROUTER_LOST_B cycles=256 csr_write_delta=%0d bvalid=%0d",control_writes-before_writes,HOST_bvalid);
                check(control_writes==before_writes && !HOST_bvalid,"lost B must retain old write responsibility");
                send_read(32'h80000000,4'h9); receive_read(4'h9,result);
                check(result==64'h0000000152564b50 && write_pending,"CSR read must not clear pending write");
                $display("ROUTER_CSR_READ_DURING_LOST_B write_pending=%0d",write_pending);
                release_write=1; receive_write();
            end
        join
        receive_write(); check(reset_pulses==2,"late write and second reset");
        check(ddr_reads==2 && ddr_writes==1,"target transaction conservation");
        $display("M1_HOST_ROUTER_PASS checks=%0d ddr_reads=%0d ddr_writes=%0d csr_reads=%0d csr_writes=%0d reset_pulses=%0d",checks,ddr_reads,ddr_writes,control_reads,control_writes,reset_pulses);
        $finish;
    end
    initial begin #1000000; $fatal(1,"global observation timeout"); end
endmodule
