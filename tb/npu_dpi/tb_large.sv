module tb_large;
  localparam int WORDS=1<<29,D=128,LAT=8;
  logic clk=0;always #5 clk=~clk;
  logic a_req=0,a_we=0,sw_req=0,b_req=0,b_tag=0,b_we=0,dump=0;
  logic [31:0] a_addr=0,a_wdata=0,sw_addr=0,sw_wdata=0,b_addr=0;
  logic [3:0] a_be=15,sw_be=0;
  logic [D/4-1:0] b_wmask=0;logic [D*8-1:0] b_wdata=0;
  logic a_rvalid,b_rvalid,b_rtag,rd_idle;
  logic [255:0] a_rdata;logic [D*8-1:0] b_rdata;
  otpu_dram #(.WORDS(WORDS),.D(D),.LAT(LAT),.SID(0)) dut(.*);
  initial begin
    @(negedge clk);a_req=1;a_we=1;a_addr=WORDS-1;a_wdata=32'hdeadbeef;
    @(negedge clk);a_we=0;b_req=1;b_addr=WORDS-1;
    repeat(LAT+2)@(posedge clk);
    #1;
    if(!a_rvalid || !b_rvalid || a_rdata[255:224]!=32'hdeadbeef || b_rdata[31:0]!=32'hdeadbeef)
      $fatal(1,"2GiB high-address read/write failed");
    if(b_rdata[63:32]!=32'hcafebabe)$fatal(1,"high address aliased low word or wrap semantics changed");
    $display("DPI_LARGE_PASS bytes=2147483648");$finish;
  end
endmodule
