# AreaMatrix Prompt Dependency Graph

> Runner 按本文件解析批次依赖；同一批次内 task 按文件名顺序执行。

## Layer 0: 执行体系

- `0-1` 执行体系

## Layer 1: 工程骨架

- `0-2` 工程骨架 ← 依赖 `0-1`

## Layer 2: Rust Core

- `1-1` Repo 与 Config 能力 ← 依赖 `0-2`
- `1-2` Classify 与 Import 能力 ← 依赖 `1-1`
- `1-3` Query、Detail 与 Tree 能力 ← 依赖 `1-2`
- `1-4` Recovery、Sync、Overview 与 Error 能力 ← 依赖 `1-2`, `1-3`
- `1-5` File Actions、iCloud Conflict 与 Metadata Repair ← 依赖 `1-3`, `1-4`

## Layer 3: macOS App

- `2-1` First Launch 与主窗口真实数据 ← 依赖 `1-1`, `1-3`, `1-4`
- `2-2` Import 与 Conflict 纵向闭环 ← 依赖 `2-1`, `1-2`, `1-3`
- `2-3` Detail、Settings、Error Recovery 与 File Actions ← 依赖 `2-1`, `1-3`, `1-4`, `1-5`
- `2-4` FSEvents、iCloud、Overview 与 Repair UI 合同 ← 依赖 `2-1`, `2-2`, `2-3`, `1-4`, `1-5`

## Layer 4: 稳定与发布

- `3-1` 稳定、测试、发布准备 ← 依赖 `2-2`, `2-3`, `2-4`

## Layer 5: 后续路线图细粒度闭环

- `4-1` Stage 2 体验完善：C2-01..C2-19 ← 依赖 `3-1`
- `4-2` Stage 3 AI：C3-01..C3-10 ← 依赖 `4-1`
- `4-3` Stage 4 多端扩展：C4-01..C4-21 ← 依赖 `4-2`
