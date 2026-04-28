# Stage 1 MVP 详细任务拆解

> Stage 1 完成"拖入 → 自动归类 → 树状导航 → 详情查看"的端到端闭环。本文件是该阶段的可执行 backlog，约 5 个月、3 个迭代。
>
> 阅读时长：约 8 分钟。

---

## MVP 范围确认

### 一句话定义

**用户能在 macOS 上选择任意文件夹作为资料库；即使目录非空，也能先建立索引，再把新文件拖入 AreaMatrix，看到它被自动归类、树状展示、内容可预览、改动可追踪——全程无云依赖、关机重启数据完整。**

### 必做（Must Have）

详见 [milestones.md#stage-1-mvp](milestones.md#stage-1mvp约-5-个月) 核心交付。

### 可选（Should Have）

- 命令面板（⌘K）
- 详情面板的 markdown 预览
- 启动时的"上次未完成导入"提示

### 不做（Out of Scope）

- AI 分类
- 标签系统
- 全文搜索
- 多窗口
- 公开发布渠道

---

## 团队配置假设

| 角色 | 投入 |
|---|---|
| Tech Lead（Rust + Swift 都熟） | 1 人 100% |
| Rust 核心开发 | 0.5-1 人 |
| macOS / SwiftUI 开发 | 0.5-1 人 |
| 测试 / 文档 / 设计 | 0.5 人（兼） |

如果 1 人独立完成，时间估算 × 1.5。

---

## 迭代规划

```mermaid
flowchart LR
    M1[迭代 1<br/>2 月<br/>骨架与核心] --> M2[迭代 2<br/>2 月<br/>UI 与监听]
    M2 --> M3[迭代 3<br/>1 月<br/>稳定与发布]
```

---

## 迭代 1：骨架与核心（2 个月）

### 目标

跑通 "Rust core 完成 import_file → SQLite 持久化 → 通过 UniFFI 在 Swift 中调用并打印结果"。

### 任务拆解

#### 项目初始化（1 周）

- [ ] 创建 git repo + 仓库结构（`core/`, `apps/macos/`, `scripts/`, `docs/`）
- [ ] 配置 CI：core-ci.yml + macos-ci.yml
- [ ] 配置 Cursor rules + AGENTS.md
- [ ] 写 README + LICENSE + CONTRIBUTING

#### Rust core 基础（2 周）

- [ ] 设置 `core/Cargo.toml`，添加依赖 rusqlite / serde / uniffi / blake3 / sha2 / walkdir / thiserror
- [ ] 模块骨架：`api / db / classify / storage / sync / overview / change_log`
- [ ] 错误类型 `CoreError`（[error-codes.md](../api/error-codes.md)）
- [ ] DB schema v1 + migration 框架（[data-model.md](../architecture/data-model.md)）
- [ ] init_repo + open_repo + adopt_existing_repo 实现 + 单测
- [ ] 非空目录接管：扫描现有文件并以 `indexed` + `origin=adopted` 写入 DB
- [ ] `scan_sessions`：接管 / reindex 支持中断后继续或重跑
- [ ] `ignore.yaml`：首次扫描、reindex、tree-scan、FSEvents 共用忽略规则

#### 分类引擎（1 周）

- [ ] `classifier.yaml` 默认配置内置（10 类）
- [ ] keyword + extension 匹配
- [ ] NFKC + lowercase 归一
- [ ] 单元测试 ≥ 90% 覆盖

#### 存储 + 事务（2 周）

- [ ] sha256_file 实现
- [ ] resolve_target（冲突处理）
- [ ] import_file Move/Copy/Index 三模式
- [ ] StagingGuard + recover_on_startup
- [ ] 单元测试 ≥ 85%
- [ ] 崩溃测试（panic 注入 + 子进程 SIGKILL）

#### change_log（0.5 周）

- [ ] insert + list_changes
- [ ] detail_json 结构定义
- [ ] 测试

#### UniFFI 集成（1 周）

- [ ] `area_matrix.udl` 完整定义（[ffi-design.md](../architecture/ffi-design.md)）
- [ ] build.rs + scaffolding
- [ ] `scripts/build-core.sh` 跑通
- [ ] 在 Xcode 中能调用 `init_repo` 并验证 DB 创建

### 交付物

- [ ] core 单元测试覆盖率 ≥ 70%
- [ ] core CI 全绿
- [ ] Swift 端能调用核心 API 并验证文件导入

### Demo 验收

打开 SwiftUI 临时 Demo App → 选择一个临时目录作为 repo → 点击按钮 → 调用 `import_file("~/Desktop/test.pdf")` → DB 中出现记录、`<repo>/docs/test.pdf` 出现 → 控制台打印 FileEntry。

---

## 迭代 2：UI 与监听（2 个月）

### 目标

把核心能力包装成可用的 SwiftUI 应用，并完成 FSEvents 监听 + iCloud 兼容。

### 任务拆解

#### 主窗口骨架（1 周）

- [ ] `NavigationSplitView` 三栏：侧栏（树）/ 列表 / 详情
- [ ] 状态管理：`AppState` ObservableObject
- [ ] 启动检查：用户是否首次使用 → 引导选目录 / 接管已有目录

#### 拖拽导入（1.5 周）

- [ ] 接收 NSItemProvider 拖入
- [ ] ImportSheet：显示文件名、检测到的分类、Move/Copy/Index 选择
- [ ] 拖入目标规则：侧边栏/列表节点优先落入该目录，空白区域才自动分类
- [ ] 调用 `core.importFile`，进度反馈
- [ ] 错误处理 UI（重复 / 冲突 / 权限）

#### 树状导航（1 周）

- [ ] 调用 `core.buildTree` 拉取
- [ ] OutlineGroup 渲染
- [ ] 节点选中 → 列表过滤
- [ ] 拖到节点 = 移动到该分类

#### 文件列表（1 周）

- [ ] List + 多选
- [ ] 列：名称 / 大小 / 修改时间 / 分类 / 状态
- [ ] 排序 / 筛选
- [ ] 上下文菜单：改名 / 删除 / 在 Finder 显示 / 复制路径

#### 详情面板（1 周）

- [ ] 选中文件 → 显示 metadata
- [ ] 改动历史（调 `core.listChanges`）
- [ ] 备注编辑（调 `core.upsertNote`）
- [ ] 文件预览（QuickLook）

#### FSEvents 监听（1.5 周）

- [ ] FSWatcher actor + start/stop
- [ ] Debouncer 200ms
- [ ] InFlightTracker
- [ ] 调用 `core.syncExternalChanges` 把事件同步进 DB
- [ ] DB 变化 → UI 自动刷新（Notification / Combine）

#### iCloud 兼容（1 周）

- [ ] 检测仓库是否在 iCloud Drive
- [ ] NSFileCoordinator 包装所有 IO
- [ ] 占位符触发下载（按需）
- [ ] iCloud 错误友好提示

#### AreaMatrix 概览自动维护（0.5 周）

- [ ] 导入 / 删除 / 改名后异步触发 regenerate_overview
- [ ] `.areamatrix/generated/root.md` 与顶层节点概览维护
- [ ] 可选根目录 `AREAMATRIX.md`
- [ ] 保护已有 `README.md`：默认不读取改写、不插入标记块、不覆盖

### 交付物

- [ ] macOS app 完整跑通端到端
- [ ] 拖入 → 分类 → 导航 → 编辑 备注 → 改动 历史 全部可用
- [ ] 非空目录接管验证通过，已有文件与 README 保持原样
- [ ] iCloud 仓库验证通过
- [ ] 至少 5 个 Swift 单元测试 + 手工冒烟全过

### Demo 验收

新 Mac 上首次启动 → 选择一个已有内容的目录 → 确认接管并完成扫描 → 拖 10 个不同类型文件 → 看到自动分类 → 在 Finder 改名某文件 → UI 自动更新 → 关闭应用 → 在 Finder 添加文件 → 重启应用 → 新文件出现。

---

## 迭代 3：稳定与发布（1 个月）

### 目标

让 MVP 达到"内测 30 天不出严重问题"的水准，准备 alpha 分发。

### 任务拆解

#### 错误处理打磨（0.5 周）

- [ ] 所有 CoreError 在 UI 有对应提示
- [ ] 网络 / iCloud 错误重试 UI
- [ ] 启动 recovery 完成情况提示

#### 性能优化（1 周）

- [ ] 大量文件（1 万+）的列表 / 树渲染优化
- [ ] hash 计算异步化 + 进度
- [ ] DB query 加 EXPLAIN 验证索引使用
- [ ] Instruments profile 关键路径

#### 测试加固（1 周）

- [ ] 集成测试覆盖核心场景
- [ ] 手工冒烟清单 100% 过
- [ ] 崩溃测试至少 50 轮无丢数据
- [ ] 性能基准对照（[testing.md#性能测试](../development/testing.md)）

#### 设置面板（0.5 周）

- [ ] 修改仓库路径
- [ ] 切换 locale
- [ ] 查看 / 编辑 classifier.yaml（只读 + 跳到 Finder 编辑）
- [ ] 关于 / 版本号 / 许可证

#### 文档与发布（1 周）

- [ ] 更新 CHANGELOG
- [ ] 用户手册（首次接管目录 + Tips & Tricks）
- [ ] 内测分发说明（如何获取 / 如何反馈）
- [ ] Release 流程演练（[release.md](../development/release.md)）
- [ ] 签名 + 公证测试

### 交付物

- [ ] 0.1.0 内测版可下载（DMG，已签名 + 公证）
- [ ] 用户安装后无需任何配置即可使用
- [ ] alpha tester 名单 + 反馈渠道（GitHub Discussions）
- [ ] 所有 CHANGELOG / 版本号 / 文档同步

---

## 验收清单（最终 MVP 标准）

发布 0.1.0 前必须满足：

### 功能完整性

- [ ] 拖入单文件 → 自动归类 → 出现在列表 + 树
- [ ] 拖入文件夹 → 递归导入
- [ ] 可选择非空目录作为资料库根，并完成首次索引
- [ ] 接管已有目录不移动、不重命名、不删除、不覆盖任何用户文件
- [ ] 接管扫描可中断恢复，`origin=adopted` 可在详情中识别
- [ ] 默认 `ignore.yaml` 生效，且不默认忽略用户 `README.md`
- [ ] 拖入目标语义正确：显式节点导入不自动重分类，空白导入才自动分类
- [ ] Move / Copy / Index 三模式可选
- [ ] 重复文件给提示（Skip / Overwrite / KeepBoth）
- [ ] 改名 / 删除 / 跨分类移动可用
- [ ] 软删除 + 30 天保留
- [ ] 改动历史完整记录
- [ ] 用户备注可编辑
- [ ] FSEvents 自动同步外部变化
- [ ] iCloud 仓库可用
- [ ] `.areamatrix/generated/` 概览自动生成
- [ ] 已有 `README.md` 不被覆盖或改写

### 稳定性

- [ ] 崩溃恢复无半成品
- [ ] 不丢数据（任何场景）
- [ ] 启动时间 < 1.5s
- [ ] 100 文件批量导入 < 5s
- [ ] 内存稳定 < 200MB

### 质量

- [ ] core 加权覆盖率 ≥ 70%
- [ ] CI 全绿
- [ ] 0 P0 / P1 已知 bug
- [ ] Swift / Rust lint 0 warning
- [ ] 手工冒烟清单 100%

### 文档

- [ ] 用户手册（中英）
- [ ] 内测说明
- [ ] CHANGELOG 0.1.0 完整
- [ ] 已知问题列表

### 发布工具链

- [ ] codesign 通过
- [ ] notarize 通过
- [ ] DMG 可在干净 Mac 上首次启动成功

---

## 风险与对策

| 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|
| UniFFI 0.x 出现破坏性变更 | 中 | 中 | 锁定版本，升级前跑全量测试 |
| iCloud 行为不稳定 | 中 | 高 | 早期用真机测试，建立专项测试集 |
| FSEvents 漏事件 | 低 | 中 | 启动时全量 reindex 兜底 |
| 性能不达标 | 中 | 中 | Instruments 早期介入，避免后期重构 |
| SwiftUI macOS 14 bug | 中 | 中 | 关键场景有 AppKit fallback 通路 |
| 时间超出预算 | 高 | 中 | 砍可选范围（Should Have），保 Must |

---

## 反向追踪

每周 status report 检查：

- 上周完成了什么 ✅
- 这周计划做什么
- 阻塞 / 风险
- 是否需要调整范围

每个迭代结束做 retrospective，更新 [milestones.md](milestones.md)。

---

## Related

- [milestones.md](milestones.md)
- [../product/prd.md](../product/prd.md)
- [../product/user-stories.md](../product/user-stories.md)
- [../development/testing.md](../development/testing.md)
- [../development/release.md](../development/release.md)
- [../adr/README.md](../adr/README.md)
