#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-16-init-detection-probe-pipefail-analysis.md
# Root cause class: B. pipefail 语义（命令替换包管道，缺 || 兜底）
# Fixed by: 与本文件同一提交（见 git log -- tests/regression/2026-08-16-init-detection-probe-pipefail.bats）
#
# init.sh 的项目探测段跑在 `set -euo pipefail` 下。探测器返回非零时，包着管道的
# 命令替换随之失败，set -e 让 init.sh **静默**退出——用户看到的最后一行是
# 「🔍 Detecting project info...」，没有任何错误信息。
#
# 探测器不可用不是错误：探测的产出只是默认值，用户可以用 --lang 等参数覆盖。
# node 分支（init.sh:133）与 python 分支（:144）都带 `|| echo ""` 兜底，
# 漏掉兜底的是 go 分支（:124，探测 `go version`）与 rust 分支（:153，探测 Cargo 包名）
# —— 同一段代码里的形态漂移。
#
# 发现路径：GitHub 的 macos-latest（arm64）镜像不预装 Go，test workflow 首跑即红；
# ubuntu 预装 Go 所以一直是绿的。详见 analysis。
#
# 两个方向都要断言：探测失败不得让 init 崩，探测成功不得因为修复而丢掉探测结果。

load "../helpers/common"

setup() {
  halo_require_tools

  PROJ="$BATS_TEST_TMPDIR/proj"
  SHIM="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$PROJ" "$SHIM"
  git -C "$PROJ" init --quiet
}

install_harness() {
  bash "$REPO_DIR/install.sh" "$PROJ" > /dev/null
}

write_go_project() {
  cat > "$PROJ/go.mod" << 'EOF'
module github.com/example/testapp

go 1.22

require github.com/gin-gonic/gin v1.9.1
require gorm.io/gorm v1.25.0
EOF
  install_harness
}

# 造一个 go 探测器 shim：$1 为退出码，$2 为要打印的行（可空）。
# 退出码 127 复刻「command not found」，与 Go 未安装时管道拿到的状态一致；
# 用 shim 而不是真的卸载 Go，是为了让这条用例在装没装 Go 的机器上表现一致。
make_go_shim() { # <exit-code> [stdout-line]
  cat > "$SHIM/go" << EOF
#!/usr/bin/env bash
[[ -n "${2:-}" ]] && echo "${2:-}"
exit ${1}
EOF
  chmod +x "$SHIM/go"
}

run_init() { # [extra-init-args...]
  run env PATH="$SHIM:$PATH" bash -c \
    "cd '$PROJ' && bash .halo/framework/init.sh --non-interactive --name=testapp --ci=github $*"
}

@test "init completes when the go probe is unavailable" {
  write_go_project
  make_go_shim 127
  run_init --lang=go
  assert_success
  assert_output --partial "Language:  go"
  [ -f "$PROJ/halo/manifest.yaml" ]
}

@test "init falls back to the default version constraint when the go probe fails" {
  write_go_project
  make_go_shim 127
  run_init --lang=go
  assert_success
  run yq -r '.project.version_constraint' "$PROJ/halo/manifest.yaml"
  assert_output ">=1.0"
}

@test "init still records the detected version when the go probe works" {
  write_go_project
  make_go_shim 0 "go version go1.22.5 darwin/arm64"
  run_init --lang=go
  assert_success
  run yq -r '.project.version_constraint' "$PROJ/halo/manifest.yaml"
  assert_output ">=1.22.5"
}

@test "init completes when Cargo.toml carries no name line" {
  printf '[package]\nversion = "0.1.0"\n' > "$PROJ/Cargo.toml"
  install_harness
  run_init --lang=rust
  assert_success
  [ -f "$PROJ/halo/manifest.yaml" ]
}

@test "init still records the crate name when Cargo.toml declares one" {
  printf '[package]\nname = "crate-under-test"\nversion = "0.1.0"\n' > "$PROJ/Cargo.toml"
  install_harness
  run_init --lang=rust
  assert_success
  assert_output --partial "Name:      crate-under-test"
}
