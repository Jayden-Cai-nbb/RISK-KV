// One-object lifecycle pilot, one allocation per cold initialization.
// Admission is BEFORE NPU submission; progress is committed only on successful
// matching completion consumption. Context bytes are not fabricated by this module.
module rkv_context_guard #(
    parameter logic[31:0] KV_BASE=32'd1233223680,
    parameter logic[31:0] BUILD_ADDR=32'h60000000,DECODE_ADDR=32'h60010000,
    parameter logic[31:0] BUILD_INSNS=1026,DECODE_INSNS=1004
)(
    input logic clk,reset,bus_valid,
    input logic[11:0]bus_addr,input logic[31:0]bus_wdata,input logic[3:0]bus_wstrb,
    output logic bus_ready,output logic[31:0]bus_rdata,
    input logic session_valid,input logic[63:0]session_value,request_session,
    input logic[31:0]proposed_context,proposed_generation,proposed_args[8],
    input logic[31:0]loaded_addr,loaded_count,
    input logic active,completion_valid,accepted_event,consumed_event,fabric_idle,loader_busy,
    input logic[31:0]completion_status,completion_context,completion_generation,
    input logic[63:0]completion_session,completion_sequence,
    input logic result_valid,input logic[31:0]result_word0,result_word1,
    output logic submit_allowed,reclaimable,
    output logic[2:0]object_state,
    output logic[8:0]built_tokens,decode_steps,
    output logic bound_pair,task_reference,
    output logic[31:0]object_id,object_generation
);
    localparam [2:0] EMPTY=0,BUILDING=1,SEALED=2,RETIRING=3,FAILED=4;
    logic used_slot,ever_bound,complete_seen,complete_ok,pending_build;
    logic[63:0]object_session,pending_session,pending_sequence;
    logic[31:0]last_error,guard_reason;
    wire session_good=session_valid&&request_session==session_value;
    wire key_good=session_good&&object_session==session_value&&proposed_context==object_id&&proposed_generation==object_generation;
    wire busy=task_reference||active||completion_valid||loader_busy||!fabric_idle;
    wire build_program=loaded_addr==BUILD_ADDR&&loaded_count==BUILD_INSNS;
    wire decode_program=loaded_addr==DECODE_ADDR&&loaded_count==DECODE_INSNS;
    wire[31:0]p={23'b0,built_tokens},t={23'b0,decode_steps};
    wire build_args_ok=proposed_args[0]==0&&proposed_args[1]==(32'b0-(p<<2))&&proposed_args[2]==KV_BASE&&
        proposed_args[3]==KV_BASE+p&&proposed_args[4]==KV_BASE+(p<<2)&&proposed_args[5]==KV_BASE+(p<<7)&&
        proposed_args[6]==(p<<2)&&proposed_args[7]==(p<<8);
    wire decode_args_ok=proposed_args[0]==(32'b0-(t<<2))&&proposed_args[1]==KV_BASE&&
        proposed_args[2]==KV_BASE+t&&proposed_args[3]==KV_BASE+(t<<2)&&proposed_args[4]==KV_BASE+(t<<7)&&
        proposed_args[5][11:0]==0&&(proposed_args[5]>>12)<151936&&proposed_args[6]==(t<<8)&&
        proposed_args[7][11:0]==0&&(proposed_args[7]>>12)<151936;
    always_comb begin
        submit_allowed=0;guard_reason=0;
        if(!key_good||object_state==EMPTY)guard_reason=1;
        else if(busy)guard_reason=2;
        else if(build_program)begin
            if(object_state!=BUILDING||built_tokens>252)guard_reason=3;
            else if(!build_args_ok)guard_reason=5;
            else submit_allowed=1;
        end else if(decode_program)begin
            if(object_state!=SEALED||!bound_pair||decode_steps>=256)guard_reason=3;
            else if(!decode_args_ok)guard_reason=5;
            else submit_allowed=1;
        end else guard_reason=4;
    end
    assign reclaimable=object_state==EMPTY&&used_slot&&!busy&&!bound_pair;
    always_ff @(posedge clk)begin
        if(reset)begin
            bus_ready<=0;bus_rdata<=0;last_error<=0;object_state<=EMPTY;
            object_id<=0;object_generation<=0;object_session<=0;built_tokens<=0;decode_steps<=0;
            bound_pair<=0;task_reference<=0;used_slot<=0;ever_bound<=0;complete_seen<=0;complete_ok<=0;
            pending_build<=0;pending_session<=0;pending_sequence<=0;
        end else begin
            bus_ready<=0;
            if(accepted_event)begin
                task_reference<=1;pending_build<=build_program;
                pending_session<=completion_session;pending_sequence<=completion_sequence;
                complete_seen<=0;complete_ok<=0;
            end
            if(task_reference&&completion_valid&&!complete_seen)begin
                complete_seen<=1;
                complete_ok<=completion_status==0&&result_valid&&completion_session==pending_session&&
                    completion_sequence==pending_sequence&&completion_context==object_id&&completion_generation==object_generation&&
                    (!pending_build||(result_word0==32'h3f800000&&result_word1==32'h40800000));
            end
            if(consumed_event&&task_reference)begin
                task_reference<=0;complete_seen<=0;
                if(complete_seen&&complete_ok)begin
                    if(pending_build)built_tokens<=built_tokens+9'd4;
                    else decode_steps<=decode_steps+1'b1;
                end else if(object_state!=RETIRING)object_state<=FAILED;
            end
            if(object_state==RETIRING&&!task_reference&&!bound_pair&&!active&&!completion_valid&&!loader_busy&&fabric_idle)
                object_state<=EMPTY;
            if(bus_valid&&!bus_ready)begin
                bus_ready<=1;bus_rdata<=0;
                if(bus_addr[1:0]!=0||((|bus_wstrb)&&bus_wstrb!=4'hf))last_error<=8;
                else if(bus_wstrb==0)begin
                    case(bus_addr)
                      12'h204:bus_rdata<={20'b0,used_slot,complete_seen,task_reference,bound_pair,5'b0,object_state};
                      12'h208:bus_rdata<=last_error;
                      12'h20c:bus_rdata<=p;
                      12'h210:bus_rdata<=bound_pair?2:0;
                      12'h214:bus_rdata<=t;
                      12'h218:bus_rdata<=object_id;
                      12'h21c:bus_rdata<=object_generation;
                      12'h220:bus_rdata<=256;
                      12'h224:bus_rdata<=KV_BASE;
                      12'h228:bus_rdata<={31'b0,reclaimable};
                      12'h22c:bus_rdata<=guard_reason;
                      default:last_error<=8;
                    endcase
                end else if(bus_addr!=12'h200)last_error<=8;
                else if(!session_good)last_error<=1;
                else if(bus_wdata==1)begin // REGISTER/BEGIN; no dirty-slot reuse in this pilot
                    if(object_state!=EMPTY||used_slot)last_error<=2;
                    else if(busy)last_error<=3;
                    else if(proposed_context==0||proposed_generation==0)last_error<=1;
                    else begin
                        object_id<=proposed_context;object_generation<=proposed_generation;object_session<=session_value;
                        object_state<=BUILDING;used_slot<=1;built_tokens<=0;decode_steps<=0;last_error<=0;
                    end
                end else if(!key_good||object_state==EMPTY)last_error<=1;
                else begin
                    case(bus_wdata)
                      2:begin // SEAL after all successful build completions were consumed
                          if(object_state!=BUILDING)last_error<=2;
                          else if(busy)last_error<=3;
                          else if(built_tokens!=256)last_error<=4;
                          else begin object_state<=SEALED;last_error<=0;end
                      end
                      3:begin // Bind one pair to the single sealed physical prefix
                          if(object_state!=SEALED||bound_pair||ever_bound)last_error<=2;
                          else if(busy)last_error<=3;
                          else begin bound_pair<=1;ever_bound<=1;decode_steps<=0;last_error<=0;end
                      end
                      4:begin // Release pair only after its in-flight task/CQ was consumed
                          if(!bound_pair)last_error<=2;
                          else if(busy)last_error<=3;
                          else begin bound_pair<=0;last_error<=0;end
                      end
                      5:begin // Retire request can wait on outstanding computation/bindings
                          if(object_state==RETIRING)last_error<=2;
                          else begin object_state<=RETIRING;last_error<=0;end
                      end
                      default:last_error<=8;
                    endcase
                end
            end
        end
    end
endmodule
