; RUN: opt -mtriple=x86_64-unknown-linux-gnu -passes='default<O2>' -S %s | FileCheck %s --check-prefix=X86
; RUN: opt -mtriple=x86_64-unknown-linux-gnu -passes='default<O2>' -S %s | llc -mtriple=x86_64-unknown-linux-gnu -O2 -relocation-model=pic -o - | FileCheck %s --check-prefix=X86-ASM
; RUN: opt -mtriple=thumbv8m.main-none-eabi -mcpu=cortex-m33 -passes='default<O2>' -S %s | llc -mtriple=thumbv8m.main-none-eabi -mcpu=cortex-m33 -O2 -relocation-model=pic -o - | FileCheck %s --check-prefix=ARM

%four.i32 = type { i32, i32, i32, i32 }

@g = internal global %four.i32 zeroinitializer, align 4
@g_partial = internal global %four.i32 zeroinitializer, align 4
@g_gapped = internal global %four.i32 zeroinitializer, align 4
@g_size = internal global %four.i32 zeroinitializer, align 4

; X86-LABEL: define void @test()
; X86: load <4 x i32>, ptr @g
; X86: add{{.*}}<4 x i32>
; X86: store <4 x i32>
define void @test() {
  %a = load i32, ptr @g, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @g, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @g, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @g, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  %d.ptr = getelementptr inbounds %four.i32, ptr @g, i64 0, i32 3
  %d = load i32, ptr %d.ptr, align 4
  %d.inc = add nsw i32 %d, 1
  store i32 %d.inc, ptr %d.ptr, align 4
  ret void
}

; X86-LABEL: define void @test_partial()
; X86: load <2 x i32>, ptr @g_partial.0
; X86: add{{.*}}<2 x i32>
; X86: store <2 x i32>
; ARM-LABEL: test_partial:
; ARM: ldrd
; ARM: strd
define void @test_partial() {
  %a = load i32, ptr @g_partial, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @g_partial, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @g_partial, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  ret void
}

; X86-LABEL: define void @test_gapped()
; X86: load <2 x i32>, ptr @g_gapped.0
; X86: add{{.*}}<2 x i32>
; X86: store <2 x i32>
; X86-ASM-LABEL: test_gapped:
; X86-ASM: movq g_gapped.0(%rip), %xmm0
; X86-ASM: psubd
; X86-ASM: movq %xmm0, g_gapped.0(%rip)
; ARM-LABEL: test_gapped:
; ARM: ldrd
; ARM: strd
define void @test_gapped() {
  %a = load i32, ptr @g_gapped, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @g_gapped, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @g_gapped, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  ret void
}

; ARM-LABEL: test_size:
; ARM: ldm
; ARM: stm
define void @test_size() optsize {
  %a = load i32, ptr @g_size, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @g_size, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @g_size, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @g_size, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  %d.ptr = getelementptr inbounds %four.i32, ptr @g_size, i64 0, i32 3
  %d = load i32, ptr %d.ptr, align 4
  %d.inc = add nsw i32 %d, 1
  store i32 %d.inc, ptr %d.ptr, align 4
  ret void
}
