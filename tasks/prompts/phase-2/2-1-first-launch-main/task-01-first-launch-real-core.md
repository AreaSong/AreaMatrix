# 2-1/task-01: 首次启动真实 Core 闭环

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 S1-01 到 S1-07 的首次启动闭环，接入真实 CoreBridge，不用静态 mock 通过验收。

## 绑定

- UX 页面：S1-01, S1-02, S1-03, S1-04, S1-05, S1-06, S1-07
- Core 能力：C1-01, C1-02, C1-03, C1-04, C1-16, C1-21

## 核对清单

1. 首次启动可选择资料库目录并调用路径校验。
2. 空目录初始化与非空目录接管在 UI 上明确区分。
3. 初始化/接管调用真实 CoreBridge，失败进入 S1-06。
4. 完成后进入主窗口所需 repo state。

## 完成标准

- S1-02/S1-03/S1-04/S1-05/S1-06/S1-07 页面路径可串起来。
- 非空目录接管 UI 明确“不移动、不重命名、不删除、不覆盖”。
- 验收时若仍用 mock init/adopt，判定不通过。

## 验证

```bash
xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
