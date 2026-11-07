`timescale 1ns/1ps
module tb_rkv_m1_boot_mux;
    logic  clk = 0;
    logic  release_request = 0;
    logic  qualified = 0;
    logic  qualification_idle = 0;
    logic  health_fault = 0;
    logic  service_mode;
    logic  switch_fault;
    logic [3:0] q_awid = 0;
    logic [32:0] q_awaddr = 0;
    logic [7:0] q_awlen = 0;
    logic [2:0] q_awsize = 0;
    logic [1:0] q_awburst = 0;
    logic  q_awlock = 0;
    logic [3:0] q_awcache = 0;
    logic [2:0] q_awprot = 0;
    logic [3:0] q_awqos = 0;
    logic  q_awvalid = 0;
    logic [511:0] q_wdata = 0;
    logic [63:0] q_wstrb = 0;
    logic  q_wlast = 0;
    logic  q_wvalid = 0;
    logic  q_bready = 0;
    logic [3:0] q_arid = 0;
    logic [32:0] q_araddr = 0;
    logic [7:0] q_arlen = 0;
    logic [2:0] q_arsize = 0;
    logic [1:0] q_arburst = 0;
    logic  q_arlock = 0;
    logic [3:0] q_arcache = 0;
    logic [2:0] q_arprot = 0;
    logic [3:0] q_arqos = 0;
    logic  q_arvalid = 0;
    logic  q_rready = 0;
    logic  q_awready;
    logic  q_wready;
    logic [3:0] q_bid;
    logic [1:0] q_bresp;
    logic  q_bvalid;
    logic  q_arready;
    logic [3:0] q_rid;
    logic [511:0] q_rdata;
    logic [1:0] q_rresp;
    logic  q_rlast;
    logic  q_rvalid;
    logic [3:0] s_awid = 0;
    logic [32:0] s_awaddr = 0;
    logic [7:0] s_awlen = 0;
    logic [2:0] s_awsize = 0;
    logic [1:0] s_awburst = 0;
    logic  s_awlock = 0;
    logic [3:0] s_awcache = 0;
    logic [2:0] s_awprot = 0;
    logic [3:0] s_awqos = 0;
    logic  s_awvalid = 0;
    logic [511:0] s_wdata = 0;
    logic [63:0] s_wstrb = 0;
    logic  s_wlast = 0;
    logic  s_wvalid = 0;
    logic  s_bready = 0;
    logic [3:0] s_arid = 0;
    logic [32:0] s_araddr = 0;
    logic [7:0] s_arlen = 0;
    logic [2:0] s_arsize = 0;
    logic [1:0] s_arburst = 0;
    logic  s_arlock = 0;
    logic [3:0] s_arcache = 0;
    logic [2:0] s_arprot = 0;
    logic [3:0] s_arqos = 0;
    logic  s_arvalid = 0;
    logic  s_rready = 0;
    logic  s_awready;
    logic  s_wready;
    logic [3:0] s_bid;
    logic [1:0] s_bresp;
    logic  s_bvalid;
    logic  s_arready;
    logic [3:0] s_rid;
    logic [511:0] s_rdata;
    logic [1:0] s_rresp;
    logic  s_rlast;
    logic  s_rvalid;
    logic [3:0] m_awid;
    logic [32:0] m_awaddr;
    logic [7:0] m_awlen;
    logic [2:0] m_awsize;
    logic [1:0] m_awburst;
    logic  m_awlock;
    logic [3:0] m_awcache;
    logic [2:0] m_awprot;
    logic [3:0] m_awqos;
    logic  m_awvalid;
    logic [511:0] m_wdata;
    logic [63:0] m_wstrb;
    logic  m_wlast;
    logic  m_wvalid;
    logic  m_bready;
    logic [3:0] m_arid;
    logic [32:0] m_araddr;
    logic [7:0] m_arlen;
    logic [2:0] m_arsize;
    logic [1:0] m_arburst;
    logic  m_arlock;
    logic [3:0] m_arcache;
    logic [2:0] m_arprot;
    logic [3:0] m_arqos;
    logic  m_arvalid;
    logic  m_rready;
    logic  m_awready = 0;
    logic  m_wready = 0;
    logic [3:0] m_bid = 0;
    logic [1:0] m_bresp = 0;
    logic  m_bvalid = 0;
    logic  m_arready = 0;
    logic [3:0] m_rid = 0;
    logic [511:0] m_rdata = 0;
    logic [1:0] m_rresp = 0;
    logic  m_rlast = 0;
    logic  m_rvalid = 0;
    rkv_m1_boot_mux dut (
        .clk(clk),
        .release_request(release_request),
        .qualified(qualified),
        .qualification_idle(qualification_idle),
        .health_fault(health_fault),
        .service_mode(service_mode),
        .switch_fault(switch_fault),
        .q_awid(q_awid),
        .q_awaddr(q_awaddr),
        .q_awlen(q_awlen),
        .q_awsize(q_awsize),
        .q_awburst(q_awburst),
        .q_awlock(q_awlock),
        .q_awcache(q_awcache),
        .q_awprot(q_awprot),
        .q_awqos(q_awqos),
        .q_awvalid(q_awvalid),
        .q_wdata(q_wdata),
        .q_wstrb(q_wstrb),
        .q_wlast(q_wlast),
        .q_wvalid(q_wvalid),
        .q_bready(q_bready),
        .q_arid(q_arid),
        .q_araddr(q_araddr),
        .q_arlen(q_arlen),
        .q_arsize(q_arsize),
        .q_arburst(q_arburst),
        .q_arlock(q_arlock),
        .q_arcache(q_arcache),
        .q_arprot(q_arprot),
        .q_arqos(q_arqos),
        .q_arvalid(q_arvalid),
        .q_rready(q_rready),
        .q_awready(q_awready),
        .q_wready(q_wready),
        .q_bid(q_bid),
        .q_bresp(q_bresp),
        .q_bvalid(q_bvalid),
        .q_arready(q_arready),
        .q_rid(q_rid),
        .q_rdata(q_rdata),
        .q_rresp(q_rresp),
        .q_rlast(q_rlast),
        .q_rvalid(q_rvalid),
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
        .s_wdata(s_wdata),
        .s_wstrb(s_wstrb),
        .s_wlast(s_wlast),
        .s_wvalid(s_wvalid),
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
        .s_rready(s_rready),
        .s_awready(s_awready),
        .s_wready(s_wready),
        .s_bid(s_bid),
        .s_bresp(s_bresp),
        .s_bvalid(s_bvalid),
        .s_arready(s_arready),
        .s_rid(s_rid),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .s_rvalid(s_rvalid),
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
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_wlast(m_wlast),
        .m_wvalid(m_wvalid),
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
        .m_rready(m_rready),
        .m_awready(m_awready),
        .m_wready(m_wready),
        .m_bid(m_bid),
        .m_bresp(m_bresp),
        .m_bvalid(m_bvalid),
        .m_arready(m_arready),
        .m_rid(m_rid),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_rlast(m_rlast),
        .m_rvalid(m_rvalid)
    );
    always #5 clk = !clk;
    task tick; @(posedge clk); #1; endtask
    integer scenario, i;
    initial begin
        if (!$value$plusargs("case=%d", scenario)) $fatal(1,"missing scenario");
        tick();
        if (service_mode || switch_fault) $fatal(1,"configuration init");
        @(negedge clk);
        q_awaddr=33'h100; q_wdata=512'h55; q_wstrb=64'hff;
        s_awaddr=33'h200; s_wdata=512'haa; s_wstrb=64'hf0;
        q_awvalid=1; s_awvalid=1; m_awready=1;
        #1;
        if (m_awaddr!=33'h100 || !q_awready || s_awready) $fatal(1,"boot owner");
        tick(); @(negedge clk); q_awvalid=0;
        qualified=1; qualification_idle=1;
        case(scenario)
            1: qualified=0;
            2: qualification_idle=0;
            3: q_awvalid=1;
            4: q_wvalid=1;
            5: q_arvalid=1;
            6: m_bvalid=1;
            7: m_rvalid=1;
            8: health_fault=1;
            9: begin
                // 一次不合格移交必须永久拒绝，后续资格变好不能清首错。
                qualified=0; release_request=1; tick();
                @(negedge clk); release_request=0; qualified=1;
            end
            default: begin end
        endcase
        release_request=1; tick();
        if (scenario!=0) begin
            if (service_mode || !switch_fault) $fatal(1,"unsafe handover accepted %d",scenario);
            @(negedge clk); qualified=1; qualification_idle=1; health_fault=0;
            q_awvalid=0; q_wvalid=0; q_arvalid=0; m_bvalid=0; m_rvalid=0;
            repeat(3) tick();
            if (service_mode || !switch_fault) $fatal(1,"fault forgotten");
        end else begin
            if (!service_mode || switch_fault) $fatal(1,"safe handover refused");
            // 交接之后迟到资格下降/故障不得切回检查器、丢弃在途服务请求。
            @(negedge clk); release_request=0; qualified=0; health_fault=1;
            s_awvalid=1; s_wvalid=1; s_bready=1; m_bvalid=1;
            q_awvalid=1; q_bready=1;
            repeat(10) begin
                tick();
                if (!service_mode || !switch_fault || m_awaddr!=33'h200 || m_wdata!=512'haa || m_wstrb!=64'hf0)
                    $fatal(1,"service ownership changed after failure");
                if (q_awready || q_bvalid || !s_bvalid || !m_bready) $fatal(1,"response misroute");
            end
        end
        $display("BOOT_MUX_PASS case=%0d",scenario); $finish;
    end
    initial begin #10000; $fatal(1,"timeout"); end
endmodule
