# Context Layer

Context 层负责给 AI Agent 提供可靠的项目上下文。主入口是 `halo/context/README.md`，不是 shell 命令。

## Agent Flow

1. 读取 `halo/context/README.md`。
2. 根据上下文地图查找相关项目知识、外部引用、代码、测试、schema、接口契约和历史 spec。
3. 只选择会影响 scope、AC、risk、interface、compatibility 或 verification 的事实。
4. 将本次采用的上下文依据写入 `halo/specs/<spec-id>/spec.md` 的 Context Basis。
5. 基于 `spec.md` 继续规划和实现。

## Directory Contract

```text
halo/context/
  README.md                    # Agent-readable context map
  external.md                  # 外部知识和中心知识入口
  knowledge/
    architecture.md
    rules.md
    pitfalls.md
    glossary.md
    decisions/
  drafts/                      # 待确认的知识沉淀
  sources.yaml                 # 可选：给脚本/自动化消费
halo/specs/<spec-id>/
  spec.md                      # 含本次 spec 的 Context Basis
```

## Optional Tooling

```bash
# 检索 curated project knowledge
halo/kernel/context/backends/knowledge.sh auth rate-limit idempotency

# 兼容旧入口
halo/kernel/context/loader.sh auth rate-limit idempotency

# 同步可选中心知识缓存
halo/kernel/context/sync.sh pull
halo/kernel/context/sync.sh push
halo/kernel/context/sync.sh status
```

这些脚本是确定性辅助工具，不替代 Agent 主导的 Context Discovery。

## Manifest

```yaml
kernel:
  layers:
    context: true

context:
  root: halo/context
  map_file: halo/context/README.md
  external_file: halo/context/external.md
  sources_file: halo/context/sources.yaml
  knowledge:
    dir: halo/context/knowledge
    drafts_dir: halo/context/drafts
  central:
    repo: ""
    cache_dir: halo/context/.central
    mode: read-only
    conflict: project-wins
```
