# 架构决策记录（ADR）

> 本目录存放 AreaMatrix 的所有重要架构决策。每条决策一个文件，记录"上下文 + 决定 + 备选 + 后果 + 何时重审"。
>
> 阅读时长：本页约 3 分钟。

---

## 什么是 ADR

[Architecture Decision Record](https://adr.github.io/) 是一种轻量级的决策记录格式。每个决策一个 markdown 文件，单调追加（已发布的不再修改，要变就发新一条 supersedes 旧的）。

为什么用 ADR：

1. **避免遗忘**：半年后还能查"为什么当时这么选"
2. **新人加入无障碍**：不用问当事人就能理解全部约束
3. **决策可见**：评审 PR 时能引用 ADR 而不是反复争论
4. **变更有迹可循**：废弃 / 取代关系清晰

---

## ADR 索引

| # | 状态 | 主题 | 文件 |
|---|---|---|---|
| 0001 | Accepted | 桌面技术栈选型 | [0001-tech-stack.md](0001-tech-stack.md) |
| 0002 | Accepted | FFI 工具选择 UniFFI | [0002-uniffi-vs-others.md](0002-uniffi-vs-others.md) |
| 0003 | Accepted | 真相源策略：Hybrid | [0003-source-of-truth-strategy.md](0003-source-of-truth-strategy.md) |
| 0004 | Accepted | 事务式存储 | [0004-transactional-storage.md](0004-transactional-storage.md) |
| 0005 | Accepted | 文件系统监听用 FSEventStream | [0005-fsevents-listener.md](0005-fsevents-listener.md) |
| 0006 | Accepted | 完整支持 iCloud Drive | [0006-icloud-support.md](0006-icloud-support.md) |
| 0007 | Accepted | README 生成粒度 | [0007-readme-granularity.md](0007-readme-granularity.md) |
| 0008 | Accepted | 命名与国际化策略 | [0008-naming-and-i18n.md](0008-naming-and-i18n.md) |
| 0009 | Accepted | 最低 macOS 版本 14 Sonoma | [0009-min-macos-version.md](0009-min-macos-version.md) |

未来新增的 ADR 编号顺延（0010、0011…）。

---

## 状态枚举

| 状态 | 含义 |
|---|---|
| Proposed | 提议中，待评审 |
| Accepted | 已采纳，当前有效 |
| Deprecated | 不再推荐，但暂未替换 |
| Superseded | 已被新 ADR 取代（标注 by ADR-NNNN） |
| Rejected | 评审后否决（保留作为历史） |

---

## 写一份新 ADR

### 何时该写

- 影响多个模块的技术选择
- 有多个合理选项需要权衡
- 决定后会影响半年以上的后续开发
- 决定的细节难以从代码看出来

### 何时不必写

- 单一模块内部实现细节
- 编码规范类（写到 [coding-standards.md](../development/coding-standards.md)）
- 临时性的实现选择（用注释即可）

### 流程

1. 复制下方模板，文件名 `NNNN-kebab-case-title.md`，编号取下一个
2. 在 PR 中提交
3. 评审通过 → 状态改 `Accepted` → 合并
4. 后续要废弃 → 写新 ADR + 在旧 ADR 顶部加 `> Superseded by [ADR-NNNN]`

---

## ADR 模板

```markdown
# ADR-NNNN: 决策标题

> 一句话决策摘要。
>
> 状态：Proposed | Accepted | Deprecated | Superseded by [ADR-NNNN] | Rejected
> 日期：YYYY-MM-DD
> 决策者：@user1 @user2
> 影响范围：core / macos-app / build / ...

## 上下文

什么背景下需要做这个决策？有什么约束？

## 决定

我们选择 XXX。

## 理由

1. ...
2. ...

## 考虑过的备选

### A. 备选名

- 优点：...
- 缺点：...
- 为什么没选：...

### B. 备选名

...

## 后果

### 正面

- ...

### 负面 / 代价

- ...

### 风险

- ...

## 何时重审

什么条件下应该重新审视这个决策？

## Related

- [其他 ADR 或 docs/]
```

---

## 常见问题

### Q: 决策已经做了但没写 ADR 怎么办

补一份 ADR。状态写 Accepted、日期写实际决策时间，作者写当时的人。比没有强。

### Q: 不同决策互相冲突

写一份新 ADR 解释关系，把旧的标 Superseded 或 Deprecated。

### Q: ADR 太多看不过来

正常项目 ADR 总数应在 10-50 之间。如果超过 50 → 大概率把"实现细节"写成了 ADR，应该挪到模块 docs。

---

## Related

- [../README.md](../README.md)
- [../architecture/overview.md](../architecture/overview.md)
- [../development/coding-standards.md](../development/coding-standards.md)
