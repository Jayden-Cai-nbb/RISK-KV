// 实验性完整NPU板级顶层；启动DDR资格检查与服务单向互斥。
module rkv_m1_board_top #(
    parameter [63:0] EXPERIMENT_ID = 64'd0
) (
    input wire sys_rst_n,
    input wire c0_sys_clk_p,
    input wire c0_sys_clk_n,
    output wire c0_ddr4_act_n,
    output wire [16:0] c0_ddr4_adr,
    output wire [1:0] c0_ddr4_ba,
    output wire [1:0] c0_ddr4_bg,
    output wire [0:0] c0_ddr4_cke,
    output wire [0:0] c0_ddr4_odt,
    output wire [0:0] c0_ddr4_cs_n,
    output wire [0:0] c0_ddr4_ck_t,
    output wire [0:0] c0_ddr4_ck_c,
    output wire c0_ddr4_reset_n,
    inout wire [7:0] c0_ddr4_dm_dbi_n,
    inout wire [63:0] c0_ddr4_dq,
    inout wire [7:0] c0_ddr4_dqs_t,
    inout wire [7:0] c0_ddr4_dqs_c
);
    // 校准状态归MIG；应用流量和首错归独立批次测试器及配置级保护。
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE" *) wire calib_complete;
    (* KEEP = "TRUE", MARK_DEBUG = "TRUE" *) wire compare_error;

    // 手册 RESET_IN1 低有效，MIG 示例 sys_rst 高有效；这里只做极性转换。
    // 复位同步与校准时序由示例/IP 实现，不连接 M1 受控复位接口。
    rkv_m1_board_memory #(
        .EXPERIMENT_ID(EXPERIMENT_ID)
    ) example (
        .sys_rst(~sys_rst_n),
        .c0_init_calib_complete(calib_complete),
        .c0_data_compare_error(compare_error),
        .c0_sys_clk_p(c0_sys_clk_p),
        .c0_sys_clk_n(c0_sys_clk_n),
        .c0_ddr4_act_n(c0_ddr4_act_n),
        .c0_ddr4_adr(c0_ddr4_adr),
        .c0_ddr4_ba(c0_ddr4_ba),
        .c0_ddr4_bg(c0_ddr4_bg),
        .c0_ddr4_cke(c0_ddr4_cke),
        .c0_ddr4_odt(c0_ddr4_odt),
        .c0_ddr4_cs_n(c0_ddr4_cs_n),
        .c0_ddr4_ck_t(c0_ddr4_ck_t),
        .c0_ddr4_ck_c(c0_ddr4_ck_c),
        .c0_ddr4_reset_n(c0_ddr4_reset_n),
        .c0_ddr4_dm_dbi_n(c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq(c0_ddr4_dq),
        .c0_ddr4_dqs_t(c0_ddr4_dqs_t),
        .c0_ddr4_dqs_c(c0_ddr4_dqs_c)
    );
endmodule
