; RUN: opt -passes=globalopt %s | llc -mtriple=x86_64-unknown-linux-gnu -filetype=obj -o %t
; RUN: llvm-dwarfdump --debug-info %t | FileCheck %s
; RUN: llvm-dwarfdump --verify %t

%four.i32 = type { i32, i32, i32, i32 }

@partial = internal global %four.i32 { i32 1, i32 2, i32 3, i32 4 }, align 4, !dbg !0

; CHECK: DW_TAG_variable
; CHECK-NEXT: DW_AT_name ("partial")
; CHECK: DW_AT_location (DW_OP_piece 0x4, DW_OP_addr {{.*}}, DW_OP_piece 0x4, DW_OP_addr {{.*}}, DW_OP_plus_uconst 0x4, DW_OP_piece 0x4)

define void @access_partial() {
  %b.ptr = getelementptr inbounds %four.i32, ptr @partial, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @partial, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  ret void
}

!llvm.dbg.cu = !{!2}
!llvm.module.flags = !{!6}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(name: "partial", scope: !2, file: !3, line: 1, type: !5, isLocal: true, isDefinition: true)
!2 = distinct !DICompileUnit(language: DW_LANG_C99, file: !3, producer: "clang", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, globals: !4)
!3 = !DIFile(filename: "global-sra.c", directory: "/")
!4 = !{!0}
!5 = !DICompositeType(tag: DW_TAG_structure_type, name: "four", size: 128)
!6 = !{i32 2, !"Debug Info Version", i32 3}
