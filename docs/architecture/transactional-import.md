# 事务式导入

> 记录 AreaMatrix Copy、Move、Index 导入的真实提交顺序、补偿 guard 和启动恢复边界。
>
> 阅读时长：约 8 分钟。

---

## 核心不变量

- 成功导入后，资料库文件和 active DB row 同时可见。
- 失败导入不得留下最终目录半成品。
- Copy/Move 的内部 staging 只位于 `.areamatrix/staging/`。
- Move 在资料库提交成功前不删除原源文件。
- Indexed 不复制、移动、删除或覆盖外部源文件。
- replacement 和恢复路径不得覆盖已存在的用户文件。

AreaMatrix 通过多个短 SQLite transaction、文件系统操作和 RAII guard（作用域退出时执行补偿的资源
守卫）协作实现这些不变量。它不是一个跨文件系统和 SQLite 的单一 transaction。

## Copy 与 Move 顺序

```mermaid
flowchart LR
    source["源文件"] --> stagingCopy["复制并 hash 到内部 staging"]
    stagingCopy --> stagingRow["提交 staging DB row"]
    stagingRow --> finalFile["安全移动到最终路径"]
    finalFile --> promote["提交 active row 与 imported log"]
    promote --> overview["更新 generated overview"]
    overview --> removal["Move 最后尝试删除源文件"]
```

真实顺序：

1. 校验资料库、源文件、文件名和目标分类。
2. 创建 `copy-import-<uuid-v4>` 或 `move-import-<uuid-v4>` staging 路径。
3. 把源文件复制到 staging，同时计算 SHA-256 和 size。
4. 解析 duplicate strategy 和最终目标路径。
5. 在独立 transaction 中插入 `files.status = staging` row。
6. 把 staging 文件以 no-replace 方式落到最终路径。
7. 在第二个 transaction 中把 row 提升为 active，并写入 `change_log.action = imported`。
8. 更新 generated overview。
9. replacement 场景确认旧文件已进入可恢复的系统废纸篓路径。
10. 解除补偿 guard。
11. Move 模式最后删除原源文件。

Move 的最后一步失败时，导入结果仍保留已安全提交的资料库文件，并返回
`source_removal_status = Retained` 与失败原因，避免为“移动语义”反向删除已经成功导入的文件。

### 跨文件系统安全落位

staging 到最终路径的 no-replace 落位不依赖单一文件系统 rename：

1. 优先用 `hard_link(source, destination)` 创建不覆盖目标的最终路径。
2. 目标已存在时立即返回 `Conflict`。
3. hard link 不可用（包括跨文件系统）时，使用 `create_new` 创建目标并复制内容。
4. fallback copy 校验实际复制字节数；复制写入执行 `flush` 和 `sync_all`。
5. 最终路径完成后才删除旧 staging 路径。
6. 删除旧路径失败时删除刚创建的目标，避免重复文件或半提交状态。

## Indexed 顺序

Indexed 模式直接读取外部源文件的 metadata 和 hash，不进入 staging，也不创建资料库内最终副本。

- 普通 Indexed import 在一个 transaction 中写 active row 和 imported log。
- replacement 会先保护原有 repo-owned 文件，再在 transaction 中替换 metadata。
- overview 或 replacement 保护失败时执行专用 DB rollback。
- 成功与失败都不移动、删除、重命名或覆盖 Indexed 源文件。

Copy/Move 的 `staging` DB row 不进入普通文件列表、overview 或 command index；即使读取接口包含 deleted row，
也必须继续排除未提交的 staging 状态。

## 补偿 guard

| Guard | 负责状态 | 失败补偿 |
|---|---|---|
| `StagingFileGuard` | 本次内部 staging 文件 | best-effort 删除本次文件 |
| `DbStagingRowGuard` | 本次 staging DB row | best-effort 删除 row |
| `FinalFileGuard` | 已落位的最终文件 | Copy 删除本次半成品；Move 尝试恢复源路径 |
| `ReplacementFileGuard` | 被替换的旧文件 | 保持旧文件可恢复并配合 DB rollback |

所有补偿都只处理本次尝试拥有的路径。no-replace 安全移动拒绝已存在目标，不覆盖用户文件。

## 启动恢复

`recover_on_startup` 检查 staging rows 和 staging 目录：

- Copy staging row：只在路径通过 `.areamatrix/staging/**` 安全校验后删除内部文件，再删除 row。
- Move staging row：优先把 staging 文件恢复到记录的原绝对路径。
- 源路径已经存在、父目录缺失或路径不安全：保留 staging 文件与 row，并返回 warning。
- 没有 DB row 的孤儿文件只自动清理受控的 `copy-import-*` 文件名。
- 未分类文件、目录、符号链接和受保护路径保持不动并返回 warning。

当前没有 24 小时 staging GC、每 6 小时 timer、成功导入后的 GC 或公开手工 cleanup API。恢复只在明确的
startup recovery 调用中执行。

## 失败状态

| 失败位置 | 结果 |
|---|---|
| staging copy/hash | 源文件保留；内部 staging 由 guard 清理 |
| staging row transaction | 源文件保留；无最终文件 |
| staging → final | staging row/文件进入补偿或启动恢复 |
| active promotion transaction | 最终半成品由 guard 清理或恢复源路径 |
| overview | 本次 active metadata 回滚；最终文件 guard 执行补偿 |
| Move 源删除 | 导入保持成功，源文件保留并报告 `Retained` |

恢复和补偿不得删除无法证明属于本次导入的文件。

## 验证重点

- Copy 成功后源文件和资料库文件都存在。
- Move 成功删除源文件；源删除失败返回 `Retained`。
- Indexed 始终无 staging/final 副本。
- duplicate Skip/KeepBoth/Overwrite/Ask 的 FS 与 DB 状态一致。
- promotion、overview、replacement 和 Trash 失败均不留下半成品。
- startup recovery 对 Copy/Move、非法路径、symlink 和未知文件 fail closed。
- 既有 `README.md` 和用户文件不被覆盖。

## Related

- [source-of-truth.md](source-of-truth.md)
- [data-model.md](data-model.md)
- [fs-watcher.md](fs-watcher.md)
- [../modules/storage.md](../modules/storage.md)
- [../development/recovery.md](../development/recovery.md)
