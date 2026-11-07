// 完整 Qwen3 计算 RTL 夹具；DPI 仅存储字节与只读输出观察。
`timescale 1ns/1ps
module tb_top;
    import rkv_m1_layout_pkg::*;
    logic clk = '0;
    logic cold_reset = '0;
    logic cpu_reset_pulse;
    logic cmd_ready;
    logic cq_valid;
    logic [31:0] cq_op;
    logic [31:0] cq_status;
    logic [63:0] cq_session;
    logic [31:0] cq_epoch;
    logic [63:0] cq_sequence;
    logic [31:0] cq_context;
    logic [31:0] cq_generation;
    logic [31:0] cq_token0;
    logic [31:0] cq_token1;
    logic isolated;
    logic reset_pending;
    logic session_valid;
    logic [63:0] session;
    logic [31:0] epoch;
    logic [63:0] next_sequence;
    logic [31:0] generation;
    logic [31:0] object_id;
    logic [2:0] object_state;
    logic bound_pair;
    logic [31:0] built_tokens;
    logic [31:0] decode_steps;
    logic [63:0] accepted_count;
    logic [63:0] rejected_count;
    logic [63:0] committed_tasks;
    logic [31:0] last_error;
    logic loader_start;
    logic [31:0] loader_addr;
    logic [31:0] loader_count;
    logic npu_reset;
    logic [31:0] npu_args [8];
    logic protocol_error;
    logic launch_pulse;
    logic [63:0] task_cycles;
    logic [63:0] loader_cycles;
    logic flush_req;
    logic req_valid;
    logic req_write;
    logic [31:0] req_addr;
    logic [1023:0] req_data;
    logic [127:0] req_mask;
    logic rsp_ready;
    logic [31:0] clear_fault_code;
    logic [63:0] clear_reads_accepted;
    logic [63:0] clear_reads_retired;
    logic [63:0] clear_writes_accepted;
    logic [63:0] clear_writes_retired;
    logic [63:0] clear_cleaned_bytes;
    logic boot_hold = '0;
    logic boot_waiting;
    logic host_reset_request = '0;
    logic host_valid = '0;
    logic [15:0] host_addr = '0;
    logic [31:0] host_wdata = '0;
    logic [3:0] host_wstrb = '0;
    logic host_ready;
    logic [31:0] host_rdata;
    logic host_error;
    logic trap;
    logic test_done;
    logic [31:0] test_code;
    logic token_trace_valid;
    logic token_trace_row;
    logic [31:0] token_trace_data;
    logic cache_flush;
    logic cache_flush_ack = '0;
    logic transport_idle = '0;
    logic transport_error = '0;
    logic mem_wr_idle = '0;
    logic mem_rd_idle = '0;
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
    logic clk_f = '0;
    logic inject_task_error = 1'b0;
    logic [31:0] injected_errors;
    logic a_inval;
    logic host_idle = '0;
    logic host_read_grant;
    logic host_write_grant;
    logic dump = '0;
    logic [31:0] icount;
    rkv_m1_system dut (
        .host_accept_now(1'b0),
        .clk(clk),
        .cold_reset(cold_reset),
        .cpu_reset_pulse(cpu_reset_pulse),
        .cmd_ready(cmd_ready),
        .cq_valid(cq_valid),
        .cq_op(cq_op),
        .cq_status(cq_status),
        .cq_session(cq_session),
        .cq_epoch(cq_epoch),
        .cq_sequence(cq_sequence),
        .cq_context(cq_context),
        .cq_generation(cq_generation),
        .cq_token0(cq_token0),
        .cq_token1(cq_token1),
        .isolated(isolated),
        .reset_pending(reset_pending),
        .session_valid(session_valid),
        .session(session),
        .epoch(epoch),
        .next_sequence(next_sequence),
        .generation(generation),
        .object_id(object_id),
        .object_state(object_state),
        .bound_pair(bound_pair),
        .built_tokens(built_tokens),
        .decode_steps(decode_steps),
        .accepted_count(accepted_count),
        .rejected_count(rejected_count),
        .committed_tasks(committed_tasks),
        .last_error(last_error),
        .loader_start(loader_start),
        .loader_addr(loader_addr),
        .loader_count(loader_count),
        .npu_reset(npu_reset),
        .npu_args(npu_args),
        .protocol_error(protocol_error),
        .launch_pulse(launch_pulse),
        .task_cycles(task_cycles),
        .loader_cycles(loader_cycles),
        .flush_req(flush_req),
        .req_valid(req_valid),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_data(req_data),
        .req_mask(req_mask),
        .rsp_ready(rsp_ready),
        .clear_fault_code(clear_fault_code),
        .clear_reads_accepted(clear_reads_accepted),
        .clear_reads_retired(clear_reads_retired),
        .clear_writes_accepted(clear_writes_accepted),
        .clear_writes_retired(clear_writes_retired),
        .clear_cleaned_bytes(clear_cleaned_bytes),
        .boot_hold(boot_hold),
        .boot_waiting(boot_waiting),
        .host_reset_request(host_reset_request),
        .host_valid(host_valid),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_wstrb(host_wstrb),
        .host_ready(host_ready),
        .host_rdata(host_rdata),
        .host_error(host_error),
        .trap(trap),
        .test_done(test_done),
        .test_code(test_code),
        .token_trace_valid(token_trace_valid),
        .token_trace_row(token_trace_row),
        .token_trace_data(token_trace_data),
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
        .mem_b_rdata(mem_b_rdata),
        .clk_f(clk_f),
        .inject_task_error(inject_task_error),
        .injected_errors(injected_errors),
        .a_inval(a_inval),
        .host_idle(host_idle),
        .host_read_grant(host_read_grant),
        .host_write_grant(host_write_grant),
        .dump(dump),
        .icount(icount)
    );
    assign mem_a_rdy = 1'b1;
    assign mem_sw_rdy = 1'b1;
    assign mem_b_rdy = 1'b1;
    assign mem_wr_idle = 1'b1;
    assign transport_idle = mem_rd_idle;
    assign cache_flush_ack = cache_flush;
    otpu_dram #(
        .WORDS(536870912),
        .D(128),
        .LAT(8),
        .SID(0)
    ) memory (
        .clk(clk),
        .a_req(mem_a_req && mem_a_rdy),
        .a_we(mem_a_we),
        .a_addr(mem_a_addr),
        .a_wdata(mem_a_wdata),
        .a_be(mem_a_be),
        .a_rvalid(mem_a_rvalid),
        .a_rdata(mem_a_rdata),
        .sw_req(mem_sw_req && mem_sw_rdy),
        .sw_addr(mem_sw_addr),
        .sw_wdata(mem_sw_wdata),
        .sw_be(mem_sw_be),
        .b_req(mem_b_req && mem_b_rdy),
        .b_we(mem_b_we),
        .b_tag(mem_b_tag),
        .b_addr(mem_b_addr),
        .b_wdata(mem_b_wdata),
        .b_wmask(mem_b_wmask),
        .b_rvalid(mem_b_rvalid),
        .b_rtag(mem_b_rtag),
        .b_rdata(mem_b_rdata),
        .rd_idle(mem_rd_idle),
        .dump(dump)
    );

    // 两个时钟在同一个进程推进，core 两边沿与 fast 上升沿同相。
    // 仿真周期 20/10 ns 只表明合同设置，不构成 FPGA STA 证据。
    initial forever begin
        #5 clk_f = 1'b0;
        #5 begin clk = ~clk; clk_f = 1'b1; end
    end
    import "DPI-C" function void rkv_observe_logits(input int sid, input string directory, input int step, input int address, input int words);
    import "DPI-C" function void rkv_observe_context(input string directory, input string name, input int address, input int bytes);
    import "DPI-C" function void rkv_m1_progress(input string directory, input string event_name, input longint unsigned cycle, input int unsigned built);
    string directory;
    longint unsigned cycles = 0;
    longint unsigned max_cycles = 500000000;
    longint unsigned npu_read_bytes = 0;
    longint unsigned npu_write_bytes = 0;
    integer short_test = 0;
    integer launches = 0;
    integer decodes = 0;
    integer binds = 0;
    integer loads = 0;
    logic previous_cq = 0;
    logic previous_bound = 0;
    logic [31:0] previous_built = 0;
    logic [31:0] expected_build [32768];
    logic [31:0] expected_decode [32768];
    initial begin
        if (!$value$plusargs("dir=%s", directory)) $fatal(1, "missing input directory");
        void'($value$plusargs("short=%d", short_test));
        void'($value$plusargs("max_cycles=%d", max_cycles));
        for (int i = 0; i < 32768; i++) begin expected_build[i] = 0; expected_decode[i] = 0; end
        $readmemh($sformatf("%s/expected_build.hex", directory), expected_build);
        $readmemh($sformatf("%s/expected_decode.hex", directory), expected_decode);
        cold_reset = 1; host_idle = 1;
        repeat (5) @(negedge clk);
        cold_reset = 0;
    end
    always @(posedge clk) if (!cold_reset) begin
        cycles <= cycles + 64'd1;
        if (cycles[19:0] == 0) rkv_m1_progress(directory, "heartbeat", cycles, built_tokens);
        if (cycles >= max_cycles) $fatal(1, "full model cycle watchdog");
        if (trap || isolated || protocol_error) $fatal(1, "M1 failure trap=%b isolated=%b error=%0d cleaner=%0d", trap, isolated, last_error, clear_fault_code);
        previous_cq <= cq_valid;
        previous_bound <= bound_pair;
        previous_built <= built_tokens;
        if (loader_start) begin
            loads <= loads + 1;
            $display("M1_LOAD address=%h instructions=%0d cycle=%0d", loader_addr, loader_count, cycles); $fflush();
        end
        if (launch_pulse) begin
            rkv_m1_progress(directory, "launch", cycles, built_tokens);
            launches <= launches + 1;
            for (int i = 0; i < int'(loader_count)*8; i++) begin
                if (dut.compute.compute.u_seq.u_imem.g_auto.mem[i/32][(i%32)*32 +: 32] !==
                    (loader_addr == BUILD_ADDR ? expected_build[i] : expected_decode[i])) $fatal(1, "IMEM program mismatch");
            end
            $display("M1_LAUNCH seq=%h generation=%0d program=%h cycle=%0d", cq_sequence, generation, loader_addr, cycles); $fflush();
        end
        if (built_tokens != previous_built) begin
            rkv_m1_progress(directory, "build_commit", cycles, built_tokens);
            $display("M1_BUILD_COMMIT tokens=%0d cycle=%0d", built_tokens, cycles); $fflush();
        end
        if (bound_pair && !previous_bound) begin
            binds <= binds + 1;
            rkv_observe_context(directory, $sformatf("private-bind-%0d.bin", binds), int'(KV_BASE+PREFIX_BYTES), int'(OBJECT_BYTES-PREFIX_BYTES));
            rkv_observe_context(directory, $sformatf("prefix-bind-%0d.bin", binds), int'(KV_BASE), int'(PREFIX_BYTES));
        end
        if (cq_valid && !previous_cq) begin
            if (cq_status != 0) $fatal(1, "task failed op=%0d status=%0d", cq_op, cq_status);
            if (cq_op == OP_BUILD || cq_op == OP_DECODE) begin
                if (!npu_reset || !dut.fabric_idle || dut.loader_busy) $fatal(1, "completion before drain");
                $display("M1_COMPLETE op=%0d seq=%h token0=%0d token1=%0d cycle=%0d", cq_op, cq_sequence, cq_token0, cq_token1, cycles); $fflush();
            end
            if (cq_op == OP_DECODE) begin
                decodes <= decodes + 1;
                rkv_observe_logits(0, directory, decodes+1, int'(LOGITS_ADDRESS), int'(LOGITS_BYTES/4));
                if (decodes == 2 || decodes == 5)
                    rkv_observe_context(directory, $sformatf("context-pair-%0d.bin", decodes/3), int'(KV_BASE), int'(OBJECT_BYTES));
            end
        end
        // 计数仅反映 NPU 原生请求量；真实 DDR 事务与吞吐另由板级计数器报告。
        npu_read_bytes <= npu_read_bytes +
            ((dut.a_req && dut.a_rdy && !dut.a_we) ? 64'd32 : 64'd0) +
            ((dut.b_req && dut.b_rdy && !dut.b_we) ? 64'd128 : 64'd0);
        npu_write_bytes <= npu_write_bytes +
            ((dut.a_req && dut.a_rdy && dut.a_we) ? 64'($countones(dut.a_be)) : 64'd0) +
            ((dut.sw_req && dut.sw_rdy) ? 64'($countones(dut.sw_be)) : 64'd0) +
            ((dut.b_req && dut.b_rdy && dut.b_we) ? 64'($countones(dut.b_wmask))*64'd4 : 64'd0);
    end
    initial begin
        wait (!cold_reset);
        wait (test_done);
        @(negedge clk);
        if (short_test != 0) begin
            if (test_code != 32'h600d0004 || launches != 1 || built_tokens != 4 || decodes != 0) $fatal(1, "four-token result");
        end else begin
            if (test_code != 32'h600d4102 || launches != 70 || built_tokens != 256 || decodes != 6 || binds != 2 ||
                accepted_count != 76 || clear_cleaned_bytes != 64'(OBJECT_BYTES)-64'(PREFIX_BYTES)+64'(SCRATCH_BYTES))
                $fatal(1, "continuous lifecycle result code=%h launches=%0d decodes=%0d", test_code, launches, decodes);
        end
        if (!dut.fabric_idle || dut.loader_busy || cq_valid || !npu_reset) $fatal(1, "unsafe test end");
        rkv_observe_context(directory, "prefix-final.bin", int'(KV_BASE), int'(PREFIX_BYTES));
        dump = 1;
        @(negedge clk); dump = 0;
        $display("M1_FULL_RESULT short=%0d cycles=%0d launches=%0d decodes=%0d binds=%0d task_cycles=%0d loader_cycles=%0d clean_bytes=%0d npu_read_bytes=%0d npu_write_bytes=%0d",
            short_test, cycles, launches, decodes, binds, task_cycles, loader_cycles, clear_cleaned_bytes, npu_read_bytes, npu_write_bytes);
        $fflush(); $finish;
    end
endmodule
