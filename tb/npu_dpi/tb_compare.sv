module tb_compare;
  parameter int WORDS=256,D=32,LAT=8;
  logic clk=0;
  always #5 clk=~clk;
  logic a_req=0,a_we=0,sw_req=0,b_req=0,b_tag=0,b_we=0,dump=0;
  logic [31:0] a_addr=0,a_wdata=0,sw_addr=0,sw_wdata=0,b_addr=0;
  logic [3:0] a_be=0,sw_be=0;
  logic [D/4-1:0] b_wmask=0;
  logic [D*8-1:0] b_wdata=0;
  logic ra,rb,rt,ri,da,db,dt,di;
  logic [255:0] rad,dad;
  logic [D*8-1:0] rbd,dbd;
  otpu_dram_reference #(.WORDS(WORDS),.D(D),.LAT(LAT),.SID(0)) reference_dram(
    .clk,.a_req,.a_we,.a_addr,.a_wdata,.a_be,.sw_req,.sw_addr,.sw_wdata,.sw_be,
    .b_req,.b_tag,.b_we,.b_wmask,.b_wdata,.b_addr,.dump,
    .a_rvalid(ra),.a_rdata(rad),.b_rvalid(rb),.b_rtag(rt),.b_rdata(rbd),.rd_idle(ri));
  otpu_dram #(.WORDS(WORDS),.D(D),.LAT(LAT),.SID(1)) dpi_dram(
    .clk,.a_req,.a_we,.a_addr,.a_wdata,.a_be,.sw_req,.sw_addr,.sw_wdata,.sw_be,
    .b_req,.b_tag,.b_we,.b_wmask,.b_wdata,.b_addr,.dump,
    .a_rvalid(da),.a_rdata(dad),.b_rvalid(db),.b_rtag(dt),.b_rdata(dbd),.rd_idle(di));
  task automatic check;
    if ({ra,rb,ri}!={da,db,di}) $fatal(1,"valid/idle mismatch");
    if (ra && rad!==dad) $fatal(1,"A read-first/data mismatch");
    if (rb && (rt!==dt || rbd!==dbd)) $fatal(1,"B tag/data mismatch");
  endtask
  logic [31:0] rng=32'h12345678;
  initial begin
    for(int i=0;i<200;i++) begin
      @(negedge clk);
      rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
      a_req=rng[0];a_we=rng[1];a_addr=rng>>3;a_wdata=~rng;a_be=rng[7:4];
      sw_req=rng[2];sw_addr=rng>>11;sw_wdata=rng^32'h55aa55aa;sw_be=rng[15:12];
      b_req=rng[3];b_we=rng[4];b_addr=rng>>5;b_tag=rng[5];b_wmask=(D/4)'(rng);
      for(int w=0;w<D/4;w++)b_wdata[32*w+:32]=rng+32'(w);
      if(i<8 || i==199) begin
        a_req=1;sw_req=1;b_req=1;a_addr=WORDS-1;sw_addr=WORDS-1;b_addr=WORDS-1;
        a_be=5;sw_be=10;a_we=i[0];b_we=i[1];b_wmask='1;
      end
      if(i==199)begin a_we=1;b_we=1;dump=1;end
      @(posedge clk);#1;check();
    end
    @(negedge clk);dump=0;a_req=0;sw_req=0;b_req=0;
    repeat(LAT+2)begin @(posedge clk);#1;check();end
    if(!ri || !di)$fatal(1,"did not drain");
    $display("DPI_COMPARE_PASS D=%0d LAT=%0d",D,LAT);$finish;
  end
endmodule
