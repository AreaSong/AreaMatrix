# AreaMatrix Scripts

> 本目录承载 AreaMatrix 的本地工具实现层。根目录 `dev` 和
> `task-loop` 只是薄入口，实际逻辑在这里。
>
> 阅读时长：约 2 分钟。

---

## 定位

`scripts/` 只放开发、检查、workflow、task-loop 和发布辅助工具。它不是产品语义源事实，也不承载长期架构决策。

权威来源仍按以下顺序理解：

- 产品、架构、API、测试与发布规则：`docs/`
- AI 协作规则与项目不变量：`.ai-governance/`
- 版本生命周期与历史执行证据：`workflow/`
- Codex 专用材料：`.codex/`

## 根入口关系

```text
dev        -> scripts.task_loop.console.main()
task-loop  -> scripts.task_loop.cli.main()
```

`dev` 是日常推荐入口，用于查看状态、进入控制台、调用检查、构建、workflow、tasks、backlog 和 release 工具。

`task-loop` 是 prompt runner 的直达入口，只用于已批准的 version execution queue 或 v1 历史执行队列恢复场景。

## 目录结构

```text
scripts/
├── brand/           # 品牌 SVG、数字端、原生端与印刷资产生成/校验
├── task_loop/       # Dev Console、task-loop runner、状态、锁、i18n、Git checkpoint
├── dev_tools/       # build/check/workflow/tasks/backlog/release/skills 等子命令
├── task_loop.md     # task-loop 操作手册
└── check-secrets.sh # secret scan wrapper
```

## 边界

- 不在本目录定义产品行为；产品行为先写入 `docs/`。
- 不在本目录定义 AI 协作源规则；协作规则先写入 `.ai-governance/`。
- 不在本目录创建第二套 runner、progress、queue 或 checkpoint。
- 不绕过 `workflow/` 的 discussion、promotion 和 execution gate。
- 不把 `.codex/runtime/**` 或本机日志当作长期完成证据。

## 常用入口

```bash
./dev --once
./dev check governance
./dev check skills
./dev check wording
./dev workflow status
./dev tasks status
./task-loop status
./task-loop check
python3 scripts/brand/export_assets.py --refresh
python3 scripts/brand/validate_assets.py
```

涉及真实 runner 执行前，先确认没有已有 live runner、工作区状态符合 checkpoint 要求，并遵守 `AGENTS.md`、`.ai-governance/` 和 `workflow/AGENTS.md` 的边界。

## Related

- [../AGENTS.md](../AGENTS.md)
- [../.ai-governance/README.md](../.ai-governance/README.md)
- [../.codex/README.md](../.codex/README.md)
- [../workflow/AGENTS.md](../workflow/AGENTS.md)
- [task_loop.md](task_loop.md)
