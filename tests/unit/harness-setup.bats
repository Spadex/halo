#!/usr/bin/env bats
# 验证 helpers/common.bash 的沙箱契约：
# 模板每文件装一次，用例各拿隔离副本，副本内核可直接调用。

load "../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

@test "template install produces manifest and kernel" {
  [ -f "$SANDBOX/halo/manifest.yaml" ]
  [ -d "$SANDBOX/halo/kernel/delivery/gates" ]
  [ -f "$SANDBOX/prismspec/bin/lint.sh" ]
}

@test "sandbox clone is isolated from template" {
  touch "$SANDBOX/pollution-marker"
  [ ! -e "$HALO_TEMPLATE_DIR/pollution-marker" ]
}

@test "sandbox cwd is the project root" {
  [ "$(pwd)" = "$SANDBOX" ]
  [ -f halo/manifest.yaml ]
}
