module tb; reg clk=0; always #10 clk=~clk;
reg rw_en=0,r_en=0; reg [3:0] we=0; reg [8:0] a=0,ra=0; reg [31:0] wd=0; wire [31:0] rd,rrd; integer i;
npu_sram_bank #(.DEPTH_WORDS(512)) d(.clk(clk),.rw_en(rw_en),.rw_we(we),.rw_addr(a),.rw_wdata(wd),.rw_rdata(rd),.r_en(r_en),.r_addr(ra),.r_rdata(rrd));
// consumer view: values a flop would capture at each posedge
always @(posedge clk) $display("C %0d rw=%h r=%h", $time/20, rd, rrd);
task cyc(input e,input [3:0] w,input [8:0] ad,input [31:0] dd,input re,input [8:0] rad);
 begin @(negedge clk); rw_en=e; we=w; a=ad; wd=dd; r_en=re; ra=rad; end endtask
initial begin
 cyc(1,4'hF,5,32'hdeadbeef,0,0); cyc(1,4'b0101,5,32'h11223344,0,0); cyc(1,4'hF,9,32'hcafef00d,0,0);
 cyc(1,0,5,0,1,9);  cyc(0,0,0,0,0,0); cyc(0,0,0,0,0,0);   // read both, then idle: data must hold
 cyc(1,0,9,0,0,0);  cyc(0,0,0,0,0,0); cyc(0,0,0,0,0,0); cyc(0,0,0,0,0,0);
 @(negedge clk); $finish; end
endmodule
