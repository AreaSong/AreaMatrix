# Cursor Native Adapter Admission Record

## 定位

本记录是 Cursor 原生能力（rules、skills、commands、hooks、plans、canvas 面板）进入 AreaMatrix 的 [外部能力接入门禁](../../.ai-governance/workflows/external-capability-admission.md) 判定结果。它不是 live queue 材料，不由 `./task-loop` 执行。

## Admission Record

### cursor-native-adapter

- Upstream source: Cursor 官方原生能力（project rules、agent skills、commands、hooks、plans、workspace canvases），参考同机 AreaSong 仓库已验证的落地形态。
- AreaMatrix gap: Cursor 会话此前只依赖 `AGENTS.md` 注入，缺少会话引导、收口规程、计划生命周期、push 前审阅的 Cursor 侧触发器，也缺少 residual ledger 与产品能力的可视化面板。
- Dedup with: 业务语义 owner 仍是 `.agents/skills/areamatrix-*` 九个 repo-local skills；Cursor skills 只做操作规程（bootstrap / closeout / plan-sync / pre-push-review），命中业务语义时交接给对应 owner，不新增同名能力。Codex hooks 决策不变（默认不新增 `.codex/hooks.json`）。
- Local source of truth: [.ai-governance/workflows/cursor-adapter-layer.md](../../.ai-governance/workflows/cursor-adapter-layer.md)；产品与账本源事实仍是 `docs/**` 与 `workflow/residuals/**`。
- Trigger condition: 新对话、宣称完成前、不少于 3 步的任务、push / PR 前四类时机静默触发对应 skill；hooks 只在 sessionStart、stop、beforeShellExecution 三个事件运行。
- Live mainline impact: 无。不写 `workflow/versions/<version>/execution/**`、progress、queue、checkpoint、runner lock、task-loop logs；beforeShellExecution 守卫只对 live 主线命令返回 ask，不自动 allow / deny。
- User-file / privacy / remote-call impact: 无。hooks 只读仓库状态；canvas 只投影仓库内文档与账本，不触碰用户文件、`.areamatrix/`、DB、staging、FSEvents、iCloud 或远程调用。
- Verification: `./dev check governance`、`./dev check docs`、`./dev check wording`、`bash -n .cursor/hooks/*.sh`；canvas 以 Cursor 侧渲染验证。
- Owner / landing: 规则语义进 `.ai-governance/workflows/cursor-adapter-layer.md`；投影文本进 `.cursor/**`；本记录进 `tasks/backlog/**`。
- Decision: 吸收
- Evidence: `.cursor/rules/areamatrix-cursor-workflow.mdc`、`.cursor/skills/areamatrix-{session-bootstrap,closeout,plan-sync,pre-push-review}/SKILL.md`、`.cursor/commands/*.md`、`.cursor/hooks/hooks.json` 与脚本、工作区级 `canvases/areamatrix-{residuals-dashboard,capability-map}.canvas.tsx`。
