module imem #(parameter MEM_FILE = "riscvtest.mem") (
  input  [31:0] a,
  output [31:0] rd
);
  reg [31:0] RAM[63:0];

  initial $readmemh(MEM_FILE, RAM);

  assign rd = RAM[a[31:2]]; // word aligned
endmodule
