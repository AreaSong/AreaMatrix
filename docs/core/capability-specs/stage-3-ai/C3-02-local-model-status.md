# C3-02 local-model-status

## 服务的 UX 页面

- S3-02 local-model-status

## Core API

- 计划新增：`get_local_model_status`、`locate_local_model_folder`

## 输入

- model id、storage location、cached status snapshot。

## 输出

- availability、version、size、last_error、recommended_action、last_checked_at、diagnostics_summary。

## DB 变化

- 记录模型状态和最后检查时间。

## 文件系统变化

- 读取本地模型 manifest、模型目录元数据和 runtime 状态。
- 不下载、安装、删除或训练模型；安装器/下载器需要独立规格。

## 错误码

- `Config`
- `PermissionDenied`
- `Io`

## 验收标准

- 本地模型不可用时不阻断 Core 基础功能。
- 模型状态可被 UI 刷新。
- 状态检测或定位失败不启用远程 fallback。
- 健康检查和 diagnostics summary 不读取用户文件正文。

## 延后范围

- 模型 marketplace、模型下载器、模型训练器和缓存删除器不在当前 S3-02 UI 范围。
