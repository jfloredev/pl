module top(input  clk, reset, 
           output [31:0] WriteData, DataAdr, 
           output MemWrite);
  
  wire [31:0] PC, Instr, ReadData; 
  
  // instantiate processor and memories
  riscvsingle rvsingle(
    .clk(clk), 
    .reset(reset), 
    .PC(PC), 
    .Instr(Instr), 
    .MemWrite(MemWrite), 
    .DataAdr(DataAdr), 
    .WriteData(WriteData), 
    .ReadData(ReadData)
  ); 

  imem imem(
    .a(PC), 
    .rd(Instr)
  ); 

  dmem dmem(
    .clk(clk), 
    .we(MemWrite), 
    .a(DataAdr), 
    .wd(WriteData), 
    .rd(ReadData)
  ); 
endmodule