# AreaMatrix 文档

> 本目录保存 AreaMatrix 需要长期维护的产品、用户、UX、架构、API 和开发事实。
>
> 阅读时长：约 5 分钟。

功能、界面、API、配置或安全边界发生变化时，对应长期文档必须在同一变更中更新。历史计划、任务、执行证据、收口决策和分发记录从 [workflow versions](../workflow/versions/README.md) 查阅；它们不参与当前产品导航。未实现且不属于正式产品的方向保存在未来 workflow，不得写成可用能力。

## 治理

- [企业工作流治理基线](governance/enterprise-workflow-baseline.md)
- [项目章程](governance/project-charter.md)
- [治理登记册](governance/governance-register.yaml)
- [运行与能力生命周期](governance/operations-lifecycle.md)

## 安全

- [威胁模型](security/threat-model.md)

## 开始使用

- [用户指南](user-guide/README.md)
- [安装与首次运行](user-guide/getting-started.md)
- [创建和打开资料库](user-guide/repositories.md)
- [接管已有目录](user-guide/adopting-existing-folders.md)
- [导入文件](user-guide/importing-files.md)
- [整理文件](user-guide/organizing-files.md)
- [搜索、标签与智能列表](user-guide/search-tags-and-smart-lists.md)
- [AI 功能与隐私](user-guide/ai-features-and-privacy.md)
- [设置](user-guide/settings.md)
- [冲突与恢复](user-guide/conflicts-and-recovery.md)
- [常见问题与排障](user-guide/troubleshooting.md)

## 产品

- [产品概览](product/overview.md)
- [产品能力](product/capabilities.md)
- [当前实现清单](product/current-implementation-inventory.md)
- [产品界面地图](product/product-surfaces.md)
- [用户工作流](product/workflows.md)
- [隐私与数据处理](product/privacy.md)
- [产品需求](product/prd.md)
- [用户故事](product/user-stories.md)
- [术语表](product/glossary.md)
- [能力方向](product/capability-direction.md)

## UX

- [UX 总览](ux/README.md)
- [首次启动](ux/first-launch.md)
- [拖拽与导入](ux/drag-import-flow.md)
- [主界面状态](ux/ui-states.md)
- [分类器调教](ux/classifier-calibration.md)
- [去重与冲突](ux/dedup-conflict.md)
- [搜索](ux/search.md)
- [标签、批量、Undo 与命令面板](ux/deep-features.md)
- [设置](ux/settings-panel.md)
- [错误信息](ux/error-messages.md)
- [品牌资产](ux/brand-assets.md)
- [竞品与定位](ux/competitive-analysis.md)

## 架构

- [架构总览](architecture/overview.md)
- [技术栈](architecture/tech-stack.md)
- [分层设计](architecture/layered-design.md)
- [macOS 前端架构](architecture/macos-frontend-architecture.md)
- [Core 内部架构](architecture/core-internal-architecture.md)
- [真相源策略](architecture/source-of-truth.md)
- [接管已有目录](architecture/adopt-existing-folders.md)
- [事务式导入](architecture/transactional-import.md)
- [数据模型](architecture/data-model.md)
- [FFI 设计](architecture/ffi-design.md)
- [文件监听与 iCloud](architecture/fs-watcher.md)
- [并发模型](architecture/concurrency.md)
- [数据库迁移](architecture/migration.md)

## 模块

- [存储](modules/storage.md)
- [分类](modules/classify.md)
- [概览生成](modules/overview-gen.md)
- [目录扫描](modules/tree-scan.md)
- [改动日志](modules/change-log.md)
- [资料库初始化](modules/repo-init.md)
- [导入冲突批处理](modules/import-conflict-batch.md)
- [元数据修复](modules/repair.md)
- [资料库扫描](modules/repo-scan.md)
- [缺失文件恢复](modules/missing-file-recovery.md)
- [批量删除](modules/batch-delete.md)
- [同步冲突解决](modules/sync-conflict-resolve.md)
- [语义搜索](modules/semantic-search.md)

## API 与配置

- [Core API](api/core-api.md)
- [错误码](api/error-codes.md)
- [classifier.yaml](api/classifier-yaml.md)
- [UniFFI Swift 集成](api/uniffi-recipes.md)

## 开发与运维

- [开发环境](development/setup.md)
- [构建与运行](development/build.md)
- [编码规范](development/coding-standards.md)
- [Git 工作流](development/git-workflow.md)
- [测试策略](development/testing.md)
- [错误恢复矩阵](development/error-recovery-matrix.md)
- [依赖政策](development/dependency-policy.md)
- [CI 治理](development/ci-governance.md)
- [发布流程](development/release.md)
- [性能工程](development/performance.md)
- [恢复说明](development/recovery.md)
- [可观测性](development/observability.md)
- [开发排障](development/troubleshooting.md)
- [Secret Scan Runbook](development/secret-scan-runbook.md)

## 决策与方向

- [ADR 索引](adr/README.md)
- [长期能力方向](product/capability-direction.md)
- [Roadmap 导航](roadmap/README.md)

历史版本、source docs、执行证据和 closeout 从 [workflow versions](../workflow/versions/README.md) 查阅。未关闭的外部证据、接受的例外和历史引用从 [residual ledger](../workflow/residuals/README.md) 查阅。两者都不替代本目录的产品事实。

## 文档规则

1. `README.md` 和 `README.zh-CN.md` 只做产品介绍、最短上手和导航。
2. `docs/**` 解释产品如何使用、系统如何工作以及长期不变量。
3. ADR 解释重要决策为什么成立，不充当当前用户指南。
4. 历史状态和未来方向不能混入当前能力说明。
5. 用户文件、DB、导入、恢复、iCloud 和远程 AI 文档必须写清副作用与取消或恢复路径。
6. 每篇 Markdown 使用一级标题、摘要、正文和 `Related`，代码块注明语言。
7. 文档变更后检查相对链接、导航完整性和长期措辞。
8. 长期治理文档的 owner、状态和复审条件登记在 `governance/governance-register.yaml`；新建或实质修改时再逐步加入内嵌元数据。

## Related

- [项目 README](../README.zh-CN.md)
- [产品概览](product/overview.md)
- [用户指南](user-guide/README.md)
- [架构总览](architecture/overview.md)
- [开发环境](development/setup.md)
