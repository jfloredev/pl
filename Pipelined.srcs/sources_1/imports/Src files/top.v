module top #(parameter MEM_FILE = "riscvtest.mem") (
  input        clk, reset,
  output [31:0] WriteData, DataAdr,
  output        MemWrite
);

  wire [31:0] PC, Instr, ReadData;

  riscvsingle rvsingle(
    .clk(clk),      .reset(reset),
    .PC(PC),        .Instr(Instr),
    .MemWrite(MemWrite),
    .DataAdr(DataAdr), .WriteData(WriteData),
    .ReadData(ReadData)
  );

  imem #(.MEM_FILE(MEM_FILE)) imem(.a(PC), .rd(Instr));

  dmem dmem(
    .clk(clk), .we(MemWrite),
    .a(DataAdr), .wd(WriteData), .rd(ReadData)
  );
endmodule