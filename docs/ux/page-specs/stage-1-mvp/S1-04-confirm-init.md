# S1-04 confirm-init - 初始化确认

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-04
> 页面类型：首次启动
> 页面文件：`S1-04-confirm-init.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 首次启动向导
- **建议目录**：`apps/macos/AreaMatrix/Features/Onboarding/`
- **建议组件**：`ConfirmInitStepView`、`InitPlanSummaryView`
- **实现说明**：这是真正写入前最后确认页。点击主按钮后才调用 Core 初始化或接管。

## 页面背景

路径已经校验通过。用户需要最后确认 AreaMatrix 将新建资料库，或接管已有目录。

## 页面功能

- 区分空目录新建和非空目录接管。
- 列出将创建/执行的内容。
- 列出不会执行的危险动作。
- 提供开始初始化/接管按钮。

## 布局与内容

顶部路径信息框显示 repoPath。

空目录版本标题：`将创建新的 AreaMatrix 资料库`

将创建列表：

- `docs/`
- `code/`
- `design/`
- `finance/`
- `media/`
- `inbox/`
- `.areamatrix/index.db`
- `.areamatrix/ignore.yaml`
- `.areamatrix/generated/`
- `.areamatrix/staging/`

非空目录版本标题：`将接管已有目录`

将执行列表：

- 创建 `.areamatrix/` 内部目录。
- 创建 `.areamatrix/ignore.yaml`。
- 创建本地索引数据库。
- 扫描现有文件和文件夹。
- 将已有文件标记为 adopted / indexed。
- 生成 `.areamatrix/generated/root.md`。

不会执行列表必须醒目：

- 不移动已有文件。
- 不重命名已有文件。
- 不删除已有文件。
- 不覆盖已有 `README.md`。
- 不修改已有项目目录结构。

底部按钮：`Back`、`Create Repository` 或 `Adopt Folder`、`Cancel Setup`。

## 状态与规则

- 默认状态：根据 `adopt=false/true` 显示空目录新建或非空目录接管版本；主按钮可用。
- 路径校验结果缺失、过期或 repo fingerprint 变化时，禁用主按钮并要求返回校验页。
- 如果上一步检查结果过期，点击主按钮应先重新校验或返回校验页。
- iCloud 路径保留黄色提示，不阻止已确认用户继续。
- `Cancel Setup` 退出向导，下次启动可继续。
- 点击主按钮前不得创建、移动、重命名、删除或覆盖任何文件。
- 如果 repoPath 已变为完整 AreaMatrix repo，返回 `S1-03 validate-path` 的已存在 repo 分支，不继续初始化。

## 交互

- `Create Repository` 进入 `S1-05 initializing`，执行空目录初始化。
- `Adopt Folder` 进入 `S1-05 initializing`，执行接管扫描。
- `Back` 返回 `S1-03 validate-path`。
- `Cancel Setup` 弹确认：`退出设置？AreaMatrix 不会写入资料库，下次启动可重新选择。`
- 确认 Cancel 后退出向导，不写 repo 配置；下次启动从 `S1-01 welcome` 或最近未完成的安全 step 恢复。

## 数据与依赖

- 上一步 path validation result。
- init options，包括 repoPath、overview policy、是否 adopt。
- Core `init_repo` / `adopt_existing_repo`。
- validation timestamp / repo fingerprint，用于判断确认页是否过期。

## 验收清单

- 空目录和非空目录文案不同。
- 非空目录确认页必须出现“不覆盖 README”。
- 点击主按钮前没有最终写入。
- 取消后用户文件不变。
- Cancel Setup 有确认，不会留下 repo 配置或半初始化状态。

## 来源

- `docs/ux/first-launch.md#4-confirminit初始化确认`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-01 welcome](S1-01-welcome.md)
- [S1-03 validate-path](S1-03-validate-path.md)
- [S1-05 initializing](S1-05-initializing.md)
