# Stage 4 Multiplatform Core 能力索引

> Stage 4 目标是复用 Rust core，把 AreaMatrix 扩展到 iOS、Windows、Linux，并显式处理平台文件权限、监听、云盘差异和多端冲突。

## 能力列表

| ID | 能力 | 类型 | 主要消费页面 | Prompt |
|---|---|---|---|---|
| C4-01 | [cross-platform-ffi-contract](stage-4-multiplatform/C4-01-cross-platform-ffi-contract.md) | Platform | S4-X-02 | `4-3/task-01` |
| C4-02 | [mobile-repo-connect](stage-4-multiplatform/C4-02-mobile-repo-connect.md) | iOS Repo | S4-IOS-01, S4-X-04, S4-X-05 | `4-3/task-02` |
| C4-03 | [mobile-library-query](stage-4-multiplatform/C4-03-mobile-library-query.md) | iOS Query | S4-IOS-02, S4-IOS-05 | `4-3/task-03` |
| C4-04 | [camera-import](stage-4-multiplatform/C4-04-camera-import.md) | iOS Import | S4-IOS-03 | `4-3/task-04` |
| C4-05 | [share-extension-import](stage-4-multiplatform/C4-05-share-extension-import.md) | iOS Import | S4-IOS-04 | `4-3/task-05` |
| C4-06 | [files-import](stage-4-multiplatform/C4-06-files-import.md) | iOS Import | S4-IOS-07 | `4-3/task-06` |
| C4-07 | [mobile-detail](stage-4-multiplatform/C4-07-mobile-detail.md) | iOS Detail | S4-IOS-05 | `4-3/task-07` |
| C4-08 | [cloud-permission-state](stage-4-multiplatform/C4-08-cloud-permission-state.md) | Cloud | S4-IOS-06, S4-WIN-03 | `4-3/task-08` |
| C4-09 | [windows-repo-connect](stage-4-multiplatform/C4-09-windows-repo-connect.md) | Windows Repo | S4-WIN-01, S4-X-04, S4-X-05 | `4-3/task-09` |
| C4-10 | [linux-repo-connect](stage-4-multiplatform/C4-10-linux-repo-connect.md) | Linux Repo | S4-LNX-01, S4-LNX-03 | `4-3/task-10` |
| C4-11 | [desktop-main-query](stage-4-multiplatform/C4-11-desktop-main-query.md) | Desktop Query | S4-WIN-02, S4-LNX-02 | `4-3/task-11` |
| C4-12 | [platform-watcher-status](stage-4-multiplatform/C4-12-platform-watcher-status.md) | Watcher | S4-WIN-04, S4-LNX-04 | `4-3/task-12` |
| C4-13 | [desktop-import-flow](stage-4-multiplatform/C4-13-desktop-import-flow.md) | Import | S4-WIN-05, S4-LNX-05 | `4-3/task-13` |
| C4-14 | [onedrive-risk-state](stage-4-multiplatform/C4-14-onedrive-risk-state.md) | Cloud | S4-WIN-03 | `4-3/task-14` |
| C4-15 | [sync-conflict-detect](stage-4-multiplatform/C4-15-sync-conflict-detect.md) | Sync | S4-X-03, S4-X-01 | `4-3/task-15` |
| C4-16 | [sync-conflict-resolve](stage-4-multiplatform/C4-16-sync-conflict-resolve.md) | Sync | S4-X-01, S4-X-09 | `4-3/task-16` |
| C4-17 | [platform-capabilities](stage-4-multiplatform/C4-17-platform-capabilities.md) | Platform | S4-X-02 | `4-3/task-17` |
| C4-18 | [missing-file-recovery](stage-4-multiplatform/C4-18-missing-file-recovery.md) | Recovery | S4-X-06 | `4-3/task-18` |
| C4-19 | [manual-rescan](stage-4-multiplatform/C4-19-manual-rescan.md) | Recovery | S4-X-07 | `4-3/task-19` |
| C4-20 | [repository-settings-cross-platform](stage-4-multiplatform/C4-20-repository-settings-cross-platform.md) | Settings | S4-X-08 | `4-3/task-20` |
| C4-21 | [replace-confirm-cross-platform](stage-4-multiplatform/C4-21-replace-confirm-cross-platform.md) | Safety | S4-X-09 | `4-3/task-21` |

## 切片原则

- Rust Core 只承载跨平台一致能力；文件 picker、bookmark、watcher 和系统 Trash 由平台层适配。
- 平台能力差异必须结构化暴露给 UI，不能用文案硬猜。
- 多端冲突不静默解决，不删除用户文件，不覆盖已有资料。
