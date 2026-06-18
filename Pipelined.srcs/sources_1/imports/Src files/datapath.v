module datapath(
  input  clk, reset,

  // ---- IF stage ----
  output [31:0] PCF,
  input  [31:0] InstrF,

  // ---- ID stage: instruction & register addresses to controller/hazard ----
  output [31:0] InstrD,
  output [4:0]  Rs1D, Rs2D,

  // ---- ID stage: control signals from controller ----
  input         RegWriteD, ALUSrcD, MemWriteD, JumpD, BranchD,
  input  [1:0]  ResultSrcD, ImmSrcD,
  input  [2:0]  ALUControlD,

  // ---- EX stage: to hazard unit ----
  output [4:0]  Rs1E, Rs2E, RdE,
  output        PCSrcE,
  output        ResultSrcE0,   // 1 for loads (lw hazard detection)

  // ---- MEM stage: to hazard unit and external memory ----
  output        RegWriteM, MemWriteM,
  output [4:0]  RdM,
  output [31:0] ALUResultM, WriteDataM,
  input  [31:0] ReadDataM,

  // ---- WB stage: to hazard unit ----
  output        RegWriteW,
  output [4:0]  RdW,

  // ---- Hazard unit control inputs ----
  input         StallF, StallD, FlushD, FlushE,
  input  [1:0]  ForwardAE, ForwardBE
);

  localparam WIDTH = 32;

  // ================================================================
  // IF Stage
  // ================================================================
  wire [31:0] PCNextF, PCPlus4F, PCTargetE;

  flopenr #(WIDTH) pcreg(
    .clk(clk), .reset(reset), .en(~StallF),
    .d(PCNextF), .q(PCF)
  );
  adder pcadd4(.a(PCF), .b(32'd4), .y(PCPlus4F));

  // ----------------------------------------------------------------
  // IF/ID pipeline register
  // ----------------------------------------------------------------
  wire [31:0] PCD, PCPlus4D;

  flopenrc #(WIDTH) IFID_PC(
    .clk(clk), .reset(reset), .clear(FlushD), .en(~StallD),
    .d(PCF),      .q(PCD)
  );
  flopenrc #(WIDTH) IFID_Instr(
    .clk(clk), .reset(reset), .clear(FlushD), .en(~StallD),
    .d(InstrF),   .q(InstrD)
  );
  flopenrc #(WIDTH) IFID_PC4(
    .clk(clk), .reset(reset), .clear(FlushD), .en(~StallD),
    .d(PCPlus4F), .q(PCPlus4D)
  );

  // ================================================================
  // ID Stage
  // ================================================================
  assign Rs1D = InstrD[19:15];
  assign Rs2D = InstrD[24:20];
  wire [4:0]  RdD = InstrD[11:7];

  wire [31:0] RD1D, RD2D, ImmExtD, ResultW;

  regfile rf(
    .clk(clk), .we3(RegWriteW),
    .a1(Rs1D), .a2(Rs2D), .a3(RdW),
    .wd3(ResultW),
    .rd1(RD1D), .rd2(RD2D)
  );

  extend ext(
    .instr(InstrD[31:7]), .immsrc(ImmSrcD), .immext(ImmExtD)
  );

  // ----------------------------------------------------------------
  // ID/EX pipeline register
  // ----------------------------------------------------------------
  reg        RegWriteE_r, ALUSrcE_r, MemWriteE_r, JumpE_r, BranchE_r;
  reg [1:0]  ResultSrcE_r;
  reg [2:0]  ALUControlE_r;
  reg [31:0] RD1E_r, RD2E_r, PCE_r, ImmExtE_r, PCPlus4E_r;
  reg [4:0]  Rs1E_r, Rs2E_r, RdE_r;

  always @(posedge clk or posedge reset) begin
    if (reset || FlushE) begin
      RegWriteE_r  <= 0; ALUSrcE_r    <= 0; MemWriteE_r  <= 0;
      JumpE_r      <= 0; BranchE_r    <= 0;
      ResultSrcE_r <= 0; ALUControlE_r<= 0;
      RD1E_r       <= 0; RD2E_r       <= 0; PCE_r        <= 0;
      Rs1E_r       <= 0; Rs2E_r       <= 0; RdE_r        <= 0;
      ImmExtE_r    <= 0; PCPlus4E_r   <= 0;
    end else begin
      RegWriteE_r  <= RegWriteD;  ALUSrcE_r    <= ALUSrcD;
      MemWriteE_r  <= MemWriteD;  JumpE_r      <= JumpD;
      BranchE_r    <= BranchD;    ResultSrcE_r <= ResultSrcD;
      ALUControlE_r<= ALUControlD;
      RD1E_r       <= RD1D;       RD2E_r       <= RD2D;
      PCE_r        <= PCD;        Rs1E_r       <= Rs1D;
      Rs2E_r       <= Rs2D;       RdE_r        <= RdD;
      ImmExtE_r    <= ImmExtD;    PCPlus4E_r   <= PCPlus4D;
    end
  end

  // Wire aliases for readability in EX stage
  wire        RegWriteE  = RegWriteE_r;
  wire        ALUSrcE    = ALUSrcE_r;
  wire        MemWriteE  = MemWriteE_r;
  wire        JumpE      = JumpE_r;
  wire        BranchE    = BranchE_r;
  wire [1:0]  ResultSrcE = ResultSrcE_r;
  wire [2:0]  ALUControlE= ALUControlE_r;
  wire [31:0] RD1E       = RD1E_r;
  wire [31:0] RD2E       = RD2E_r;
  wire [31:0] PCE        = PCE_r;
  wire [31:0] ImmExtE    = ImmExtE_r;
  wire [31:0] PCPlus4E   = PCPlus4E_r;
  assign Rs1E       = Rs1E_r;
  assign Rs2E       = Rs2E_r;
  assign RdE        = RdE_r;
  assign ResultSrcE0= ResultSrcE_r[0];

  // ================================================================
  // EX Stage
  // ================================================================
  wire [31:0] SrcAE, SrcBE, WriteDataE, ALUResultE;
  wire        ZeroE;

  // Forwarding muxes
  mux3 #(WIDTH) fwdamux(.d0(RD1E), .d1(ResultW), .d2(ALUResultM), .s(ForwardAE), .y(SrcAE));
  mux3 #(WIDTH) fwdbmux(.d0(RD2E), .d1(ResultW), .d2(ALUResultM), .s(ForwardBE), .y(WriteDataE));
  mux2 #(WIDTH) srcbmux(.d0(WriteDataE), .d1(ImmExtE), .s(ALUSrcE), .y(SrcBE));

  alu alu_unit(
    .a(SrcAE), .b(SrcBE),
    .alucontrol(ALUControlE),
    .result(ALUResultE), .zero(ZeroE)
  );

  adder pcaddbranch(.a(PCE), .b(ImmExtE), .y(PCTargetE));

  assign PCSrcE = (BranchE & ZeroE) | JumpE;
  assign PCNextF = PCSrcE ? PCTargetE : PCPlus4F;

  // ----------------------------------------------------------------
  // EX/MEM pipeline register
  // ----------------------------------------------------------------
  reg        RegWriteM_r, MemWriteM_r;
  reg [1:0]  ResultSrcM_r;
  reg [31:0] ALUResultM_r, WriteDataM_r, PCPlus4M_r;
  reg [4:0]  RdM_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      RegWriteM_r  <= 0; MemWriteM_r  <= 0; ResultSrcM_r <= 0;
      ALUResultM_r <= 0; WriteDataM_r <= 0;
      PCPlus4M_r   <= 0; RdM_r        <= 0;
    end else begin
      RegWriteM_r  <= RegWriteE;  MemWriteM_r  <= MemWriteE;
      ResultSrcM_r <= ResultSrcE;
      ALUResultM_r <= ALUResultE; WriteDataM_r <= WriteDataE;
      PCPlus4M_r   <= PCPlus4E;  RdM_r         <= RdE;
    end
  end

  assign RegWriteM  = RegWriteM_r;
  assign MemWriteM  = MemWriteM_r;
  assign ALUResultM = ALUResultM_r;
  assign WriteDataM = WriteDataM_r;
  assign RdM        = RdM_r;
  wire [1:0]  ResultSrcM = ResultSrcM_r;
  wire [31:0] PCPlus4M   = PCPlus4M_r;

  // ================================================================
  // MEM Stage  (external dmem access happens in top/riscvsingle)
  // ================================================================

  // ----------------------------------------------------------------
  // MEM/WB pipeline register
  // ----------------------------------------------------------------
  reg        RegWriteW_r;
  reg [1:0]  ResultSrcW_r;
  reg [31:0] ALUResultW_r, ReadDataW_r, PCPlus4W_r;
  reg [4:0]  RdW_r;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      RegWriteW_r  <= 0; ResultSrcW_r <= 0;
      ALUResultW_r <= 0; ReadDataW_r  <= 0;
      PCPlus4W_r   <= 0; RdW_r        <= 0;
    end else begin
      RegWriteW_r  <= RegWriteM;
      ResultSrcW_r <= ResultSrcM;
      ALUResultW_r <= ALUResultM_r;
      ReadDataW_r  <= ReadDataM;
      PCPlus4W_r   <= PCPlus4M;
      RdW_r        <= RdM_r;
    end
  end

  assign RegWriteW = RegWriteW_r;
  assign RdW       = RdW_r;

  // ================================================================
  // WB Stage
  // ================================================================
  mux3 #(WIDTH) resultmux(
    .d0(ALUResultW_r),
    .d1(ReadDataW_r),
    .d2(PCPlus4W_r),
    .s(ResultSrcW_r),
    .y(ResultW)
  );

endmodule
