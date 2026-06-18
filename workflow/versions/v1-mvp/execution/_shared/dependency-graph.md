# AreaMatrix Prompt Dependency Graph

> Runner 以 manifest 中的 task-level `depends` 为真实依赖；本文件只描述阶段批次结构。

## Layer 0: 执行体系

- `0-1` 执行体系

## Layer 1: 工程骨架

- `0-2` atomic foundation tasks + foundation integration verify ← 依赖 `0-1`

## Layer 2: Rust Core

- `1-1` Repo / Config C1-01..C1-04 atomic contract、implementation、failure、validation、integration verify ← 依赖 `0-2`
- `1-2` Import / Classify / Conflict C1-05..C1-10 atomic tasks ← 依赖 `1-1`
- `1-3` Query / Detail / Tree C1-11..C1-15 atomic tasks ← 依赖 `1-2`
- `1-4` Recovery / Sync / Overview / Error C1-16..C1-21 atomic tasks ← 依赖 `1-3`
- `1-5` File Actions / iCloud / Repair C1-22..C1-26 atomic tasks ← 依赖 `1-4`

## Layer 3: macOS App

- `2-1` S1-01..S1-11 page-feature tasks + page / first launch / main integration verify ← 依赖对应 C1 integration verify
- `2-2` S1-16..S1-24 page-feature tasks + page / import-conflict integration verify ← 依赖 `2-1` 与对应 C1 integration verify
- `2-3` S1-12..S1-15、S1-26..S1-35 page-feature tasks + page / detail/settings/actions integration verify ← 依赖 `2-1` 与对应 C1 integration verify
- `2-4` S1-25、S1-36、S1-37 page-feature tasks + page / sync/repair integration verify ← 依赖 `2-2`、`2-3` 与对应 C1 integration verify

## Layer 4: 稳定与发布

- `3-1` error recovery、recovery scenarios、performance、release、stage1 integration verify ← 依赖 `2-4/task-08`

## Layer 5: 后续路线图细粒度闭环

- `4-1` Stage 2：C2-01..C2-19 每个拆为 contract / implementation / failure-edge / validation / integration verify，随后 S2-01..S2-23 page-feature + page integration verify，最后 stage verify ← 依赖 `3-1`
- `4-2` Stage 3：C3-01..C3-10 每个拆为 contract / implementation / failure-edge / validation / integration verify，随后 S3-01..S3-10 page-feature + page integration verify，最后 stage verify ← 依赖 `4-1`
- `4-3` Stage 4：C4-01..C4-21 每个拆为 contract / implementation / failure-edge / validation / integration verify，随后 S4-* page-feature + page integration verify，最后 stage verify ← 依赖 `4-2`
