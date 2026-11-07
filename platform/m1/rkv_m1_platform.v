// 完整数字平台：真实CPU/NPU/native缓存与主机共享AXI/CDC；物理MIG与时钟源另层绑定。
// 不包含DPI或行为存储。未绑定实际DIMM参数时不可作为可烧写DDR工程。
module rkv_m1_platform #(
    parameter FIRMWARE = "",
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000,
    parameter [63:0] EXPERIMENT_ID = 64'd0
) (
    input wire core_clk,
    input wire fast_clk,
    input wire ddr_clk,
    input wire chain_cold_reset,
    input wire core_locked,
    input wire ddr_locked,
    input wire ddr_calibrated,
    input wire external_fault,
    input wire inject_task_error,
    input wire [3:0] h_awid,
    input wire [31:0] h_awaddr,
    input wire [7:0] h_awlen,
    input wire [2:0] h_awsize,
    input wire [1:0] h_awburst,
    input wire h_awlock,
    input wire [3:0] h_awcache,
    input wire [2:0] h_awprot,
    input wire [3:0] h_awqos,
    input wire h_awvalid,
    output wire h_awready,
    input wire [63:0] h_wdata,
    input wire [7:0] h_wstrb,
    input wire h_wlast,
    input wire h_wvalid,
    output wire h_wready,
    output wire [3:0] h_bid,
    output wire [1:0] h_bresp,
    output wire h_bvalid,
    input wire h_bready,
    input wire [3:0] h_arid,
    input wire [31:0] h_araddr,
    input wire [7:0] h_arlen,
    input wire [2:0] h_arsize,
    input wire [1:0] h_arburst,
    input wire h_arlock,
    input wire [3:0] h_arcache,
    input wire [2:0] h_arprot,
    input wire [3:0] h_arqos,
    input wire h_arvalid,
    output wire h_arready,
    output wire [3:0] h_rid,
    output wire [63:0] h_rdata,
    output wire [1:0] h_rresp,
    output wire h_rlast,
    output wire h_rvalid,
    input wire h_rready,
    output wire [3:0] m_awid,
    output wire [32:0] m_awaddr,
    output wire [7:0] m_awlen,
    output wire [2:0] m_awsize,
    output wire [1:0] m_awburst,
    output wire m_awlock,
    output wire [3:0] m_awcache,
    output wire [2:0] m_awprot,
    output wire [3:0] m_awqos,
    output wire m_awvalid,
    input wire m_awready,
    output wire [511:0] m_wdata,
    output wire [63:0] m_wstrb,
    output wire m_wlast,
    output wire m_wvalid,
    input wire m_wready,
    input wire [3:0] m_bid,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    output wire m_bready,
    output wire [3:0] m_arid,
    output wire [32:0] m_araddr,
    output wire [7:0] m_arlen,
    output wire [2:0] m_arsize,
    output wire [1:0] m_arburst,
    output wire m_arlock,
    output wire [3:0] m_arcache,
    output wire [2:0] m_arprot,
    output wire [3:0] m_arqos,
    output wire m_arvalid,
    input wire m_arready,
    input wire [3:0] m_rid,
    input wire [511:0] m_rdata,
    input wire [1:0] m_rresp,
    input wire m_rlast,
    input wire m_rvalid,
    output wire m_rready,
    output wire control_cold_reset,
    output wire core_cold_reset,
    output wire ddr_axi_aresetn,
    output wire admission_enable,
    output wire [3:0] fault_causes,
    output wire platform_error,
    output wire [63:0] host_verified_beats,
    output wire [63:0] native_verified_writes,
    output wire cpu_reset_pulse,
    output wire cq_valid,
    output wire isolated,
    output wire reset_pending,
    output wire [31:0] epoch,
    output wire [31:0] generation,
    output wire [31:0] built_tokens,
    output wire [63:0] committed_tasks,
    output wire [31:0] last_error,
    output wire boot_waiting,
    output wire trap,
    output wire test_done,
    output wire [31:0] test_code,
    output wire boot_hold,
    output wire [1279:0] observation_data
);
    // 无新增事务寄存；身份、准入、退休分别由下面已有实例唯一保存。
    wire [63:0] accepted_reads;
    wire [63:0] accepted_writes;
    wire [63:0] rejected_requests;
    wire reset_request;
    wire control_idle;
    wire [63:0] control_requests;
    wire host_valid;
    wire [15:0] host_addr;
    wire [31:0] host_wdata;
    wire [3:0] host_wstrb;
    wire host_ready;
    wire [31:0] host_rdata;
    wire host_error;
    wire memory_idle;
    wire memory_accept_now;
    wire saved_read_grant;
    wire saved_write_grant;
    wire [1:0] memory_outstanding;
    wire [31:0] d_awaddr;
    wire [7:0] d_awlen;
    wire [2:0] d_awsize;
    wire [1:0] d_awburst;
    wire d_awlock;
    wire [3:0] d_awcache;
    wire [2:0] d_awprot;
    wire [3:0] d_awqos;
    wire d_awvalid;
    wire d_awready;
    wire [63:0] d_wdata;
    wire [7:0] d_wstrb;
    wire d_wlast;
    wire d_wvalid;
    wire d_wready;
    wire [1:0] d_bresp;
    wire d_bvalid;
    wire d_bready;
    wire [31:0] d_araddr;
    wire [7:0] d_arlen;
    wire [2:0] d_arsize;
    wire [1:0] d_arburst;
    wire d_arlock;
    wire [3:0] d_arcache;
    wire [2:0] d_arprot;
    wire [3:0] d_arqos;
    wire d_arvalid;
    wire d_arready;
    wire [63:0] d_rdata;
    wire [1:0] d_rresp;
    wire d_rlast;
    wire d_rvalid;
    wire d_rready;
    wire transport_ready;
    wire guard_armed;
    wire host_idle;
    wire bridge_idle;
    wire shared_idle;
    wire host_fault;
    wire [31:0] host_fault_code;
    wire bridge_fault;
    wire [31:0] bridge_fault_code;
    wire route_fault;
    wire [1:0] n_cvalid;
    wire [1:0] n_cready;
    wire [1:0] n_cwe;
    wire [49:0] n_caddr;
    wire [1:0] n_wvalid;
    wire [1:0] n_wready;
    wire [1023:0] n_wdata;
    wire [127:0] n_wmask;
    wire [1:0] n_rvalid;
    wire [1023:0] n_rdata;
    wire [31:0] n_wdone;
    wire cmd_ready;
    wire [31:0] cq_op;
    wire [31:0] cq_status;
    wire [63:0] cq_session;
    wire [31:0] cq_epoch;
    wire [63:0] cq_sequence;
    wire [31:0] cq_context;
    wire [31:0] cq_generation;
    wire [31:0] cq_token0;
    wire [31:0] cq_token1;
    wire session_valid;
    wire [63:0] session;
    wire [63:0] next_sequence;
    wire [31:0] object_id;
    wire [2:0] object_state;
    wire bound_pair;
    wire [31:0] decode_steps;
    wire [63:0] accepted_count;
    wire [63:0] rejected_count;
    wire loader_start;
    wire [31:0] loader_addr;
    wire [31:0] loader_count;
    wire npu_reset;
    wire protocol_error;
    wire launch_pulse;
    wire [63:0] task_cycles;
    wire [63:0] loader_cycles;
    wire flush_req;
    wire req_valid;
    wire req_write;
    wire [31:0] req_addr;
    wire [1023:0] req_data;
    wire [127:0] req_mask;
    wire rsp_ready;
    wire [31:0] clear_fault_code;
    wire [63:0] clear_reads_accepted;
    wire [63:0] clear_reads_retired;
    wire [63:0] clear_writes_accepted;
    wire [63:0] clear_writes_retired;
    wire [63:0] clear_cleaned_bytes;
    wire token_trace_valid;
    wire token_trace_row;
    wire [31:0] token_trace_data;
    wire [31:0] injected_errors;
    wire a_inval;
    wire [31:0] icount;
    wire [31:0] combined_error_code;
    wire ingress_fault;
    wire [31:0] ingress_fault_code;
    wire native_host_read_grant;
    wire native_host_write_grant;
    // 错误诊断优先保留最早主机入口，再看主机DDR门控、native桥与业务错误。
    assign combined_error_code = ingress_fault ? ingress_fault_code :
        host_fault ? host_fault_code : bridge_fault ? bridge_fault_code : last_error;

    // 主机接收沿保存原权限；最终R/B消费前，root责任不能被下游idle替代。
    rkv_m1_host_link #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES),
        .EXPERIMENT_ID(EXPERIMENT_ID)
    ) host (
        .clk(core_clk),
        .cold_reset(control_cold_reset),
        .platform_ready(admission_enable),
        .platform_error(platform_error),
        .ddr_idle(shared_idle),
        .ddr_accept_now(1'b0),
        .status_flags({26'd0, fault_causes, transport_ready, guard_armed}),
        .epoch(epoch),
        .generation(generation),
        .error_code(combined_error_code),
        .host_verified(host_verified_beats),
        .native_verified(native_verified_writes),
        .accepted_reads(accepted_reads),
        .accepted_writes(accepted_writes),
        .rejected_requests(rejected_requests),
        .boot_hold(boot_hold),
        .reset_request(reset_request),
        .control_idle(control_idle),
        .control_requests(control_requests),
        .host_valid(host_valid),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_wstrb(host_wstrb),
        .host_ready(host_ready),
        .host_rdata(host_rdata),
        .host_error(host_error),
        .read_grant(native_host_read_grant && admission_enable),
        .write_grant(native_host_write_grant && admission_enable),
        .memory_idle(memory_idle),
        .memory_accept_now(memory_accept_now),
        .saved_read_grant(saved_read_grant),
        .saved_write_grant(saved_write_grant),
        .fault(ingress_fault),
        .fault_code(ingress_fault_code),
        .memory_outstanding(memory_outstanding),
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
        .d_awaddr(d_awaddr),
        .d_awlen(d_awlen),
        .d_awsize(d_awsize),
        .d_awburst(d_awburst),
        .d_awlock(d_awlock),
        .d_awcache(d_awcache),
        .d_awprot(d_awprot),
        .d_awqos(d_awqos),
        .d_awvalid(d_awvalid),
        .d_awready(d_awready),
        .d_wdata(d_wdata),
        .d_wstrb(d_wstrb),
        .d_wlast(d_wlast),
        .d_wvalid(d_wvalid),
        .d_wready(d_wready),
        .d_bresp(d_bresp),
        .d_bvalid(d_bvalid),
        .d_bready(d_bready),
        .d_araddr(d_araddr),
        .d_arlen(d_arlen),
        .d_arsize(d_arsize),
        .d_arburst(d_arburst),
        .d_arlock(d_arlock),
        .d_arcache(d_arcache),
        .d_arprot(d_arprot),
        .d_arqos(d_arqos),
        .d_arvalid(d_arvalid),
        .d_arready(d_arready),
        .d_rdata(d_rdata),
        .d_rresp(d_rresp),
        .d_rlast(d_rlast),
        .d_rvalid(d_rvalid),
        .d_rready(d_rready)
    );

    // 普通CPU复位不触及native缓存/退休计数；冷复位等待两个时钟域释放。
    rkv_m1_native_system #(
        .FIRMWARE(FIRMWARE)
    ) native (
        .clk(core_clk),
        .cold_reset(core_cold_reset),
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
        .npu_args(),
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
        .host_reset_request(reset_request),
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
        .clk_f(fast_clk),
        .inject_task_error(inject_task_error),
        .injected_errors(injected_errors),
        .a_inval(a_inval),
        .host_idle(memory_idle && shared_idle),
        .host_accept_now(memory_accept_now),
        .host_read_grant(native_host_read_grant),
        .host_write_grant(native_host_write_grant),
        .dump(1'b0),
        .icount(icount),
        .platform_error(platform_error),
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
        .n_wdone(n_wdone)
    );

    // native桥一直受健康准入约束；既有arbiter决定计算/清理互斥，不以busy反向拒绝旧责任。
    rkv_m1_shared_axi #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) shared (
        .core_clk(core_clk),
        .ddr_clk(ddr_clk),
        .chain_cold_reset(chain_cold_reset),
        .core_locked(core_locked),
        .ddr_locked(ddr_locked),
        .ddr_calibrated(ddr_calibrated),
        .external_fault(external_fault || ingress_fault),
        .host_read_grant(saved_read_grant),
        .host_write_grant(saved_write_grant),
        .native_grant(1'b1),
        .control_cold_reset(control_cold_reset),
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
        .h_awid(4'd0),
        .h_awaddr(d_awaddr),
        .h_awlen(d_awlen),
        .h_awsize(d_awsize),
        .h_awburst(d_awburst),
        .h_awlock(d_awlock),
        .h_awcache(d_awcache),
        .h_awprot(d_awprot),
        .h_awqos(d_awqos),
        .h_awvalid(d_awvalid),
        .h_awready(d_awready),
        .h_wdata(d_wdata),
        .h_wstrb(d_wstrb),
        .h_wlast(d_wlast),
        .h_wvalid(d_wvalid),
        .h_wready(d_wready),
        .h_bid(),
        .h_bresp(d_bresp),
        .h_bvalid(d_bvalid),
        .h_bready(d_bready),
        .h_arid(4'd0),
        .h_araddr(d_araddr),
        .h_arlen(d_arlen),
        .h_arsize(d_arsize),
        .h_arburst(d_arburst),
        .h_arlock(d_arlock),
        .h_arcache(d_arcache),
        .h_arprot(d_arprot),
        .h_arqos(d_arqos),
        .h_arvalid(d_arvalid),
        .h_arready(d_arready),
        .h_rid(),
        .h_rdata(d_rdata),
        .h_rresp(d_rresp),
        .h_rlast(d_rlast),
        .h_rvalid(d_rvalid),
        .h_rready(d_rready),
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
    // 所有字段均为core域；外层在一个core沿锁存整份1280位快照。
    assign observation_data[31:0] = {15'd0,cmd_ready,boot_hold,memory_accept_now,flush_req,trap,platform_error,admission_enable,session_valid,bound_pair,(memory_idle && shared_idle),native_host_write_grant,native_host_read_grant,boot_waiting,reset_pending,isolated,cq_valid,!npu_reset};
    assign observation_data[63:32] = epoch;
    assign observation_data[95:64] = generation;
    assign observation_data[127:96] = built_tokens;
    assign observation_data[159:128] = committed_tasks[31:0];
    assign observation_data[191:160] = committed_tasks[63:32];
    assign observation_data[223:192] = task_cycles[31:0];
    assign observation_data[255:224] = task_cycles[63:32];
    assign observation_data[287:256] = clear_cleaned_bytes[31:0];
    assign observation_data[319:288] = clear_cleaned_bytes[63:32];
    assign observation_data[351:320] = last_error;
    assign observation_data[383:352] = {29'd0,object_state};
    assign observation_data[415:384] = decode_steps;
    assign observation_data[447:416] = next_sequence[31:0];
    assign observation_data[479:448] = next_sequence[63:32];
    assign observation_data[511:480] = session[31:0];
    assign observation_data[543:512] = session[63:32];
    assign observation_data[575:544] = accepted_count[31:0];
    assign observation_data[607:576] = accepted_count[63:32];
    assign observation_data[639:608] = rejected_count[31:0];
    assign observation_data[671:640] = rejected_count[63:32];
    assign observation_data[703:672] = host_verified_beats[31:0];
    assign observation_data[735:704] = host_verified_beats[63:32];
    assign observation_data[767:736] = native_verified_writes[31:0];
    assign observation_data[799:768] = native_verified_writes[63:32];
    assign observation_data[831:800] = cq_token0;
    assign observation_data[863:832] = cq_token1;
    assign observation_data[895:864] = clear_fault_code;
    assign observation_data[927:896] = loader_cycles[31:0];
    assign observation_data[959:928] = loader_cycles[63:32];
    assign observation_data[991:960] = {30'd0,memory_outstanding};
    assign observation_data[1023:992] = object_id;
    assign observation_data[1055:1024] = injected_errors;
    assign observation_data[1087:1056] = combined_error_code;
    assign observation_data[1119:1088] = clear_writes_accepted[31:0];
    assign observation_data[1151:1120] = clear_writes_accepted[63:32];
    assign observation_data[1183:1152] = clear_writes_retired[31:0];
    assign observation_data[1215:1184] = clear_writes_retired[63:32];
    assign observation_data[1247:1216] = {30'd0,transport_ready,shared_idle};
    assign observation_data[1279:1248] = 32'd0;
endmodule
