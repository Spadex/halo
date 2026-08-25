# Halo 测试维护手册

本目录是 Halo 的测试体系。设计全貌见
`docs/superpowers/specs/2026-08-07-halo-test-system-design.md`。

## 怎么跑

```bash
bash tests/run.sh              # 全量（bats 各套件 + 存量 smoke-test）
bash tests/run.sh unit         # 只跑某个套件：unit|regression|e2e|meta|legacy
tests/vendor/bats-core/bin/bats tests/unit/fixtures.bats            # 单文件
tests/vendor/bats-core/bin/bats tests/unit/fixtures.bats -f "make_spec"  # 按名字过滤单用例
```

首次使用先初始化 submodule：`git submodule update --init`。

## 目录结构

| 目录 | 职责 |
|------|------|
| `unit/` | 契约单测与门禁行为单测（50 条） |
| `regression/` | 回归语料库：一份 bug 报告 = 一个 `.bats` 文件或一个同名目录（78 条） |
| `e2e/` | 端到端：init → spec → plan → 门禁 → 证据 黄金路径 （批次 4 起）|
| `meta/` | 原则守护 lint：把 AGENTS.md Gate Rules 变成机器断言 （批次 3 起）|
| `helpers/` | `common.bash`（沙箱）、`fixtures.bash`（spec/plan 构造函数） |
| `fixtures/` | 静态语法变体 fixture，见 `fixtures/README.md` 的变体矩阵 |
| `vendor/` | bats-core / bats-support / bats-assert（git submodule，锁版本） |

`smoke-test.sh` 是迁移中的存量：**已冻结，只删不加**。新测试一律写 bats。

## 遇到 bug 怎么办（处置 SOP）

1. **收报告**：上报原文放 `docs/bug_report/YYYY-MM-DD-<slug>.md`（多文件建同名目录），原文一字不改。
2. **独立复核**：不采信报告的结论与建议，自行验证根因，复核结论写同名 `…-analysis.md`。
3. **写回归测试**：`tests/regression/YYYY-MM-DD-<slug>.bats`，文件名与报告对齐。文件头固定三行注释：

   ```bash
   # Bug report: docs/bug_report/YYYY-MM-DD-<slug>.md
   # Root cause class: <见下方根因类别表>
   # Fixed by: <commit hash>
   ```

   入库纪律：
   - **双向断言**——「误报已消除」和「真缺陷仍被抓住」两个方向都要有；
   - **先红后绿**——先在未修复代码上确认 FAIL，再确认修复后 PASS，提交信息里记录；
     历史 bug 已经修过、回不到修复前的，走下方「等价性验证」；
   - **竞态必须确定化**——不允许重复跑碰运气（参考 #11 注入慢 yq 的做法）。

   **命名规则**（对拍靠它，别随手起名）：
   - 报告已合规（文件名是 `YYYY-MM-DD-<slug>.md` 或同名目录）→ bats 文件名与报告
     basename **逐字相同**；
   - **聚合上报**（一份报告含多条互不相干的已修缺陷）→ **目录形态**
     `tests/regression/<报告 basename>/<缺陷 slug>.bats`，目录名与报告 basename 逐字相同，
     每条缺陷一个文件（见下方四条理由）；
   - 历史遗留报告（命名不合规）→ 日期取**修复提交的作者日期**，slug 取语义 slug，
     映射登记到 `docs/bug_report/INDEX.md`。
   - 自查/CI 发现、没有上报原文的缺陷 → 只写 analysis，正文必须写清**发现路径**
     （哪次 CI、哪个 run），**不许**为了凑格式补造一份「上报原文」。

   **为什么聚合上报走目录而不是平铺成一个文件**（批次 2 决定一，四条理由）：

   1. **一份聚合报告可能横跨多个批次**（决定性理由）。平铺的话，后续批次得回来往一个
      已通过等价性验证、已写进提交记录的文件里追加，归因链就断了；目录形态下各批各加一个文件。
   2. **`setup` 形态无法共存。** 同一份报告里的缺陷往往需要互不兼容的沙箱：真实 git 提交历史
      与分支、`language=python` + `framework=fastapi`、`halo/specs/<id>/` 下的 spec+plan 对……
      塞进一个文件就要写一个服务多种沙箱形态的 `setup`——那正是把 smoke-test 的问题搬进 bats。
   3. **目录形态是仓内既有语汇**，不是新发明：`docs/bug_report/` 下已有 `ac-coverage-bug/`
      与 `2026-08-07-runningtime-report/` 两份目录形态报告。
   4. **机器对拍不受影响。** `tests/run.sh` 的 `find … -name '*.bats'` 与 `bats --recursive`
      都已递归，无需改动；对拍规则改成「`<base>.bats` **或** `<base>/` 目录」即可。

   代价（已知并接受）：子目录里 `load` 路径变成 `load "../../helpers/common"`。
   被否决的替代是 `<base>.<slug>.bats` 点号分隔——它发明了一套新文件名语法，
   对拍规则要变成前缀匹配，且解决不了理由 1。
4. **随修复一并提交**：报告、analysis、回归测试、修复代码同一批提交，不留未跟踪文件。
5. **根因归类**：归入下表。若是已有类别的复发，必须回答：「meta-lint 或契约单测为什么没拦住？」——答案通常就是要新增的 lint 规则或单测。

## 根因类别表

| 类别 | 含义 | 机器防线 |
|------|------|----------|
| A. 词法「提及≠声明」 | 全文 grep 把散文/交叉引用当结构化声明 | `unit/` 对 `narrow_acs_to_declared` 等的契约单测 |
| B. pipefail 语义 | grep 未命中崩溃、SIGPIPE、while 退出码 | `meta/` 反模式扫描 + 单测边界条件族。**判定标准必须写明「`pipefail` 取管道里最右侧的非零码，末段是谁与危险性无关」**——2026-08-25 的 `ac-coverage.sh:188` 正是被「`head` 在末段吞掉了退出码」这个错误理由判为无害的 |
| C. 失败方向搞反 | fail-open/fail-closed 用错边 | `meta/` 失败方向注释强制 + **诚实 skip 检查**。注释规则只管「有没有说明方向」，管不到「方向本身对不对」；同一守卫在多个门禁里的**齐平断言**才是拦住单边漂移的那道（见 `regression/2026-08-25-compliance-missing-spec-fail-open.bats` 第四条） |
| D. 非确定性依赖 | mtime 排序、find 目录序、表格列序 | `meta/` 扫描 |
| E. 框架读不懂自带模板 | 默认模板触发自家门禁误报 | `e2e/` + examples 黄金路径 |
| F. 语法变体覆盖不足 | 只认单一书写形态 | `fixtures/` 变体矩阵 + examples 真实工程 |
| G. 判定量词错误 | 任一 vs 全部 | 回归用例双向断言 |
| H. 同一语义多份定义漂移 | 重复实现各自演化 | `meta/` 重复定义检测 + 契约单测 |

## 新增框架支持的配套义务

drift-check 每声称支持一种框架，`examples/` 必须新增该框架的可运行工程，
且工程里刻意包含该框架的惯用语法变体（多行装饰器、集合根路由等）。

## meta-lint 豁免

误报不改代码迁就 lint：在 `tests/meta/allowlist.txt` 登记一行豁免，
必须附原因注释。豁免在 review 中可见。（meta-lint 于批次 3 上线。）

## 等价性验证（变异测试）

**用在哪**：迁移存量测试、或为早已修复的历史 bug 补回归测试时——这两种情况都回不到
「未修复代码」，SOP 的先红后绿无从执行。

做法是反过来：**对修复点注入定向缺陷，确认预期的用例变红**。

六步协议，每条变异都要走完：

```bash
git status --porcelain          # 1. 必须为空
#  2. 精确改一处（手工编辑，或脚本做单次字符串替换；禁止 sed -i）
git diff                        # 3. 先确认变异真的落盘了，再跑测试（见下方「先看 diff」）
tests/vendor/bats-core/bin/bats tests/regression/<file>.bats   # 4. 记录变红的用例名
git checkout -- harness-template/ prismspec/                   # 5. 回滚（两个目录都要）
git status --porcelain          # 6. 必须再次为空，且重跑全绿
```

**红线：任何变异都不得进入提交。** 产出是执行记录（提交信息或计划文档里的逐条表格），不是代码改动。

协议的五条补充约束，每条都有实测教训：

- **回滚范围含 `prismspec/`。** 注入点不止 `harness-template/`；只回滚一个目录会把另一个目录的
  变异留在工作树里，污染后续所有变异的基线。
- **先看 `git diff` 确认落盘，再跑测试。** 批次 2 两次栽在这里：一次是 `perl -0pi -e` 因引号与
  `\Q…\E` 转义而静默不生效，产出「看起来是变异、实则是基线」的**假绿**；一次是并行子代理共用
  scratchpad 根目录，辅助脚本被同名文件覆盖。因此：**禁止用 `perl -0pi -e` 与无后缀 `sed -i`
  施加变异**；推荐 python 字面替换，并断言「目标串恰好出现 1 次，否则中止且不写文件」。
- **并行跑变异必须各自使用隔离的 git worktree 与私有的临时目录。** 变异改的是共享的
  `harness-template/` 与 `prismspec/`，同一工作树内并行必然互相污染。
  实操坑：`tests/vendor/bats-*` 是 git submodule，worktree 里 `git submodule update --init`
  会挂在网络上；解法是从主仓 `cp -R` 三个 vendor 目录再删掉里面的 `.git` 文件。
- **平台专属变异**（BSD awk 多字节 `==` 一类）的记录方式是 **「macOS RED / Linux GREEN」，
  两个结果都要写**。只记一侧等于把「这条变异在某平台上打不中」这个结论藏起来；
  某一侧本机跑不了就写明归 CI，不许留空。
- **启用模板缓存时，变异必须能禁用缓存。** 缓存会让沙箱继续用变异前的模板副本，
  表现同样是假绿。

验收门槛：**每条被迁移的断言都必须至少被一条变异点亮**。某条断言没有任何变异能点亮，
先分清是哪种情况——

| 情况 | 表现 | 怎么办 |
|------|------|--------|
| 断言没判别力 | 换任何实现都绿 | 回去加强断言 |
| 变异集有缺口 | 断言守的是另一个方向（比如「不许过严」），而变异全在放松 | 补一条反方向的变异 |

批次 1 就撞上第二种：21 条变异全在让门禁变松，4 条「正向归属」用例因此没被点亮；
补一条让 Tier 1 恒不命中的变异（门禁最大限度误红）后精确点亮了那 4 条。

### 变异测试的两条经验

批次 2 跑完 74 条变异后沉淀的两条，都不是推论，是被实测逼出来的。

**一、一条断言的「绿」，只有在它被独立证伪过之后，才构成证据。**

来源是批次 2 的 M58。加强前的 `rp-2` 是一条**恒绿断言**（全文 `grep -F`，无论段落作用域坏没坏都命中），
于是「M58 之下 rp-2 保持绿」这个观察无法区分两种解释：

- M58 客观上没碰坏那份清单；
- rp-2 根本测不出那份清单坏没坏。

拿恒真命题当证据，等于没有证据。加强之后 rp-2 已被 M57 独立证伪过（一打断它就红），
此时同一个「绿」才只剩第一种解释。**推论**：报告某条变异「未点亮某用例、故实现未被破坏」之前，
先确认该用例存在至少一条能把它打红的变异；否则那句话只是在复述断言的无判别力。

**二、防御性冗余会吸收单点变异，需复合变异才打得穿。**

批次 2 出现两次：

| 被吸收的变异 | 吸收它的冗余 | 打穿它的复合变异 |
|---|---|---|
| M30 | `drift-check.sh:452-456` 的全文数值回退（主抽取失败时整份 spec 重扫一遍数字行） | M69（同时打 `:444` 与 `:452-456`） |
| M14 | `_lib.sh:170` 的 `-n "$selected"` 冗余守卫（`rc` 已为 0 时该判空恒真） | M71（复合，跨 `spec-select.sh` 与 `_lib.sh`） |

**含义不是「变异法失效」，而是代码里存在未被任何测试覆盖的防御层。**
单点变异法对「同一契约被上下游各守一道」的位置有**系统性盲区**：上游被打断时下游兜住，
测试照绿，于是那条兜底路径从未被验证过。撞上「变异了却零变红」时，先查是不是这种结构，
再决定是补复合变异，还是把那层冗余本身列为待测对象。

## 写用例的约定

> **红线：`harness-template/halo/kernel/_lib.sh` 绝对不可以 `source` 进 bats 测试进程。**
>
> 实测核对：`_lib.sh:79-82` 定义了 `pass()` / `fail()` / `warn()` / `skip()`，其中
>
> - `fail` 与 `tests/vendor/bats-support/src/error.bash:38` 的 `fail()` 同名——
>   那是 bats-assert 全部 `assert_*` / `refute_*` 的失败原语；
> - `skip` 与 `tests/vendor/bats-core/lib/bats-core/test_functions.bash:437` 的 bats 内建 `skip()` 同名。
>
> source 进测试进程后，`_lib.sh` 的 `fail()` 会把断言失败变成一行 `❌ …` 输出、计数器加一、
> **返回 0**——所有 `assert_*` 从此永不让用例变红。这是最坏的一类失败：**全绿的假绿**。
>
> 因此契约单测一律走子进程：
>
> ```bash
> # 必须走子进程：_lib.sh:79-82 的 pass/fail/warn/skip 与 bats 内建 skip、
> # bats-support 的 fail 同名，source 进测试进程会把断言失败原语替换掉（假绿）。
> # 附带收益：_lib.sh:12 的 set -euo pipefail 不外溢；find_spec 的 rc 1/2 直接落到 $status。
> lib_run() { # <bash 片段>
>   run --separate-stderr bash -c 'source halo/kernel/_lib.sh; eval "$1"' _ "$1"
> }
> ```
>
> 这段是 `tests/unit/lib-find-spec.bats:55-57` 与 `tests/unit/lib-ac-declaration.bats:40-42`
> 的**逐字实现**，两处细节都不是可选的：
>
> - **`--separate-stderr` 不能省，但两个文件的理由不同。** 在 `lib-find-spec.bats` 是
>   `spec_select`（`spec-select.sh:118` 起）把选中依据与落选候选打到 stderr，而 `run` 默认把
>   stdout+stderr 合并进 `$output`；不分离的话，`find_spec_with_source` 的 stdout 契约
>   （`source|detail|path`）会被诊断行污染。`lib-ac-declaration.bats` 测的两个函数**不经过**
>   `spec_select`，该理由不成立；它在那里的作用是把子进程 stderr 挡在 `$output` 外，让
>   `ac-5`/`ac-6` 的 `assert_output ""` 只约束 stdout——代价是 stderr 一侧的退化对这两条不可观测
>   （详见该文件 `lib_run` 上方的注释与计划里的 M65 附注）。
> - **是 `eval "$1"`，不是 `shift; eval "$*"`。** `bash -c '…' _ "$1"` 里的 `_` 已经占掉 `$0`，
>   实参从 `$1` 起；再 `shift` 会把唯一那个实参丢掉，`$*` 变成空串，`eval` 求值空串。
>   后果是**恒得 `$status=0` 且 `$output` 为空**——本条红线要防的假绿，会原样从这个写法里长出来。
>   实测对照：
>
>   ```
>   $ bash -c 'shift; eval "$*"' _ 'exit 1';  echo $?    → 0    # 假绿
>   $ bash -c 'eval "$1"'        _ 'exit 1';  echo $?    → 1    # 正确
>   ```
>
> `spec-select.sh` 不受此限（只定义 `spec_select*` 与 `SPEC_SELECT_DETAIL`），它本来就可执行。
> 但**调用形态分两档**，取决于该用例是否需要已初始化的项目：
>
> - **不装 harness**（`spec-select.sh` 的 standalone 契约本身就是被测对象时）——直接跑仓库里的源文件：
>
>   ```bash
>   run --separate-stderr bash "$REPO_DIR/harness-template/halo/kernel/spec-select.sh" "$ROOT"
>   ```
>
>   理由是契约不是速度：`spec-select.sh:6-8` 写明「刻意不依赖 `_lib.sh` 与 `yq`，因为 `guide.sh`
>   必须能在没有 halo 的 standalone 宿主下工作」——在装好 harness 的沙箱里测它，恰好把这条契约测没了。
> - **装 harness**（用例要在已初始化的项目里跑 `pipeline.sh` / `guide.sh`）——用沙箱相对路径：
>
>   ```bash
>   run --separate-stderr bash halo/kernel/spec-select.sh halo/specs
>   ```
>
> 两档的现成范例见 `regression/2026-08-03-halo-gate-findings_2/spec-discovery.bats:22-37`
> 的 setup 说明（disc-1..8 走第一档，disc-9..11 走第二档）。

- 用 `helpers/fixtures.bash` 的 `make_spec` / `make_plan` 生成黄金形态，
  语法变体用 `sed`/`awk` 改写产物或放 `fixtures/` 静态文件；不要复制粘贴整段 heredoc。
- **构造函数 / 派生 / 静态文件的三档分界线**：
  - 跨用例复用、差异可用少量标量参数表达的**黄金形态** → 构造函数；
  - **单元素变体**（改一个单元格、改一个 AC 号、复制一行）→ 用例内 `sed`/`awk` 派生；
  - **多个陷阱元素同时出现在一份文档不同位置** → `fixtures/` 静态文件，
    因为它的价值在于可被逐字审阅，参数化会把陷阱藏进生成逻辑。
    详见 `fixtures/README.md`。
- **跨平台**：`sed -i` 在 BSD 上要后缀、GNU 上不要，两边不通用，一律改写到临时文件再 `mv`；
  BSD sed 的替换串不支持 `\n`，**复制行用 `awk`**。
- **yq 是 mikefarah v4，表达式语言不是 jq**：数组字面量比较（`.a == ["x","y"]`）会静默求值为
  false，数组断言走 `join(",")` 或 `length`。
- **量词对空集返回 true——必须配 `length > 0` 的反向哨兵。** `all_c` 之类的全称量词
  在数组为 `[]` 时求值为 true，于是一条形如

  ```
  .findings | all_c(.category == "error_codes" and .status == "skip")
  ```

  的断言，在「整条 finding 被删掉、数组变成 `[]`」时**照样通过**。正确写法是把存在性一并断上：

  ```
  ([.findings[] | select(.category == "error_codes")] | length > 0)
    and ([.findings[] | select(.category == "error_codes")] | all_c(.status == "skip"))
  ```

  判据是**两个方向都要能红**：「谎报方向」（状态被改成别的值）与「蒸发方向」（整条 finding 消失）。
  这条有实测支撑——批次 2 的独立评审构造了反例，去掉哨兵后「维度凭空蒸发」这个方向确实被放过。
- 沙箱用 `helpers/common.bash`：`setup_file` 里 `halo_template_install`（每文件装一次），
  `setup` 里 `halo_sandbox_clone`（每用例一个隔离副本，自动 cd）；
  静态 fixture 用 `halo_install_fixture <rel>` 叠加，语言形态用 `halo_set_language <lang>`。
- 断言出口语义（退出码、eval JSON 关键字段），不断言中间实现细节。
- 契约单测文件头注明被测函数的调用方清单，让改动者看到爆炸半径。
- **只服务单个文件的前置构造函数就留在那个文件里**，不要提到 `helpers/`——
  没有第二个调用方的 helper 会变成下一个「谁在用它」的谜团。

## 契约单测 vs 回归的分层判据

`unit/` 与 `regression/` 会覆盖同一条实现路径。不写清谁守什么，就会出现
「都覆盖了，但说不清是哪层守住的」——那等于**两层都不可信**。

### 一句话判据

> **改被测函数所在的库（`_lib.sh` 之类）的分支/返回码会红的，归 `unit/`；
> 改具体算法脚本（`spec-select.sh` 之类）的排序键/输出会红的，归 `regression/`。**

换个说法：契约单测断的是**函数自身的出口契约**——来源优先级、返回码、输出形状、
以及返回码如何被各调用点消费；回归断的是**缺陷本体**——算法为什么这么算、
可察觉性、以及结果如何进入证据链（eval JSON、`--json` 输出）。
契约单测构造边界场景只为驱动返回码，**不为验证算法为什么这么排**。

判据不是口号，**变异表就是它的机器证明**：打库的变异只应点亮 `unit/` 的用例，
打算法脚本的变异只应点亮 `regression/` 的用例。某条打库的变异点亮了回归用例，
或反之，就说明分层被破坏，回到对应文件**收窄断言**，而不是接受现状。

### 容许的交叠：必须逐条写明正当性

交叠不是一律禁止，但每一处都要说清「断言对象不同在哪」，并给出机器证明。批次 2 保留了两处：

| 交叠 | 断言对象为什么不同 | 正当性的机器证明 |
|---|---|---|
| `find-8` ↔ `disc-4`（并列场景） | `disc-4` 断「选取器拒绝猜测并给出 `--spec=` 提示」（报告的诉求）；`find-8` 断「rc=2 被 `_lib.sh:174` 原样透传而不塌成 1」 | 打 `spec-select.sh` 的变异两条都点亮；而**删掉 `_lib.sh:174` 的 rc=2 透传（批次 2 的 M4）点亮 `find-8` 而不点亮 `disc-4`**——它另外还点亮同属库层的 `find-12`，关键在于**一条 `disc-*` 都没红**，这就是正当性的证明。若它也点亮 `disc-4`，说明 `disc-4` 越界断了库的行为，须收窄 |
| `find-9` ↔ `disc-1`（时间戳排序） | `find-9` 借排序结果驱动 rc=0，不断排序本身 | 打排序键的变异会同时点亮两者——属**容许交叠，记录即可**，不作为分层破坏 |

### 两条禁令

- 契约单测文件**不得**出现断言算法脚本 stderr 文案、mtime 行为、排序键、字段比较的用例。
- 回归文件**不得**出现断言库层优先级（`specs.active` / `SPEC_FILE` 之类）、
  函数输出形状的用例。

**两个文件的文件头都要写上这两行禁令，并互指对方路径。** 禁令写在文件头而不是只写在这里，
是因为改动者打开的是 `.bats`，不是本手册。

## 门禁诚实性契约

AGENTS.md 的 Gate Rules 明写：**没比较过的维度必须报「未验证」，`drift_count: 0`
不允许从「什么都没查」到达。** 落到测试上就是一条硬契约：

> **任何 `gate_skip` 都必须同时满足三条，且三条都要有断言：**
> ① 输出含 `NOT verified`；② 对应的 `checked.*` 为 `false`；③ 不计入 `checks_run`。

**只断其中一条，就是把「跳过」和「干净」混同。** 这不是理论风险——批次 2 的变异测试
恰好证明了只断一条的后果，两条实证：

1. **`drift-check.sh` 的路由维度有六条 `gate_skip` 出口**
   （`:348`、`:358`、`:388`、`:398`、`:415`、`:418`）。走到其中任何一条时，
   `drift_count == 0` 与 `exit 0` 照样成立——旧的 `drt-3` / `fca-5` 只断这两项，
   于是把 `mark_checked` 删掉之后**照常绿**。补上 `checked.routes == true` 才红。
2. **`ok()` 与 `gate_skip()` 都不调 `mark_checked`**，所以 `checked.* == false`
   也区分不了二者。旧的 `dec-6` 三条断言（`exit 0` / 消息文本 / `checked.error_codes == false`）
   在把 `gate_skip` 换成 `ok` 之后**全部成立**——而该用例名恰恰写着
   `reports NOT verified instead of clean`，它守不住的正是「报成 clean」。
   补一条带 `length > 0` 哨兵的 per-finding 状态枚举断言才红。

**两条实证的共同形状**：被守护的行为坏掉时，断言仍然是绿的，而且它藏在已通过多轮独立评审的
测试里。所以三条缺一不可——`exit 0` 与 `drift_count == 0` 在「跳过」和「干净」两种世界里
取值完全相同，靠它们分辨不了这两种世界。

度量的选法：**不要**把 `checks_skipped` 收紧成精确值（`== 4` 一类）——那是硬编码计数，
会被无关的维度新增误伤。用语义等价且不脆的 `checks_run == 0` 加上逐个 `checked.*` 为 `false`。

## 批次 3 待办注记

`red-many-ac` 的 SIGPIPE 竞态（#11）迁移时需要一个可复用的慢 yq 注入函数。
本批次不实现（没有调用方，YAGNI），接口先记在这里：

```bash
# halo_slow_yq_path <yq-arg-1> <yq-arg-2>
#   造一个把匹配指定参数的 yq 调用逐行慢放（每行 sleep 0.05）的 shim 目录，回显该路径，
#   供调用方 PATH="$(halo_slow_yq_path -r '.ac_ids[]?'):$PATH" 使用。
#   用途：把「读端提前关闭 → SIGPIPE(141) 在 pipefail 下毒化退出码」的竞态确定化为 100% 触发。
#   蓝本：见 git history 的 tests/smoke-test.sh 慢 yq shim（批次 1 前的 :1338-1356）。
```
