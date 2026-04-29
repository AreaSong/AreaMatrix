# C4-17 platform-capabilities

## 服务的 UX 页面

- S4-X-02 platform-differences

## Core API

- 计划新增：`get_platform_capabilities(platform) -> PlatformCapabilities`

## 输入

- platform id、app version。

## 输出

- watcher、trash、share extension、cloud placeholder、security bookmark 支持矩阵。

## DB 变化

- 无。

## 文件系统变化

- 无。

## 错误码

- `Config`

## 验收标准

- UI 显示的平台差异来自结构化能力。
- 不支持的危险操作必须在 UI 层禁用。
- 文案不承诺平台不存在的能力。

## 延后范围

- 插件能力发现后续扩展。
