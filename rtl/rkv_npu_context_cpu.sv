// RV32I boot RAM + native-MMIO control. Same clock as the NPU control domain.
// Test-result port is separate from the NPU interface; not a host transport.
module rkv_npu_context_cpu #(
    parameter string FIRMWARE="",
    parameter logic[31:0] RESULT_ADDR=32'd1229289088
) (
    input logic clk,reset,
    input logic npu_halted,npu_error,fabric_idle,fabric_error,loader_busy,
    output logic loader_start,
    output logic[31:0]loader_addr,loader_count,
    input logic result_store_valid,result_other_write,
    input logic[31:0]result_store_addr,
    input logic[1023:0]result_store_data,
    input logic[31:0]result_store_mask,
    output logic program_ready,result_valid,
    output logic[31:0]result_token0,result_token1,
    output logic token_trace_valid,token_trace_row,
    output logic[31:0]token_trace_data,
    output logic npu_reset,
    output logic [31:0] npu_args[8],
    output logic trap,test_done,
    output logic [31:0] test_code,
    output logic completion_valid,active,launch_pulse,
    output logic [31:0] completion_status,completion_context,completion_generation,
    output logic [63:0] completion_session,completion_sequence,
    output logic [31:0] accepted_count,rejected_count
);
    logic valid,instr,ready;logic [31:0] addr,wdata,rdata;logic [3:0] wstrb;
    wire ram_select=addr[31:16]==0;
    wire control_select=addr[31:12]==20'h40000;
    wire result_select=addr==32'h50000000;
    logic ram_ready;logic[31:0] ram_rdata;
    logic control_ready;logic[31:0] control_rdata;
    logic [31:0] ram[16384];
    string image;
    initial begin
        for(int i=0;i<16384;i++)ram[i]=0;
        image=FIRMWARE;
`ifndef SYNTHESIS
        if(image=="")void'($value$plusargs("firmware=%s",image));
`endif
        if(image!="")$readmemh(image,ram);
    end
    always_ff @(posedge clk) begin
        if(reset)begin ram_ready<=0;ram_rdata<=0;test_done<=0;test_code<=0;token_trace_valid<=0;token_trace_row<=0;token_trace_data<=0;end
        else begin
            ram_ready<=0;token_trace_valid<=0;
            if(valid&&!control_select&&!ram_ready)begin
                ram_ready<=1;ram_rdata<=0;
                if(ram_select)begin
                    ram_rdata<=ram[addr[15:2]];
                    for(int b=0;b<4;b++)if(wstrb[b])ram[addr[15:2]][b*8+:8]<=wdata[b*8+:8];
                end else if((addr==32'h50000010||addr==32'h50000014)&&wstrb==4'hf)begin
                    token_trace_valid<=1;token_trace_row<=addr[2];token_trace_data<=wdata;
                end else if(result_select&&wstrb==4'hf)begin test_done<=1;test_code<=wdata;end
                else begin test_done<=1;test_code<=32'hbad00001;end
            end
        end
    end
    assign ready=control_select?control_ready:ram_ready;
    assign rdata=control_select?control_rdata:ram_rdata;
    picorv32 #(.PROGADDR_RESET(0),.STACKADDR(32'h10000),.ENABLE_COUNTERS(1),.ENABLE_COUNTERS64(1),
        .COMPRESSED_ISA(0),.ENABLE_MUL(0),.ENABLE_DIV(0),.ENABLE_IRQ(0)) cpu(
        .clk,.resetn(!reset),.trap,.mem_valid(valid),.mem_instr(instr),.mem_ready(ready),
        .mem_addr(addr),.mem_wdata(wdata),.mem_wstrb(wstrb),.mem_rdata(rdata),
        .mem_la_read(),.mem_la_write(),.mem_la_addr(),.mem_la_wdata(),.mem_la_wstrb(),
        .pcpi_valid(),.pcpi_insn(),.pcpi_rs1(),.pcpi_rs2(),.pcpi_wr(1'b0),.pcpi_rd(32'b0),
        .pcpi_wait(1'b0),.pcpi_ready(1'b0),.irq(32'b0),.eoi(),.trace_valid(),.trace_data());
    rkv_npu_context_service #(.RESULT_ADDR(RESULT_ADDR),.KV_BASE(32'd1233223680),.BUILD_INSNS(1026),.DECODE_INSNS(1004)) control(.clk,.reset,.bus_valid(valid&&control_select),.bus_addr(addr[11:0]),
        .bus_wdata(wdata),.bus_wstrb(wstrb),.bus_ready(control_ready),.bus_rdata(control_rdata),
        .npu_halted,.npu_error,.fabric_idle,.fabric_error,.loader_busy,.loader_start,.loader_addr,.loader_count,
        .result_store_valid,.result_other_write,.result_store_addr,.result_store_data,.result_store_mask,
        .program_ready,.result_valid,.result_token0,.result_token1,.npu_reset,.npu_args,
        .completion_valid,.completion_status,.completion_session,.completion_sequence,
        .completion_context,.completion_generation,.active,.launch_pulse,.accepted_count,.rejected_count);
endmodule
