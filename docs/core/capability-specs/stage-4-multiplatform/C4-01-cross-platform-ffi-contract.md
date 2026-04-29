# C4-01 cross-platform-ffi-contract

## 服务的 UX 页面

- S4-X-02 platform-differences

## Core API

- 计划新增：平台中立 UDL/Kotlin/Python/Swift 绑定检查接口。

## 输入

- target platform、binding version。

## 输出

- 支持的 API、类型映射、缺失能力。

## DB 变化

- 无。

## 文件系统变化

- 无。

## 错误码

- `Config`
- `Internal`

## 验收标准

- Core 不依赖 macOS 专属 API。
- 绑定生成在 iOS/Windows/Linux 可验证。
- 平台差异以 capability 输出，不靠 UI 猜测。

## 延后范围

- Web/Android 绑定不在当前 Stage 4。
