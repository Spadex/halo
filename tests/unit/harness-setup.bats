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

@test "fixture install lays the tree over the sandbox" {
  halo_install_fixture ac/cross-spec-mentions
  [ -f "$SANDBOX/halo/specs/cross-spec-ac/spec.md" ]
  [ -f "$SANDBOX/halo/specs/cross-spec-ac/plan.md" ]
  # 叠加不得清掉沙箱原有内容
  [ -f "$SANDBOX/halo/manifest.yaml" ]
}

@test "fixture install fails loudly on a missing fixture" {
  run halo_install_fixture ac/no-such-fixture
  assert_failure
  assert_output --partial "no such fixture"
}

@test "language override lands in the sandbox manifest" {
  halo_set_language python
  run yq -r '.project.language' "$SANDBOX/halo/manifest.yaml"
  assert_output "python"
}
