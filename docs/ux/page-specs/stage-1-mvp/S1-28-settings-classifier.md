# S1-28 settings-classifier - 分类规则设置

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-28
> 页面类型：设置
> 页面文件：`S1-28-settings-classifier.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 设置窗口
- **建议目录**：`apps/macos/AreaMatrix/Features/Settings/`
- **建议组件**：`ClassifierSettingsPane`、`ClassifierYamlActionsView`
- **实现说明**：Stage 1 不提供图形化规则编辑器，只提供打开、校验、恢复入口。

## 页面背景

用户或高级用户需要查看和调整分类规则。Stage 1 仍以 classifier.yaml 为主。

入口：Settings > Classifier。
退出：关闭 Settings、切换设置 tab、打开 classifier.yaml、校验完成、恢复上次有效版本。

## 页面功能

- 开关扩展名规则、关键词规则、fallback inbox。
- 打开 classifier.yaml。
- 校验规则并显示错误行号。
- 回退到上次有效版本。

## 布局与内容

规则引擎开关：

- `enableExtensionRules`：默认 true
- `enableKeywordRules`：默认 true
- `fallbackToInbox`：默认 true

YAML 操作：

- `Open classifier.yaml`
- `Validate`
- `Revert to last valid`

校验失败示例：

```text
校验失败：categories[2].slug 重复（line 47）
```

按钮：`Fix in editor`、`Revert to last valid`。

## 状态与规则

- 校验失败不能保存为有效配置。
- YAML 不存在时可创建默认配置或显示恢复默认。
- Stage 1 不提供完整内置编辑器。
- Stage 1 不提供规则 Export / Import；用户需要共享规则时在 Finder 中复制 `classifier.yaml`。
- 打开页面时显示当前配置路径和最近一次校验状态。
- `Open classifier.yaml` 失败时显示 `无法打开分类规则文件`，提供 `Reveal in Finder` / `Create default`。
- `Validate` 执行中禁用重复点击，显示 `Validating...`。
- `Revert to last valid` 需要确认；没有 last valid backup 时禁用。
- 开关保存失败时回滚到上一个已保存值，并显示 `Retry save`。

## 交互

- Open 使用 Finder 或默认编辑器打开。
- Validate 不自动写入。
- Revert 恢复上次有效配置。
- Create default 只写 `.areamatrix/classifier.yaml` 或约定配置路径，不扫描用户文件。
- 校验失败时保留错误行号和错误字段；用户切换 tab 后错误摘要仍可见。
- Revert 成功后重新 Validate，并显示恢复后的状态。

## 数据与依赖

- classifier.yaml path。
- classifier validator。
- last valid backup。
- classifier settings save state。
- file opener / Finder reveal。

## 验收清单

- 校验错误显示行号。
- 用户能打开 classifier.yaml。
- 失败配置可恢复。
- 页面不显示 Export / Import 或内置规则编辑器入口。
- Open、Validate、Revert、保存失败都有可见恢复路径。

## 来源

- `docs/ux/settings-panel.md#tab分类规则classifier`（直接）。
- `docs/roadmap/milestones.md#stage-1mvp约-5-个月`（组合，范围收敛）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
