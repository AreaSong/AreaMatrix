# 错误码表（CoreError）

> 记录 AreaMatrix Core 通过 UniFFI 暴露的结构化错误、稳定映射元数据和恢复边界。
>
> 阅读时长：约 8 分钟。

---

## 合同边界

`CoreError` 是 Rust Core 与 Swift 平台层之间的错误合同。调用方必须按 variant 和结构化字段分支，
不能解析 `Display`、`localizedDescription` 或用户文案来决定业务流程。

Core 通过 `to_error_mapping` / `map_core_error` 返回：

- `kind`：稳定错误分类。
- `code`：稳定英文错误码，例如 `repo_config_revision_conflict`。
- `field`：可选稳定字段名，不是翻译后的 label。
- `arguments`：由稳定 name/value 组成的结构化参数；值按 verbatim 处理。
- `recovery_action_ids`：可执行恢复动作标识，例如 `reload_latest`、`review_changes`。
- `severity`：呈现严重度。
- `recoverability`：恢复姿态。
- `technical_details`：可选原始技术详情，只用于受控详情和诊断。

Core 不返回 `user_message`、`suggested_action` 或任何中文/英文展示句子。Swift 使用当前界面语言按
`code + arguments` 从 String Catalog 生成标题、说明、按钮和 VoiceOver 文案；未知 code 使用本地化通用
错误，同时原样保留 technical details。日志和 recovery state 也只保存稳定 code/payload。

错误映射是无副作用纯函数：不得读取文件系统、打开 DB、写日志或修改资料库。

## CoreError 完整表

| Variant | 稳定语义 | Severity | Recoverability | 默认恢复方向 |
|---|---|---|---|---|
| `Io { message }` | 文件或底层 IO 失败 | medium | Retryable | 重试；持续失败时检查磁盘和文件状态 |
| `Db { message }` | SQLite 或 metadata 失败 | high | UserActionRequired | 按 DB 子语义处理 |
| `DbLocked { message }` | SQLite typed busy/locked | medium | Retryable | 重试；不进入 repair |
| `DbCorrupted { message }` | SQLite typed corrupt/not-a-database | critical | Fatal | 进入阻断恢复或 repair |
| `Config { reason }` | 配置无效或保存失败 | medium | UserActionRequired | 打开设置并修正或恢复有效配置 |
| `Validation { reason }` | API 输入或编辑草稿无效 | low | UserActionRequired | 修正当前输入 |
| `Classify { reason }` | 分类规则执行失败 | low | RefreshRequired | 保留文件并回落 inbox，再检查规则 |
| `Conflict { path }` | 路径、命名或状态冲突 | medium | UserActionRequired | 更名、选择冲突策略或刷新状态 |
| `DuplicateFile { existing_path }` | active 文件已拥有相同内容 | low | UserActionRequired | Skip、Keep both 或经确认 Replace |
| `FileNotFound { path }` | DB row 或操作目标对应文件不存在 | low | RefreshRequired | 刷新；缺失文件页可 Relink 或移除索引 |
| `ExpiredAction { action_id }` | Undo/Redo token 已过期或不可再执行 | low | RefreshRequired | 刷新 Undo History |
| `RepoNotInitialized { path }` | 所选目录不是已初始化资料库 | high | UserActionRequired | 初始化、重新选择或进入恢复页面 |
| `InvalidPath { path }` | 路径越界、格式无效或不满足资料库约束 | low | UserActionRequired | 修改路径或名称 |
| `ICloudPlaceholder { path }` | 所需本地内容尚未下载 | medium | Retryable | 用户触发 Download & retry 或换本地位置 |
| `StagingRecoveryRequired { path }` | staging 状态必须先恢复 | high | UserActionRequired | 进入导入恢复上下文 |
| `PermissionDenied { path }` | 文件或资料库权限不足 | high | UserActionRequired | 修复权限或选择其他位置 |
| `Internal { message }` | 未预期内部失败或不变量破坏 | critical | Fatal | 保留上下文并进入当前页面的阻断恢复 |
| `RevisionConflict { resource, expected_revision, current_revision }` | revision CAS 已过期 | medium | UserActionRequired | 保留草稿，reload latest 或 review 后显式重存 |

实际 Rust 定义位于 `core/src/error/core_error.rs`，FFI 定义位于 `core/area_matrix.udl`。

`Config { reason }` 的 reason 是 technical details，不是 UI 文案。字段、规则、行列和恢复动作必须由稳定
code/field/arguments 明确提供；Swift 不解析 reason。只有 Core 明确提供 parse location 时 UI 才显示
行号/列号。`Revert` 仅在 recovery action IDs 包含且 last-valid backup 确实存在时可用。

## DB 子语义

`Db` 保持通用公开 variant；`DbLocked` 与 `DbCorrupted` 承载 SQLite typed error code。Core 不再按 SQLite
message 子串猜测 locked/corrupt。已知来源必须在产生错误的边界返回 typed variant 和稳定 code，未知 DB
文本只作为 technical details：

| 子语义 | Severity | Recoverability | UI |
|---|---|---|---|
| 明确的 db busy code | medium | Retryable | inline 或 banner Retry |
| 明确的 db integrity code | critical | Fatal | blocking repair |
| 其他 DB 错误 | high | UserActionRequired | 保留上下文，进入诊断或恢复 |

不得把未知 `Db` 默认当成可重试，也不得用任意字符串让 UI 自动执行 repair。

## Severity 与 UI

| Severity | 默认 UI 形态 |
|---|---|
| low | toast 3s 自动消失 |
| medium | banner 可手动关闭 |
| high | modal alert |
| critical | blocking modal |

页面上下文可以提高阻断强度。例如 `RepoNotInitialized` 的 Core severity 是 high，资料库打开页仍可使用
blocking route；这不改变 Core error contract。

## 重试规则

`Retryable` 表示同一操作在外部条件变化后可以再次尝试，不等于允许静默循环。

- DB locked/busy 可以由页面提供 Retry，并使用 SQLite `busy_timeout` 控制短暂竞争。
- 短暂 IO busy 可以在明确边界内有限退避；失败仍需返回用户可见状态。
- `ICloudPlaceholder` 不自动下载。只有用户点击 `Download & retry` 后，macOS 平台层才请求下载；Core
  和 watcher 都不触发下载，也不在后台自动重试。
- `PermissionDenied`、`DuplicateFile`、`Conflict`、`StagingRecoveryRequired` 和 `Internal` 不自动重试。
- cursor、overview 或 DB 提交失败时，外部同步必须保留可重放状态，不能通过吞错推进 cursor。

## Swift 侧映射

Swift 使用 `CoreErrorMappingSnapshot` 和 `CoreErrorKindSnapshot`，并通过 Core 的
`map_core_error(ErrorMappingInput)` 获取稳定 code/payload。应用语义错误使用 `AppSemanticError` 携带同一
snapshot；不存在另一套字符串型 `AppError` 合同，也不缓存翻译后的 String。

```swift
let mapping = await errorMapper.mapCoreError(error)
let display = localizer.errorDisplay(
    code: mapping.code,
    arguments: mapping.arguments,
    recoveryActionIDs: mapping.recoveryActionIds
)
switch mapping.recoverability {
case .retryable:
    showRetry(mapping)
case .userActionRequired:
    showUserAction(mapping)
case .refreshRequired:
    refreshAndPresent(mapping)
case .fatal:
    showBlockingRecovery(mapping)
}
```

Swift 可以在 Technical Details 中显示经过控制的 `technicalDetails`，但不得把包含用户名或绝对路径的
`error.localizedDescription` 直接显示给用户，也不得把原始上下文自动上传。

## 恢复与隐私约束

- `ICloudPlaceholder` 的 Download & retry 必须由用户触发。
- `StagingRecoveryRequired` 必须进入当前 import/startup recovery 上下文，不能自动删除 residue。
- `FileNotFound` 的 Relink 只更新索引指向；移除索引不得删除外部用户文件。
- repository diagnostics 可能包含完整 metadata DB、WAL 和 SHM；导出前必须确认，不得称为全文脱敏。
- About 文本诊断不包含用户文件正文，并按其专用合同处理路径和用户名。
- `Internal` 默认提供 Leave flow、Collect diagnostics 和 Open Issue；不假设存在全局重启或统一 zip
  bundle。只有当前上下文接入了真实可执行且经过验证的 restart 动作时，才显示 Restart。

## 反模式

- 用技术术语吓退用户，或把 SQLite/Rust 原始文本直接作为标题。
- 把 `error.localizedDescription` 直接显示并据此选择业务动作。
- 对 `Db`、iCloud、权限或 staging 错误“不要硬来”：不静默下载、不猜测修复、不覆盖用户文件。
- 把同机 dry-run、截图或日志文本当作恢复路径已经闭环的证据。

## 验证

```bash
cd core
cargo test --test error_mapping_contract_api
cargo test --test error_recovery_matrix
```

涉及 Swift 消费路径时还需运行对应 error mapping / recovery XCTest。

## Related

- [Core API](core-api.md)
- [错误文案与恢复路径](../ux/error-messages.md)
- [错误恢复矩阵](../development/error-recovery-matrix.md)
- [文件监听与外部变化同步](../architecture/fs-watcher.md)
