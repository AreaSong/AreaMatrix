# ADR-0003: 真相源策略——Hybrid（DB + FS 混合）

> DB 是元数据真相源、文件系统是文件内容真相源；冲突时 FSEvents 同步，DB 跟随 FS。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：core/storage / core/sync / db
> 关联 ADR：[0004 事务式存储](0004-transactional-storage.md)、[0005 FSEvents](0005-fsevents-listener.md)、[0006 iCloud](0006-icloud-support.md)

## 上下文

AreaMatrix 同时维护：

- **SQLite DB**（`~/AreaMatrix/.areamatrix/index.db`）：files 表、change_log、tags 等
- **真实文件系统**（`~/AreaMatrix/<category>/<filename>`）：用户实际文件

二者可能不一致，例如：

1. 用户在 Finder 直接改名 / 删除 / 移动 → DB 不知道
2. 用户在 iCloud 网页端编辑 → 通过 iCloud 同步下来时本地 FS 变了，DB 不知道
3. 用户跨机器同步（iCloud / Dropbox）→ 收到的文件 DB 没有
4. 应用崩溃 → DB 已写但 FS 操作未完成（或反之）

需要明确"哪边是真相"，以及发现冲突时如何解决。

## 决定

采用 **Hybrid（混合真相源）**：

| 维度 | 真相源 |
|---|---|
| 文件是否存在、内容是什么 | **文件系统**（FS） |
| 文件的元数据（分类、标签、备注、改动历史、hash） | **数据库**（DB） |
| 冲突时同步方向 | **FS → DB**（FSEvents 驱动） |

操作原则：

- 应用内操作（导入 / 改名 / 删除）走"先 FS 后 DB"的事务（[ADR-0004](0004-transactional-storage.md)）
- 外部 FS 变化（Finder / iCloud / Dropbox）由 FSEventStream 监听（[ADR-0005](0005-fsevents-listener.md)），同步更新 DB
- DB 中孤儿记录（FS 文件已不存在）→ 软删除并打 `deleted_at`
- FS 中 DB 不知道的文件 → 自动 INSERT 并通过分类引擎归位

## 理由

1. **符合用户直觉**：用户认为"文件就是文件"，删了就是没了，不会接受"DB 还存着"
2. **支持外部工具**：Finder / iCloud / git / Dropbox 等都直接动 FS，不动 DB；DB 跟随 FS 才能兼容
3. **DB 持有不可见信息**：分类、标签、改动历史这些 FS 上不存在，所以 DB 仍是必要的
4. **事故恢复简单**：DB 损坏时，从 FS 重建（reindex）即可；FS 损坏（误删）时元数据还在 DB，可恢复部分上下文
5. **防止双向同步陷阱**：双向同步会陷入循环，单向（FS → DB）逻辑清晰

## 考虑过的备选

### A. DB 主导，FS 跟随

DB 是绝对真相，FS 由 DB 同步生成。

- 优点：内部一致性最强、事务化最简单
- 缺点：
  - 用户在 Finder 删除文件 → 应用看到后会"恢复"它（用户视角是 bug）
  - 不兼容 iCloud / Dropbox / git 等外部工具
  - 不符合"本地优先 + 用户拥有数据"的产品定位
- **为什么没选**：违反产品哲学

### B. FS 唯一真相，无 DB

不要 DB，元数据写到伴生 `.md` 或扩展属性。

- 优点：完全开放、用户可读、最简单
- 缺点：
  - 改动历史 / 跨文件查询无法实现（要 grep 几万个文件）
  - 性能差，每次启动重新扫描
  - 标签 / 分类规则等无处存
- **为什么没选**：MVP 的核心功能（树状图、改动历史、查询）严重依赖 DB

### C. 完全双向同步

DB ↔ FS 双向写、双向监听。

- 优点：理论上可以"哪边改都行"
- 缺点：
  - 容易死循环（DB 改 → 写 FS → FSEvents 触发 → 又改 DB）
  - 冲突解决（同时改）极复杂
  - 多机同步场景下要 vector clock 之类的机制
- **为什么没选**：复杂度暴涨，2-3 人团队 hold 不住

### D. 严格 Lock 模式

应用打开时锁住整个仓库目录，外部不能改。

- 优点：消除冲突源
- 缺点：
  - macOS 没有可靠的目录锁
  - 用户体验差（应用关闭才能用 Finder 操作）
  - 与 iCloud / Dropbox 完全不兼容
- **为什么没选**：体验差且技术上做不到

## 后果

### 正面

- 用户用 Finder 自由操作，应用自动适配
- 与 iCloud / Dropbox / git 等外部工具天然兼容
- DB 损坏可从 FS 重建，灾难恢复路径清晰
- 代码逻辑简单：单向同步无死循环风险

### 负面 / 代价

- **DB 始终是"近似真相"**：可能滞后于 FS（FSEvents 有 < 1 秒延迟）
- **依赖 FSEvents 可靠性**：FSEvents 偶发漏事件需要 reindex 兜底
- **In-flight 过滤复杂**：应用自己改 FS 时要避免 FSEvents 反馈给自己造成循环（[InFlightTracker](../architecture/fs-watcher.md)）
- **元数据可能丢失**：用户在 Finder 把文件移到仓库外 → DB 中删除并丢失分类/标签/历史
  - 缓解：删除走软删除，30 天保留期
  - 缓解：Stage 2 提供"找回"功能

### 风险

- iCloud 占位符文件场景下 FSEvents 行为复杂（缓解：[ADR-0006](0006-icloud-support.md) 处理）
- 大量外部变更（一次性收到 1000 文件同步）时同步延迟（缓解：批量处理 + 进度提示）
- 跨机器多副本时 hash 冲突（缓解：保留两份，标 conflict 状态）

## 何时重审

- 用户反馈"在 Finder 删了文件没有立刻在应用里消失"成为高频投诉 → 评估更激进的轮询补充
- 跨机器同步出现 conflict 比例 > 5% → 引入 conflict resolution UI
- 元数据丢失成为产品差评的主要原因 → 评估扩展属性 / 伴生文件存储元数据
- 性能 profile 显示同步是瓶颈 → 评估增量 reindex / 跳过未变文件

## Related

- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../modules/storage.md](../modules/storage.md)
- [0004-transactional-storage.md](0004-transactional-storage.md)
- [0005-fsevents-listener.md](0005-fsevents-listener.md)
- [0006-icloud-support.md](0006-icloud-support.md)
