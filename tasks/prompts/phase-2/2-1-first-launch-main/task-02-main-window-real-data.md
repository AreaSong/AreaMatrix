# 2-1/task-02: 主窗口真实数据闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 S1-08 到 S1-11 的三栏主窗口，侧栏、列表、加载态和 repo 错误态接真实 Core 数据。

## 绑定

- UX 页面：S1-08, S1-09, S1-10, S1-11
- Core 能力：C1-01, C1-11, C1-12, C1-15, C1-16, C1-21

## 核对清单

1. 主窗口使用三栏结构：Tree / List / Detail。
2. 空库、正常列表、加载/扫描、repo 错误态均有 UI。
3. Tree 和 List 来自 `list_tree_json` / `list_files`，不是静态 fixture。
4. Repo 错误通过 AppError 映射展示。

## 完成标准

- 完成首次启动后可进入主窗口并读取真实空库或文件列表。
- S1-08/S1-09/S1-10/S1-11 状态切换稳定。
- 验收时若列表或 Tree 仍为硬编码数据，判定不通过。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
