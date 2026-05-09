# 3-1/task-03: performance benchmarks

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

建立 Stage 1 MVP 的 performance benchmarks（性能基线）和发布前性能验收证据。本任务只补 benchmark、测试或性能记录，不补产品实现。

## 绑定

- 阶段级性能任务；不绑定单个 UX 页面或 Core 能力。
- 性能阈值以 `docs/development/performance.md` 和 `docs/roadmap/stage-1-mvp.md` 为准。

## 核对清单

1. 读取 testing、performance、observability 和 Stage 1 MVP 最终验收清单。
2. 记录或补齐性能基线，至少覆盖启动、单文件导入、100 文件批量导入、reindex、Tree/list 响应和内存。
3. 每个指标必须写明数据集规模、设备/环境、命令或测试入口、阈值、实测值和通过/不通过结论。
4. Core hot path 优先使用 `cargo bench` 或集成测试；Swift UI 性能优先使用 XCTest performance 或 Instruments 证据。
5. 性能不达标时记录阻断项和回退到 Phase 1/2 的修复建议；不得在本任务中顺手重写产品逻辑。
6. 只补 benchmark、测试、测试工程引用、脚本或 `docs/development/**` 下的性能证据。

## 完成标准

- 已形成 Stage 1 MVP 性能基线，并覆盖发布清单要求的启动、导入、reindex、Tree/list 和内存指标。
- 每个性能指标都有可重复运行的命令或明确手工测量方法。
- 任何 P0/P1 性能回退或未测指标都阻断 release checklist，不得默认通过。
- Validation 全部运行；未运行项必须说明环境原因和剩余风险。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
cargo bench --manifest-path core/Cargo.toml --workspace --no-run
./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests
```
