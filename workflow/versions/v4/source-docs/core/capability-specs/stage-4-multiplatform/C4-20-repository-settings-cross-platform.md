# C4-20 repository-settings-cross-platform

## 服务的 UX 页面

- S4-X-08 repository-settings

## Core API

- `load_config`
- `update_config`
- `get_platform_capabilities`

## 输入

- repo config、platform。

## 输出

- 跨平台资料库设置和能力约束。

## DB 变化

- 更新 repo_config。

## 文件系统变化

- 原子更新配置。

## 错误码

- `Config`
- `PermissionDenied`
- `Io`

## 验收标准

- 平台不支持的设置项禁用或解释。
- 修改配置不移动用户文件。
- 配置失败回滚旧值。

## 延后范围

- 账号级云同步设置不在当前 Stage 4。
