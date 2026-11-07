// 仅协议测试：加载时真实读取A，运行时真实写入B；固定数据不代表模型计算。
// 无模型计算，禁止把本夹具输出当KV/logits或现场演示。
module rkv_m1_compute (
    input logic clk,
    input logic clk_f,
    input logic cold_reset,
    input logic npu_reset,
    input logic [31:0] npu_args [8],
    input logic loader_start,
    input logic [31:0] loader_addr,
    input logic [31:0] loader_count,
    output logic loader_busy,
    input logic wr_idle,
    input logic rd_idle,
    output logic halted,
    output logic error,
    output logic a_inval,
    output logic [31:0] icount,
    input logic dump,
    output logic a_req,
    output logic a_we,
    output logic [31:0] a_addr,
    output logic [31:0] a_wdata,
    output logic [3:0] a_be,
    input logic a_rdy,
    input logic a_rvalid,
    input logic [255:0] a_rdata,
    output logic sw_req,
    output logic [31:0] sw_addr,
    output logic [31:0] sw_wdata,
    output logic [3:0] sw_be,
    input logic sw_rdy,
    output logic b_req,
    output logic b_we,
    output logic b_tag,
    output logic b_par,
    output logic [31:0] b_addr,
    output logic [1023:0] b_wdata,
    output logic [31:0] b_wmask,
    input logic b_rdy,
    input logic b_rvalid,
    input logic b_rtag,
    input logic [1023:0] b_rdata
);
    import rkv_m1_layout_pkg::*;
    integer run_count=0,load_count=0,load_returns=0;
    logic [255:0] last_load;
    logic result_sent=0;
    logic sw_sent=0;
    assign halted=!npu_reset && run_count>=2000 && result_sent && sw_sent;
    assign error=0;assign a_inval=0;assign icount=32'(run_count);
    assign a_req=loader_busy && load_count==1;assign a_we=0;assign a_addr=32'h10000/4;assign a_wdata=0;assign a_be=0;
    // 仅测试：标量字节掩码写通过真实聚合器；不是模型输出。
    assign sw_req=!npu_reset && !sw_sent;assign sw_addr=32'h20000/4;assign sw_wdata=32'h7fc12345;assign sw_be=4'b1011;
    assign b_req=!npu_reset && run_count>=9 && !result_sent;
    assign b_we=1;assign b_tag=0;assign b_par=0;assign b_addr=RESULT_ADDRESS>>2;
    assign b_wdata={960'd0,32'h40800000,32'h3f800000};assign b_wmask=32'd3;
    always @(posedge clk)begin
        if(cold_reset)begin run_count<=0;result_sent<=0;sw_sent<=0;load_count<=0;loader_busy<=0;load_returns<=0;last_load<=0;end
        else begin
            if(loader_start)begin load_count<=1;loader_busy<=1;end
            else if(load_count==1 && a_req && a_rdy)load_count<=2;
            else if(load_count==2 && a_rvalid)begin load_count<=0;loader_busy<=0;last_load<=a_rdata;load_returns<=load_returns+1;end
            if(npu_reset)begin run_count<=0;result_sent<=0;sw_sent<=0;end
            else begin if(run_count<2000)run_count<=run_count+1;if(b_req&&b_rdy)result_sent<=1;if(sw_req&&sw_rdy)sw_sent<=1;end
        end
    end
endmodule
