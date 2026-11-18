//==- ARMScheduleM33.td - Cortex-M33 Scheduling Definitions -*- tablegen -*-====//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines the SchedRead/Write data for the ARM Cortex-M33 processor.
//
//===----------------------------------------------------------------------===//

class ShiftedRegNotLsl0To3<int n> : CheckNot<
                                      CheckAny<[
                                        CheckSORegNoShift<n>,
                                        CheckAll<[
                                          CheckSORegShiftLSL<n>,
                                          CheckAny<[
                                            CheckSORegOffset<n, 0>,
                                            CheckSORegOffset<n, 1>,
                                            CheckSORegOffset<n, 2>,
                                            CheckSORegOffset<n, 3>,
                                          ]>
                                        ]>
                                      ]>
                                    >;

class ShiftedRegNotLsl0To3Pred<int n> : MCSchedPredicate<ShiftedRegNotLsl0To3<n>>;

def CortexM33Model : SchedMachineModel {
  let IssueWidth        = 2; // Limited dual-issue of 16-bit instruction pairs
  let MicroOpBufferSize = 0; // In-order
  let LoadLatency       = 2; // Latency when not pipelined
  let MispredictPenalty = 2; // Best case branch taken cost
  let PostRAScheduler   = 1;

  let CompleteModel = 0;
  let FullInstRWOverlapCheck = 1;
  let UnsupportedFeatures = [IsARM, HasNEON, HasDotProd, HasZCZ, HasMVEInt,
          IsNotMClass, HasDPVFP, HasFPARMv8, HasFullFP16, HasV8_3a, HasDFB,
          IsWindows];
}

// We model the cpu as pipelines with BufferSize = 0 for in-order execution.
// Since Cortex-M33 dual-issue depends on whether an instruction is the first
// or second 16-bit instruction in a 32-bit word, we define two execution units
// based on which halfword the instruction can be issued from.
// Wide instructions always require both execution units.

def M33EX0 : ProcResource<1> { let BufferSize = 0; }
def M33EX1 : ProcResource<1> { let BufferSize = 0; }

// This variable is used for wide instructions to occupy both execution units.
defvar M33Unit = [M33EX0, M33EX1];

// Due to restrictions on dual-issuing conditional branch and narrow MUL,
// define an execution unit consumed only by both of those instruction types.
def M33MulUnit : ProcResource<1> { let BufferSize = 0; }

// When FPU is present, FP operations can run in parallel with integer
// operations after issue.
def M33FPUnit : ProcResource<1> { let BufferSize = 0; }

let SchedModel = CortexM33Model in {

// This group is used for 16-bit instructions which may be issued as either
// the first or second instruction in a 32-bit word.
def M33EXAny : ProcResGroup<[M33EX0, M33EX1]>;

// Latency definitions for typical 32-bit instructions,
// which occupy both execution units and cannot be dual-issued.
def M33UnitL1 : SchedWriteRes<M33Unit> { let Latency = 1; }
def M33UnitL2 : SchedWriteRes<M33Unit> { let Latency = 2; }
def M33UnitL3 : SchedWriteRes<M33Unit> { let Latency = 2; }
def M33UnitL2_E2 : SchedWriteRes<M33Unit> { let Latency = 2;
                                            let ReleaseAtCycles = [2, 2]; }
def M33UnitL12_E11 : SchedWriteRes<M33Unit> { let Latency = 12;
                                              let ReleaseAtCycles = [11, 11]; }
class M33UnitL1I<dag instr> : InstRW<[M33UnitL1], instr>;
class M33UnitL2I<dag instr> : InstRW<[M33UnitL2], instr>;

// Latency definitions for typical 16-bit instructions,
// which can only be issued as the first instruction in a pair.
def M33EX0_L1 : SchedWriteRes<[M33EX0]> { let Latency = 1; }
def M33EX0_L2 : SchedWriteRes<[M33EX0]> { let Latency = 2; }
def M33EX0_MUL_L2 : SchedWriteRes<[M33EX0, M33MulUnit]> { let Latency = 2; }
def M33EX0_MUL_L2_E2 : SchedWriteRes<[M33EX0, M33MulUnit]> { let Latency = 2;
                                                             let ReleaseAtCycles = [2, 2]; }

// Latency definitions for 16-bit instructions issuable as either
// instruction in a pair.
def M33EXAny_L1 : SchedWriteRes<[M33EXAny]> { let Latency = 1; }
def M33EXAny_MUL_L1 : SchedWriteRes<[M33EXAny, M33MulUnit]> { let Latency = 1; }

def M33WrBackOne : SchedWriteRes<[]> {
  let Latency = 1;
  let NumMicroOps = 0;
}
def M33WrBackTwo : SchedWriteRes<[]> {
  let Latency = 2;
  let NumMicroOps = 0;
}

// Loads have latency 2
def : SchedAlias<WriteLd, M33UnitL2>;
// Load base register writeback has latency 1
def : InstRW<[WriteLd, M33WrBackOne], (instregex "t2LDR[^D]")>;
// Load double has a latency of 3 for the second register
def : InstRW<[WriteLd, M33UnitL3, M33WrBackOne], (instregex "t2LDRD")>;

// Handle 16-bit loads for dual-issue
def : InstRW<[M33EX0_L2, M33WrBackOne], (instregex "tLDR")>;

class M33NumOpsPred<int NumOps> : MCSchedPredicate<CheckNumOperands<NumOps>>;

// LDM reads 1 register per cycle
class M33LDMWriteOp<list<ProcResourceKind> resources, int OpIndex> : SchedWriteRes<resources> {
  let Latency = !add(OpIndex, 2);
}
class M33LDMSchedVar<list<ProcResourceKind> resources, int BaseOps, int NumOps> :
  SchedVar<M33NumOpsPred<!add(BaseOps, NumOps)>,
           !foreach(OpIndex, !range(NumOps), M33LDMWriteOp<resources, OpIndex>)>;

class M33WriteLDM<list<ProcResourceKind> resources, int BaseOps> : SchedWriteVariant<
  !foreach(NumOps, !range(1, 17), M33LDMSchedVar<resources, BaseOps, NumOps>)
> { let Variadic=1; }

// 32-bit LDM
def : InstRW<[M33WriteLDM<M33Unit, 3>], (instregex "t2LDM(IA|DB)$")>;
def : InstRW<[M33WrBackOne, M33WriteLDM<M33Unit, 4>], (instregex "t2LDM(IA|DB)_UPD")>;
// 16-bit LDM
def : InstRW<[M33WriteLDM<[M33EX0], 3>], (instregex "tLDM(IA|DB)$")>;
def : InstRW<[M33WrBackOne, M33WriteLDM<[M33EX0], 4>], (instregex "tLDM(IA|DB)_UPD", "tPOP")>;

// Give store transfer registers a special read operand type so they can be advanced
def M33ReadST : SchedReadAdvance<1>;
// Store base register writeback has latency 1
def : SchedAlias<WriteST, M33UnitL1>;
// Store non-double has latency 1
def : InstRW<[M33UnitL1, M33ReadST], (instregex "t2ST(R|L)(B|H)?[^DE]")>;
// Store exclusive has latency 2 for the status output
def : InstRW<[M33UnitL2, M33ReadST], (instregex "t2ST(R|L)EX")>;
// Store double executes for 2 cycles
def : InstRW<[M33UnitL2_E2, M33ReadST, M33ReadST], (instregex "t2STRD")>;

// Handle 16-bit stores for dual-issue
def : InstRW<[M33EX0_L1, M33ReadST], (instregex "tSTR")>;

// STM writes 1 register per cycle
class M33STMWriteOp<list<ProcResourceKind> resources, int NumOps> : SchedWriteRes<resources> {
  let Latency = NumOps;
  let ReleaseAtCycles = !listsplat(NumOps, !size(resources));
}

class M33STMSchedVar<list<ProcResourceKind> resources, int BaseOps, int NumOps> :
  SchedVar<M33NumOpsPred<!add(BaseOps, NumOps)>,
           [M33STMWriteOp<resources, NumOps>]>;

class M33WriteSTM<list<ProcResourceKind> resources, int BaseOps> : SchedWriteVariant<
  !foreach(NumOps, !range(1, 17), M33STMSchedVar<resources, BaseOps, NumOps>)
>;

defvar M33STMReads = !listsplat(ReadDefault, 3) # !listsplat(M33ReadST, 16);

// 32-bit STM
def : InstRW<[M33WriteSTM<M33Unit, 3>] # M33STMReads, (instregex "t2STM(IA|DB)$")>;
def : InstRW<[M33WriteSTM<M33Unit, 4>] # M33STMReads, (instregex "t2STM(IA|DB)_UPD")>;
// 16-bit STM
def : InstRW<[M33WriteSTM<[M33EX0], 4>] # M33STMReads, (instrs tSTMIA_UPD, tPUSH)>;

// MULs have latency 2, and 64-bit writeback does not consume additional cycles
def : SchedAlias<WriteMUL32, M33UnitL2>;
def : SchedAlias<WriteMUL64Lo, M33UnitL2>;
def : SchedAlias<WriteMUL64Hi, M33WrBackTwo>;
def : SchedAlias<WriteMUL16, M33UnitL2>;
def : SchedAlias<WriteMAC32, M33UnitL2>;
def : SchedAlias<WriteMAC64Lo, M33UnitL2>;
def : SchedAlias<WriteMAC64Hi, M33WrBackTwo>;
def : SchedAlias<WriteMAC16, M33UnitL2>;

// Flag-setting MUL occupies the execute stage for its duration,
// and the 16-bit form in general does not dual-issue with conditional branches.
def M33WriteThumbMUL : SchedWriteVariant<[
  SchedVar<IsCPSRDefinedPred, [M33EX0_MUL_L2_E2]>,
  SchedVar<NoSchedPred,       [M33EX0_MUL_L2]>
]>;
def : InstRW<[M33WriteThumbMUL], (instrs tMUL)>;

// DIVs have a maximum latency of 12, and occupy execution for all but the last cycle
def : SchedAlias<WriteDIV, M33UnitL12_E11>;

// Shifted register operands have latency 2 if anything other than LSL 0-3
class M33WriteALUsi<int n> : SchedWriteVariant<[
  SchedVar<AllOfSchedPreds<[ShiftedRegNotLsl0To3Pred<n>, IsCPSRDefinedPred]>, [M33UnitL2_E2]>,
  SchedVar<ShiftedRegNotLsl0To3Pred<n>, [M33UnitL2]>,
  SchedVar<NoSchedPred, [M33UnitL1]>
]>;

def M33WriteCMPsi : SchedWriteVariant<[
  SchedVar<ShiftedRegNotLsl0To3Pred<2>, [M33UnitL2_E2]>,
  SchedVar<NoSchedPred, [M33UnitL1]>
]>;

def : InstRW<[M33WriteALUsi<2>], (instregex "t2MVNS?s$")>;
def : InstRW<[M33WriteALUsi<3>], (instregex "t2(ADD|SUB|RSB|ADC|SBC|AND|BIC|ORR|ORN|EOR)S?rs$")>;
def : InstRW<[M33WriteCMPsi], (instregex "t2(CMP|CMN|TST|TEQ)rs$")>;

// Rotated immediate operands have latency 2
class M33WriteALUi<int n> : SchedWriteVariant<[
  SchedVar<AllOfSchedPreds<[IsT2SOImmValRotatePred<n>, IsCPSRDefinedPred]>, [M33UnitL2_E2]>,
  SchedVar<IsT2SOImmValRotatePred<n>, [M33UnitL2]>,
  SchedVar<NoSchedPred, [M33UnitL1]>
]>;

def M33WriteCMPi : SchedWriteVariant<[
  SchedVar<IsT2SOImmValRotatePred<1>, [M33UnitL2_E2]>,
  SchedVar<NoSchedPred, [M33UnitL1]>
]>;

def : InstRW<[M33WriteALUi<1>], (instregex "t2MVNS?i$")>;
def : InstRW<[M33WriteALUi<2>], (instregex "t2(ADD|SUB|RSB|ADC|SBC|AND|BIC|ORR|ORN|EOR)S?(ri|spImm)$")>;
def : InstRW<[M33WriteCMPi], (instregex "t2(CMP|CMN|TST|TEQ)ri$")>;

// The only high-latency DSP instruction documented by the RP2350 Datasheet,
// other than multiplications handled generically above, is SEL
def : M33UnitL2I<(instrs t2SEL)>;

// Handle 16-bit instructions dual-issuable in the second halfword
def M33WriteHint : SchedWriteVariant<[
  SchedVar<MCSchedPredicate<CheckImmOperand<0, 0>>, [M33EXAny_L1]>,
  SchedVar<NoSchedPred, [M33EX0_L1]>
]>;
def M33WriteBX : SchedWriteVariant<[
  SchedVar<MCSchedPredicate<CheckRegOperand<0, LR>>, [M33EXAny_L1]>,
  SchedVar<NoSchedPred, [M33EX0_L1]>
]>;
def : InstRW<[M33WriteHint], (instrs tHINT)>;
def : InstRW<[M33WriteBX], (instrs tBX)>;
def : InstRW<[M33EXAny_L1], (instregex "tB$", "tBX_RET", "t2IT")>;
def : InstRW<[M33EXAny_MUL_L1], (instrs tBcc)>;

// Miscellaneous 1-cycle latency 16-bit instructions for dual-issue
def : InstRW<[M33EX0_L1], (instregex "t(ADD|SUB|RSB|ADC|SBC|CMP[^_]|CMN|ADJ|ADR|LEA|PICADD)")>;
def : InstRW<[M33EX0_L1], (instregex "t(MOV|MVN|AND|BIC|ORR|EOR|TST|ASR|LSL|LSR|ROR|REV|SXT|UXT)")>;
def : InstRW<[M33EX0_L1], (instregex "t(BXNS|BLX)")>;

// Everything else has a Latency of 1
def : SchedAlias<WriteALU, M33UnitL1>;
def : SchedAlias<WriteALUsi, M33UnitL1>;
def : SchedAlias<WriteALUsr, M33UnitL1>;
def : SchedAlias<WriteALUSsr, M33UnitL1>;
def : SchedAlias<WriteBr, M33UnitL1>;
def : SchedAlias<WriteBrL, M33UnitL1>;
def : SchedAlias<WriteBrTbl, M33UnitL1>;
def : SchedAlias<WriteCMP, M33UnitL1>;
def : SchedAlias<WriteCMPsi, M33UnitL1>;
def : SchedAlias<WriteCMPsr, M33UnitL1>;
def : SchedAlias<WriteNoop, M33UnitL1>;
def : SchedAlias<WritePreLd, M33UnitL1>;
def : M33UnitL1I<(instregex "t2MOV")>;
def : M33UnitL1I<(instrs COPY)>;
def : M33UnitL1I<(instregex "t2MSR", "t2MRS")>;
def : M33UnitL1I<(instregex "t2CLREX")>;

// These instructions are not of much interest to scheduling as they will not
// be generated or it is not very useful to schedule them. They are here to make
// the model more complete.
def : M33UnitL1I<(instregex "t2CDP", "t2LDC", "t2MCR", "t2MRC", "t2MRRC", "t2STC")>;
def : M33UnitL1I<(instregex "tCPS", "t2ISB", "t2DSB", "t2DMB", "t2HINT$")>;
def : M33UnitL1I<(instregex "t2?UDF$", "tBKPT", "t2DBG")>;
def : M33UnitL1I<(instregex "t?2?Int_eh_sjlj_", "ADJCALL")>;
def : M33UnitL1I<(instregex "CMP_SWAP", "JUMPTABLE", "MEMCPY")>;
def : M33UnitL1I<(instregex "VSETLNi32", "VGETLNi32")>;

def : ReadAdvance<ReadALU, 0>;
def : ReadAdvance<ReadALUsr, 0>;
def : ReadAdvance<ReadMUL, 0>;
def : ReadAdvance<ReadMAC, 1>;

// The following is based on the RP2350 Datasheet, except for loads/stores
// which are assumed to be identical to integer loads/stores plus FPU resource.

// FPU instructions retire out-of-order with the main pipeline,
// but require at least 1 main pipeline execution cycle to be issued.
// These instructions are always 32-bit and never dual-issue.
defvar M33FPUnitIssue = M33Unit # [M33FPUnit];

let RetireOOO = 1 in {
  def M33FPUnitL1 : SchedWriteRes<M33FPUnitIssue> { let Latency = 1; }
  def M33FPUnitL2 : SchedWriteRes<M33FPUnitIssue> { let Latency = 2; }
  def M33FPUnitL2_F2 : SchedWriteRes<M33FPUnitIssue> {
    let Latency = 2;
    let ReleaseAtCycles = [1, 1, 2];
  }
  def M33FPUnitL4_F3 : SchedWriteRes<M33FPUnitIssue> {
    let Latency = 4;
    let ReleaseAtCycles = [1, 1, 3];
  }
  def M33FPUnitL15_F14 : SchedWriteRes<M33FPUnitIssue> {
    let Latency = 15;
    let ReleaseAtCycles = [1, 1, 14];
  }
}
def M33FPUnitL2_E2_F2 : SchedWriteRes<M33FPUnitIssue> {
  let Latency = 2;
  let ReleaseAtCycles = [2, 2, 2];
}

def : SchedAlias<WriteFPCVT, M33FPUnitL1>;
def : SchedAlias<WriteFPMOV, M33FPUnitL1>;
def : SchedAlias<WriteFPALU32, M33FPUnitL2>;
def : SchedAlias<WriteFPALU64, M33FPUnitL2>;
def : SchedAlias<WriteFPMUL32, M33FPUnitL2>;
def : SchedAlias<WriteFPMUL64, M33FPUnitL2>;
def : InstRW<[M33FPUnitL2], (instregex "VLD")>;
def : InstRW<[M33FPUnitL1, M33ReadST], (instregex "VST")>;
def : SchedAlias<WriteFPMAC32, M33FPUnitL4_F3>;
def : SchedAlias<WriteFPMAC64, M33FPUnitL4_F3>;
def : SchedAlias<WriteFPDIV32, M33FPUnitL15_F14>;
def : SchedAlias<WriteFPDIV64, M33FPUnitL15_F14>;
def : SchedAlias<WriteFPSQRT32, M33FPUnitL15_F14>;
def : SchedAlias<WriteFPSQRT64, M33FPUnitL15_F14>;
def : InstRW<[M33FPUnitL1], (instregex "VMOVS", "FCONSTS", "VCMP", "VNEG", "VABS")>;
def : InstRW<[M33FPUnitL2_F2], (instregex "VMOVD")>;
def : InstRW<[M33FPUnitL2], (instregex "VMOVRS")>;
def : InstRW<[M33FPUnitL2_E2_F2], (instregex "VMOVRRD")>;
def : InstRW<[M33FPUnitL1], (instregex "VMRS", "VMSR", "FMSTAT")>;

def : ReadAdvance<ReadFPMUL, 0>;
def : ReadAdvance<ReadFPMAC, 1>;

def : WriteRes<WriteVLD1, []>;
def : WriteRes<WriteVLD2, []>;
def : WriteRes<WriteVLD3, []>;
def : WriteRes<WriteVLD4, []>;
def : WriteRes<WriteVST1, []>;
def : WriteRes<WriteVST2, []>;
def : WriteRes<WriteVST3, []>;
def : WriteRes<WriteVST4, []>;

}
