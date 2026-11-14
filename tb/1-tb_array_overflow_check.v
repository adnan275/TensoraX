// Overflow demo (repo root): iverilog -g2012 -I rtl -o sim/ovf.vvp rtl/mac_unit.v rtl/pe.v rtl/systolic_array_3x3.v tb/tb_array_overflow_check.v && vvp sim/ovf.vvp
// All -32768 operands: 3*2^30 wraps in the 32-bit accumulator to -1073741824.
`timescale 1ns/1ps
module tb_ovf;
 reg clk=0,rst_n=0,clr=0,v=0; reg signed [47:0] a=0,b=0; wire signed [287:0] c;
 systolic_array_3x3 d(.clk(clk),.rst_n(rst_n),.clr_acc(clr),.valid_in(v),.a_rows(a),.b_cols(b),.c_flat(c));
 always #5 clk=~clk; integer t,i;
 initial begin #20 rst_n=1; @(negedge clk); v=1;
  for(t=0;t<7;t=t+1) begin
   for(i=0;i<3;i=i+1) begin
     a[i*16+:16] = (t-i>=0 && t-i<3) ? 16'sh8000 : 0;
     b[i*16+:16] = (t-i>=0 && t-i<3) ? 16'sh8000 : 0; end
   clr=(t==0); @(negedge clk); end
  v=0;a=0;b=0; repeat(3) @(negedge clk);
  $display("C00=%0d (exact 3*2^30=3221225472, wrapped expected %0d)", $signed(c[31:0]), 3221225472-4294967296);
  $finish; end
endmodule
