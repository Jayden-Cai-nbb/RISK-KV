// RNP2 extension: actual loader handshake + accepted-write token mailbox.
// The mailbox publishes only after completion AND the fabric retirement contract.
module rkv_npu_io_control #(
    parameter int D=128,
    parameter logic [31:0] PROGRAM_BASE=32'h60000000,
    parameter logic [31:0] PROGRAM_LIMIT=32'h60020000,
    parameter logic [31:0] RESULT_ADDR=32'd1229289344
)(
    input logic clk,reset,bus_valid,
    input logic[11:0]bus_addr,
    input logic[31:0]bus_wdata,
    input logic[3:0]bus_wstrb,
    output logic bus_ready,
    output logic[31:0]bus_rdata,
    input logic npu_halted,npu_error,fabric_idle,fabric_error,loader_busy,
    output logic loader_start,
    output logic[31:0]loader_addr,loader_count,
    input logic result_store_valid,result_other_write,
    input logic[31:0]result_store_addr,
    input logic[D*8-1:0]result_store_data,
    input logic[D/4-1:0]result_store_mask,
    output logic npu_reset,
    output logic[31:0]npu_args[8],
    output logic completion_valid,active,launch_pulse,program_ready,result_valid,
    output logic[31:0]completion_status,completion_context,completion_generation,
    output logic[63:0]completion_session,completion_sequence,
    output logic[31:0]accepted_count,rejected_count,
    output logic[31:0]result_token0,result_token1,
    input logic submit_allowed,
    output logic observed_session_valid,
    output logic[63:0]observed_session,request_session,
    output logic[31:0]proposed_context,proposed_generation,proposed_args[8],loaded_program_addr,loaded_program_count,
    output logic accepted_event,consumed_event
);
    localparam [2:0] L_IDLE=0,L_WAIT=1,L_ACTIVE=2,L_DRAIN=3;
    localparam [31:0] RESULT_WORD=RESULT_ADDR>>2;
    logic[2:0]load_state;
    logic[31:0]shadow_addr,shadow_count,io_error,loaded_addr,loaded_count;
    logic[1:0]load_written,seen;
    logic loaded,io_fault,quiet_previous,active_previous;
    logic ext_ready,core_ready;logic[31:0]ext_rdata,core_rdata;
    wire ext_select=bus_addr>=12'h100;
    wire fire=bus_valid&&ext_select&&!ext_ready;
    wire write_access=|bus_wstrb;
    wire idle_control=npu_reset&&!active&&!completion_valid;
    wire[32:0]rounded_bytes=(({1'b0,shadow_count}+33'd3)>>2)<<7;
    wire[32:0]load_end={1'b0,shadow_addr}+rounded_bytes;
    initial if(D!=128)$fatal(1,"RNP2 pilot requires the frozen D=128 memory port");
    assign loaded_program_addr=loaded_addr;
    assign loaded_program_count=loaded_count;
    assign program_ready=loaded&&load_state==L_IDLE&&!io_fault;
    assign result_valid=completion_valid&&completion_status==0&&seen==2'b11&&!io_fault;
    assign bus_ready=ext_select?ext_ready:core_ready;
    assign bus_rdata=ext_select?ext_rdata:((bus_addr==0)?32'h524e5032:core_rdata);
    rkv_npu_control core(.clk,.reset,.bus_valid(bus_valid&&!ext_select),.bus_addr,.bus_wdata,.bus_wstrb,
        .bus_ready(core_ready),.bus_rdata(core_rdata),.npu_halted,.npu_error(npu_error||io_fault||fabric_error),
        .fabric_idle,.loader_busy,.program_ready,.npu_reset,.npu_args,.completion_valid,.completion_status,
        .completion_session,.completion_sequence,.completion_context,.completion_generation,
        .active,.launch_pulse,.accepted_count,.rejected_count,.submit_allowed,.observed_session_valid,.observed_session,
        .request_session,.proposed_context,.proposed_generation,.proposed_args,.accepted_event,.consumed_event);
    always_ff @(posedge clk)begin
        if(reset)begin
            load_state<=L_IDLE;shadow_addr<=0;shadow_count<=0;load_written<=0;
            loader_start<=0;loader_addr<=0;loader_count<=0;loaded<=0;loaded_addr<=0;loaded_count<=0;
            io_error<=0;io_fault<=0;quiet_previous<=0;active_previous<=0;seen<=0;
            result_token0<=0;result_token1<=0;ext_ready<=0;ext_rdata<=0;
        end else begin
            loader_start<=0;ext_ready<=0;
            quiet_previous<=fabric_idle&&!loader_busy;active_previous<=active;
            if(fabric_error)io_fault<=1;
            if(load_state==L_WAIT&&loader_busy)load_state<=L_ACTIVE;
            if(load_state==L_ACTIVE&&!loader_busy)load_state<=L_DRAIN;
            if(load_state==L_DRAIN&&fabric_idle&&quiet_previous&&!loader_busy)begin
                loaded<=!io_fault&&!fabric_error;load_state<=L_IDLE;
                loaded_addr<=loader_addr;loaded_count<=loader_count;
            end
            if(active&&!active_previous)begin
                seen<=0;result_token0<=0;result_token1<=0;
            end
            if(result_store_valid)begin
                for(int w=0;w<D/4;w++)begin
                    if(result_store_mask[w]&&(result_store_addr+32'(w)==RESULT_WORD||result_store_addr+32'(w)==RESULT_WORD+1))begin
                        if(!active||npu_reset||seen[result_store_addr+32'(w)==RESULT_WORD+1])io_fault<=1;
                        else begin
                            if(result_store_addr+32'(w)==RESULT_WORD)begin result_token0<=result_store_data[w*32+:32];seen[0]<=1;end
                            else begin result_token1<=result_store_data[w*32+:32];seen[1]<=1;end
                        end
                    end
                end
            end
            if(result_other_write)io_fault<=1;
            if(completion_valid&&completion_status==0&&seen!=2'b11)io_fault<=1;
            if(completion_valid&&completion_status==2)io_fault<=1;
            if(fire)begin
                ext_ready<=1;ext_rdata<=0;
                if(bus_addr[1:0]!=0||(write_access&&bus_wstrb!=4'hf))io_error<=1;
                else if(!write_access)begin
                    case(bus_addr)
                      12'h100:ext_rdata<=shadow_addr;
                      12'h104:ext_rdata<=shadow_count;
                      12'h10c:ext_rdata<={29'b0,io_fault,(load_state!=L_IDLE||loader_busy),program_ready};
                      12'h110:ext_rdata<=io_error;
                      12'h114:ext_rdata<=loaded_addr;
                      12'h118:ext_rdata<=loaded_count;
                      12'h120:ext_rdata<={28'b0,seen,io_fault,result_valid};
                      12'h124:begin if(result_valid)begin ext_rdata<=result_token0;io_error<=0;end else io_error<=6;end
                      12'h128:begin if(result_valid)begin ext_rdata<=result_token1;io_error<=0;end else io_error<=6;end
                      default:io_error<=2;
                    endcase
                end else if(bus_addr==12'h100||bus_addr==12'h104)begin
                    if(!idle_control||load_state!=L_IDLE||loader_busy)io_error<=4;
                    else if(io_fault)io_error<=7;
                    else if(bus_addr==12'h100)begin shadow_addr<=bus_wdata;load_written[0]<=1;io_error<=0;end
                    else begin shadow_count<=bus_wdata;load_written[1]<=1;io_error<=0;end
                end else if(bus_addr==12'h108&&bus_wdata==1)begin
                    if(!idle_control||load_state!=L_IDLE||loader_busy||!fabric_idle||!quiet_previous)io_error<=4;
                    else if(io_fault)io_error<=7;
                    else if(load_written!=2'b11)io_error<=5;
                    else if(shadow_count==0||shadow_count>4096||shadow_addr[6:0]!=0||shadow_addr<PROGRAM_BASE||load_end>{1'b0,PROGRAM_LIMIT})io_error<=3;
                    else begin
                        loaded<=0;loader_addr<=shadow_addr;loader_count<=shadow_count;
                        loader_start<=1;load_state<=L_WAIT;load_written<=0;io_error<=0;
                    end
                end else io_error<=2;
            end
        end
    end
endmodule
