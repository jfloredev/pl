module regfile(
  input        clk,
  input        we3,
  input  [4:0] a1, a2, a3,
  input  [31:0] wd3,
  output [31:0] rd1, rd2
);

  reg [31:0] rf[31:0];

  always @(posedge clk)
    if (we3) rf[a3] <= wd3;

  // Internal forwarding: if WB is writing the same register being read,
  // return the new value combinatorially to avoid a 3-instruction hazard.
  assign rd1 = (a1 != 0) ? ((we3 && a3 == a1) ? wd3 : rf[a1]) : 0;
  assign rd2 = (a2 != 0) ? ((we3 && a3 == a2) ? wd3 : rf[a2]) : 0;

endmodule
