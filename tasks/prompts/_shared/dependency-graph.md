# AreaMatrix Prompt Dependency Graph

> Runner 按本文件解析批次依赖；同一批次内 task 按文件名顺序执行。

## Layer 0: 执行体系

- `0-1` 执行体系

## Layer 1: 工程骨架

- `0-2` 工程骨架 ← 依赖 `0-1`

## Layer 2: Rust Core

- `1-1` Core DB 与 Repo ← 依赖 `0-2`
- `1-2` Classify 与 Storage ← 依赖 `1-1`
- `1-3` FFI 集成 ← 依赖 `1-1`, `1-2`

## Layer 3: macOS App

- `2-1` macOS Shell 与 UI ← 依赖 `1-3`
- `2-2` Watcher、iCloud 与 Overview ← 依赖 `2-1`, `1-3`

## Layer 4: 稳定与发布

- `3-1` 稳定、测试、发布准备 ← 依赖 `2-1`, `2-2`

## Layer 5: 后续路线图

- `4-1` Stage 2 体验完善 ← 依赖 `3-1`
- `4-2` Stage 3 智能化 ← 依赖 `4-1`
- `4-3` Stage 4 多端扩展 ← 依赖 `4-2`

