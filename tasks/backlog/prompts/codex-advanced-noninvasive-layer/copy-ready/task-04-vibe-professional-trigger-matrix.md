# Copy-ready: Vibe Professional Skill Trigger Matrix

你在 `.` 工作。本任务补 Vibe-Skills 专业领域 skill 白名单与触发矩阵，不安装、不启用、不复制全量仓库。

## 目标

把 “Vibe 专业领域 skills 暂缓” 收敛为可执行判断：

- 哪些专业 skill 类别可能未来有用。
- 哪些类别对 AreaMatrix 当前产品任务无直接收益。
- 每类触发条件是什么。
- 接入前需要什么 admission gate 证据。
- 接入后落到哪个 AreaMatrix repo-local owner，还是只作为一次性参考。

## 非目标

- 不安装 Vibe-Skills。
- 不复制 Vibe-Skills 内容。
- 不创建大量 AreaMatrix 同义 skill。
- 不启用 Vibe runtime、VCO、`.vibeskills/**`、memory plane、specialist router。
- 不修改 `tasks/prompts/**`。

## Source of Truth

- Current screening: `.codex/references/vibe-skills-capability-screening.md`
- External admission: `.ai-governance/workflows/external-capability-admission.md`
- Backlog task: `tasks/backlog/codex-native-area-vibe-optimization.md`
- Vibe source for reference only: `../Vibe-Skills/README.zh.md`, `../Vibe-Skills/SKILL.md`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Supporting owners by domain:
  - docs / planning: `areamatrix-doc-sync`, `areamatrix-workflow-planning`
  - validation / testing: `areamatrix-validation-driver`
  - review / security: `areamatrix-enterprise-governance`
  - user file risk: `areamatrix-file-safety`
- Landing: `.codex/references/vibe-skills-capability-screening.md` or a new concise professional trigger matrix under `.codex/references/**`
- Backlog landing: `tasks/backlog/**`

## 先读

1. `AGENTS.md`
2. `.codex/references/vibe-skills-capability-screening.md`
3. `.ai-governance/workflows/external-capability-admission.md`
4. `tasks/backlog/codex-native-area-vibe-optimization.md`
5. `tasks/backlog/prompts/vibe-skills-absorption/README.md`
6. `../Vibe-Skills/README.zh.md` if present
7. `../Vibe-Skills/SKILL.md` if present

## 允许修改

- `.codex/references/**`
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- `../Vibe-Skills/**`
- `.agents/skills/**` unless explicitly adding a symlink for an approved AreaMatrix repo-local skill, which this task should not need

## 执行要求

1. 建立专业 skill 触发矩阵，至少覆盖：
   - 数据分析 / 统计
   - ML / AI 工程
   - 模型解释 / 评估
   - 科研 / 文献 / 学术写作
   - 生命科学 / 生信 / 医学
   - 数学 / 科学计算 / 仿真
   - 可视化 / 图表 / 信息图
   - 文档格式处理
   - 金融 / 数据源 / 数据库
   - 设计 / 创作 / 多媒体
2. 每类给出 decision：trigger-based reference、defer、reject。
3. 每类给出 trigger、do-not-adopt、AreaMatrix owner、validation。
4. 明确当前 AreaMatrix 产品主线默认不需要这些专业 skill。
5. 明确未来单项接入必须经 external capability admission gate，且优先吸收方法，不复制 runtime。

## Rollback / Blocked

- 若需要安装 Vibe-Skills 才能完成矩阵，停止并标记 blocked。
- 若发现某专业领域已经成为当前产品任务 blocker，记录为 trigger candidate，但不在本任务接入。
- 若矩阵导致新增大量同义 skill，停止并收敛到 owner / reference。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```

汇报时说明每类专业 skill 的判断、触发条件、owner、为什么不全量接入和未触碰 `tasks/prompts/**`。
