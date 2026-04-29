# C1-01 validate-repo-path

## 服务的 UX 页面

- S1-02 choose-path
- S1-03 validate-path
- S1-11 main-repo-error
- S1-32 error-recovery

## Core API

- 计划新增：`validate_repo_path(repo_path) -> RepoPathValidation`
- 过渡相关：`load_config(repo_path)`、`get_latest_scan_session(repo_path)`

## 输入

- `repo_path`: 用户选择的目录路径。

## 输出

- 路径是否存在、是否可读写、是否为空、是否已初始化、是否位于 `.areamatrix/` 内部。
- 是否疑似 iCloud 路径、是否有未完成 scan session。
- 推荐初始化模式：`CreateEmpty` 或 `AdoptExisting`。

## DB 变化

- 无。

## 文件系统变化

- 只读检查：metadata、权限、子项数量、`.areamatrix/` 探测。
- 不创建、不删除、不移动任何文件。

## 错误码

- `InvalidPath`
- `PermissionDenied`
- `ICloudPlaceholder`
- `RepoNotInitialized`

## 验收标准

- 空目录、非空目录、已初始化目录、不可写目录、`.areamatrix/` 子目录都有测试。
- 非空目录只返回风险与推荐模式，不做接管副作用。
- Swift UI 可以用结构化结果展示 S1-03 风险提示，而不是解析错误字符串。

## 延后范围

- 沙盒 bookmark 持久化属于 macOS app 层。
- iCloud 占位符自动下载不在本能力内。
