#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-03-fastapi-collection-root-route-dropped.md
# Root cause class: C. 失败方向搞反 + F. 语法变体覆盖不足
# Fixed by: 55db4cb
#
# spec 侧丢一行 = 少比一条（fail-closed 可接受）；
# code 侧丢一行 = 凭空多报一条漂移（必须 fail-open）。
# #12 把 spec 侧的「路径必须以 / 开头」谓词原样搬到了 code 侧（drift-check.sh:325）。
#
# fixture 见 tests/fixtures/README.md：
#   drift/fastapi-collection-root → fca-1/fca-2（空路径 `get("")`/`post("")`)
#   drift/fastapi-slash-root      → fca-5（独立目录，`get("/")`，防止两种回归互相掩护）
#   drift/fastapi-multiline       → fca-3/fca-4（多行装饰器 + 多行 APIRouter prefix）
# PROJECT 参数必须指向 fixture 自己的子目录，不能指向整个 $SANDBOX
# （README「五条容易踩的约束」第五条——否则 vendor 进 .halo/framework/ 的框架自身
# 源码树会被一并当项目代码扫描，兄弟 fixture 互相污染，失败表现是假绿）。

load "../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  halo_set_language python
  halo_set_framework fastapi
}

@test "an empty-path collection root is registered through the router prefix" {
  # 分析 §1-§3：`APIRouter(prefix="/model-sets")` + `@router.get("")`/`post("")` 的
  # 空路径装饰器曾被 code 侧 `[[ "$path" == /* ]] || continue` 整条丢弃——continue 在
  # prefix 拼接循环之前，丢的不只是裸路径而是整条注册记录。fixture 刻意缺 DELETE：
  # 三条空路径/带参路由必须被认出已注册，同时真缺的那一条仍要被抓出来。
  halo_install_fixture drift/fastapi-collection-root

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/collection-root/spec.md" "$SANDBOX/drift/collection-root" \
    --json-out="$SANDBOX/drift-collection-root.json"
  assert_failure 1

  run yq -e '.metrics.spec_routes == 4
    and .metrics.drift_count == 1' "$SANDBOX/drift-collection-root.json"
  assert_success
}

@test "the gate passes once a prefix-only router is complete" {
  # 分析 §5 的修复反向态：补齐 DELETE handler 后应转为无漂移，证明 fail-open 的
  # 空路径守卫没有引入假阴性——该报的漂移仍然报，不该报的不再凭空产生。
  halo_install_fixture drift/fastapi-collection-root
  cat >> "$SANDBOX/drift/collection-root/src/routers.py" << 'PY'


@router.delete("/{set_id}")
def delete_model_set(set_id: str):
    return {}
PY

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/collection-root/spec.md" "$SANDBOX/drift/collection-root" \
    --json-out="$SANDBOX/drift-collection-root-clean.json"
  assert_success

  run yq -e '.metrics.drift_count == 0
    and .metrics.checked.routes == true' "$SANDBOX/drift-collection-root-clean.json"
  assert_success
}

@test "multi-line route decorators are read as registrations" {
  # 分析 §4：grep 按行工作，跨多行的 `post(...)`/`delete(...)` 装饰器曾完全匹配不到，
  # 失败表现与 #16 上报的缺陷相同——凭空多报漂移。本用例只测装饰器本身的多行读取，
  # 用一份剔除了 fca-4 专属「GET /api」行（该行是多行 prefix 陷阱的专属信号，见下一条
  # 用例）的 3 路由 spec 变体；单行 `GET /reports` 兜底防止 CODE_ROUTES 判空触发
  # gate_skip 假通过（README 第四条约束）。
  halo_install_fixture drift/fastapi-multiline
  awk '!/^\| GET \| \/api \| 报表服务根 \|$/' "$SANDBOX/drift/multiline/spec.md" \
    > "$SANDBOX/drift/multiline/spec-decorators-only.md"

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/multiline/spec-decorators-only.md" "$SANDBOX/drift/multiline" \
    --json-out="$SANDBOX/drift-multiline.json"
  assert_success

  run yq -e '.metrics.spec_routes == 3
    and .metrics.drift_count == 0
    and .metrics.checked.routes == true' "$SANDBOX/drift-multiline.json"
  assert_success
}

@test "a multi-line APIRouter prefix is read" {
  # 分析 §4 逐字点名、旧三条断言完全没覆盖的第二种形态：跨多行的
  # `APIRouter(\n    prefix="/api",\n)` 声明。`@router.get("")` 只靠 prefix 展开成
  # `GET /api`，装饰器路径本身不带任何段——是多行 prefix 读取失败时唯一不会被
  # `route_registered` 的「结尾段宽容匹配」掩盖的信号（其余装饰器自带完整路径段，
  # 即使 prefix 读取失败仍会靠该宽容匹配假通过）。用完整 4 路由 spec（含该行），
  # 既验证整体无漂移，也直接点名这条依赖 prefix 展开的路由被判为已注册。
  halo_install_fixture drift/fastapi-multiline

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/multiline/spec.md" "$SANDBOX/drift/multiline" \
    --json-out="$SANDBOX/drift-multiline-prefix.json"
  assert_success

  run yq -e '.metrics.spec_routes == 4
    and .metrics.drift_count == 0
    and .metrics.checked.routes == true' "$SANDBOX/drift-multiline-prefix.json"
  assert_success

  run yq -e '.findings[] | select(.category == "routes"
    and .status == "pass"
    and .message == "Route: GET /api")' "$SANDBOX/drift-multiline-prefix.json"
  assert_success
}

@test "the \"/\" collection root form still resolves through the prefix" {
  # 分析 §5/§6：修复放宽了空路径守卫（`-z "$path"` 分支），必须证明没弄坏既有
  # `"/"` 形态——`@router.get("/")` 走的是守卫里 `"$path" == /*` 那一半，不是新放宽
  # 的 `-z` 那一半。必须用独立 fixture（README 第三条约束）：同一份 routers.py 里
  # 同时放 `get("")` 与 `get("/")` 会让 `route_registered` 的结尾段宽松匹配把空路径
  # 漏检掩盖掉。补齐 DELETE 后应无漂移，与 fca-2 对称。
  halo_install_fixture drift/fastapi-slash-root
  cat >> "$SANDBOX/drift/slash-root/src/routers.py" << 'PY'


@router.delete("/{report_id}")
def delete_report(report_id: str):
    return {}
PY

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/slash-root/spec.md" "$SANDBOX/drift/slash-root" \
    --json-out="$SANDBOX/drift-slash-root.json"
  assert_success

  run yq -e '.metrics.drift_count == 0' "$SANDBOX/drift-slash-root.json"
  assert_success
}
