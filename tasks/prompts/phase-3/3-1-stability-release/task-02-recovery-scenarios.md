# 3-1/task-02: recovery scenarios

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

落地 Stage 1 MVP 的 recovery scenarios（恢复场景）测试或手工验证清单。本任务只补恢复验收证据，不补产品实现。

## 绑定

- 阶段级稳定性任务；不绑定单个 UX 页面或 Core 能力。
- 依赖 `3-1/task-01` 的 error recovery matrix 作为场景来源。

## 核对清单

1. 读取 testing、troubleshooting、transactional import 和 recovery/error/repair 相关 Core 能力规格。
2. 将 `3-1/task-01` 的矩阵转成可执行恢复场景，区分自动化测试、手工冒烟和暂缺证据。
3. 覆盖崩溃、中断、staging 残留、DB 修复、iCloud 占位符、权限失败、导入失败、reindex/repair 失败。
4. 每个场景都必须说明初始状态、触发方式、预期恢复结果、用户文件不变量和验证方式。
5. 对无法自动化的场景建立手工验证清单；缺少证据的 P0/P1 场景必须阻断发布。
6. 只补测试、脚本或 `docs/development/**` 下的恢复证据；不修改 Core/Swift 主功能。

## 完成标准

- 恢复场景清单覆盖 Stage 1 MVP 的高风险恢复路径，并能追溯到 matrix、测试或手工验证项。
- 崩溃/中断类场景明确证明不会丢用户文件、不会留下最终目录半成品、不会把失败操作标为成功。
- DB 修复、iCloud/权限失败和 staging recovery 均有通过/不通过结论。
- Validation 全部运行；未运行项必须说明原因、影响和替代证据。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
cargo test --workspace recovery
cargo test --workspace transactional_import
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
