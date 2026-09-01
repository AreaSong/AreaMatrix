# AreaMatrix 文档、API、UDL、Bridge 与生成物漂移审计记录

本目录只保存本次只读审计的可恢复证据，不修改产品源、UDL、bindings、manifest、workflow 或 live queue。

## 启动状态

- 审计快照：见 `scope.json`。
- 原始工作树已有改动：按 `scope.json.dirty_paths_at_start` 保留，不覆盖、不回退。
- 当前审计目录从审计宇宙排除，避免台账生成导致自引用范围不断增长。
- 冻结后出现的仓库文件或内容变化必须登记为 scope delta，并在收口前纳入或标记 `BLOCKED`。

## 源事实层级

1. 产品、架构、API、UX 与开发事实：`docs/**`。
2. AI 协作和不变量：`.ai-governance/**`。
3. Core API：`docs/api/core-api.md` -> `core/area_matrix.udl` -> Rust -> UniFFI/Swift/.NET -> 调用方/测试。
4. Prompt：task -> matching manifest -> shared rules -> rendered copy-ready/verify-ready。
5. README、Codex、Cursor、skills、residual ledger 均为摘要、适配或索引层，不得成为唯一产品事实。

## 审计日志

- 2026-08-20：完整读取根、Core、macOS、workflow `AGENTS.md`，doc-sync skill、source map、drift checklist 及要求的治理/docs/workflow/residual 入口。
- 2026-08-20：记录工作树；冻结首个文件快照并启动三个只读子代理。
- 2026-08-20：冻结后检测到其他并行审计新增 untracked runtime 文件，待收口时做 scope delta 守恒。

## 候选线索

待逐项复核。
