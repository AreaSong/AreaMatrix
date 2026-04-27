# ADR-0008: 命名与国际化策略

> 文件系统层一律用英文 slug；UI 显示按 locale 切换；用户文件名保留原貌不修改。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：core/classify / core/storage / apps/macos UI
> 关联 ADR：—

## 上下文

AreaMatrix 是面向中文用户为主的本地资料管理工具，但要兼顾跨语言场景：

- **分类目录名**：`docs` / `code` / `media` / `inbox` 还是 `文档` / `代码` / `媒体` / `收件箱`？
- **文件名**：用户拖入的可能是 `小米发布会.pdf` / `Q4 财报.xlsx` / `meeting-notes.md` 等中英混合
- **应用 UI**：菜单 / 按钮 / 提示需要本地化
- **未来扩展**：英文用户、日韩用户场景

需要决定 FS 层、DB 层、UI 层各自的命名策略。

## 决定

**三层分离**：

| 层 | 命名策略 |
|---|---|
| **文件系统**（分类目录、staging 等内部目录） | 英文 slug：`docs`, `code`, `media`, `archive`, `data`, `software`, `finance`, `health`, `personal`, `inbox` |
| **数据库**（files.category 列） | 同 FS：英文 slug |
| **UI 显示**（侧栏、详情、设置） | 按 `Locale.preferredLanguages.first` 取本地化字符串 |
| **用户文件名** | **完全保留**，不做翻译 / 拼音化 / 转码 |

**Locale 配置文件**：每个 locale 一个 strings 文件，编译进 app bundle：

```text
apps/macos/AreaMatrix/Localizations/
├── en.lproj/Localizable.strings
├── zh-Hans.lproj/Localizable.strings
└── zh-Hant.lproj/Localizable.strings
```

`classifier.yaml` 中 category 的 `display_name` 字段提供国际化别名（[ADR](../api/classifier-yaml.md)）。

## 理由

1. **FS 用英文最稳**：跨平台同步（iCloud / Dropbox / git）、shell 操作、备份脚本都不用关心非 ASCII 字符
2. **DB 用英文 slug** = 用户改 locale 不影响 DB 查询
3. **UI 切换灵活**：locale 切换不动 FS，只换显示
4. **用户文件名保留**：用户起的名字是用户的资产，应用无权改
5. **跨用户协作**：仓库共享给英文同事时，目录结构他能看懂；文件名按用户原文保留
6. **避免编码踩坑**：HFS+ vs APFS 对 NFC/NFD 处理不同，全 ASCII 目录名规避了一类问题

## 考虑过的备选

### A. 全中文目录名

`~/AreaMatrix/文档/` / `~/AreaMatrix/代码/` 等。

- 优点：中文用户在 Finder 中最直观
- 缺点：
  - 英文 / 日文用户切换 locale 后目录名仍是中文（要么不改要么大规模 rename）
  - shell 路径处理 / 备份脚本要处理 unicode
  - DB query 全是中文，IDE 看着难受
- **为什么没选**：跨语言场景吃亏

### B. 全英文 + UI 也英文

不本地化。

- 优点：实现最简单
- 缺点：中文用户体验差，违反目标用户群定位
- **为什么没选**：失去主用户群

### C. FS 用 emoji 前缀（如 `📄 docs`）

- 优点：视觉醒目
- 缺点：
  - 跨工具兼容差（git / shell 需要转义）
  - 部分系统不支持 emoji
  - 路径长度增加
- **为什么没选**：兼容性问题

### D. 用户自定义分类名

让用户启动时选目录名（中文 / 英文 / 日文）。

- 优点：极致灵活
- 缺点：
  - 配置复杂
  - 用户再也无法跨语言切换 UI
- **为什么没选**：分类是 Stage 1 内置的（10 个），用户自定义在 Stage 2 加（仍用英文 slug + 显示名分离）

### E. 自动音译 / 拼音化中文文件名

`小米发布会.pdf` → `xiaomi_fabuhui.pdf`。

- 优点：FS 全 ASCII
- 缺点：
  - 语义损失大
  - 同音字冲突
  - 用户要求"原文件名保留"是基本预期
- **为什么没选**：违反"用户文件名是用户资产"原则

## 后果

### 正面

- FS 在所有 OS / 工具下都干净
- UI 多语言切换实时生效
- 跨语言团队协作友好
- 用户文件名一字不改 → 信任度高
- DB 查询 / 日志 / 错误信息都是英文，开发调试方便

### 负面 / 代价

- **首次启动需要本地化决策**：UI 文案要为每个 locale 准备完整翻译
  - MVP 仅支持 `zh-Hans` 和 `en`，`zh-Hant` Stage 2 加
- **classifier.yaml 双名维护**：内部 `slug` + UI `display_name` × N 个 locale
  - 缓解：display_name 字段是 map，缺失 locale 自动 fallback 到 slug
- **错误消息本地化**：core 层 [error-codes.md](../api/error-codes.md) 中的 `code` 用英文，UI 层翻译展示
- **路径中包含中文文件名**：仍然存在（用户文件名）
  - 缓解：所有路径处理用 `PathBuf` / `URL`，不假设 ASCII

### 风险

- 用户改了 macOS locale 但应用没自动跟随 → 提供"语言切换"设置项
- 用户文件名包含 NTFS / FAT 不允许的字符（`:`, `?`, `*` 等）→ 在导入时验证 + 转义建议
- 大小写敏感性：APFS 默认不敏感、ext4 敏感 → 跨平台同步时可能出冲突
  - 缓解：DB 中 path 列做 NFC 归一 + case-insensitive 索引

## 何时重审

- 加日 / 韩 / 法 等 locale 时，整套 strings 流程要扩展
- 用户大量要求"目录改成中文" → 重审是否在 UI 层提供"目录别名"
- 跨平台同步（macOS ↔ Windows）出现 case 冲突频繁 → 决定统一 case 策略
- 加用户自定义分类（Stage 2）时，slug 由用户输入或自动生成的策略

## Related

- [../api/classifier-yaml.md](../api/classifier-yaml.md)
- [../modules/classify.md](../modules/classify.md)
- [../product/glossary.md](../product/glossary.md)
