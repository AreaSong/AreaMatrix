# Vibe Professional Skill Trigger Matrix

> 本文件把 Vibe-Skills 专业领域能力从“暂缓”收敛为可执行判断。它是 AreaMatrix 的候选参考矩阵，不是安装清单、启用清单或 runtime 入口。

## 基线结论

- 当前 AreaMatrix 产品主线默认不需要 Vibe 专业领域 skills。
- 本矩阵只允许未来按具体任务触发单项参考；不安装、不复制、不启用 `/Users/as/Ai-Project/project/Vibe-Skills/**`。
- `vibe`、VCO runtime、`.vibeskills/**`、memory plane、specialist router 和 Vibe 全量 skill catalog 不进入 AreaMatrix 主线。
- 未来任何单项接入必须先走 [External Capability Admission Gate](../../.ai-governance/workflows/external-capability-admission.md)，并形成可复查 admission record。
- 接入优先吸收方法、检查表、术语或一次性参考，不复制外部 runtime、目录布局、执行器、状态面或同义 repo-local skill。
- Owner 默认是 `areamatrix-workflow-planning`。领域落点按下表转给现有 AreaMatrix owner，不新增大批同义 skill。

## Source Of Truth

- Current screening: [vibe-skills-capability-screening.md](vibe-skills-capability-screening.md)
- External admission: [external-capability-admission.md](../../.ai-governance/workflows/external-capability-admission.md)
- Backlog task: [codex-native-area-vibe-optimization.md](../../tasks/backlog/codex-native-area-vibe-optimization.md)
- Vibe reference only: `/Users/as/Ai-Project/project/Vibe-Skills/README.zh.md`
- Vibe runtime reference only: `/Users/as/Ai-Project/project/Vibe-Skills/SKILL.md`

## Decision Vocabulary

| Decision | 含义 | AreaMatrix 行为 |
|---|---|---|
| `trigger-based reference` | 有明确未来使用场景，但只能由具体任务触发 | 先写 admission record；只参考方法或局部 checklist；优先落到现有 owner |
| `defer` | 有潜在价值，但当前没有产品缺口、证据或安全边界 | 只保留 backlog / reference 记录；不启用、不路由、不新增 skill |
| `reject` | 与当前主线冲突、风险过高、重复率过高或无产品收益 | 不采用；除非未来产品 source of truth 发生明确变化并重新 admission |

## Trigger Matrix

| 专业类别 | Vibe 代表项，仅作参考 | Decision | Trigger | Do-not-adopt | AreaMatrix owner | Validation / admission evidence |
|---|---|---|---|---|---|---|
| 数据分析 / 统计 | `statistical-analysis`, `performing-regression-analysis`, `exploratory-data-analysis`, `detecting-data-anomalies` | `trigger-based reference` | 任务明确要求分析测试、benchmark、导入质量、索引质量或产品内本地数据统计，并给出数据来源、输出格式和验收口径 | 不用于普通 lint/test 选择；不上传用户文件；不引入 notebook / data dump 作为 live state；不创建默认数据分析 skill | `areamatrix-validation-driver`; 数据涉及用户文件时加 `areamatrix-file-safety`; 文档口径由 `areamatrix-doc-sync` | Admission record 说明数据范围、隐私边界、可复现命令、统计口径和阈值；运行相应脚本 / 测试 / benchmark；路径级 diff check |
| ML / AI 工程 | `senior-ml-engineer`, `scikit-learn`, `ml-pipeline-workflow`, `pytorch-lightning`, `transformers` | `trigger-based reference` | 已批准产品任务需要训练、推理、embedding、分类器、模型 artifact 策略或模型集成方案，且现有 AreaMatrix docs / owner 不足以覆盖 | 不为普通 prompt、文档或规则任务启用；不引入 Vibe ML runtime；不让远程 AI 默认读取用户内容；不保存未经批准模型产物 | `areamatrix-workflow-planning`; `areamatrix-validation-driver`; 涉及远程 AI / 用户数据时加 `areamatrix-file-safety` 和 `areamatrix-enterprise-governance` | Admission record 说明模型用途、数据来源、隐私 / 远程调用、license、资源约束、eval 数据集和回滚；补充模型测试、质量阈值和安全审查 |
| 模型解释 / 评估 | `evaluating-machine-learning-models`, `explaining-machine-learning-models`, `shap`, `evals-context`, `ml-data-leakage-guard` | `trigger-based reference` | AI / ML 功能已经进入已批准任务，且需要解释性、leakage 检查、模型质量门槛、ranking / classifier 评估或 regression guard | 不替代普通 code review、security review 或 prompt doctor；不把 synthetic pass 当验收；不留下未追踪 eval 产物 | `areamatrix-validation-driver`; AI 风险由 `areamatrix-enterprise-governance`; 产品指标口径由 `areamatrix-doc-sync` | Admission record 说明 eval target、数据 provenance、指标阈值、失败处理、leakage / privacy 检查；验证必须可重复并回指任务验收 |
| 科研 / 文献 / 学术写作 | `literature-review`, `research-lookup`, `scientific-writing`, `citation-management`, `scholarly-publishing` | `defer` | 用户明确要求文献综述、学术写作、研究证据整理，或未来产品文档明确需要外部研究背景 | 不让论文、博客或 Vibe research skill 成为 AreaMatrix 产品 source of truth；不在 task-loop 内做泛化文献搜索；不生成无来源引用 | `areamatrix-doc-sync`; `areamatrix-workflow-planning` | Admission record 说明研究问题、来源类型、引用时间范围、输出落点；需要最新事实时重新查证；产品语义仍必须落回 `docs/**` |
| 生命科学 / 生信 | `biopython`, `scanpy`, `scikit-bio`, `pubmed-database`, `uniprot-database` | `defer` | 只有用户明确给出非临床、非产品主线的研究数据处理任务，或未来 AreaMatrix 明确支持该类资料工作流时才记录 trigger candidate | 不默认处理用户生物数据；不把领域数据库接入产品主线；不对结果做专家结论；不绕过用户文件、隐私和 license 边界 | `areamatrix-file-safety`; `areamatrix-validation-driver`; `areamatrix-doc-sync` | Admission record 说明数据所有权、敏感性、license、工具链、离线 / 远程边界和可复现命令；必要时要求人工领域复核 |
| 医学 / 临床决策 | `clinical-decision-support`, `clinical-reports`, `treatment-plans`, `pyhealth` | `reject` | 无默认触发。仅可在用户明确要求非诊疗性资料整理时重新走高风险 admission，并标记不提供医疗建议 | 不做诊断、治疗、用药、临床建议或医疗器械合规判断；不把医疗 skill 接入 AreaMatrix 产品任务；不处理真实患者数据 | `areamatrix-enterprise-governance`; `areamatrix-file-safety` | 默认 blocked。任何重新评估都必须先说明法律、隐私、人工专家、数据处理和回滚边界；没有这些证据不得接入 |
| 数学 / 科学计算 / 仿真 | `sympy`, `math-tools`, `pymc-bayesian-modeling`, `pymoo`, `simpy`, `fluidsim`, `matlab` | `trigger-based reference` | 已批准任务需要算法推导、优化、概率模型、仿真、数值稳定性或可复现计算证明 | 不把 Python / notebook 例子直接当 Rust core 设计；不引入长时计算或外部工具链作为默认门禁；不覆盖 `docs/architecture/**` | `areamatrix-workflow-planning`; `areamatrix-validation-driver` | Admission record 说明公式来源、算法选择、输入输出、数值误差、性能边界和 Rust / Swift 落点；补充 unit test、property test 或 benchmark |
| 可视化 / 图表 / 信息图 | `plotly`, `matplotlib`, `seaborn`, `datavis`, `creating-data-visualizations`, `infographics`, `scientific-visualization` | `trigger-based reference` | 任务明确要求生成验证图表、路线图图形、benchmark 可视化、报告图或 UI 说明图 | 不用视觉资产替代产品 docs；不把生成图当 source of truth；不引入 Vibe 图表 skill 到默认工作流；不生成低价值装饰图 | `areamatrix-doc-sync`; `areamatrix-validation-driver`; UI 说明由 `areamatrix-workflow-planning` | Admission record 说明数据来源、图表目的、可访问性、输出路径和刷新方式；图表必须可复现并与文本证据一致 |
| 文档格式处理 | `document-skills`, `docx`, `pdf`, `pptx`, `spreadsheet`, `markitdown`, `docx-comment-reply` | `trigger-based reference` | 用户明确要求处理 workspace 内 `.docx` / `.pdf` / `.pptx` / `.xlsx`，或未来产品任务需要验证文档导入 / 解析能力 | 不安装 Vibe document skills；优先使用当前 Codex Documents / Spreadsheets / Presentations 插件或 repo 内解析器；不覆盖用户原文件；不把二进制样例写进 live queue | `areamatrix-doc-sync`; `areamatrix-validation-driver`; 触碰用户文件时加 `areamatrix-file-safety` | Admission record 说明文件来源、是否用户文件、读写边界、输出路径和渲染 / 打开验证；必须有不覆盖原件证据 |
| 金融 / 外部数据源 | `alpha-vantage`, `fred-economic-data`, `edgartools`, `usfiscaldata`, `market-research-reports`, `datacommons-client` | `reject` | 当前 AreaMatrix 产品主线无金融、交易、市场数据或外部数据源需求；未来若产品 docs 明确新增只读 connector，重新 admission | 不提供投资、交易、估值或合规建议；不引入 API key、远程数据源或抓取任务；不让外部数据源进入默认索引 / task-loop | `areamatrix-enterprise-governance`; `areamatrix-file-safety`; `areamatrix-doc-sync` | 默认 blocked。重新评估需证明产品 source of truth、凭证处理、license / terms、隐私、缓存、离线失败和验证策略 |
| 数据库专项 | `geo-database`, `openalex-database`, `clinicaltrials-database`, `metabolomics-workbench-database`, `lamindb` | `defer` | 只有当 DB schema、migration、index、metadata store 或专业数据库连接成为已批准任务 blocker 时记录 trigger candidate | 不用 Vibe database skill 执行 AreaMatrix migration；不绕过 Core API / UDL / migration docs；不接入外部专业数据库为默认产品能力 | `areamatrix-file-safety`; `areamatrix-validation-driver`; `areamatrix-doc-sync` | Admission record 说明本地 DB 影响、migration / rollback、数据 ownership、fixture 和验证命令；按 DB 高风险边界先确认 |
| 设计 / 创作 / 多媒体 | `ux-researcher-designer`, `figma-implement-design`, `generate-image`, `imagegen`, `video-studio`, `transcribe`, `speech`, `algorithmic-art` | `trigger-based reference` | 已批准 UI / UX、品牌素材、截图、音视频转录或演示资产任务明确需要专业参考，且不会替代 AreaMatrix 产品 docs | 不让 Vibe 设计 / 多媒体 skill 改写 `docs/ux/**` 或产品语义；不默认生成产品资产；不处理真实用户音视频或远程上传内容；不启用 media runtime | `areamatrix-workflow-planning`; `areamatrix-doc-sync`; 触碰用户媒体 / 远程服务时加 `areamatrix-file-safety` | Admission record 说明素材来源、版权、隐私、输出路径、可访问性和 UI 证据；涉及前端 / app 需补截图或 UI smoke 验证 |

## Admission Requirements

未来任何 `trigger-based reference` 或 `defer` 项转为实际接入前，必须先写明：

- AreaMatrix gap: 解决哪个当前 docs、workflow、skill、validation 或 task-loop 缺口。
- Dedup with: 为什么现有 repo-local owner 不足，或如何只补现有 owner。
- Local source of truth: 产品语义仍落在 `docs/**`，治理语义仍落在 `.ai-governance/**`。
- Trigger condition: 精确关键词、任务类型、风险等级和 explicit-only 边界。
- Live mainline impact: 默认无。不得写 `tasks/prompts/**`、progress、logs、run summaries、runner lock、checkpoint 或 promotion state。
- User-file / privacy / remote-call impact: 命中用户文件、隐私、远程 AI、凭证、DB、staging、FSEvents 或 iCloud 时，先转 `areamatrix-file-safety`。
- Verification: 至少运行本文件底部最小验证，并按实际影响面补充 Rust、Swift、docs、workflow 或 UI 检查。
- Owner / landing: 优先落到既有 AreaMatrix owner；若只是一次性参考，记录在 `.codex/references/**` 或 `tasks/backlog/**`。

## Landing Rules

- docs / planning: `areamatrix-doc-sync` 与 `areamatrix-workflow-planning`。
- validation / testing / eval: `areamatrix-validation-driver`。
- review / security / dependency / CI / compliance: `areamatrix-enterprise-governance`。
- user file risk / DB / staging / remote calls / privacy: `areamatrix-file-safety`。
- 专业能力默认作为一次性参考或方法吸收；除非用户明确批准并且 admission record 证明有真实剩余价值，不创建新的 repo-local skill。

## Current Product Blocker Scan

本任务读取的 AreaMatrix 源事实和 backlog 中没有发现某个 Vibe 专业领域已经成为当前产品任务 blocker。若后续出现真实 blocker，只记录为 trigger candidate，并在独立任务中走 external capability admission gate；本矩阵本身不授权接入。

## Rollback

本文件只是参考矩阵。若判断过宽，可删除或收紧本文件与 backlog 记录，不涉及 runtime 回滚、不涉及 Vibe-Skills 源目录、不影响 `tasks/prompts/**` live queue。

## Minimal Validation

修改本矩阵或相关 backlog / reference 后至少运行：

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```
