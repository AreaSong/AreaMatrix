# S1-26 settings-general - 通用设置

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-26
> 页面类型：设置
> 页面文件：`S1-26-settings-general.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 设置窗口
- **建议目录**：`apps/macos/AreaMatrix/Features/Settings/`
- **建议组件**：`SettingsView`、`GeneralSettingsPane`
- **实现说明**：设置只影响之后的默认行为，不回溯修改已有文件。

## 页面背景

用户需要配置导入默认模式、概览输出、语言和外观。默认值应安全且适合新用户。

入口：Settings > General。
退出：关闭 Settings、切换到其他设置 tab、打开 ignore.yaml、确认或取消风险弹窗；若概览输出保存失败，保留在本页并显示可恢复错误。

## 页面功能

- 配置默认存储模式。
- 配置资料库概览输出位置。
- 配置根目录 `AREAMATRIX.md` 输出确认。
- 配置语言和外观。
- 打开 ignore.yaml。

## 布局与内容

左侧 Settings tab 选中 `通用`。

默认存储模式：

- Copy（推荐，默认）
- Move
- Index-only

说明：`导入时仍可在 ImportSheet 临时更改。`

资料库概览：

- `仅保存在 .areamatrix/generated/`
- `同时在根目录生成 AREAMATRIX.md`

说明：`AreaMatrix 永远不会覆盖已有 README.md。`

选择 `同时在根目录生成 AREAMATRIX.md` 时的确认 sheet：

- 标题：`Enable root AREAMATRIX.md?`
- 说明：`AreaMatrix will continue writing generated overviews to .areamatrix/generated/. If AREAMATRIX.md already exists, AreaMatrix will only update its own managed block after you confirm. README.md is never used as an automatic output target.`
- 文件不存在：显示 `A new AREAMATRIX.md will be created at the repository root.`
- 文件已存在且有 AreaMatrix 标记块：显示 `Only the AreaMatrix managed block will be updated.`
- 文件已存在但没有 AreaMatrix 标记块：显示 `AreaMatrix will append a clearly marked managed block to AREAMATRIX.md. Existing content will remain unchanged.`
- 按钮：`Cancel`、主按钮 `Enable root overview`。

忽略规则：按钮 `Open ignore.yaml`。

语言：system / zh-CN / en。

外观：system。Stage 1 只跟随系统外观，不要求深色模式单独打磨；light / dark 可作为未来阶段设置占位但不得影响 Stage 1 验收。

## 状态与规则

- 设置 Move 为默认：弹确认，说明源文件会从原位置消失。
- 设置 Index-only 为默认：弹确认，说明源文件移动会导致缺失。
- 选择根目录 `AREAMATRIX.md` 必须先弹确认 sheet；取消后 radio 回到 `仅保存在 .areamatrix/generated/`。
- `AREAMATRIX.md` 已存在且没有 AreaMatrix 标记块时，只允许追加明确标记的托管段，不覆盖、不重排、不删除已有内容。
- `AREAMATRIX.md` 已存在且包含 AreaMatrix 标记块时，只允许更新该标记块。
- 无法判断标记块或文件权限时，禁用 `Enable root overview`，显示 `Cannot safely update AREAMATRIX.md` 和 `Reveal in Finder`。
- README 永不作为自动输出目标。
- 默认状态：defaultStorageMode=Copy，overviewOutput=GeneratedOnly，uiLocale=system，appearance=system。
- 风险确认弹窗打开时禁用设置窗口背后的其他写入控件。
- settings store 保存失败时恢复到上一个已保存值，显示 inline error 和 `Retry save`。
- 根目录概览策略保存失败时，UI 必须回滚到上一个已保存的 overviewOutput，并提示用户 `.areamatrix/generated/` 仍是默认安全输出位置。
- `Open ignore.yaml` 失败时显示可恢复错误，不自动创建覆盖用户文件；若 ignore.yaml 缺失，提供 `Create default ignore.yaml` 并需说明只写 `.areamatrix/ignore.yaml`。
- 空态不适用：General tab 始终显示默认存储、概览、忽略规则、语言和外观区块。
- 加载态：读取 settings 时显示 `Loading settings...`，禁用写入控件但保留关闭 Settings。

## 交互

- 更改存储模式立即保存到 settings store。
- `Open ignore.yaml` 使用系统默认编辑器。
- `Reset this tab` 恢复本 tab 默认值。
- 用户选择 Move / Index-only 后先弹确认；取消确认则 radio 回到原值。
- 用户选择根目录 `AREAMATRIX.md` 后先弹确认；确认后保存 overviewOutput，保存成功才显示为选中。
- `Cancel` 根目录概览确认不写文件、不改 settings store。
- `Enable root overview` 只更新 settings store；实际文件写入由 overview 生成流程执行，且必须遵守本页确认结果。
- `Retry save` 只重试最近一次设置写入，不重新应用用户已经取消的风险设置。
- 切换 tab 时若有保存失败 banner，保留 banner 并允许用户稍后重试。

## 可访问性

- radio、toggle 和确认 sheet 必须有明确标签和当前值。
- 保存失败和回滚提示需要和对应设置项关联。
- 危险选项确认不能只靠黄色或红色表达，必须有文本说明后果。

## 数据与依赖

- settings store。
- overview output policy。
- `AREAMATRIX.md` presence and managed-block detector。
- ignore.yaml 路径。
- settings save state and last saved snapshot。

## 验收清单

- 默认存储模式为 Copy。
- Move / Index-only 默认值需要确认。
- README 不作为自动输出目标。
- 根目录 `AREAMATRIX.md` 需要确认，已有内容不得被覆盖。
- 取消根目录概览确认时不写文件、不改设置。
- 保存失败时 UI 回滚到上一个真实 settings 值。
- 保存失败不会让 UI 显示与实际 settings 不一致的值。
- Stage 1 不要求实现自定义 light/dark 外观。

## 来源

- `docs/ux/settings-panel.md#tab通用general`（直接）。
- `AGENTS.md` 中自动概览写入位置和 README 不变量（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-27 settings-repository](S1-27-settings-repository.md)
- [S1-28 settings-classifier](S1-28-settings-classifier.md)
- [S1-29 settings-integrations](S1-29-settings-integrations.md)
- [S1-30 settings-advanced](S1-30-settings-advanced.md)
- [S1-31 settings-about](S1-31-settings-about.md)
