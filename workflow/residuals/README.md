# AreaMatrix Residual Ledger

AreaMatrix 遗留问题账本入口：集中索引仍会影响规划、发布或协作判断的 blocker、deferred item、accepted exception、reference-only 材料和 template-only 材料。

阅读时长：约 3 分钟。

---

## 定位

`workflow/residuals/` 是索引层，不是产品源事实、不是 live queue，也不是第二套 task system。

- 产品语义仍以 `docs/` 为准。
- 发布证据仍以 `workflow/versions/<version>/evidence/` 为准。
- 版本 closeout 决策仍以 `workflow/versions/<version>/closeout/` 为准。
- 可执行任务仍必须进入 `tasks/active/**` 或经 workflow promotion 进入 `workflow/versions/<version>/execution/**`。

本目录只回答：还有哪些遗留项、它们属于哪种状态、权威来源在哪里、是否可以转成任务、关闭条件是什么。

## 当前总览

| 范围 | 状态 | 入口 | 说明 |
|---|---|---|---|
| v1-mvp release evidence | `blocked-external` | [../versions/v1-mvp/residuals/](../versions/v1-mvp/residuals/) | 正式 Stage 1 alpha 仍因 release evidence 不放行。 |
| v1-mvp checkpoint gaps | `accepted-exception` | [../versions/v1-mvp/residuals/accepted-exceptions.md](../versions/v1-mvp/residuals/accepted-exceptions.md) | 35 个历史 checkpoint gaps 已接受为 closeout exceptions，不回填历史。 |
| AreaFlow | `reference-only` | [non-current-references.md](non-current-references.md) | 历史愿景材料，不是当前产品范围或 active backlog。 |
| v-template | `template-only` | [non-current-references.md](non-current-references.md) | 模板参考实例，blocked-by-design，不是真版本未完成。 |
| closed backlog packages | `reference-only` | [../../tasks/indexes/residuals.md](../../tasks/indexes/residuals.md) | 5 个 backlog prompt package 均 closed，不是当前待执行任务。 |

机器可读索引见 [residuals.yaml](residuals.yaml)。字段含义见 [schema.md](schema.md)。

## 使用规则

1. 查询“还有什么没完成”时，先读本页，再读对应版本 residuals。
2. 更新 residual 时，先更新权威源文件，再同步本索引。
3. 不在本目录记录临时想法、未讨论需求或执行日志。
4. 不把 `reference-only`、`template-only` 或 `accepted-exception` 自动转成任务。
5. 只有 `executable_task: true` 且有明确 owner / validation / close condition 的条目，才允许人工转入 `tasks/active/**`。

## Related

- [v1-mvp residuals](../versions/v1-mvp/residuals/)
- [tasks residual index](../../tasks/indexes/residuals.md)
- [workflow versions](../versions/)
- [docs navigation](../../docs/README.md)
