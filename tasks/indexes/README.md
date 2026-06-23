# AreaMatrix Task Indexes

`tasks/indexes/` 保存 lightweight task 系统的索引视角，帮助区分当前任务、closed backlog 和可转任务的遗留项。

阅读时长：约 2 分钟。

---

## 定位

本目录是任务视角索引，不是第二套 task runner。

- 当前可执行轻量任务仍在 `tasks/active/**`。
- 已完成轻量任务仍在 `tasks/done/**`。
- 候选材料仍在 `tasks/backlog/**`。
- 版本级遗留项仍在 `workflow/versions/<version>/residuals/**`。

## 索引

| 文件 | 说明 |
|---|---|
| [residuals.md](residuals.md) | 哪些 residual 可以或不可以转为 lightweight task。 |

## Related

- [tasks README](../README.md)
- [global residual ledger](../../workflow/residuals/)
- [v1-mvp residuals](../../workflow/versions/v1-mvp/residuals/)
