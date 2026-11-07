`timescale 1ns/1ps
module tb_rkv_m1_memory_arbiter;
    logic clk = '0;
    logic cold_reset = '0;
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
    logic cache_flush_ack = '0;
    logic transport_idle = '0;
    logic transport_error = '0;
    logic mem_wr_idle = '0;
    logic mem_rd_idle = '0;
    logic fabric_idle;
    logic fabric_error;
    logic mem_a_req;
    logic mem_a_we;
    logic [31:0] mem_a_addr;
    logic [31:0] mem_a_wdata;
    logic [3:0] mem_a_be;
    logic mem_a_rdy = '0;
    logic mem_a_rvalid = '0;
    logic [255:0] mem_a_rdata = '0;
    logic mem_sw_req;
    logic [31:0] mem_sw_addr;
    logic [31:0] mem_sw_wdata;
    logic [3:0] mem_sw_be;
    logic mem_sw_rdy = '0;
    logic mem_b_req;
    logic mem_b_we;
    logic mem_b_tag;
    logic mem_b_par;
    logic [31:0] mem_b_addr;
    logic [1023:0] mem_b_wdata;
    logic [31:0] mem_b_wmask;
    logic mem_b_rdy = '0;
    logic mem_b_rvalid = '0;
    logic mem_b_rtag = '0;
    logic [1023:0] mem_b_rdata = '0;
    always #5 clk = !clk;
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
    logic [31:0] memory [logic [31:0]];
    logic pending_write = 0;
    logic pending_read = 0;
    logic pending_a = 0;
    logic [31:0] saved_address;
    logic [1023:0] saved_data;
    logic [127:0] saved_mask;
    logic saved_tag;
    integer delay_left = 0;
    integer transactions = 0;
    integer checks = 0;
    logic [31:0] rng = 32'h20261104;
    logic [1023:0] pattern;
    logic [1023:0] actual;
    logic blocked = 0;
    logic holding = 0;
    logic [1088:0] held_payload;
    function automatic logic [31:0] load_word(input logic [31:0] address);
        return memory.exists(address) ? memory[address] : (32'hf00d0000 ^ address);
    endfunction
    assign mem_wr_idle = !pending_write;
    assign mem_rd_idle = !pending_read;
    always @(negedge clk) begin
        rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5);
        mem_a_rdy = !pending_read && !pending_write && rng[0];
        mem_sw_rdy = !pending_read && !pending_write && rng[1];
        mem_b_rdy = !pending_read && !pending_write && rng[2] && !blocked;
    end
    always @(posedge clk) begin
        if (cold_reset) begin
            pending_write <= 0; pending_read <= 0;
            mem_a_rvalid <= 0; mem_b_rvalid <= 0; holding <= 0;
        end else begin
            mem_a_rvalid <= 0; mem_b_rvalid <= 0;
            if (holding && (!mem_b_req || held_payload != {mem_b_we, mem_b_addr, mem_b_wdata, mem_b_wmask}))
                $fatal(1, "downstream request changed while blocked");
            holding <= mem_b_req && !mem_b_rdy;
            held_payload <= {mem_b_we, mem_b_addr, mem_b_wdata, mem_b_wmask};
            if (delay_left > 0) delay_left <= delay_left - 1;
            if (delay_left == 0 && pending_write) begin
                for (int w = 0; w < 32; w++) begin
                    automatic logic [31:0] word_value;
                    word_value = load_word(saved_address + 32'(w));
                    for (int b = 0; b < 4; b++)
                        if (saved_mask[w*4+b]) word_value[b*8 +: 8] = saved_data[w*32+b*8 +: 8];
                    if (saved_mask[w*4 +: 4] != 0) memory[saved_address + 32'(w)] = word_value;
                end
                pending_write <= 0;
            end
            if (delay_left == 0 && pending_read) begin
                if (pending_a) begin
                    mem_a_rvalid <= 1;
                    for (int w = 0; w < 8; w++) mem_a_rdata[w*32 +: 32] <= load_word({saved_address[31:3],3'd0} + 32'(w));
                end else begin
                    mem_b_rvalid <= 1; mem_b_rtag <= saved_tag;
                    for (int w = 0; w < 32; w++) mem_b_rdata[w*32 +: 32] <= load_word(saved_address + 32'(w));
                end
                pending_read <= 0;
            end
            if ((mem_b_req && mem_b_rdy) || (mem_a_req && mem_a_rdy) || (mem_sw_req && mem_sw_rdy)) begin
                if (pending_read || pending_write) $fatal(1, "BFM overrun");
                transactions <= transactions + 1;
                delay_left <= int'(rng[6:3]) + 2;
                saved_mask <= 128'd0; saved_data <= 1024'd0;
                if (mem_b_req && mem_b_rdy) begin
                    saved_address <= mem_b_addr; saved_tag <= mem_b_tag; pending_a <= 0;
                    pending_write <= mem_b_we; pending_read <= !mem_b_we;
                    saved_data <= mem_b_wdata;
                    for (int w = 0; w < 32; w++) saved_mask[w*4 +: 4] <= {4{mem_b_wmask[w]}};
                end else if (mem_a_req && mem_a_rdy) begin
                    saved_address <= mem_a_addr; pending_a <= 1;
                    pending_write <= mem_a_we; pending_read <= !mem_a_we;
                    saved_data[31:0] <= mem_a_wdata; saved_mask[3:0] <= mem_a_be;
                end else begin
                    saved_address <= mem_sw_addr;
                    pending_write <= 1; pending_read <= 0;
                    saved_data[31:0] <= mem_sw_wdata; saved_mask[3:0] <= mem_sw_be;
                end
            end
        end
    end
    task automatic tick(input integer n);
        repeat (n) begin @(posedge clk); #1; end
    endtask
    task automatic drain;
        do begin tick(1); end while (!fabric_idle);
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
        if (clean_rsp_error != expect_error || pending_write) $fatal(1, "clean response before retirement / wrong status");
        actual = clean_rsp_data;
        tick(5);
        if (!clean_rsp_valid || clean_req_ready || clean_rsp_data != actual) $fatal(1, "response under backpressure");
        @(negedge clk); clean_rsp_ready = 1;
        tick(1);
        @(negedge clk); clean_rsp_ready = 0;
        tick(3);
        checks += 2;
    endtask
    initial begin
        cold_reset = 1; transport_idle = 1; npu_reset = 1;
        tick(3);
        @(negedge clk); cold_reset = 0;
        tick(3);
        // 标量字节掩码及 A 的 32-byte 对齐返回。
        @(negedge clk); sw_req = 1; sw_addr = 32'h1233; sw_wdata = 32'h12345678; sw_be = 4'b0101;
        do begin @(posedge clk); end while (!sw_rdy);
        @(negedge clk); sw_req = 0;
        drain();
        if (load_word(32'h1233) != 32'hf0341278) $fatal(1, "SW byte mask / little endian");
        @(negedge clk); a_req = 1; a_we = 0; a_addr = 32'h1233;
        do begin @(posedge clk); end while (!a_rdy);
        @(negedge clk); a_req = 0;
        while (!a_rvalid) tick(1);
        if (a_rdata[3*32 +: 32] != 32'hf0341278) $fatal(1, "A word address alignment");
        drain(); checks += 2;
        for (int w = 0; w < 32; w++) pattern[w*32 +: 32] = 32'hcafe0000 + 32'(w);
        // 逻辑 2 GiB 最后一块以及所有字节；不得截断高地址。
        clear_access(1, 32'h7fffff80, {128{1'b1}}, 0);
        clear_access(0, 32'h7fffff80, 128'd0, 0);
        if (actual != pattern) $fatal(1, "last chunk / endian");
        // 整字稀疏掩码保留未选字，平台标量通路另验证任意字节掩码。
        clear_access(1, 32'h00004000, {32{4'hf}}, 0);
        pattern = ~pattern;
        clear_access(1, 32'h00004000, {16{8'h0f}}, 0);
        clear_access(0, 32'h00004000, 128'd0, 0);
        for (int w = 0; w < 32; w++)
            if (actual[w*32 +: 32] != (w[0] ? ~pattern[w*32 +: 32] : pattern[w*32 +: 32])) $fatal(1, "word mask");
        clear_access(1, 32'h80000000, {128{1'b1}}, 1);
        clear_access(1, 32'h00004004, {128{1'b1}}, 1);
        clear_access(1, 32'h00004000, 128'd1, 1);
        checks += 2;
        @(negedge clk); flush_req = 1; cache_flush_ack = 0;
        tick(5);
        if (flush_ack || !cache_flush) $fatal(1, "cache fence bypassed");
        @(negedge clk); cache_flush_ack = 1; transport_idle = 0;
        tick(3);
        if (flush_ack) $fatal(1, "unreturned physical prefetch bypassed");
        @(negedge clk); transport_idle = 1;
        tick(3);
        if (!flush_ack) $fatal(1, "cache fence not complete");
        checks += 3;
        $display("M1_MEMORY_ARBITER_PASS checks=%0d transactions=%0d seed=20261104", checks, transactions);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "test timeout");
    end
endmodule
