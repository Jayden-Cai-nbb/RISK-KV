// RNP3: object commands plus the observed/gated RNP2 integration variant.
// The generated RNP1/RNP2 variants add explicit event/metadata ports; frozen
// original files remain unchanged. No hierarchical control signal injection.
module rkv_npu_context_service #(
    parameter logic[31:0] RESULT_ADDR=32'd1229289088,
    parameter logic[31:0] KV_BASE=32'd1233223680,
    parameter logic[31:0] BUILD_INSNS=1026,DECODE_INSNS=1004
)(
    input logic clk,reset,bus_valid,
    input logic[11:0]bus_addr,input logic[31:0]bus_wdata,input logic[3:0]bus_wstrb,
    output logic bus_ready,output logic[31:0]bus_rdata,
    input logic npu_halted,npu_error,fabric_idle,fabric_error,loader_busy,
    output logic loader_start,output logic[31:0]loader_addr,loader_count,
    input logic result_store_valid,result_other_write,
    input logic[31:0]result_store_addr,input logic[1023:0]result_store_data,input logic[31:0]result_store_mask,
    output logic npu_reset,output logic[31:0]npu_args[8],
    output logic completion_valid,active,launch_pulse,program_ready,result_valid,
    output logic[31:0]completion_status,completion_context,completion_generation,
    output logic[63:0]completion_session,completion_sequence,
    output logic[31:0]accepted_count,rejected_count,result_token0,result_token1
);
    wire object_select=bus_addr>=12'h200;
    logic object_ready,io_ready;logic[31:0]object_data,io_data;
    logic session_valid,accepted_event,consumed_event,submit_allowed;
    logic[63:0]session_value,request_session;
    logic[31:0]proposed_context,proposed_generation,proposed_args[8],loaded_program_addr,loaded_program_count;
    logic reclaimable,bound_pair,task_reference;logic[2:0]object_state;
    logic[8:0]built_tokens,decode_steps;logic[31:0]object_id,object_generation;
    assign bus_ready=object_select?object_ready:io_ready;
    assign bus_rdata=object_select?object_data:((bus_addr==0)?32'h524e5033:io_data);
    rkv_npu_io_control #(.RESULT_ADDR(RESULT_ADDR)) io(
        .clk,.reset,.bus_valid(bus_valid&&!object_select),.bus_addr,.bus_wdata,.bus_wstrb,
        .bus_ready(io_ready),.bus_rdata(io_data),.npu_halted,.npu_error,.fabric_idle,.fabric_error,.loader_busy,
        .loader_start,.loader_addr,.loader_count,.result_store_valid,.result_other_write,.result_store_addr,.result_store_data,.result_store_mask,
        .npu_reset,.npu_args,.completion_valid,.active,.launch_pulse,.program_ready,.result_valid,
        .completion_status,.completion_context,.completion_generation,.completion_session,.completion_sequence,
        .accepted_count,.rejected_count,.result_token0,.result_token1,.submit_allowed,
        .observed_session_valid(session_valid),.observed_session(session_value),.request_session,.proposed_context,.proposed_generation,
        .proposed_args,.accepted_event,.consumed_event,.loaded_program_addr,.loaded_program_count);
    rkv_context_guard #(.KV_BASE(KV_BASE),.BUILD_INSNS(BUILD_INSNS),.DECODE_INSNS(DECODE_INSNS)) guard(
        .clk,.reset,.bus_valid(bus_valid&&object_select),.bus_addr,.bus_wdata,.bus_wstrb,.bus_ready(object_ready),.bus_rdata(object_data),
        .session_valid,.session_value,.request_session,.proposed_context,.proposed_generation,.proposed_args,
        .loaded_addr(loaded_program_addr),.loaded_count(loaded_program_count),.active,.completion_valid,
        .accepted_event,.consumed_event,.fabric_idle,.loader_busy,.completion_status,.completion_context,.completion_generation,
        .completion_session,.completion_sequence,.result_valid,.result_word0(result_token0),.result_word1(result_token1),
        .submit_allowed,.reclaimable,.object_state,.built_tokens,.decode_steps,.bound_pair,.task_reference,.object_id,.object_generation);
endmodule
