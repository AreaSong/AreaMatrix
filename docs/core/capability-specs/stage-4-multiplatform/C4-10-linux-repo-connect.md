# C4-10 linux-repo-connect

## 服务的 UX 页面

- S4-LNX-01 choose-repo
- S4-LNX-03 local-folder-notice
- S4-X-04 repository-init-confirm
- S4-X-05 repository-adopt-confirm

## Core API

- `validate_repo_path`
- `init_repo`

## 输入

- Linux path。

## 输出

- path validation、risk、repo state。

## DB 变化

- 同 Stage 1 repo 能力。

## 文件系统变化

- 只处理授权路径；不执行 sudo/chmod。

## 错误码

- `InvalidPath`
- `PermissionDenied`
- `Io`

## 验收标准

- 本地目录风险提示可结构化展示。
- 不建议用户执行危险权限命令。
- 接管不改变用户文件。

## 延后范围

- Flatpak/Snap 沙盒细节后续单独拆分。
