# classifier.yaml 配置规范

> 定义 `<repo>/.areamatrix/classifier.yaml` 当前由 Rust parser 实际接受的字段和匹配语义。
>
> 阅读时长：约 7 分钟。

---

## 文件与 fallback

- 路径：`<repo>/.areamatrix/classifier.yaml`。
- 初始化资料库时，Core 把内嵌 `core/resources/classifier.yaml` 写入该路径。
- 文件缺失：使用内嵌 `core/resources/classifier.yaml`。
- 文件存在但 unreadable、YAML 无效或校验失败：返回 `Config`/`Classify` error。
- parser 拒绝 unknown fields。

普通打开资料库或 Core 升级不会覆盖已有 YAML。只有明确的 rule save/editor API 会写入用户配置。

仓库当前没有 tracked `classifier.schema.json` 或 AJV CI gate；机械合同由 Rust parser 和测试执行。

## Schema

```yaml
version: 1
default: inbox
categories:
  - slug: docs
    display_name:
      zh-Hans: 文档
      en: Documents
    description:
      zh-Hans: 文档资料
      en: Documents
    extensions: [pdf, docx, txt, md]
    keywords: [report, 报告]
    priority: 0
    naming_template: "{date}_{stem}.{ext}"
```

顶层只允许：

| 字段 | 约束 |
|---|---|
| `version` | 必须为 `1` |
| `default` | 必须匹配一个 category slug |
| `categories` | 1 到 64 项 |

Category 只允许：

| 字段 | 约束 |
|---|---|
| `slug` | 必填；小写字母开头；小写字母/数字/`_`/`-`；最多 32 字符；唯一 |
| `display_name` | optional map；value 非空且最多 32 字符 |
| `description` | optional map；value 最多 200 字符 |
| `extensions` | optional；小写字母/数字，不含点，1–16 字符；category 内唯一 |
| `keywords` | optional；trim 后非空，最多 32 字符；category 内唯一 |
| `priority` | optional；`-1000..=1000` |
| `naming_template` | optional；最多 200 字符 |

locale key 当前作为普通 map key 保存，Core 不额外验证 BCP 47 格式。

## 匹配

文件名先做 NFKC 和 lowercase。

### Keyword

- CJK keyword：normalized filename contains。
- 非 CJK keyword：按空格、`_`、`-`、`.`、tab、slash、backslash、括号和方括号切 token 后等值匹配。
- tie-break：priority 高 → keyword 长 → category 顺序早。

### Extension

- 只使用最后一层 extension。
- tie-break：priority 高 → category 顺序早。
- Keyword 命中后不再检查 extension。

### Default

没有 keyword/extension hit 时返回 `default`，confidence 为 0，不代表错误。

稳定的分类结果语义：

| 命中方式 | `reason` | `confidence` |
|---|---|---|
| keyword | `Keyword` | `0.9` |
| extension | `Extension` | `0.7` |
| fallback | `Default` | `0.0` |

## Naming template

| Placeholder | 输出 |
|---|---|
| `{original}` | 完整原文件名 |
| `{stem}` | stem |
| `{ext}` | 不含点的最后一层 extension |
| `{date}` | 本地日期 `YYYY-MM-DD` |
| `{date_iso}` | UTC RFC3339，例如 `2026-04-28T10:30:00Z` |
| `{slug}` | category slug |

未识别 placeholder 当前保持原字符串。模板结果仍需 storage filename validation；不能用模板绕过路径安全。

## 保存和编辑

Core 的 rule save/editor API 都先写入同目录临时文件、同步文件内容，再原子替换 YAML 并同步父目录：

- `save_classifier_rule` 在原子替换或临时文件清理失败时返回错误；它不承诺在替换后的父目录同步失败时恢复旧内容。
- classifier editor mutation 会保留旧 bytes；替换后的父目录同步失败时，重新原子写回旧内容。
- 两类入口都执行各自的规则校验；需要影响确认的 editor 操作和过宽 extension-only rule 未确认时会被拒绝。

- 保存只影响未来分类。
- 不自动重分类、移动、重命名、删除或 reindex 已有文件。
- 删除 default category、最后一个 category 或未确认影响的规则会被拒绝。
- Swift UI 不直接编辑 YAML；通过 Core API 获取 editor snapshot 和提交 request。

用户手工编辑 YAML 后，下次规则读取会重新解析；当前没有 classifier cache。

## AI 边界

`classifier.yaml` 只定义本地规则。AI category suggestion 使用独立 API、privacy/provider 配置和 audit log，
不是 YAML 的隐式 fallback。

## 验证

```bash
cd core
cargo test --workspace classify
```

完整 Core 改动仍需 fmt、clippy 和 workspace tests。

## Related

- [core-api.md](core-api.md)
- [../modules/classify.md](../modules/classify.md)
- [../ux/classifier-calibration.md](../ux/classifier-calibration.md)
- [../development/testing.md](../development/testing.md)
