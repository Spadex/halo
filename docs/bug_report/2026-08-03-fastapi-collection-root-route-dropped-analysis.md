# 分析：drift-check 丢弃 FastAPI 集合根路由

上报原文：[`2026-08-03-fastapi-collection-root-route-dropped.md`](2026-08-03-fastapi-collection-root-route-dropped.md)
（上报日期 2026-08-03，指向 `df7991e (#12)` 新实装的 FastAPI 路由漂移检测）。
上报者按纪律只上报不改框架代码，本文是 halo 侧的独立复核。

涉及脚本：`harness-template/halo/kernel/delivery/gates/drift-check.sh`。

## 结论

上报成立，缺陷真实且定位准确：`drift-check.sh` 会把 FastAPI 标准的集合根注册
`APIRouter(prefix="/x") + @router.get("")` 整条丢弃，导致 spec 中**已经实现**的路由被判为
`Spec route not registered in code`，gate 误报 FAIL。

这是 `df7991e (#12)` 引入的新缺陷 —— 不是历史遗留：该提交之前 FastAPI 分支是
`gate_skip "Framework 'fastapi' route drift detection: not yet implemented"`，
`collect_code_routes` 整个函数是这次新写的。

复核中另发现**同一函数、同一提交引入、上报未覆盖**的第二个同类缺陷：多行装饰器
（以及多行 `APIRouter(...)` prefix）因为 grep 按行工作而完全匹配不到，失败表现同样是误报漂移。

已修复，并补上三条确定性回归断言与一个可运行示例工程作为护栏。

## 1. 缺陷位置

`harness-template/halo/kernel/delivery/gates/drift-check.sh:305`（修复前）：

```bash
collect_code_routes() {
  local raw="$1" prefixes="$2" line method path prefix
  while IFS= read -r line; do
    ...
    path="$(printf '%s' "$line" | sed -E 's/.*[("'"'"'`]([^"'"'"'`]*)$/\1/')"
    [[ "$path" == /* ]] || continue        # ← 在 prefix 拼接之前
    printf '%s %s\n' "$method" "$(normalize_path "$path")"
    while IFS= read -r prefix; do
      ...
      printf '%s %s\n' "$method" "$(normalize_path "${prefix}${path}")"
    done <<< "$prefixes"
  done <<< "$raw"
}
```

`continue` 位于 prefix 展开循环**之前**，所以被丢的不只是裸路径，而是整条注册记录。

## 2. 复现

按脚本原样重放提取管线：

```
raw=[@router.get("]          method=[GET]   path=[]           -> DROPPED (continue)
raw=[@router.post("]         method=[POST]  path=[]           -> DROPPED (continue)
raw=[@router.get("/{set_id}] method=[GET]   path=[/{set_id}]  -> KEEP
```

`DECORATOR_PAT` 对 `@router.get("")` 抓到的是 `@router.get("`，路径捕获组为空串，
`[[ "$path" == /* ]]` 不成立 → 整条丢弃，`prefix` 再也拼不上去。

`route_registered` 的 basename 宽松匹配救不回来：spec 的 `GET /model-sets` 会去找结尾是
`/model-sets` 的 code route，而剩下的 `GET /model-sets/{}` 不满足，于是报漂移。

上报中的三行示意与实测输出逐字一致。

## 3. 根因

`#12` 为修复「`| 端点 | 方法 | 说明 |` 列错位会把说明列当路径提取」这个缺陷，在 **spec 侧** 的
awk 里加了「路径必须以 `/` 开头」（`:285` 的 `is_method(m) && p ~ /^\//`），
然后把同一个谓词原样用到了 **code 侧** 的 `collect_code_routes`。

两侧的失败方向是相反的：

| 侧 | 丢一行的后果 | 安全方向 |
|---|---|---|
| spec（声明） | 少比一条 | fail-closed 可接受 |
| code（证据） | 凭空多报一条漂移 | **必须 fail-open** |

`#12` 自己写下的设计原则是「imprecise prefix modelling under-reports rather than failing
the gate」，这个守卫恰好违反了它。

## 4. 上报未覆盖的同类缺陷：多行装饰器

`grep` 按行工作，而下面两种都是 FastAPI/Express 的常规写法：

```python
@router.put(
    "/{set_id}",
    summary="Rename a model set",
)

router = APIRouter(
    prefix="/api/model-set-members",
    tags=["model-set-members"],
)
```

前者整条路由匹配不到；后者 prefix 读不到，该文件所有路由都无法还原成完整 URL。
失败表现与上报的缺陷完全一致 —— 误报漂移。

`tests/smoke-test.sh:2155` 的 FastAPI 用例只有「单行 + 非空路径」一种形态，
测试与实现出自同一次心智模型，因此只能验证编码正确性，验证不了「真实世界还有哪些写法」。

## 5. 修复

`harness-template/halo/kernel/delivery/gates/drift-check.sh`：

1. `collect_code_routes` 的守卫改为 fail-open，空路径按 prefix-only 处理：

```bash
[[ -z "$path" || "$path" == /* ]] || continue
[[ -z "$path" ]] || printf '%s %s\n' "$method" "$(normalize_path "$path")"
```

空串只经由 prefix 拼接产出（`normalize_path "/model-sets" == /model-sets`），
绝不产出裸的空路由；真正的非路径（Express 里的 `axios.get("https://…")`）仍然被拒。

2. 新增 `grep_folded()`：先用一次批量 `grep -lE "$REGISTRATION_PAT"` 收窄候选文件，
再逐文件把换行折成空格后匹配。`DECORATOR_PAT` / `PREFIX_PAT` 里的 `\([[:space:]]*`
折行后即可命中。折行只可能多匹配（少报漂移），不会少匹配，方向与既有设计一致。
收窄那一步保证 monorepo 不会为每个源文件付一次进程开销。

## 6. 回归护栏

**`tests/smoke-test.sh` §7c，三条新断言，均先确认在未打补丁的脚本上 FAIL：**

| 断言 | 覆盖 |
|---|---|
| `drift-check treats empty-path FastAPI collection roots as registered` | 空路径集合根被识别，且仍能报出真正缺失的 DELETE（`drift_count == 1`） |
| `drift-check passes once a prefix-only FastAPI router is complete` | 补齐后 exit 0、`drift_count == 0` |
| `drift-check reads multi-line FastAPI route decorators` | 多行装饰器 |

空路径场景与 `"/"` 场景**必须分开写**：同一份 fixture 里放 `@router.get("/")` 会让
`route_registered` 的 basename 宽松匹配把空路径漏检掩盖掉，断言就失去鉴别力。
多行场景里必须保留一条单行路由，否则 `CODE_ROUTES` 为空会走 `gate_skip`，exit 0 会假通过。

**`examples/py-fastapi/`**：新增可运行示例工程，`app/routers/` 刻意铺满惯用写法
（空路径集合根、`"/"` 形式、单行装饰器、多行装饰器、多行 `APIRouter` prefix），
`try-it.sh` 第 5 步断言 6 条 spec 路由全部解析、`drift_count == 0`。
用修复前的 gate 跑该示例，6 条中有 4 条误报为未注册 —— 护栏有效。

**`AGENTS.md` 新增 `## Gate Rules`**，把两条规则写死：
code 侧过滤必须 fail-open 且注明失败方向；gate 从 `gate_skip "not yet implemented"`
转为出裁决属于高风险变更，需变体矩阵 fixture、双向断言、可运行示例、并在提交信息里写明失败方向。

## 7. 验证

```
bash -n / shellcheck --severity=warning     全通过
bash tests/smoke-test.sh                     155/155（修复前 152/155）
bash examples/go-gin-gorm/try-it.sh          PASS（Go 路径无回归）
bash examples/py-fastapi/try-it.sh           PASS
bash tests/release-check.sh                  全 PASS
git diff --check                             干净
```
