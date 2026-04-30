# 2-3/task-33: S1-34 + C1-23 delete-remove-index

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

实现 S1-34 file-delete-confirm 中由 C1-23 delete-remove-index 支撑的页面功能点。

## 绑定

- UX 页面：S1-34 file-delete-confirm
- Core 能力：C1-23 delete-remove-index

## 核对清单

1. 只处理 S1-34 页面中的 C1-23 功能点。
2. 读取页面规格、MVP control map、Core API 和 C1-23 能力规格。
3. 只接入 C1-23 对应的 CoreBridge / 状态 / 错误映射，不实现本页面其他 Core 功能点。
4. 不顺手实现相邻页面。

## 完成标准

- S1-34 中 C1-23 对应的用户可见功能可被触发和验收。
- 没有使用 mock、fixture 或静态状态伪造真实 Core 闭环。
- 未触碰 control map 之外的 Core 能力。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
