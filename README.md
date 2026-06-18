# RISC-V Pipelined Processor

Conversión del procesador RISC-V de ciclo único a pipeline de 5 etapas.  
Implementa **forwarding**, **stalling** y **flushing** para manejar todos los tipos de hazards.

---

## Arquitectura del Pipeline

El pipeline divide la ejecución de cada instrucción en 5 etapas que trabajan en paralelo:

```
Ciclo →    1     2     3     4     5     6     7     8
Instr 1:  [IF]  [ID]  [EX] [MEM]  [WB]
Instr 2:        [IF]  [ID]  [EX] [MEM]  [WB]
Instr 3:              [IF]  [ID]  [EX] [MEM]  [WB]
Instr 4:                    [IF]  [ID]  [EX] [MEM]  [WB]
```

| Etapa  | Nombre   | Qué hace |
|--------|----------|----------|
| **IF** | Fetch    | Lee la instrucción de la memoria de instrucciones usando el PC |
| **ID** | Decode   | Decodifica la instrucción, lee registros, genera el inmediato extendido |
| **EX** | Execute  | La ALU opera, calcula la dirección de branch/jump, decide si se toma |
| **MEM**| Memory   | Lee o escribe la memoria de datos |
| **WB** | Writeback| Selecciona el resultado y escribe en el banco de registros |

Los 4 **registros de pipeline** (IF/ID, ID/EX, EX/MEM, MEM/WB) guardan los datos entre etapas.

---

## Los 3 Tipos de Hazards y cómo se resuelven

### 1. FORWARDING — Hazard de datos RAW

**¿Qué es?**  
Ocurre cuando una instrucción necesita un dato que la instrucción anterior aún no terminó de escribir en el banco de registros. El banco de registros se escribe en WB (etapa 5), pero el dato ya está calculado desde EX (etapa 3).

**Ejemplo:**
```
add x4, x1, x2    ← escribe x4 al final de WB (ciclo 7)
sub x5, x4, x3    ← necesita x4 en EX (ciclo 6) ← PROBLEMA: x4 no está en el banco aún
```

**¿Cómo se ve en el pipeline?**
```
Ciclo →    1     2     3     4     5     6     7
add x4:  [IF]  [ID]  [EX] [MEM]  [WB]            ← x4 calculado en EX (ciclo 3)
sub x5:        [IF]  [ID]  [EX] [MEM]  [WB]       ← necesita x4 en EX (ciclo 4)
                            ↑
                     x4 disponible en EX/MEM → se forwardea directamente
```

**Solución: Forwarding (cortocircuito)**  
En lugar de esperar al WB, se conecta la salida del registro de pipeline directamente a la entrada de la ALU.

```
                    EX/MEM.ALUResult ──────────────────────┐
                                                           ▼
          RD1E ──┤                                    [MUX 3:1] ──► SrcAE ──► ALU
          ResultW──┤  ForwardAE                            ▲
          ALUResultM┘  (de la Hazard Unit)                 │
                                                           │
ForwardAE = 10  →  usa ALUResultM  (EX→EX,  1 ciclo atrás)
ForwardAE = 01  →  usa ResultW     (WB→EX,  2 ciclos atrás)
ForwardAE = 00  →  usa RD1E        (sin forwarding)
```

**En `hazard.v`:**
```verilog
// Forward desde EX/MEM (1 ciclo atrás) — tiene prioridad
if (RegWriteM && RdM != 0 && RdM == Rs1E)
    ForwardAE = 2'b10;
// Forward desde MEM/WB (2 ciclos atrás)
else if (RegWriteW && RdW != 0 && RdW == Rs1E)
    ForwardAE = 2'b01;
else
    ForwardAE = 2'b00;
```

**No hay ciclos perdidos.** El pipeline corre a máxima velocidad.

---

### 2. STALLING — Hazard load-use

**¿Qué es?**  
Es el único caso donde el forwarding **no alcanza**. La instrucción `lw` carga un dato desde memoria, pero ese dato solo está disponible al *final* de la etapa MEM. La instrucción siguiente lo necesita al *inicio* de EX del siguiente ciclo — es físicamente imposible entregarlo a tiempo.

**Ejemplo:**
```
lw  x4, 0(x1)    ← dato de memoria disponible al FINAL de MEM (ciclo 5)
add x5, x4, x2   ← necesita x4 al INICIO de EX (ciclo 4) ← IMPOSIBLE
```

**¿Cómo se ve en el pipeline sin stall?** (muestra el problema)
```
Ciclo →    1     2     3     4     5     6
lw  x4:  [IF]  [ID]  [EX] [MEM]  [WB]
add x5:        [IF]  [ID]  [EX] [MEM]  [WB]
                            ↑
                     x4 no existe aún (MEM no terminó)
```

**Solución: Insertar 1 burbuja (stall)**
```
Ciclo →    1     2     3     4     5     6     7
lw  x4:  [IF]  [ID]  [EX] [MEM]  [WB]
          ↓     ↓     ↓     ↓
         [PC]  [ID]  [EX] [MEM]          ← PC y IF/ID se CONGELAN
burbuja:              ---  [NOP]  [NOP]  ← ID/EX se limpia → NOP en EX
add x5:        [IF]  [ID]  [ID]  [EX] [MEM]  [WB]
                            ↑           ↑
                        se congela   ahora x4 está en MEM/WB → forwarding WB→EX ✓
```

**Señales de control:**
- `StallF = 1` → PC no avanza (congela IF)
- `StallD = 1` → IF/ID no avanza (congela ID)
- `FlushE = 1` → ID/EX se limpia a cero (inserta NOP en EX)

**En `hazard.v`:**
```verilog
// ResultSrcE0 = 1 solo para lw (ResultSrc = 01)
assign lwStall = ResultSrcE0 && (RdE == Rs1D || RdE == Rs2D);

assign StallF = lwStall;
assign StallD = lwStall;
assign FlushE = lwStall | PCSrcE;
```

**Costo: 1 ciclo perdido** por cada `lw` seguido inmediatamente de una instrucción que usa el dato.

---

### 3. FLUSHING — Hazard de control (branch/jump)

**¿Qué es?**  
Cuando hay un branch (`beq`) o jump (`jal`), el procesador no sabe si se toma ni cuál es la dirección destino hasta terminar la etapa **EX** (ciclo 3 de esa instrucción). Mientras tanto, ya buscó 2 instrucciones de la ruta equivocada.

**Ejemplo:**
```
beq x1, x2, LABEL   ← ¿se toma? se sabe en EX (ciclo 3)
add x3, x4, x5      ← instrucción buscada equivocadamente (PC+4)
lw  x6, 0(x7)       ← instrucción buscada equivocadamente (PC+8)
LABEL:
sw  x1, 0(x2)       ← instrucción correcta si el branch se toma
```

**¿Cómo se ve en el pipeline?**
```
Ciclo →    1     2     3     4     5     6
beq:     [IF]  [ID]  [EX] [MEM]  [WB]
add:           [IF]  [ID]  ???         ← buscada por error
lw:                  [IF]  ???         ← buscada por error
sw:                        [IF]  [ID]  ← instrucción correcta
                      ↑
               ciclo 3: PCSrcE=1 → FLUSH
```

**Solución: Limpiar las 2 instrucciones incorrectas**
- `FlushD = 1` → limpia IF/ID (descarta `add` que estaba en ID)
- `FlushE = 1` → limpia ID/EX (descarta `lw` que estaba en IF y pasó a ID... espera, en realidad en ciclo 3 el `add` ya está en ID y el `lw` en IF)

```
Ciclo →    1     2     3     4     5     6
beq:     [IF]  [ID]  [EX] [MEM]  [WB]
add:           [IF]  [ID]  [NOP]        ← FlushE: ID/EX se limpia → NOP
lw:                  [IF]  [NOP]        ← FlushD: IF/ID se limpia → NOP
sw:                        [IF]  [ID]   ← PC ya apunta a LABEL ✓
```

**En `hazard.v`:**
```verilog
assign FlushD = PCSrcE;          // limpia IF/ID
assign FlushE = lwStall | PCSrcE; // limpia ID/EX
```

**`PCSrcE`** se calcula en EX dentro del datapath:
```verilog
assign PCSrcE = (BranchE & ZeroE) | JumpE;
assign PCNextF = PCSrcE ? PCTargetE : PCPlus4F;
```

**Costo: 2 ciclos perdidos** por cada branch/jump tomado.

---

## Cuadro 1 — Resumen de los 4 Programas de Prueba

| Programa | Archivo `.mem` | Qué prueba | Hazards activos |
|----------|---------------|------------|-----------------|
| **1** | `test_nodep.mem` | ISA sin dependencias | Ninguno |
| **2** | `test_forwarding.mem` | Forwarding EX→EX y WB→EX | Solo forwarding |
| **3** | `test_stall.mem` | Load-use hazard | Stall + Forwarding |
| **4** | `test_flush.mem` | Branch tomado | Flush |

> Todos los programas almacenan el valor **25** en la dirección **100**, que es la condición de éxito del testbench (`Simulation succeeded`).

---

## Programa 1 — ISA sin dependencias (`test_nodep.mem`)

Las instrucciones que producen y usan datos están separadas por 4 o más instrucciones de relleno. El banco de registros ya tiene el valor correcto cuando se necesita. **No se activa ningún mecanismo de hazard.**

### Ensamblador
```
addi x1, x0, 5      # x1 = 5
addi x2, x0, 20     # x2 = 20
addi x3, x0, 100    # x3 = 100  (dirección de sw)
addi x4, x0, 0      # padding — separa x1,x2 de su uso
addi x5, x0, 0      # padding
add  x6, x1, x2     # x6 = 25   ← x1 y x2 disponibles en banco (4+ ciclos atrás)
addi x7, x0, 0      # padding
addi x8, x0, 0      # padding
addi x9, x0, 0      # padding
sw   x6, 0(x3)      # mem[100] = 25 ✓
```

### Máquina (hex)
```
00500093   addi x1, x0, 5
01400113   addi x2, x0, 20
06400193   addi x3, x0, 100
00000213   addi x4, x0, 0
00000293   addi x5, x0, 0
00208333   add  x6, x1, x2
00000393   addi x7, x0, 0
00000413   addi x8, x0, 0
00000493   addi x9, x0, 0
0061A023   sw   x6, 0(x3)
```

### Pipeline (sin hazards)
```
Ciclo:    1    2    3    4    5    6    7    8    9   10   11   12   13   14
addi x1: IF   ID   EX  MEM   WB
addi x2:      IF   ID   EX  MEM   WB
addi x3:           IF   ID   EX  MEM   WB
addi x4:                IF   ID   EX  MEM   WB
addi x5:                     IF   ID   EX  MEM   WB
add  x6:                          IF   ID   EX  MEM   WB    ← lee rf[x1],rf[x2]: ya disponibles
addi x7:                               IF   ID   EX  MEM   WB
addi x8:                                    IF   ID   EX  MEM   WB
addi x9:                                         IF   ID   EX  MEM   WB
sw   x6:                                              IF   ID   EX  MEM   WB
```
No hay stalls, no hay flush, no hay forwarding. Pipeline fluye a máxima velocidad.

---

## Programa 2 — Test Forwarding (`test_forwarding.mem`)

Instrucciones consecutivas donde cada resultado es usado 1 o 2 ciclos después. La Hazard Unit activa `ForwardAE` y `ForwardBE` para entregar datos directamente desde EX/MEM o MEM/WB.

### Ensamblador
```
addi x1, x0, 10     # x1 = 10
addi x2, x0, 3      # x2 = 3
addi x3, x0, 100    # x3 = 100
add  x4, x1, x2     # x4 = 13   ← MEM/WB fwd: x2 (2 atrás); rf-fwd interno: x1 (3 atrás)
sub  x5, x4, x2     # x5 = 10   ← EX/MEM fwd: x4 (1 atrás)
add  x6, x5, x5     # x6 = 20   ← EX/MEM fwd: x5 en ForwardAE Y ForwardBE
add  x7, x6, x5     # x7 = 30   ← EX/MEM fwd: x6; MEM/WB fwd: x5
addi x8, x7, -5     # x8 = 25   ← EX/MEM fwd: x7
sw   x8, 0(x3)      # mem[100] = 25 ✓  ← EX/MEM fwd: x8
```

### Máquina (hex)
```
00A00093   addi x1, x0, 10
00300113   addi x2, x0, 3
06400193   addi x3, x0, 100
00208233   add  x4, x1, x2
402202B3   sub  x5, x4, x2
00528333   add  x6, x5, x5
005303B3   add  x7, x6, x5
FFB38413   addi x8, x7, -5
0081A023   sw   x8, 0(x3)
```

### Forwarding activo ciclo a ciclo

```
Ciclo:     4     5     6     7     8     9    10
add  x4:  [EX] [MEM]  [WB]
sub  x5:  [ID]  [EX] [MEM]  [WB]
add  x6:        [ID]  [EX] [MEM]  [WB]
add  x7:              [ID]  [EX] [MEM]  [WB]
addi x8:                    [ID]  [EX] [MEM]  [WB]
sw   x8:                          [ID]  [EX] [MEM]
```

| Instrucción | Operando | Forwarding usado | Fuente |
|-------------|----------|-----------------|--------|
| `add x4` | x2 | MEM/WB → EX (`ForwardBE=01`) | ResultW = 3 |
| `sub x5` | x4 | EX/MEM → EX (`ForwardAE=10`) | ALUResultM = 13 |
| `add x6` | x5 (A y B) | EX/MEM → EX (`ForwardAE=ForwardBE=10`) | ALUResultM = 10 |
| `add x7` | x6 | EX/MEM → EX (`ForwardAE=10`) | ALUResultM = 20 |
| `add x7` | x5 | MEM/WB → EX (`ForwardBE=01`) | ResultW = 10 |
| `addi x8` | x7 | EX/MEM → EX (`ForwardAE=10`) | ALUResultM = 30 |
| `sw` | x8 | EX/MEM → EX (`ForwardBE=10`) | ALUResultM = 25 |

No hay ciclos perdidos. El forwarding resuelve todo en hardware.

---

## Programa 3 — Test Stalling (`test_stall.mem`)

Muestra el único caso que forwarding no puede resolver: `lw` seguido inmediatamente de una instrucción que usa el dato cargado.

### Ensamblador
```
addi x1, x0, 0      # x1 = 0   (dirección base)
addi x2, x0, 25     # x2 = 25
addi x3, x0, 100    # x3 = 100
sw   x2, 0(x1)      # mem[0] = 25        (preparar dato en memoria)
lw   x4, 0(x1)      # x4 = mem[0] = 25  ← carga
add  x5, x4, x1     # x5 = 25 + 0 = 25  ← STALL: usa x4 del lw anterior
sw   x5, 0(x3)      # mem[100] = 25 ✓
```

### Máquina (hex)
```
00000093   addi x1, x0, 0
01900113   addi x2, x0, 25
06400193   addi x3, x0, 100
0020A023   sw   x2, 0(x1)
0000A203   lw   x4, 0(x1)
001202B3   add  x5, x4, x1   ← LOAD-USE HAZARD
0051A023   sw   x5, 0(x3)
```

### Pipeline con Stall

```
Ciclo:     1    2    3    4    5    6    7    8    9   10
lw  x4:   IF   ID   EX  MEM   WB                        ← dato listo al final de MEM (ciclo 5)
add x5:        IF   ID   ID   EX  MEM   WB               ← STALL: ID se repite en ciclo 4
                          ↑    ↑
                     FlushE  ForwardBE=01 (MEM/WB→EX)
                     inserta  ↑ x4 disponible ahora
                      [NOP]
sw  x5:              IF   IF   ID   EX  MEM   WB          ← también se congela
                          ↑
                      StallF,StallD
```

**Detección en `hazard.v`:**
```verilog
assign lwStall = ResultSrcE0 && (RdE == Rs1D || RdE == Rs2D);
//               ^lw en EX         ^x4 == x4 ← MATCH → stall!
```

- Ciclo 3: `lw` en EX, `add` en ID → `lwStall = 1`
  - `StallF=1`: PC no cambia
  - `StallD=1`: IF/ID no cambia (add queda en ID)
  - `FlushE=1`: ID/EX se pone a cero (NOP entra a EX)
- Ciclo 4: `lw` en MEM, NOP en EX, `add` vuelve a ID → `lwStall = 0`
- Ciclo 5: `lw` en WB, `add` en EX → `ForwardBE=01` (MEM/WB→EX) entrega x4=25 ✓

Costo: **1 ciclo perdido**.

---

## Programa 4 — Test Flushing (`test_flush.mem`)

Muestra cómo el pipeline descarta las instrucciones buscadas incorrectamente cuando un branch se toma.

### Ensamblador
```
addi x1, x0, 0      # x1 = 0
addi x2, x0, 25     # x2 = 25
addi x3, x0, 100    # x3 = 100
beq  x1, x1, +12    # branch SIEMPRE tomado (x1==x1) → salta a sw
addi x2, x0, 2047   # ← FLUSHED: nunca debe ejecutarse
addi x2, x0, 2047   # ← FLUSHED: nunca debe ejecutarse
sw   x2, 0(x3)      # mem[100] = 25 ✓   (x2 sigue siendo 25)
```

Si el flush NO funcionara, x2 se sobreescribiría con 2047 y el test fallaría.

### Máquina (hex)
```
00000093   addi x1, x0, 0
01900113   addi x2, x0, 25
06400193   addi x3, x0, 100
00108663   beq  x1, x1, +12    ← branch tomado, offset=12 bytes
7FF00113   addi x2, x0, 2047   ← FLUSHED
7FF00113   addi x2, x0, 2047   ← FLUSHED
0021A023   sw   x2, 0(x3)
```

El offset de 12 bytes: beq está en PC=12, sw en PC=24 → 24-12=12 ✓

### Pipeline con Flush

```
Ciclo:     1    2    3    4    5    6    7    8    9
addi x1:  IF   ID   EX  MEM   WB
addi x2:       IF   ID   EX  MEM   WB
addi x3:            IF   ID   EX  MEM   WB
beq:                     IF   ID   EX  MEM   WB
                               ↑    ↑
addi 2047:                    [IF] [ID] ← instrucción en ID → FlushE la convierte en NOP
addi 2047:                         [IF] ← instrucción en IF → FlushD la convierte en NOP
sw   x2:                                  IF   ID   EX  MEM   WB
                                     ↑
                          ciclo 3 del beq: PCSrcE=1 (BranchE & ZeroE)
                          PC = PCTargetE = 12 + 12 = 24 → apunta a sw ✓
```

**Cálculo de `PCSrcE` en el datapath (etapa EX):**
```verilog
assign PCSrcE  = (BranchE & ZeroE) | JumpE;
// BranchE=1 (beq), ZeroE=1 (x1-x1=0) → PCSrcE=1

assign PCNextF = PCSrcE ? PCTargetE : PCPlus4F;
// PCTargetE = PCE + ImmExtE = 12 + 12 = 24
```

**Flush en `hazard.v`:**
```verilog
assign FlushD = PCSrcE;   // limpia IF/ID: descarta addi 2047 que estaba en ID
assign FlushE = PCSrcE;   // limpia ID/EX: descarta addi 2047 que estaba en IF (ahora en ID)
```

Costo: **2 ciclos perdidos**.

---

## Cómo cambiar el programa de prueba

Editar `imem.v` y cambiar el nombre del archivo `.mem`:

```verilog
initial begin
    $readmemh("test_nodep.mem",    RAM);  // Programa 1: sin dependencias
  //$readmemh("test_forwarding.mem", RAM);  // Programa 2: forwarding
  //$readmemh("test_stall.mem",    RAM);  // Programa 3: stall
  //$readmemh("test_flush.mem",    RAM);  // Programa 4: flush
end
```

El testbench imprime `Simulation succeeded` cuando se escribe 25 en la dirección 100.

---

## Archivos del Proyecto

### Nuevos (pipeline)
| Archivo | Descripción |
|---------|-------------|
| `flopenr.v` | Flip-flop con enable y reset asíncrono — usado para el PC |
| `flopenrc.v` | Flip-flop con enable, reset asíncrono y clear síncrono — usado para IF/ID |
| `hazard.v` | Unidad de hazards: detecta y resuelve forwarding, stall y flush |
| `test_nodep.mem` | Programa 1: ISA sin dependencias |
| `test_forwarding.mem` | Programa 2: prueba forwarding |
| `test_stall.mem` | Programa 3: prueba stalling |
| `test_flush.mem` | Programa 4: prueba flushing |

### Modificados
| Archivo | Cambio |
|---------|--------|
| `datapath.v` | Reescrito: 5 etapas con 4 registros de pipeline |
| `controller.v` | Removido `Zero`/`PCSrc` (ahora `PCSrcE` se calcula en EX) |
| `regfile.v` | Agregado forwarding interno (hazard de 3 ciclos sin lógica extra) |
| `riscvsingle.v` | Reescrito: conecta `controller` + `datapath` + `hazard` |

### Sin cambios
`adder.v` · `alu.v` · `aludec.v` · `dmem.v` · `extend.v` · `flopr.v` · `imem.v` · `maindec.v` · `mux2.v` · `mux3.v` · `top.v` · `testbench.v`
