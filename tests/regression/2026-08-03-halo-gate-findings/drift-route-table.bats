#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-03-halo-gate-findings.md
#   （聚合上报，8 条已修缺陷按缺陷拆分到本目录；映射见 docs/bug_report/INDEX.md）
# Root cause class: D. 非确定性依赖（列序）+ F. 语法变体覆盖不足
# Fixed by: df7991e (#12 "Stop drift-check from reporting unchecked dimensions as clean"；
#   错误码与路由表两个缺陷在同一次提交里一并修复，见
#   docs/bug_report/2026-08-03-halo-gate-findings-analysis.md §2)
#
# 复核 §2 的结论：旧版 `drift-check.sh:163-170`（修复前）把方法固定读 awk 第 3 字段、
# 路径固定读第 4 字段——表格列序成了任何文档都没声明的隐式契约。更严重的是，
# 中文列序表 `| 端点 | 方法 | 说明 |` 在旧实现下**不是提取失败，而是把「说明」列
# 当成了路径**：spec_routes 计数正常，比对结果却全错，是一条不会报错的假绿。
#
# 修复后：表格解析按表头名（`Method|方法` 与 `Path|路径|端点|URL|Endpoint`）定位两列，
# 找不到表头才回退到旧的 $3/$4；数据行额外要求路径以 `/` 开头。同时实装了 FastAPI
# 路由检测：抓装饰器/`APIRouter(prefix=)` 前缀做笛卡尔拼接。
#
# fixture 见 tests/fixtures/drift/fastapi-prefixed-router/：`APIRouter(prefix="/api")` +
# 单行 get/post("/model-sets")，刻意缺 DELETE；两份 spec 变体一份方法列在前，
# 一份路径列在前（且是中文表头，逐字取自复核 §2 举的例子）。

load "../../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  halo_set_language python
  halo_set_framework fastapi
  halo_install_fixture drift/fastapi-prefixed-router
}

@test "an unregistered FastAPI route is reported as drift" {
  # 复核 §2：fixture 的 routers.py 只注册了 GET/POST /model-sets，刻意缺 DELETE。
  # PROJECT 指向 fixture 自己的子目录 drift/prefixed，不是整个 $SANDBOX
  # （fixtures/README.md 第五条约束——指向 $SANDBOX 会把 vendor 进来的框架源码树
  # 一起当项目代码扫描，兄弟 fixture 互相污染）。
  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/prefixed/spec-method-first.md" "$SANDBOX/drift/prefixed" \
    --json-out="$SANDBOX/drift-route.json"
  assert_failure 1

  run yq -e '.metrics.spec_routes == 3
    and .metrics.drift_count == 1
    and .metrics.checked.routes == true' "$SANDBOX/drift-route.json"
  assert_success
}

@test "the gate passes once every FastAPI route is registered" {
  # 复核 §2 的反向态：补齐 DELETE handler 后应转为无漂移。
  cat >> "$SANDBOX/drift/prefixed/src/routers.py" << 'PY'


@router.delete("/model-sets/{set_id}")
def delete_model_set(set_id: str):
    return {}
PY

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/prefixed/spec-method-first.md" "$SANDBOX/drift/prefixed" \
    --json-out="$SANDBOX/drift-route-clean.json"
  assert_success

  run yq -e '.metrics.drift_count == 0
    and .metrics.checked.routes == true' "$SANDBOX/drift-route-clean.json"
  assert_success
}

@test "route table columns are located by header name, not by position" {
  # 复核 §2：spec-path-first.md 是「端点 | 方法 | 说明」中文表头、端点列在前——
  # 逐字取自复核举的那个「说明列被误当路径」的例子。列序必须靠表头名定位，
  # 不能靠第 3/4 字段的位置假设。代码侧已补齐 DELETE，预期无漂移。
  cat >> "$SANDBOX/drift/prefixed/src/routers.py" << 'PY'


@router.delete("/model-sets/{set_id}")
def delete_model_set(set_id: str):
    return {}
PY

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/prefixed/spec-path-first.md" "$SANDBOX/drift/prefixed" \
    --json-out="$SANDBOX/drift-route-order.json"
  assert_success

  # `checked.routes` 不是装饰性断言：路由维度有六条 gate_skip 出口，任何一条被走到时
  # drift_count 都保持 0 且 gate 仍 exit 0——「压根没验」与「验过且干净」在
  # assert_success + drift_count == 0 之下完全同形。spec_routes 也救不了场：它在
  # gate_skip 分支之前就算好，跳过时照常输出。mark_checked 置的这个标志位是区分
  # 二者的唯一信号，缺了它本用例会把静默跳过读成通过（#12 要根除、O-16 同族的形态）。
  run yq -e '.metrics.spec_routes == 3
    and .metrics.drift_count == 0
    and .metrics.checked.routes == true' "$SANDBOX/drift-route-order.json"
  assert_success
}

@test "a path-first column order still reports a genuinely missing route" {
  # drt-4（本批次新增，收紧方向）：drt-3/drt-4 真实守住的是「列序无关」这个维度——
  # 已由一条精确变异证明：把 awk 里 `mi = hm; pi = hp` 硬编码成 `mi = 2; pi = 3` 时，
  # drt-1/drt-2（方法列在前的 spec）仍绿，drt-3/drt-4（路径列在前）转红。
  # 这里用同一份列序倒置 spec 配**未补齐**（仍缺 DELETE）的代码，钉住真缺失
  # 依然要被抓出来，而不是被列序解析的松弛悄悄吞掉。
  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/prefixed/spec-path-first.md" "$SANDBOX/drift/prefixed" \
    --json-out="$SANDBOX/drift-route-order-missing.json"
  assert_failure 1

  run yq -e '.metrics.spec_routes == 3
    and .metrics.drift_count == 1' "$SANDBOX/drift-route-order-missing.json"
  assert_success
}
