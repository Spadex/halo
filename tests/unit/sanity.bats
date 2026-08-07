#!/usr/bin/env bats
# Sanity: bats 骨架、断言库、必备工具就位。

setup() {
  load "../vendor/bats-support/load"
  load "../vendor/bats-assert/load"
}

@test "bats runs and assertions work" {
  run echo "halo"
  assert_success
  assert_output "halo"
}

@test "required tools are available" {
  command -v yq
  command -v git
}
