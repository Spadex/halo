#!/usr/bin/env bash
# tests/helpers/common.bash — Halo bats 套件共享 setup。
#
# 用法（.bats 文件内）：
#   load "../helpers/common"
#   setup_file() { halo_require_tools; halo_template_install; }
#   setup()      { halo_sandbox_clone; }
#
# BATS_FILE_TMPDIR / BATS_TEST_TMPDIR 由 bats 创建和清理，无需 teardown。

HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HELPERS_DIR/../.." && pwd)"
export REPO_DIR

# shellcheck source=/dev/null
source "$HELPERS_DIR/../vendor/bats-support/load.bash"
# shellcheck source=/dev/null
source "$HELPERS_DIR/../vendor/bats-assert/load.bash"

# 缺工具时跳过整个文件（与 smoke-test 的 skip 语义一致：环境缺失≠失败）。
halo_require_tools() {
  local tool
  for tool in yq git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      skip "requires $tool"
    fi
  done
}

# 每个测试文件安装一次 harness 模板（install + init 较慢，~秒级）。
# 产出：$HALO_TEMPLATE_DIR —— 已完成 install.sh + init.sh 的 Go 项目。
halo_template_install() {
  export HALO_TEMPLATE_DIR="$BATS_FILE_TMPDIR/template"
  mkdir -p "$HALO_TEMPLATE_DIR"
  git -C "$HALO_TEMPLATE_DIR" init --quiet
  cat > "$HALO_TEMPLATE_DIR/go.mod" << 'EOF'
module github.com/example/testapp

go 1.22

require github.com/gin-gonic/gin v1.9.1
require gorm.io/gorm v1.25.0
EOF
  bash "$REPO_DIR/install.sh" "$HALO_TEMPLATE_DIR" > /dev/null
  (
    cd "$HALO_TEMPLATE_DIR" || exit
    bash .halo/framework/init.sh --non-interactive --lang=go --name=testapp --ci=github > /dev/null
  )
}

# 每条用例克隆一个隔离副本并 cd 进去（门禁脚本按 cwd 定位 halo/specs）。
# 产出：$SANDBOX。
halo_sandbox_clone() {
  export SANDBOX="$BATS_TEST_TMPDIR/project"
  cp -R "$HALO_TEMPLATE_DIR" "$SANDBOX"
  cd "$SANDBOX" || return 1
}
