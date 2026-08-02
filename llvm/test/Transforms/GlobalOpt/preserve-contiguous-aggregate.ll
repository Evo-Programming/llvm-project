; RUN: opt -passes=globalopt -S %s | FileCheck %s

%four.i32 = type { i32, i32, i32, i32 }
%padded = type { i8, i32 }

@together = internal global %four.i32 zeroinitializer, align 4
@partial = internal global %four.i32 { i32 1, i32 2, i32 3, i32 4 }, align 4, !dbg !0
@gapped = internal global %four.i32 zeroinitializer, align 4
@load_only_gap = internal global %four.i32 { i32 0, i32 7, i32 0, i32 0 }, align 4
@store_only_gap = internal global %four.i32 zeroinitializer, align 4
@different_liveness = internal global %four.i32 zeroinitializer, align 4
@dispersed = internal global %four.i32 zeroinitializer, align 4
@transitive = internal global %four.i32 zeroinitializer, align 4
@padded = internal global %padded zeroinitializer, align 4

; Keep the complete aggregate so later passes can combine or vectorize the
; contiguous accesses.
; CHECK: @together = internal unnamed_addr global %four.i32 zeroinitializer, align 4
; CHECK-NOT: @together.
define void @access_together() {
  %a = load i32, ptr @together, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @together, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @together, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @together, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  %d.ptr = getelementptr inbounds %four.i32, ptr @together, i64 0, i32 3
  %d = load i32, ptr %d.ptr, align 4
  %d.inc = add nsw i32 %d, 1
  store i32 %d.inc, ptr %d.ptr, align 4
  ret void
}

; Group co-accessed parts while removing unused leading and trailing storage.
; CHECK: @partial.0 = internal unnamed_addr global <{ i32, i32 }> <{ i32 2, i32 3 }>, align 4
; CHECK-SAME: !dbg ![[PARTIAL_B:[0-9]+]], !dbg ![[PARTIAL_C:[0-9]+]]
; CHECK-NOT: @partial.1
; CHECK-NOT: @partial =
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

; Compact unused storage between co-accessed parts.
; CHECK: @gapped.0 = internal unnamed_addr global <{ i32, i32 }> zeroinitializer, align 4
; CHECK-NOT: @gapped.1
; CHECK-NOT: @gapped =
define void @access_gapped() {
  %a = load i32, ptr @gapped, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @gapped, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @gapped, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  ret void
}

; Pull one-sided parts into separate globals so they can be removed without
; breaking the co-access relationship between the parts on either side.
; CHECK: @load_only_gap.0 = internal unnamed_addr global <{ i32, i32 }> zeroinitializer, align 4
; CHECK-NOT: @load_only_gap.1
; CHECK-NOT: @load_only_gap =
define i32 @access_load_only_gap() {
  %a = load i32, ptr @load_only_gap, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @load_only_gap, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @load_only_gap, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @load_only_gap, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  ret i32 %b
}

; CHECK: @store_only_gap.0 = internal unnamed_addr global <{ i32, i32 }> zeroinitializer, align 4
; CHECK-NOT: @store_only_gap.1
; CHECK-NOT: @store_only_gap =
define void @access_store_only_gap(i32 %value) {
  %a = load i32, ptr @store_only_gap, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @store_only_gap, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @store_only_gap, i64 0, i32 1
  store i32 %value, ptr %b.ptr, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @store_only_gap, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  ret void
}

; Keep parts with different accessing-function sets in separate replacement
; globals so later dead stripping can discard them independently.
; CHECK-DAG: @different_liveness.0 = internal unnamed_addr global i32 0, align 4
; CHECK-DAG: @different_liveness.1 = internal unnamed_addr global <{ i32, i32, i32 }> zeroinitializer, align 4
; CHECK-NOT: @different_liveness.2
; CHECK-NOT: @different_liveness =
define void @access_all_liveness_parts() {
  %a = load i32, ptr @different_liveness, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @different_liveness, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @different_liveness, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @different_liveness, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  %d.ptr = getelementptr inbounds %four.i32, ptr @different_liveness, i64 0, i32 3
  %d = load i32, ptr %d.ptr, align 4
  %d.inc = add nsw i32 %d, 1
  store i32 %d.inc, ptr %d.ptr, align 4
  ret void
}

define i32 @access_one_liveness_part() {
  %a = load i32, ptr @different_liveness, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @different_liveness, align 4
  ret i32 %a.inc
}

; Form separate groups for parts co-accessed in different blocks.
; CHECK-DAG: @dispersed.0 = internal unnamed_addr global <{ i32, i32 }> zeroinitializer, align 4
; CHECK-DAG: @dispersed.1 = internal unnamed_addr global <{ i32, i32 }> zeroinitializer, align 4
; CHECK-NOT: @dispersed.2
; CHECK-NOT: @dispersed =
define void @access_dispersed(i1 %condition) {
entry:
  %a = load i32, ptr @dispersed, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @dispersed, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @dispersed, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  br i1 %condition, label %more, label %exit

more:
  %c.ptr = getelementptr inbounds %four.i32, ptr @dispersed, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  %d.ptr = getelementptr inbounds %four.i32, ptr @dispersed, i64 0, i32 3
  %d = load i32, ptr %d.ptr, align 4
  %d.inc = add nsw i32 %d, 1
  store i32 %d.inc, ptr %d.ptr, align 4
  br label %exit

exit:
  ret void
}

; Form one group from transitively co-accessed parts.
; CHECK: @transitive.0 = internal unnamed_addr global <{ i32, i32, i32 }> zeroinitializer, align 4
; CHECK-NOT: @transitive.1
; CHECK-NOT: @transitive =
define void @access_transitive(i1 %condition) {
entry:
  %a = load i32, ptr @transitive, align 4
  %a.inc = add nsw i32 %a, 1
  store i32 %a.inc, ptr @transitive, align 4
  %b.ptr = getelementptr inbounds %four.i32, ptr @transitive, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  br i1 %condition, label %more, label %exit

more:
  %b.more = load i32, ptr %b.ptr, align 4
  %b.more.inc = add nsw i32 %b.more, 1
  store i32 %b.more.inc, ptr %b.ptr, align 4
  %c.ptr = getelementptr inbounds %four.i32, ptr @transitive, i64 0, i32 2
  %c = load i32, ptr %c.ptr, align 4
  %c.inc = add nsw i32 %c, 1
  store i32 %c.inc, ptr %c.ptr, align 4
  br label %exit

exit:
  ret void
}

; Retain only padding needed to preserve the parts' known alignments.
; CHECK: @padded = internal unnamed_addr global %padded zeroinitializer, align 4
; CHECK-NOT: @padded.
define void @access_padded() {
  %a = load i8, ptr @padded, align 4
  %a.inc = add i8 %a, 1
  store i8 %a.inc, ptr @padded, align 4
  %b.ptr = getelementptr inbounds %padded, ptr @padded, i64 0, i32 1
  %b = load i32, ptr %b.ptr, align 4
  %b.inc = add nsw i32 %b, 1
  store i32 %b.inc, ptr %b.ptr, align 4
  ret void
}

; CHECK-LABEL: define i32 @access_load_only_gap
; CHECK: ret i32 7
; CHECK-LABEL: define void @access_store_only_gap
; CHECK-NOT: store i32 %value
; CHECK: ret void

; CHECK-DAG: ![[PARTIAL_B]] = !DIGlobalVariableExpression(var: ![[PARTIAL_VAR:[0-9]+]], expr: !DIExpression(DW_OP_LLVM_fragment, 32, 32))
; CHECK-DAG: ![[PARTIAL_C]] = !DIGlobalVariableExpression(var: ![[PARTIAL_VAR]], expr: !DIExpression(DW_OP_plus_uconst, 4, DW_OP_LLVM_fragment, 64, 32))
; CHECK-DAG: ![[PARTIAL_VAR]] = distinct !DIGlobalVariable(name: "partial"

!llvm.dbg.cu = !{!2}
!llvm.module.flags = !{!6}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(name: "partial", scope: !2, file: !3, line: 1, type: !5, isLocal: true, isDefinition: true)
!2 = distinct !DICompileUnit(language: DW_LANG_C99, file: !3, producer: "clang", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, globals: !4)
!3 = !DIFile(filename: "global-sra.c", directory: "/")
!4 = !{!0}
!5 = !DICompositeType(tag: DW_TAG_structure_type, name: "four", size: 128)
!6 = !{i32 2, !"Debug Info Version", i32 3}
