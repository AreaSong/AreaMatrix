# ADR-0004: 事务式导入存储

> 文件导入采用 staging 区 + 两阶段提交，保证崩溃 / 断电下不留半成品。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：core/storage / db
> 关联 ADR：[0003 真相源](0003-source-of-truth-strategy.md)

## 上下文

文件导入涉及多步操作：

1. 复制 / 移动文件到目标分类目录
2. 计算 SHA256
3. 写 DB（files 表 + change_log）
4. 触发 README 重新生成

任何一步失败（崩溃、断电、磁盘满、kill -9）都可能留下半成品状态：

- 文件已复制但 DB 没记录 → 用户看不到，但占空间
- DB 已记录但文件未到位 → 应用列表显示文件，点开打不开
- DB 已记录 + 文件已到位 + README 未更新 → 不是事务完整性问题，可后续补
- 跨会话恢复时不能识别"半成品"，会反复出错

需要一个机制保证：**要么完全成功，要么完全没发生（用户能继续重试）**。

## 决定

采用 **Staging 区 + 两阶段提交**：

```text
1. 计算 hash（不动目标）
2. 复制源文件到 .areamatrix/staging/<uuid>
3. INSERT files (status='staging', staging_path=<uuid>)
4. fsync staging 文件
5. rename staging → 目标分类路径（atomic on same volume）
6. UPDATE files SET status='active', staging_path=NULL
7. INSERT change_log
8. （后台）regenerate README
```

启动时调用 `recover_on_startup()`：

- 清理孤儿 staging 文件（DB 中无 status='staging' 行的）
- 回滚 status='staging' 的 DB 行（删除文件 + 删除行）
- 重新触发受影响分类的 README 生成

## 理由

1. **rename 是文件系统的原子操作**（同卷内）：要么成功要么失败，不会出现"半个文件"
2. **DB 与 FS 最终一致**：DB 中只要有 status='active' 行就说明 FS 也准备好了；遇到 status='staging' 一定是中断态
3. **可恢复性**：UUID 命名的 staging 文件 + DB 状态字段共同构成恢复信息
4. **代价可控**：只比直接复制多一次 rename，性能影响 < 5%
5. **代码上可用 RAII**：`StagingGuard` 在 Drop 时自动清理（详见 [transactional-import.md](../architecture/transactional-import.md)）

## 考虑过的备选

### A. 直接复制 + DB INSERT（无 staging）

- 优点：实现最简单
- 缺点：复制中途崩溃会留下不完整文件
  - 完整文件 + DB 无记录 → 重启后用户看不到
  - 不完整文件 + DB 有记录 → 文件打不开
- **为什么没选**：违反"不留半成品"

### B. 写时复制（COW）+ rename

只用 rename，不用 staging。

- 优点：少一次中间步骤
- 缺点：跨卷（如源在外接盘、目标在内置盘）时 rename 失败要 fallback 到 copy + delete，仍然不原子
- **为什么没选**：边界 case 太多，不如统一走 staging

### C. 应用层 WAL（Write-Ahead Log）

自己实现"先写日志再改文件"。

- 优点：理论最完备
- 缺点：实现复杂度高，等于自己造一个文件系统级 journaling
- **为什么没选**：staging 区已能解决，没必要重造

### D. 仅 DB 事务，不管 FS

DB 用事务（BEGIN / COMMIT），FS 操作不管。

- 优点：DB 一致性强
- 缺点：FS 崩溃时仍留半成品
- **为什么没选**：与目标不符

### E. 利用 macOS NSFileCoordinator 的事务能力

macOS API 提供文件操作协调机制。

- 优点：操作系统支持
- 缺点：
  - 协调的是"多个进程对同一文件"的并发，不是"原子完整性"
  - 跨平台不通用（Linux / Windows 没有等价物）
- **为什么没选**：解决的是另一类问题

## 后果

### 正面

- 任何崩溃后启动都能回到一致状态
- 用户在导入中途强退应用 → 启动后看不到半成品
- 实现可单元测试（注入 panic 模拟崩溃）
- 性能影响可忽略（< 5% 多余 IO）

### 负面 / 代价

- **额外磁盘空间**：staging 期间文件占双份空间（短暂）
- **跨卷复杂度**：源与仓库不同卷时 rename 会失败，必须 fallback copy + delete
- **DB 增加 status 字段**：所有查询都要加 `WHERE status='active'`，容易遗漏
  - 缓解：DB 视图 / Rust 端封装统一过滤
- **异常 cleanup 不做的话** staging 目录会累积垃圾
  - 缓解：每次启动 + 每天后台扫一次

### 风险

- staging 文件被外部工具误处理（如 Time Machine 备份）→ 可接受，仅是冗余备份
- 大文件（>1GB）staging 阶段崩溃需要再次完整复制（缓解：分块 hash + 增量 staging 是 Stage 3+ 优化）

## 何时重审

- 性能 profile 显示 staging 复制是瓶颈 → 评估同卷场景下的 reflink / clonefile（macOS APFS 支持）
- 用户报告 staging 目录无故膨胀 → 加强 cleanup 频率
- 出现"非崩溃但事务卡住"的 case → 加超时强制 rollback
- 加 Stage 3 AI 分类后引入异步流程 → 重审事务边界

## Related

- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [../modules/storage.md](../modules/storage.md)
- [../architecture/data-model.md](../architecture/data-model.md)
- [0003-source-of-truth-strategy.md](0003-source-of-truth-strategy.md)
