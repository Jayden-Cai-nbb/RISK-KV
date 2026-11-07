// 启动检查器向服务平台单向移交DDR；普通复位不能改变master归属。
module rkv_m1_boot_mux (
    input wire clk,
    input wire release_request,
    input wire qualified,
    input wire qualification_idle,
    input wire health_fault,
    output reg service_mode = 1'b0,
    output reg switch_fault = 1'b0,
    input wire [3:0] q_awid,
    input wire [32:0] q_awaddr,
    input wire [7:0] q_awlen,
    input wire [2:0] q_awsize,
    input wire [1:0] q_awburst,
    input wire q_awlock,
    input wire [3:0] q_awcache,
    input wire [2:0] q_awprot,
    input wire [3:0] q_awqos,
    input wire q_awvalid,
    input wire [511:0] q_wdata,
    input wire [63:0] q_wstrb,
    input wire q_wlast,
    input wire q_wvalid,
    input wire q_bready,
    input wire [3:0] q_arid,
    input wire [32:0] q_araddr,
    input wire [7:0] q_arlen,
    input wire [2:0] q_arsize,
    input wire [1:0] q_arburst,
    input wire q_arlock,
    input wire [3:0] q_arcache,
    input wire [2:0] q_arprot,
    input wire [3:0] q_arqos,
    input wire q_arvalid,
    input wire q_rready,
    output wire q_awready,
    output wire q_wready,
    output wire [3:0] q_bid,
    output wire [1:0] q_bresp,
    output wire q_bvalid,
    output wire q_arready,
    output wire [3:0] q_rid,
    output wire [511:0] q_rdata,
    output wire [1:0] q_rresp,
    output wire q_rlast,
    output wire q_rvalid,
    input wire [3:0] s_awid,
    input wire [32:0] s_awaddr,
    input wire [7:0] s_awlen,
    input wire [2:0] s_awsize,
    input wire [1:0] s_awburst,
    input wire s_awlock,
    input wire [3:0] s_awcache,
    input wire [2:0] s_awprot,
    input wire [3:0] s_awqos,
    input wire s_awvalid,
    input wire [511:0] s_wdata,
    input wire [63:0] s_wstrb,
    input wire s_wlast,
    input wire s_wvalid,
    input wire s_bready,
    input wire [3:0] s_arid,
    input wire [32:0] s_araddr,
    input wire [7:0] s_arlen,
    input wire [2:0] s_arsize,
    input wire [1:0] s_arburst,
    input wire s_arlock,
    input wire [3:0] s_arcache,
    input wire [2:0] s_arprot,
    input wire [3:0] s_arqos,
    input wire s_arvalid,
    input wire s_rready,
    output wire s_awready,
    output wire s_wready,
    output wire [3:0] s_bid,
    output wire [1:0] s_bresp,
    output wire s_bvalid,
    output wire s_arready,
    output wire [3:0] s_rid,
    output wire [511:0] s_rdata,
    output wire [1:0] s_rresp,
    output wire s_rlast,
    output wire s_rvalid,
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
    output wire [511:0] m_wdata,
    output wire [63:0] m_wstrb,
    output wire m_wlast,
    output wire m_wvalid,
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
    output wire m_rready,
    input wire m_awready,
    input wire m_wready,
    input wire [3:0] m_bid,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    input wire m_arready,
    input wire [3:0] m_rid,
    input wire [511:0] m_rdata,
    input wire [1:0] m_rresp,
    input wire m_rlast,
    input wire m_rvalid
);
    // 接收沿必须无新请求、无未消费返回；外部idle还包含已发请求和peek责任。
    wire channels_quiet = !q_awvalid && !q_wvalid && !q_arvalid && !m_bvalid && !m_rvalid;
    always @(posedge clk) begin
        if (health_fault) switch_fault <= 1'b1;
        if (release_request && !service_mode && !switch_fault) begin
            if (qualified && qualification_idle && channels_quiet && !health_fault)
                service_mode <= 1'b1;
            else switch_fault <= 1'b1;
        end
    end
    // 错误不撤销VALID或丢弃响应；保留原master以完成真实退休。
    assign m_awid = service_mode ? s_awid : q_awid;
    assign m_awaddr = service_mode ? s_awaddr : q_awaddr;
    assign m_awlen = service_mode ? s_awlen : q_awlen;
    assign m_awsize = service_mode ? s_awsize : q_awsize;
    assign m_awburst = service_mode ? s_awburst : q_awburst;
    assign m_awlock = service_mode ? s_awlock : q_awlock;
    assign m_awcache = service_mode ? s_awcache : q_awcache;
    assign m_awprot = service_mode ? s_awprot : q_awprot;
    assign m_awqos = service_mode ? s_awqos : q_awqos;
    assign m_awvalid = service_mode ? s_awvalid : q_awvalid;
    assign m_wdata = service_mode ? s_wdata : q_wdata;
    assign m_wstrb = service_mode ? s_wstrb : q_wstrb;
    assign m_wlast = service_mode ? s_wlast : q_wlast;
    assign m_wvalid = service_mode ? s_wvalid : q_wvalid;
    assign m_bready = service_mode ? s_bready : q_bready;
    assign m_arid = service_mode ? s_arid : q_arid;
    assign m_araddr = service_mode ? s_araddr : q_araddr;
    assign m_arlen = service_mode ? s_arlen : q_arlen;
    assign m_arsize = service_mode ? s_arsize : q_arsize;
    assign m_arburst = service_mode ? s_arburst : q_arburst;
    assign m_arlock = service_mode ? s_arlock : q_arlock;
    assign m_arcache = service_mode ? s_arcache : q_arcache;
    assign m_arprot = service_mode ? s_arprot : q_arprot;
    assign m_arqos = service_mode ? s_arqos : q_arqos;
    assign m_arvalid = service_mode ? s_arvalid : q_arvalid;
    assign m_rready = service_mode ? s_rready : q_rready;
    assign q_awready = !service_mode && m_awready;
    assign s_awready = service_mode && m_awready;
    assign q_wready = !service_mode && m_wready;
    assign s_wready = service_mode && m_wready;
    assign q_bid = m_bid;
    assign s_bid = m_bid;
    assign q_bresp = m_bresp;
    assign s_bresp = m_bresp;
    assign q_bvalid = !service_mode && m_bvalid;
    assign s_bvalid = service_mode && m_bvalid;
    assign q_arready = !service_mode && m_arready;
    assign s_arready = service_mode && m_arready;
    assign q_rid = m_rid;
    assign s_rid = m_rid;
    assign q_rdata = m_rdata;
    assign s_rdata = m_rdata;
    assign q_rresp = m_rresp;
    assign s_rresp = m_rresp;
    assign q_rlast = m_rlast;
    assign s_rlast = m_rlast;
    assign q_rvalid = !service_mode && m_rvalid;
    assign s_rvalid = service_mode && m_rvalid;
endmodule
