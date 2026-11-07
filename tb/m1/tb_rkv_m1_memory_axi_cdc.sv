`timescale 1ns/1ps
module tb_rkv_m1_memory_axi_cdc;
    logic clk = '0;
    wire cold_reset;
    logic npu_reset = '0;
    logic loader_busy = '0;
    logic a_req = '0;
    logic a_we = '0;
    logic [31:0] a_addr = '0;
    logic [31:0] a_wdata = '0;
    logic [3:0] a_be = '0;
    logic a_rdy;
    logic a_rvalid;
    logic [255:0] a_rdata;
    logic sw_req = '0;
    logic [31:0] sw_addr = '0;
    logic [31:0] sw_wdata = '0;
    logic [3:0] sw_be = '0;
    logic sw_rdy;
    logic b_req = '0;
    logic b_we = '0;
    logic b_tag = '0;
    logic b_par = '0;
    logic [31:0] b_addr = '0;
    logic [1023:0] b_wdata = '0;
    logic [31:0] b_wmask = '0;
    logic b_rdy;
    logic b_rvalid;
    logic b_rtag;
    logic [1023:0] b_rdata;
    logic clean_req_valid = '0;
    logic clean_req_ready;
    logic clean_req_write = '0;
    logic [31:0] clean_req_addr = '0;
    logic [1023:0] clean_req_data = '0;
    logic [127:0] clean_req_mask = '0;
    logic clean_rsp_valid;
    logic clean_rsp_ready = '0;
    logic clean_rsp_error;
    logic [1023:0] clean_rsp_data;
    logic flush_req = '0;
    logic flush_ack;
    logic cache_flush;
    logic cache_flush_ack;
    logic transport_idle;
    logic transport_error;
    logic mem_wr_idle;
    logic mem_rd_idle;
    logic fabric_idle;
    logic fabric_error;
    logic mem_a_req;
    logic mem_a_we;
    logic [31:0] mem_a_addr;
    logic [31:0] mem_a_wdata;
    logic [3:0] mem_a_be;
    logic mem_a_rdy;
    logic mem_a_rvalid;
    logic [255:0] mem_a_rdata;
    logic mem_sw_req;
    logic [31:0] mem_sw_addr;
    logic [31:0] mem_sw_wdata;
    logic [3:0] mem_sw_be;
    logic mem_sw_rdy;
    logic mem_b_req;
    logic mem_b_we;
    logic mem_b_tag;
    logic mem_b_par;
    logic [31:0] mem_b_addr;
    logic [1023:0] mem_b_wdata;
    logic [31:0] mem_b_wmask;
    logic mem_b_rdy;
    logic mem_b_rvalid;
    logic mem_b_rtag;
    logic [1023:0] mem_b_rdata;

    rkv_m1_memory_arbiter dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .npu_reset(npu_reset),
        .loader_busy(loader_busy),
        .a_req(a_req),
        .a_we(a_we),
        .a_addr(a_addr),
        .a_wdata(a_wdata),
        .a_be(a_be),
        .a_rdy(a_rdy),
        .a_rvalid(a_rvalid),
        .a_rdata(a_rdata),
        .sw_req(sw_req),
        .sw_addr(sw_addr),
        .sw_wdata(sw_wdata),
        .sw_be(sw_be),
        .sw_rdy(sw_rdy),
        .b_req(b_req),
        .b_we(b_we),
        .b_tag(b_tag),
        .b_par(b_par),
        .b_addr(b_addr),
        .b_wdata(b_wdata),
        .b_wmask(b_wmask),
        .b_rdy(b_rdy),
        .b_rvalid(b_rvalid),
        .b_rtag(b_rtag),
        .b_rdata(b_rdata),
        .clean_req_valid(clean_req_valid),
        .clean_req_ready(clean_req_ready),
        .clean_req_write(clean_req_write),
        .clean_req_addr(clean_req_addr),
        .clean_req_data(clean_req_data),
        .clean_req_mask(clean_req_mask),
        .clean_rsp_valid(clean_rsp_valid),
        .clean_rsp_ready(clean_rsp_ready),
        .clean_rsp_error(clean_rsp_error),
        .clean_rsp_data(clean_rsp_data),
        .flush_req(flush_req),
        .flush_ack(flush_ack),
        .cache_flush(cache_flush),
        .cache_flush_ack(cache_flush_ack),
        .transport_idle(transport_idle),
        .transport_error(transport_error),
        .mem_wr_idle(mem_wr_idle),
        .mem_rd_idle(mem_rd_idle),
        .fabric_idle(fabric_idle),
        .fabric_error(fabric_error),
        .mem_a_req(mem_a_req),
        .mem_a_we(mem_a_we),
        .mem_a_addr(mem_a_addr),
        .mem_a_wdata(mem_a_wdata),
        .mem_a_be(mem_a_be),
        .mem_a_rdy(mem_a_rdy),
        .mem_a_rvalid(mem_a_rvalid),
        .mem_a_rdata(mem_a_rdata),
        .mem_sw_req(mem_sw_req),
        .mem_sw_addr(mem_sw_addr),
        .mem_sw_wdata(mem_sw_wdata),
        .mem_sw_be(mem_sw_be),
        .mem_sw_rdy(mem_sw_rdy),
        .mem_b_req(mem_b_req),
        .mem_b_we(mem_b_we),
        .mem_b_tag(mem_b_tag),
        .mem_b_par(mem_b_par),
        .mem_b_addr(mem_b_addr),
        .mem_b_wdata(mem_b_wdata),
        .mem_b_wmask(mem_b_wmask),
        .mem_b_rdy(mem_b_rdy),
        .mem_b_rvalid(mem_b_rvalid),
        .mem_b_rtag(mem_b_rtag),
        .mem_b_rdata(mem_b_rdata)
    );
    logic core_running = 1;
    logic ui_running = 1;
    logic ui_clk = 0;
    integer ui_half_ps = 2604;
    integer ui_phase_ps = 3333;
    realtime ui_half_ns;
    always #10 clk = core_running ? !clk : 1'b0;
    initial begin
        if (!$value$plusargs("ui_half_ps=%d",ui_half_ps)) ui_half_ps=2604;
        if (!$value$plusargs("ui_phase_ps=%d",ui_phase_ps)) ui_phase_ps=3333;
        ui_half_ns=real'(ui_half_ps)/1000.0;
        #(real'(ui_phase_ps)/1000.0);
        forever begin
            #(ui_half_ns); ui_clk = ui_running ? !ui_clk : 1'b0;
        end
    end
    logic chain_cold_reset = 1;
    logic core_locked = 1;
    logic ddr_locked = 1;
    logic ddr_calibrated = 1;
    wire ddr_axi_aresetn;
    wire transport_ready;
    wire admission_enable;
    wire guard_armed;
    wire [3:0] fault_causes;
    wire platform_error;
    logic hold_r_response = 0;
    wire bridge_idle;
    wire fault;
    wire [31:0] fault_code;
    wire [63:0] verified_writes;
    wire run_flush = npu_reset;
    logic [3:0] m_awid;
    logic [3:0] m_arid;
    logic [3:0] m_bid;
    logic [3:0] m_rid;
    logic [32:0] m_awaddr;
    logic [32:0] m_araddr;
    logic [7:0] m_awlen;
    logic [7:0] m_arlen;
    logic [2:0] m_awsize;
    logic [2:0] m_arsize;
    logic [2:0] m_awprot;
    logic [2:0] m_arprot;
    logic [1:0] m_awburst;
    logic [1:0] m_arburst;
    logic [1:0] m_bresp;
    logic [1:0] m_rresp;
    logic m_awlock;
    logic m_arlock;
    logic [3:0] m_awcache;
    logic [3:0] m_arcache;
    logic [3:0] m_awqos;
    logic [3:0] m_arqos;
    logic m_awvalid;
    logic m_awready;
    logic m_wvalid;
    logic m_wready;
    logic m_wlast;
    logic m_bvalid;
    logic m_bready;
    logic m_arvalid;
    logic m_arready;
    logic m_rvalid;
    logic m_rready;
    logic m_rlast;
    logic [511:0] m_wdata;
    logic [511:0] m_rdata;
    logic [63:0] m_wstrb;
    // 生产包装包含未修改native适配器；独立DDR模型仅从线性字节地址生成参考。
    rkv_m1_memory_axi_cdc #(.TIMEOUT_CYCLES(512)) backend (
        .core_clk(clk),
        .ddr_clk(ui_clk),
        .chain_cold_reset(chain_cold_reset),
        .core_locked(core_locked),
        .ddr_locked(ddr_locked),
        .ddr_calibrated(ddr_calibrated),
        .core_cold_reset(cold_reset),
        .ddr_axi_aresetn(ddr_axi_aresetn),
        .transport_ready(transport_ready),
        .admission_enable(admission_enable),
        .guard_armed(guard_armed),
        .fault_causes(fault_causes),
        .platform_error(platform_error),
        .bridge_idle(bridge_idle),
        .bridge_fault(fault),
        .bridge_fault_code(fault_code),
        .verified_writes(verified_writes),
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
        .run_flush(run_flush),
        .cache_flush(cache_flush),
        .cache_flush_ack(cache_flush_ack),
        .transport_idle(transport_idle),
        .transport_error(transport_error),
        .mem_wr_idle(mem_wr_idle),
        .mem_rd_idle(mem_rd_idle),
        .mem_a_req(mem_a_req),
        .mem_a_we(mem_a_we),
        .mem_a_addr(mem_a_addr),
        .mem_a_wdata(mem_a_wdata),
        .mem_a_be(mem_a_be),
        .mem_a_rdy(mem_a_rdy),
        .mem_a_rvalid(mem_a_rvalid),
        .mem_a_rdata(mem_a_rdata),
        .mem_sw_req(mem_sw_req),
        .mem_sw_addr(mem_sw_addr),
        .mem_sw_wdata(mem_sw_wdata),
        .mem_sw_be(mem_sw_be),
        .mem_sw_rdy(mem_sw_rdy),
        .mem_b_req(mem_b_req),
        .mem_b_we(mem_b_we),
        .mem_b_tag(mem_b_tag),
        .mem_b_par(mem_b_par),
        .mem_b_addr(mem_b_addr),
        .mem_b_wdata(mem_b_wdata),
        .mem_b_wmask(mem_b_wmask),
        .mem_b_rdy(mem_b_rdy),
        .mem_b_rvalid(mem_b_rvalid),
        .mem_b_rtag(mem_b_rtag),
        .mem_b_rdata(mem_b_rdata)
    );
    // 独立线性 byte-memory 模型：AXI 地址直接索引；Golden 不读取 DUT 内部状态。
    logic [511:0] memory [int unsigned];
    logic aw_seen;
    logic w_seen;
    logic [32:0] aw_saved;
    logic [32:0] ar_saved;
    logic [511:0] w_saved;
    logic [63:0] mask_saved;
    integer b_delay;
    integer r_delay;
    integer mode;
    integer checks = 0;
    integer reads_seen = 0;
    integer axi_writes = 0;
    logic block_aw;
    logic block_ar;
    logic orphan_b;
    logic [31:0] random_state;
    integer initial_seed;
    logic hold_aw;
    logic hold_w;
    logic hold_ar;
    logic [32:0] stalled_aw;
    logic [32:0] stalled_ar;
    logic [511:0] stalled_w;
    logic [63:0] stalled_mask;
    function automatic logic [511:0] load_memory(input logic [32:0] addr);
        if (memory.exists(int'(addr >> 6)) != 0) return memory[int'(addr >> 6)];
        begin
            logic [511:0] value;
            for (int w=0;w<16;w++) value[w*32+:32] = 32'hf00d0000 ^ (32'(addr>>2)+32'(w));
            return value;
        end
    endfunction
    task automatic check(input bit ok, input string message);
        checks++;
        if (!ok) $fatal(1, "%s time=%0t fault=%0d/%0d", message, $time, fault, fault_code);
    endtask
    always @(negedge ui_clk) begin
        random_state = (random_state >> 1) ^ (random_state[0] ? 32'h80200003 : 32'd0);
        m_awready = ddr_axi_aresetn && !block_aw && !aw_seen && random_state[0];
        m_wready = ddr_axi_aresetn && !w_seen && random_state[3];
        m_arready = ddr_axi_aresetn && !block_ar && r_delay < 0 && !m_rvalid && random_state[7];
    end
    always @(posedge ui_clk) begin
        if (!ddr_axi_aresetn) begin
            aw_seen <= 0; w_seen <= 0; b_delay <= -1; r_delay <= -1;
            m_bvalid <= 0; m_rvalid <= 0; m_bresp <= 0; m_rresp <= 0;
            m_bid <= 0; m_rid <= 0; m_rlast <= 1; m_rdata <= 0;
            hold_aw <= 0; hold_w <= 0; hold_ar <= 0;
        end else begin
            // AXI VALID 在隔离/超时后也须保持，直到真实握手。
            if (hold_aw) check(m_awvalid && m_awaddr == stalled_aw, "AW changed while stalled");
            if (hold_ar) check(m_arvalid && m_araddr == stalled_ar, "AR changed while stalled");
            if (hold_w) check(m_wvalid && m_wdata == stalled_w && m_wstrb == stalled_mask, "W changed while stalled");
            hold_aw <= m_awvalid && !m_awready; stalled_aw <= m_awaddr;
            hold_ar <= m_arvalid && !m_arready; stalled_ar <= m_araddr;
            hold_w <= m_wvalid && !m_wready; stalled_w <= m_wdata; stalled_mask <= m_wstrb;
            if (m_awvalid && m_awready) begin
                check(m_awaddr < 33'h080000000 && m_awaddr[5:0] == 0, "AW range/alignment");
                check(m_awid == 0 && m_awlen == 0 && m_awsize == 6 && m_awburst == 1, "AW geometry");
                aw_seen <= 1; aw_saved <= m_awaddr;
            end
            if (m_wvalid && m_wready) begin
                check(m_wlast, "single-beat WLAST");
                w_seen <= 1; w_saved <= m_wdata; mask_saved <= m_wstrb;
            end
            if (aw_seen && w_seen && b_delay < 0 && !m_bvalid) begin
                logic [511:0] updated;
                updated = load_memory(aw_saved);
                for (int b=0;b<64;b++) if (mask_saved[b]) updated[b*8+:8] = w_saved[b*8+:8];
                memory[int'(aw_saved >> 6)] = updated;
                aw_seen <= 0; w_seen <= 0; b_delay <= int'(random_state[6:4]); axi_writes++;
            end
            if (b_delay > 0) b_delay <= b_delay-1;
            if (b_delay == 0) begin
                m_bvalid <= 1; m_bresp <= mode == 1 ? 2'b10 : 2'b00;
                m_bid <= mode == 7 ? 4'd1 : 4'd0; b_delay <= -1;
            end
            if (orphan_b) begin m_bvalid <= 1; m_bresp <= 0; m_bid <= 0; end
            if (m_bvalid && m_bready) m_bvalid <= 0;
            if (m_arvalid && m_arready) begin
                check(m_araddr < 33'h080000000 && m_araddr[5:0] == 0, "AR range/alignment");
                check(m_arid == 0 && m_arlen == 0 && m_arsize == 6 && m_arburst == 1, "AR geometry");
                ar_saved <= m_araddr; r_delay <= mode == 6 ? -1 : int'(random_state[11:8]); reads_seen++;
            end
            if (r_delay > 0 && !hold_r_response) r_delay <= r_delay-1;
            if (r_delay == 0 && !hold_r_response) begin
                m_rvalid <= 1; m_rdata <= load_memory(ar_saved) ^ (mode == 5 ? 512'd1 : 512'd0);
                m_rresp <= mode == 2 ? 2'b10 : 2'b00;
                m_rid <= mode == 3 ? 4'd1 : 4'd0; m_rlast <= mode != 4; r_delay <= -1;
            end
            if (m_rvalid && m_rready) m_rvalid <= 0;
        end
    end
    logic [1023:0] pattern;
    logic [1023:0] actual;
    integer a_returns = 0;
    integer b_returns = 0;
    always @(posedge clk) begin
        if (cold_reset) begin a_returns <= 0; b_returns <= 0; end
        else begin
            if (a_rvalid) a_returns <= a_returns+1;
            if (b_rvalid) b_returns <= b_returns+1;
        end
    end
    task automatic tick(input integer n);
        repeat (n) begin @(posedge clk); #1; end
    endtask
    task automatic drain;
        integer waited;
        waited=0;
        do begin
            tick(1); waited++;
            if (fabric_error || waited>10000) $fatal(1,"fabric drain timeout/fault code=%0d",fault_code);
        end while (!fabric_idle);
        tick(3);
    endtask
    task automatic clear_access(input logic write_op, input logic [31:0] address,
                                input logic [127:0] mask, input logic expect_error);
        drain();
        @(negedge clk);
        clean_req_valid = 1; clean_req_write = write_op; clean_req_addr = address;
        clean_req_data = pattern; clean_req_mask = mask;
        do begin @(posedge clk); end while (!clean_req_ready);
        @(negedge clk); clean_req_valid = 0;
        while (!clean_rsp_valid) tick(1);
        if (clean_rsp_error !== expect_error) $fatal(1, "clean response before retirement / wrong status");
        actual = clean_rsp_data;
        tick(5);
        if (!clean_rsp_valid || clean_req_ready || clean_rsp_data !== actual) $fatal(1, "response under backpressure");
        @(negedge clk); clean_rsp_ready = 1;
        tick(1);
        @(negedge clk); clean_rsp_ready = 0;
        tick(3);
        checks += 2;
    endtask
    task automatic wait_admission;
        integer waited;
        waited=0;
        while (!admission_enable) begin
            tick(1); waited++;
            if (waited>300) $fatal(1,"admission timeout");
        end
        tick(3);
        check(!transport_error && !cold_reset && transport_ready,"healthy admission");
    endtask
    task automatic reset_chain;
        @(negedge clk);
        chain_cold_reset=1; a_req=0; sw_req=0; b_req=0;
        clean_req_valid=0; clean_rsp_ready=0; flush_req=0;
        npu_reset=1; mode=0; block_aw=0; block_ar=0; orphan_b=0; hold_r_response=0;
        core_locked=1; ddr_locked=1; ddr_calibrated=1;
        tick(4);
        @(negedge clk);chain_cold_reset=0;
        wait_admission();drain();
    endtask
    task automatic a_read_word(input logic [31:0] address,input logic [31:0] expected);
        @(negedge clk);a_req=1;a_we=0;a_addr=address;
        do begin @(posedge clk);end while(!a_rdy);
        @(negedge clk);a_req=0;
        while(!a_rvalid) tick(1);
        check(a_rdata[32*address[2:0]+:32]===expected,"A data after write/flush");
    endtask
    task automatic launch_clean_read;
        @(negedge clk);clean_req_valid=1;clean_req_write=0;clean_req_addr=32'h00400100;clean_req_mask=0;
        do begin @(posedge clk);end while(!clean_req_ready);
        @(negedge clk);clean_req_valid=0;
    endtask
    task automatic wait_fault(input logic [31:0] expected);
        integer waited;
        waited=0;
        while(!fault) begin tick(1);waited++;if(waited>1000)$fatal(1,"missing bridge fault");end
        check(fault_code===expected && transport_error && fabric_error && !fabric_idle,"error propagation");
        check(!a_rdy && !b_rdy && !sw_rdy,"new upstream requests blocked after fault");
    endtask
    initial begin
        if (!$value$plusargs("seed=%d",initial_seed)) initial_seed=1;
        random_state=32'(initial_seed);mode=0;block_aw=0;block_ar=0;orphan_b=0;
        chain_cold_reset=1;npu_reset=1;
        tick(4);
        check(!a_rdy && !b_rdy && !sw_rdy && !transport_idle,"startup cannot claim admission or retirement");
        @(negedge clk);chain_cold_reset=0;
        wait_admission();
        @(negedge clk);npu_reset=0;
        @(negedge clk); sw_req = 1; sw_addr = 32'h1233; sw_wdata = 32'h12345678; sw_be = 4'b0101;
        do begin @(posedge clk); end while (!sw_rdy);
        @(negedge clk); sw_req = 0;
        drain();
        @(negedge clk); a_req = 1; a_we = 0; a_addr = 32'h1233;
        do begin @(posedge clk); end while (!a_rdy);
        @(negedge clk); a_req = 0;
        while (!a_rvalid) tick(1);
        if (a_rdata[3*32 +: 32] !== 32'hf0341278) $fatal(1,"native SW RMW / A mapping");
        tick(1);
        if (transport_idle) $fatal(1,"unconsumed native prefetch incorrectly idle");
        drain();
        if (fabric_error) $fatal(1,"native initial retirement error");
        checks += 2;
        @(negedge clk); npu_reset = 1;
        for (int w = 0; w < 32; w++) pattern[w*32 +: 32] = 32'hcafe0000 + 32'(w);
        clear_access(1,32'h7fffff80,{128{1'b1}},0);
        clear_access(0,32'h7fffff80,128'd0,0);
        if (actual !== pattern) $fatal(1,"native last 2 GiB chunk");
        clear_access(1,32'h00004000,{128{1'b1}},0);
        pattern = ~pattern;
        clear_access(1,32'h00004000,{16{8'h0f}},0);
        clear_access(0,32'h00004000,128'd0,0);
        for (int w = 0; w < 32; w++)
            if (actual[w*32 +: 32] !== (w[0] ? ~pattern[w*32 +: 32] : pattern[w*32 +: 32])) $fatal(1,"native masked write");
        checks += 2;
        @(negedge clk); flush_req = 1;
        while (!flush_ack) tick(1);
        if (fabric_error || !transport_idle) $fatal(1,"native flush/retirement fence");
        @(negedge clk); flush_req = 0; npu_reset = 0;
        // NPU B 返回的 tag 和两通道重组保持原合同。
        @(negedge clk); b_req = 1; b_we = 0; b_addr = 32'h1000; b_tag = 1; b_par = ^b_addr[31:5];
        do begin @(posedge clk); end while (!b_rdy);
        @(negedge clk); b_req = 0;
        while (!b_rvalid) tick(1);
        if (!b_rtag || b_rdata !== actual) $fatal(1,"native B response tag/order");
        drain();
        if (fabric_error) $fatal(1,"native integrated fabric fault");
        checks += 2;
        @(negedge clk); npu_reset = 1;
        for (int block_index=0;block_index<64;block_index++) begin
            for (int w=0;w<32;w++) pattern[w*32 +: 32] = 32'h7fc01234 ^ 32'(block_index*32+w);
            clear_access(1,32'h00400000+32'(block_index)*128,{128{1'b1}},0);
            clear_access(0,32'h00400000+32'(block_index)*128,128'd0,0);
            if (actual!==pattern) $fatal(1,"native randomized stream data mismatch");
        end
        // 同一A缓存行先被读取，再通过真实清理写覆盖；重新使用不得返回旧值。
        drain();
        for(int w=0;w<32;w++)pattern[w*32+:32]=32'h98760000+32'(w);
        clear_access(1,32'h00004880,'1,0);
        @(negedge clk);flush_req=1;
        while(!flush_ack)tick(1);
        @(negedge clk);flush_req=0;npu_reset=0;
        a_read_word(32'h1233,32'h98760013);drain();
        // A口部分字节写，随后读全字；SW读改写在前一阶段已检查。
        @(negedge clk);a_req=1;a_we=1;a_addr=32'h1233;a_wdata=32'h11223344;a_be=4'b1010;
        do begin @(posedge clk);end while(!a_rdy);
        @(negedge clk);a_req=0;drain();
        a_read_word(32'h1233,32'h11763313);drain();
        // 普通NPU复位只失效缓存，不能丢弃已接受的B读；恢复响应前禁止清理资格。
        @(negedge clk);hold_r_response=1;b_req=1;b_we=0;b_addr=32'h00100040;b_par=^b_addr[31:5];b_tag=1;
        do begin @(posedge clk);end while(!b_rdy);
        @(negedge clk);b_req=0;npu_reset=1;
        tick(100);
        check(!b_rvalid && !transport_idle && !fabric_idle,"run reset preserves pending read");
        @(negedge clk);flush_req=1;
        tick(20);check(!flush_ack,"lost return blocks cache fence");
        @(negedge clk);hold_r_response=0;
        while(!b_rvalid)tick(1);
        check(b_rtag && b_rdata==={load_memory(33'h00400140),load_memory(33'h00400100)},"pending B read survives run reset");
        while(!flush_ack)tick(1);
        check(!fabric_error && transport_idle,"late return retires and permits fence");
        @(negedge clk);flush_req=0;
        // RRESP错误不得生成清理成功，恢复正确响应也不能自行解除隔离。
        reset_chain();mode=2;launch_clean_read();wait_fault(2);
        @(negedge clk);mode=0;flush_req=1;
        tick(50);check(!clean_rsp_valid && !flush_ack && !fabric_idle,"read error has no success or reuse");
        reset_chain();
        // B错误允许已经物理写入，但写核验退休和清理资格均不推进。
        @(negedge clk);mode=1;clean_req_valid=1;clean_req_write=1;clean_req_addr=32'h00400100;clean_req_data='1;clean_req_mask='1;
        do begin @(posedge clk);end while(!clean_req_ready);
        @(negedge clk);clean_req_valid=0;
        wait_fault(1);
        check(verified_writes==0 && !clean_rsp_valid,"failed physical write does not retire");
        @(negedge clk);mode=0;flush_req=1;
        tick(40);check(!flush_ack && fabric_error,"write error cannot recover by flush");
        reset_chain();
        for(int w=0;w<32;w++)pattern[w*32+:32]=32'hbaad0000+32'(w);
        clear_access(1,32'h00400100,'1,0);clear_access(0,32'h00400100,0,0);
        check(actual===pattern,"cold recovery rewrites failed region correctly");
        // 响应保持超过桥接超时，随后放回：禁止迟到清理成功和提前flush。
        @(negedge clk);hold_r_response=1;
        launch_clean_read();wait_fault(5);
        @(negedge clk);hold_r_response=0;flush_req=1;
        tick(100);check(!clean_rsp_valid && !flush_ack && fabric_error,"timeout late R cannot create reuse");
        reset_chain();clear_access(0,32'h00400100,0,0);
        check(actual===pattern,"cold reset preserves physical memory but clears protocol state");
        // UI停钟时只隔离，普通run复位不得清除CDC/适配器在途责任。
        @(negedge clk);hold_r_response=1;launch_clean_read();
        while(r_delay<0)tick(1);
        @(negedge ui_clk);ui_running=0;ddr_locked=0;
        tick(8);wait_fault(7);
        check(!cold_reset && ddr_axi_aresetn,"health loss does not reset queues");
        @(negedge clk);npu_reset=0;tick(3);npu_reset=1;
        ddr_locked=1;ui_running=1;hold_r_response=0;
        tick(100);check(fabric_error && !clean_rsp_valid && !transport_idle,"UI recovery remains isolated");
        reset_chain();clear_access(0,32'h00400100,0,0);check(actual===pattern,"read after full-chain restart");
        // core停止期间的短失锁即使恢复也必须保留；CDC返回不能变成清理成功。
        @(negedge clk);hold_r_response=1;launch_clean_read();while(r_delay<0)tick(1);
        @(negedge clk);core_running=0;core_locked=0;
        #5;core_locked=1;hold_r_response=0;
        #150;core_running=1;
        wait_fault(7);tick(30);
        check(fault_causes==4'b0001 && !clean_rsp_valid && !fabric_idle,"stopped core fault survives buffered return");
        reset_chain();clear_access(0,32'h00400100,0,0);check(actual===pattern,"final cold recovery data");
        $display("M1_MEMORY_AXI_CDC_PASS seed=%0d checks=%0d axi_writes=%0d axi_reads=%0d",initial_seed,checks,axi_writes,reads_seen);
        $finish;
    end
    initial begin #10000000;$fatal(1,"integrated native/CDC watchdog");end
endmodule
