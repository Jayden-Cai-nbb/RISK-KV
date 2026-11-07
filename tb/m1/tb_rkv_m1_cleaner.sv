`timescale 1ns/1ps
module tb_rkv_m1_cleaner;
    import rkv_m1_layout_pkg::*;
    logic clk = 1'b0;
    always #5 clk = !clk;
    logic cold_reset = 1'b1;
    logic start_valid = 1'b0;
    logic start_ready;
    logic full_object = 1'b0;
    logic fabric_idle = 1'b1;
    logic fabric_error = 1'b0;
    logic flush_req;
    logic flush_ack = 1'b0;
    logic req_valid;
    logic req_ready = 1'b0;
    logic req_write;
    logic [31:0] req_addr;
    logic [1023:0] req_data;
    logic [127:0] req_mask;
    logic rsp_valid;
    logic rsp_ready;
    logic rsp_error;
    logic [1023:0] rsp_data;
    logic done_valid;
    logic done_ready = 1'b0;
    logic isolated;
    logic [31:0] fault_code;
    logic [63:0] ra, rr, wa, wr, cleaned;
    logic [31:0] rng = 32'h04b11d37;
    logic pending = 1'b0;
    logic [31:0] saved_addr;
    integer delay_left = 0;
    logic drop_response = 1'b0;
    logic block_request = 1'b0;
    logic inject_error = 1'b0;
    logic check_ranges = 1'b0;
    logic check_copy_write = 1'b0;
    integer range_no = 0;
    logic [31:0] offset = 32'd0;
    logic full_expected;
    integer requests = 0;
    integer checks = 0;
    logic held = 1'b0;
    logic [1184:0] held_payload;

    rkv_m1_cleaner #(.TIMEOUT_CYCLES(32'd64)) dut (
        .clk(clk),
        .cold_reset(cold_reset),
        .start_valid(start_valid),
        .start_ready(start_ready),
        .full_object(full_object),
        .fabric_idle(fabric_idle),
        .fabric_error(fabric_error),
        .flush_req(flush_req),
        .flush_ack(flush_ack),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_data(req_data),
        .req_mask(req_mask),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_error(rsp_error),
        .rsp_data(rsp_data),
        .done_valid(done_valid),
        .done_ready(done_ready),
        .isolated(isolated),
        .fault_code(fault_code),
        .reads_accepted(ra),
        .reads_retired(rr),
        .writes_accepted(wa),
        .writes_retired(wr),
        .cleaned_bytes(cleaned)
    );

    function automatic logic [1023:0] pattern(input logic [31:0] address);
        logic [1023:0] data;
        for (int i = 0; i < 32; i++) data[i*32 +: 32] = address ^ (32'h7fc00000 + 32'(i));
        return data;
    endfunction
    assign rsp_valid = pending && delay_left == 0 && !drop_response;
    assign rsp_error = inject_error;
    assign rsp_data = pattern(saved_addr);
    always @(negedge clk) begin
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        req_ready = !block_request && !pending && rng[0];
    end
    always @(posedge clk) begin
        if (cold_reset) begin
            pending <= 1'b0;
            delay_left <= 0;
            held <= 1'b0;
        end else begin
            if (held && (!req_valid || {req_write, req_addr, req_data, req_mask} != held_payload))
                $fatal(1, "request changed under backpressure");
            held <= req_valid && !req_ready;
            held_payload <= {req_write, req_addr, req_data, req_mask};
            if (pending && delay_left != 0) delay_left <= delay_left - 1;
            if (rsp_valid && rsp_ready) pending <= 1'b0;
            if (req_valid && req_ready) begin
                if (pending) $fatal(1, "more than one request outstanding");
                if (req_mask != {128{1'b1}} || req_addr[6:0] != 0) $fatal(1, "mask/alignment");
                pending <= 1'b1;
                saved_addr <= req_addr;
                delay_left <= int'(rng[3:1]) + 1;
                requests <= requests + 1;
                if (check_ranges) begin
                    if (range_no == 0) begin
                        if (!req_write || req_addr != KV_BASE + (full_expected ? 32'd0 : PREFIX_BYTES) + offset || req_data != 0)
                            $fatal(1, "KV clear address/data mismatch at %h", req_addr);
                        if (offset + 32'd128 == (full_expected ? OBJECT_BYTES : OBJECT_BYTES - PREFIX_BYTES)) begin
                            range_no <= 1;
                            offset <= 32'd0;
                        end else offset <= offset + 32'd128;
                    end else begin
                        if (req_write != check_copy_write) $fatal(1, "copy read/write order");
                        if (req_write) begin
                            if (req_addr != scratch_base(3'(range_no-1)) + offset ||
                                req_data != pattern(scratch_source(3'(range_no-1)) + offset))
                                $fatal(1, "scratch restore mismatch");
                            if (offset + 32'd128 == scratch_bytes(3'(range_no-1))) begin
                                range_no <= range_no + 1;
                                offset <= 32'd0;
                            end else offset <= offset + 32'd128;
                        end else if (req_addr != scratch_source(3'(range_no-1)) + offset) $fatal(1, "template address mismatch");
                        check_copy_write <= !check_copy_write;
                    end
                end
            end
            if (done_valid && (pending || wa != wr || ra != rr || isolated)) $fatal(1, "premature completion");
        end
    end

    task automatic tick(input integer n);
        repeat (n) begin @(posedge clk); #1; end
    endtask
    task automatic cold;
        @(negedge clk);
        cold_reset = 1'b1;
        start_valid = 1'b0;
        done_ready = 1'b0;
        flush_ack = 1'b0;
        fabric_idle = 1'b1;
        fabric_error = 1'b0;
        drop_response = 1'b0;
        block_request = 1'b0;
        inject_error = 1'b0;
        check_ranges = 1'b0;
        tick(3);
        @(negedge clk); cold_reset = 1'b0;
        tick(2);
    endtask
    task automatic start(input logic full);
        @(negedge clk);
        full_object = full;
        start_valid = 1'b1;
        do begin @(posedge clk); end while (!start_ready);
        @(negedge clk); start_valid = 1'b0;
    endtask
    task automatic verify_run(input logic full);
        logic [63:0] initial_written;
        logic [63:0] expected_bytes;
        initial_written = cleaned;
        expected_bytes = (full ? 64'(OBJECT_BYTES) : 64'(OBJECT_BYTES) - 64'(PREFIX_BYTES)) + 64'(SCRATCH_BYTES);
        range_no = 0;
        offset = 0;
        check_copy_write = 0;
        check_ranges = 1;
        full_expected = full;
        start(full);
        while (!flush_req) tick(1);
        if (done_valid || isolated || range_no != 4) $fatal(1, "range completion failed");
        tick(12);
        if (done_valid) $fatal(1, "software-free flush fence bypassed");
        @(negedge clk); flush_ack = 1;
        tick(2);
        if (!done_valid || cleaned - initial_written != expected_bytes) $fatal(1, "clean byte count");
        tick(5);
        if (!done_valid || start_ready) $fatal(1, "completion not retained");
        @(negedge clk); done_ready = 1;
        tick(1);
        @(negedge clk); done_ready = 0; flush_ack = 0;
        tick(1);
        if (!start_ready || wa != wr || ra != rr) $fatal(1, "not reusable after retirement");
        checks += 7;
    endtask

    initial begin
        cold();
        verify_run(1'b0);
        verify_run(1'b1);
        // 请求已接收但响应永不返回；不得把接受当成退休。
        cold(); drop_response = 1;
        start(1'b1);
        tick(100);
        if (!isolated || done_valid || wa != 1 || wr != 0 || start_ready) $fatal(1, "lost response not isolated");
        drop_response = 0;
        tick(20);
        if (!isolated || wr != 1 || done_valid || req_valid || start_ready) $fatal(1, "late response reopened slot");
        checks += 2;
        // 请求被背压直至超时，保持负载；迟到接受 / 退休也不能解除隔离。
        cold(); block_request = 1;
        start(1'b1); tick(100);
        if (!isolated || !req_valid || wa != 0) $fatal(1, "blocked request isolation");
        block_request = 0; tick(30);
        if (!isolated || wa != 1 || wr != 1 || done_valid) $fatal(1, "late accept isolation");
        checks += 2;
        cold(); inject_error = 1;
        start(1'b1); tick(40);
        if (!isolated || wa != wr || cleaned != 0 || done_valid) $fatal(1, "write error qualified cleanup");
        checks += 1;
        cold(); fabric_idle = 0;
        start(1'b0); tick(100);
        if (!isolated || wa != 0 || ra != 0) $fatal(1, "issued before drain");
        checks += 1;
        $display("M1_CLEANER_PASS checks=%0d transactions=%0d seed=04b11d37", checks, requests);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "test timeout");
    end
endmodule
