# Stage 4 Multiplatform Control Map

> Stage 4 映射 iOS、Windows、Linux 和多端共用页面到跨平台 Core / 平台适配能力。

## 页面到能力矩阵

| UX | 页面 | Core 能力 | API / 能力意图 | 平台/文件系统边界 | Prompt |
|---|---|---|---|---|---|
| S4-IOS-01 | connect-repo | C4-02, C4-08 | repo validate/init/adopt | iOS security-scoped URL | `4-3/task-02` |
| S4-IOS-02 | mobile-library | C4-03 | mobile list/tree query | 分页，不全量加载 | `4-3/task-03` |
| S4-IOS-03 | camera-import | C4-04 | camera staged import | 平台层处理相机/临时文件 | `4-3/task-04` |
| S4-IOS-04 | share-extension-import | C4-05 | share staged import | Extension 超时/deferred import | `4-3/task-05` |
| S4-IOS-05 | mobile-file-detail | C4-07 | detail/log/note query | 缺失进入 recovery | `4-3/task-07` |
| S4-IOS-06 | icloud-permission | C4-08 | cloud permission state | Core 不管理 iCloud 同步 | `4-3/task-08` |
| S4-IOS-07 | files-import | C4-06, C4-21 | Files import / replace confirm | 授权 URL、placeholder | `4-3/task-06` |
| S4-WIN-01 | choose-repo | C4-09, C4-14 | Windows repo connect | Windows path / OneDrive risk | `4-3/task-09` |
| S4-WIN-02 | main-window | C4-11 | desktop query | 平台 UI 不直接扫描 repo | `4-3/task-11` |
| S4-WIN-03 | onedrive-notice | C4-08, C4-14 | OneDrive risk state | 不控制 OneDrive 同步 | `4-3/task-14` |
| S4-WIN-04 | watcher-status | C4-12, C4-19 | watcher health / rescan | Windows watcher 在平台层 | `4-3/task-12` |
| S4-WIN-05 | import-flow | C4-13, C4-21 | desktop import / replace | Trash 不可用则禁用危险动作 | `4-3/task-13` |
| S4-LNX-01 | choose-repo | C4-10 | Linux repo connect | 不建议 sudo/chmod | `4-3/task-10` |
| S4-LNX-02 | main-window | C4-11 | desktop query | 平台 UI 不直接扫描 repo | `4-3/task-11` |
| S4-LNX-03 | local-folder-notice | C4-10, C4-17 | local folder risk | 本地目录和第三方同步提示 | `4-3/task-10` |
| S4-LNX-04 | watcher-status | C4-12, C4-19 | watcher health / rescan | inotify 在平台层 | `4-3/task-12` |
| S4-LNX-05 | import-flow | C4-13, C4-21 | desktop import / replace | Trash 能力差异 | `4-3/task-13` |
| S4-X-01 | sync-conflict | C4-15, C4-16, C4-21 | conflict detect/resolve | 不静默删除任一版本 | `4-3/task-15` |
| S4-X-02 | platform-differences | C4-01, C4-17 | capability matrix | UI 不硬猜平台能力 | `4-3/task-17` |
| S4-X-03 | sync-conflict-entry | C4-15 | conflict count/status | 入口不解决冲突 | `4-3/task-15` |
| S4-X-04 | repository-init-confirm | C4-02, C4-09, C4-10 | init confirm | 不绕过确认 | `4-3/task-02` |
| S4-X-05 | repository-adopt-confirm | C4-02, C4-09, C4-10 | adopt confirm | 不移动/删除/覆盖用户文件 | `4-3/task-02` |
| S4-X-06 | missing-file-recovery | C4-18 | relink/remove record | remove record 不删文件 | `4-3/task-18` |
| S4-X-07 | rescan-confirm | C4-19 | manual rescan | 只读扫描，不改用户文件 | `4-3/task-19` |
| S4-X-08 | repository-settings | C4-17, C4-20 | cross-platform settings | 不支持项禁用 | `4-3/task-20` |
| S4-X-09 | replace-confirm | C4-16, C4-21 | replace confirm | Trash/备份，禁止永久删除 | `4-3/task-21` |

## 验收口径

- Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。
- 平台差异必须结构化暴露。
- 初始化、接管、Replace、Remove record、rescan 都必须确认后执行。
