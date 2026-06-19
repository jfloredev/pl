module riscvsingle(
  input  clk, reset,
  output [31:0] PC,        // IF stage PC -> imem
  input  [31:0] Instr,     // instruction from imem (IF stage)
  output        MemWrite,  // MEM stage write enable -> dmem
  output [31:0] DataAdr,   // MEM stage ALU result -> dmem address
  output [31:0] WriteData, // MEM stage write data -> dmem
  input  [31:0] ReadData   // data from dmem (MEM stage)
);

  // ---- ID stage instruction (to controller) ----
  wire [31:0] InstrD;

  // ---- Controller outputs (ID stage, pipelined into datapath) ----
  wire        RegWriteD, ALUSrcD, MemWriteD, JumpD, BranchD;
  wire [1:0]  ResultSrcD;
  wire [2:0]  ImmSrcD;
  wire [2:0]  ALUControlD;

  // ---- EX stage signals (to hazard unit) ----
  wire [4:0]  Rs1E, Rs2E, RdE;
  wire        PCSrcE, IsLoadE;

  // ---- MEM stage signals ----
  wire        RegWriteM, MemWriteM;
  wire [4:0]  RdM;
  wire [31:0] ALUResultM, WriteDataM;

  // ---- WB stage signals ----
  wire        RegWriteW;
  wire [4:0]  RdW;

  // ---- Hazard unit outputs ----
  wire [1:0]  ForwardAE, ForwardBE;
  wire        StallF, StallD, FlushD, FlushE;

  // ---- Register addresses for hazard unit (from ID stage) ----
  wire [4:0]  Rs1D, Rs2D;

  // ---- IF stage PC ----
  wire [31:0] PCF;
  assign PC       = PCF;
  assign DataAdr  = ALUResultM;
  assign WriteData= WriteDataM;
  assign MemWrite = MemWriteM;

  controller c(
    .op(InstrD[6:0]),
    .funct3(InstrD[14:12]),
    .funct7b5(InstrD[30]),
    .ResultSrc(ResultSrcD), .MemWrite(MemWriteD),
    .ALUSrc(ALUSrcD),       .RegWrite(RegWriteD),
    .Jump(JumpD),           .Branch(BranchD),
    .ImmSrc(ImmSrcD),       .ALUControl(ALUControlD)
  );

  datapath dp(
    .clk(clk),     .reset(reset),
    // IF
    .PCF(PCF),     .InstrF(Instr),
    // ID
    .InstrD(InstrD),
    .Rs1D(Rs1D),   .Rs2D(Rs2D),
    .RegWriteD(RegWriteD), .ALUSrcD(ALUSrcD),
    .MemWriteD(MemWriteD), .JumpD(JumpD),
    .BranchD(BranchD),
    .ResultSrcD(ResultSrcD), .ImmSrcD(ImmSrcD),
    .ALUControlD(ALUControlD),
    // EX
    .Rs1E(Rs1E),   .Rs2E(Rs2E), .RdE(RdE),
    .PCSrcE(PCSrcE),
    .IsLoadE(IsLoadE),
    // MEM
    .RegWriteM(RegWriteM), .MemWriteM(MemWriteM),
    .RdM(RdM),
    .ALUResultM(ALUResultM), .WriteDataM(WriteDataM),
    .ReadDataM(ReadData),
    // WB
    .RegWriteW(RegWriteW), .RdW(RdW),
    // Hazard control
    .StallF(StallF),       .StallD(StallD),
    .FlushD(FlushD),       .FlushE(FlushE),
    .ForwardAE(ForwardAE), .ForwardBE(ForwardBE)
  );

  hazard hu(
    .Rs1D(Rs1D),       .Rs2D(Rs2D),
    .Rs1E(Rs1E),       .Rs2E(Rs2E),     .RdE(RdE),
    .RdM(RdM),         .RdW(RdW),
    .RegWriteM(RegWriteM), .RegWriteW(RegWriteW),
    .IsLoadE(IsLoadE),
    .PCSrcE(PCSrcE),
    .ForwardAE(ForwardAE), .ForwardBE(ForwardBE),
    .StallF(StallF),   .StallD(StallD),
    .FlushD(FlushD),   .FlushE(FlushE)
  );

endmodule
