# 2-3/task-27: S1-31 settings-about ui-only

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

实现 S1-31 settings-about 的 UI-only 页面状态；本页面在 control map 中没有独立 Core 能力。

## 绑定

- UX 页面：S1-31 settings-about
- Core 能力：None（UI-only）

## 核对清单

1. 只实现 S1-31 页面或页面区域。
2. 读取页面规格和 control map，确认本页无需新增 Core 能力。
3. 不新增临时 Core API 或 mock 后端能力。
4. 不顺手实现相邻页面。

## 完成标准

- S1-31 可按页面规格触发和验收。
- 没有引入未声明的 Core 能力依赖。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
