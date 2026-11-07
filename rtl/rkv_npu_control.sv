// Single-task NPU controller. Native PicoRV32-style synchronous MMIO.
// fabric_idle must mean all accepted reads/writes and port registers are retired.
// Cancel drains to natural halt; faults require cold reset after completion ACK.
module rkv_npu_control (
    input logic clk, reset,
    input logic bus_valid,
    input logic [11:0] bus_addr,
    input logic [31:0] bus_wdata,
    input logic [3:0] bus_wstrb,
    output logic bus_ready,
    output logic [31:0] bus_rdata,
    input logic npu_halted, npu_error, fabric_idle, loader_busy, program_ready,
    output logic npu_reset,
    output logic [31:0] npu_args [8],
    output logic completion_valid,
    output logic [31:0] completion_status,
    output logic [63:0] completion_session, completion_sequence,
    output logic [31:0] completion_context, completion_generation,
    output logic active, launch_pulse,
    output logic [31:0] accepted_count, rejected_count,
    input logic submit_allowed,
    output logic observed_session_valid,
    output logic[63:0]observed_session,request_session,
    output logic[31:0]proposed_context,proposed_generation,proposed_args[8],
    output logic accepted_event,consumed_event
);
    localparam [2:0] IDLE=0, ARM=1, RUN=2, DONE=3;
    logic [2:0] state;
    logic [2:0] arm_count;
    logic [31:0] staged_args [8];
    logic [7:0] arg_written;
    logic [63:0] staged_session, session, next_sequence;
    logic [63:0] token_session, token_sequence;
    logic [31:0] staged_context, staged_generation, last_error;
    logic session_valid, exhausted, faulted, cancelled, error_seen;
    logic quiet_previous;
    assign observed_session_valid=session_valid;
    assign observed_session=session;
    assign request_session=token_session;
    assign proposed_context=staged_context;
    assign proposed_generation=staged_generation;
    for(genvar i=0;i<8;i++)assign proposed_args[i]=staged_args[i];
    wire write_access=|bus_wstrb;
    wire full_write=bus_wstrb==4'hf;
    wire transfer=bus_valid&&!bus_ready;
    wire same_identity=token_session==completion_session&&token_sequence==completion_sequence;
    assign active=state==ARM||state==RUN;
    assign npu_reset=reset||state==IDLE||state==ARM||state==DONE;
    assign completion_valid=state==DONE;
    // First ARM cycle copies the frozen arguments into the sequencer. Three
    // cycles of reset allow them to be sampled; memory remains independently live.
    always_ff @(posedge clk) begin
        if (reset) begin
            state<=IDLE;arm_count<=0;bus_ready<=0;bus_rdata<=0;
            staged_session<=0;session<=0;session_valid<=0;next_sequence<=1;
            token_session<=0;token_sequence<=0;staged_context<=0;staged_generation<=0;
            completion_session<=0;completion_sequence<=0;completion_context<=0;completion_generation<=0;
            completion_status<=0;arg_written<=0;exhausted<=0;faulted<=0;cancelled<=0;error_seen<=0;
            quiet_previous<=0;last_error<=0;launch_pulse<=0;accepted_count<=0;rejected_count<=0;accepted_event<=0;consumed_event<=0;
            for (int i=0;i<8;i++) begin staged_args[i]<=0;npu_args[i]<=0;end
        end else begin
            bus_ready<=0;launch_pulse<=0;accepted_event<=0;consumed_event<=0;
            quiet_previous<=fabric_idle&&!loader_busy;
            if (state==ARM) begin
                if (arm_count==2) begin state<=RUN;launch_pulse<=1;end
                else arm_count<=arm_count+1'b1;
            end
            if (state==RUN) begin
                if (npu_error) error_seen<=1;
                if (npu_halted&&fabric_idle&&quiet_previous&&!loader_busy) begin
                    state<=DONE;
                    completion_status<=(error_seen||npu_error)?32'd2:(cancelled?32'd1:32'd0);
                    if (error_seen||npu_error) faulted<=1;
                end
            end
            if (transfer) begin
                bus_ready<=1;bus_rdata<=0;
                if (bus_addr[1:0]!=0 || (write_access&&!full_write)) begin
                    last_error<=1;rejected_count<=rejected_count+1'b1;
                end else if (!write_access) begin
                    case(bus_addr)
                      12'h000:bus_rdata<=32'h524e5031; // RNP1 experimental interface
                      12'h004:bus_rdata<={26'b0,exhausted,faulted,session_valid,completion_valid,active,state==IDLE};
                      12'h008:bus_rdata<=last_error;
                      12'h010:bus_rdata<=session[31:0];
                      12'h014:bus_rdata<=session[63:32];
                      12'h018:bus_rdata<=next_sequence[31:0];
                      12'h01c:bus_rdata<=next_sequence[63:32];
                      12'h080:bus_rdata<=completion_status;
                      12'h084:bus_rdata<=completion_session[31:0];
                      12'h088:bus_rdata<=completion_session[63:32];
                      12'h08c:bus_rdata<=completion_sequence[31:0];
                      12'h090:bus_rdata<=completion_sequence[63:32];
                      12'h094:bus_rdata<=completion_context;
                      12'h098:bus_rdata<=completion_generation;
                      12'h09c:bus_rdata<=accepted_count;
                      12'h0a0:bus_rdata<=rejected_count;
                      12'h0a4:bus_rdata<={29'b0,program_ready,loader_busy,fabric_idle};
                      default:begin last_error<=2;rejected_count<=rejected_count+1'b1;end
                    endcase
                end else if (bus_addr==12'h020) token_session[31:0]<=bus_wdata;
                else if (bus_addr==12'h024) token_session[63:32]<=bus_wdata;
                else if (bus_addr==12'h028) token_sequence[31:0]<=bus_wdata;
                else if (bus_addr==12'h02c) token_sequence[63:32]<=bus_wdata;
                else if (bus_addr==12'h00c) begin
                    // Commands: 1 SET_SESSION, 2 SUBMIT, 3 ACK, 4 CANCEL.
                    case(bus_wdata)
                      1:begin
                          if (state!=IDLE||session_valid||staged_session==0) begin last_error<=3;rejected_count<=rejected_count+1'b1;end
                          else begin session<=staged_session;session_valid<=1;last_error<=0;end
                      end
                      2:begin
                          if (state!=IDLE||faulted||exhausted) begin last_error<=4;rejected_count<=rejected_count+1'b1;end
                          else if (!session_valid||token_session!=session||token_sequence!=next_sequence) begin last_error<=5;rejected_count<=rejected_count+1'b1;end
                          else if (arg_written!=8'hff||!program_ready||loader_busy||!fabric_idle||!quiet_previous) begin last_error<=6;rejected_count<=rejected_count+1'b1;end
                          else if(!submit_allowed)begin last_error<=9;rejected_count<=rejected_count+1'b1;end
                          else begin
                              for(int i=0;i<8;i++)npu_args[i]<=staged_args[i];
                              completion_session<=session;completion_sequence<=next_sequence;
                              completion_context<=staged_context;completion_generation<=staged_generation;
                              if (&next_sequence) exhausted<=1;else next_sequence<=next_sequence+1'b1;
                              cancelled<=0;error_seen<=0;completion_status<=0;arm_count<=0;
                              state<=ARM;arg_written<=0;last_error<=0;accepted_count<=accepted_count+1'b1;accepted_event<=1;
                          end
                      end
                      3:begin
                          if (state!=DONE||!same_identity) begin last_error<=7;rejected_count<=rejected_count+1'b1;end
                          else begin state<=IDLE;last_error<=0;consumed_event<=1;end
                      end
                      4:begin
                          if (!active||!same_identity) begin last_error<=8;rejected_count<=rejected_count+1'b1;end
                          else begin
                              cancelled<=1;last_error<=0;
                              // Cancel accepted at the same edge as retirement wins
                              // over successful completion, but not execution error.
                              if (state==RUN&&npu_halted&&fabric_idle&&quiet_previous&&!loader_busy&&!(error_seen||npu_error))
                                  completion_status<=1;
                          end
                      end
                      default:begin last_error<=2;rejected_count<=rejected_count+1'b1;end
                    endcase
                end else if (state!=IDLE||faulted) begin
                    last_error<=4;rejected_count<=rejected_count+1'b1;
                end else if (bus_addr>=12'h040&&bus_addr<12'h060) begin
                    staged_args[bus_addr[4:2]]<=bus_wdata;arg_written[bus_addr[4:2]]<=1;
                end else begin
                    case(bus_addr)
                      12'h010:begin
                          if (session_valid)begin last_error<=3;rejected_count<=rejected_count+1'b1;end
                          else staged_session[31:0]<=bus_wdata;
                      end
                      12'h014:begin
                          if (session_valid)begin last_error<=3;rejected_count<=rejected_count+1'b1;end
                          else staged_session[63:32]<=bus_wdata;
                      end
                      12'h030:staged_context<=bus_wdata;
                      12'h034:staged_generation<=bus_wdata;
                      default:begin last_error<=2;rejected_count<=rejected_count+1'b1;end
                    endcase
                end
            end
        end
    end
endmodule
