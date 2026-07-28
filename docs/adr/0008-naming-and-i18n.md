# ADR-0008: 命名与国际化策略

> 文件系统层一律用英文 slug；UI 显示按 locale 切换；用户文件名保留原貌不修改。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：core/classify / core/storage / apps/macos UI
> 关联 ADR：—

> 现状更正（2026-07-23）：三层分离原则（FS 英文 slug、用户文件名保留）仍有效，以下声明按当前合同更正：
>
> - 内置分类 slug 实际为 6 个：docs / code / design / media / finance / inbox（`core/resources/classifier.yaml`），正文原「10 个」处已就地更正。
> - 本地化资源已统一为 `Localizations/Localizable.xcstrings`，正式只维护 `en` 与 `zh-Hans`；资源 locale 只决定 String Catalog、语法和复数。应用 UI 的日期、数字、文件大小和货币使用 macOS `Locale.autoupdatingCurrent` 的 region 格式；持久化生成物使用由内容 locale 定义的确定性格式，不读取设备 region。
> - 应用界面语言与资料库内容语言已拆分。`AppLanguage` 是 UserDefaults 中的设备级设置，控制全部 macOS UI；`RepositoryContentLanguage` 是每资料库配置，控制内置分类显示名和之后生成的内容。两者均支持跟随选项，但不共享持久化状态。
> - 跟随系统只检查 `AppleLanguages` / preferred languages 的第一项，不扫描后续偏好：`zh-Hans` / `zh-CN` / `zh-SG` 解析为 `zh-Hans`，`en-*` 解析为 `en`，其他第一项直接回退 `en`；`zh-Hant`、`zh-HK`、`zh-TW` 和 bare `zh` 不隐含简体中文。
> - 「DB 中 path 列做 NFC 归一 + case-insensitive 索引」未实现：`files.path` 为 `TEXT NOT NULL UNIQUE`，无 `COLLATE NOCASE`、无 NFC 归一（`core/src/db/schema.rs`）；unicode NFC 归一目前仅用于分类关键词匹配。

## 当前实施状态

截至 2026-07-26，本 ADR 的双语言合同已在 Core、UDL、生成绑定与 macOS 应用中落地：

- `AppLanguage` 与 `RepositoryContentLanguage` 使用独立持久化和解析链路；界面语言切换会立即重投影全部
  application-owned 文案，资料库内容语言只影响内置分类显示名和之后生成的内容。
- 设置窗口以独立 `language` 一级页同时呈现两套语言系统：界面语言可立即切换，当前资料库内容语言通过
  revision/CAS 显式保存。General 与 Repository 只保留当前值摘要和前往 Language 页的入口，不能形成重复
  编辑面。Welcome 右上角快捷控件仍只切换界面语言。
- 资料库内容语言通过 revision/CAS 更新，classifier 的 `display_name` / `description` locale map、未知 policy
  只读兼容、结构化冲突与错误映射均由 Core 合同约束。
- 会生成内容的 operation 冻结 concrete locale、operation provenance 与恢复上下文；路径、文件名、slug、
  provider/model、搜索正文和 technical details 保持原文。
- overview provenance 能区分 synchronized、needs regeneration、mixed 与 unknown。内容语言切换不会自动改写
  既有文件；全库 regeneration 只能由用户显式触发，并经过 preflight、durable journal、staging、backup、commit
  与恢复门禁。
- 当前工作树的 Debug build、Language 设置定向测试和本轮 Settings 文件定向 SwiftFormat/SwiftLint 已通过。
  fixture-only UI 检查覆盖 `en/en`、`en/zh-Hans`、`zh-Hans/en` 与 `zh-Hans/zh-Hans` 四种界面/内容组合，
  验证了即时界面刷新、两套语言状态独立、显式保存、摘要跳转、SQLite 完整性，以及根目录
  `README.md` / `AREAMATRIX.md` 不被创建或改写。本轮未执行 overview regeneration commit；全量 macOS
  测试仍有与本页改动无关的既有治理失败，因此 residual 在完整门禁恢复前保持 open。

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
| **文件系统**（分类目录、staging 等内部目录） | 英文 slug，内置 6 个：`docs`, `code`, `design`, `media`, `finance`, `inbox`（更正：见顶部现状说明） |
| **数据库**（files.category 列） | 同 FS：英文 slug |
| **应用界面文案**（菜单、按钮、错误、设置标签） | 按应用级 `AppLanguage` 从 String Catalog 取本地化字符串 |
| **资料库内容显示**（分类显示名、目录树、生成概述） | 按每资料库 `RepositoryContentLanguage` 显示；`system` 跟随当前已解析的界面语言 |
| **用户文件名** | **完全保留**，不做翻译 / 拼音化 / 转码 |

**Locale 配置文件**：单一 String Catalog 编译进 app bundle：

```text
apps/macos/AreaMatrix/Localizations/Localizable.xcstrings
```

`classifier.yaml` 中 category 的 `display_name` 与 `description` map 提供内容语言别名
（[classifier YAML](../api/classifier-yaml.md)）。已知显式或兼容 policy 的显示回退顺序是 exact raw locale、
resolved concrete locale、`en`、slug；`system` 从当前 concrete locale 开始，不查询 `system` map key；未知
policy 只读浏览时使用 exact raw locale、`en`、slug。custom category 允许 sparse locale map（稀疏语言映射），
不自动补译。未知非空 policy 仍允许浏览，但持续显示 unsupported 状态，并阻断所有 classifier mutation、generated
content 或可持久化 AI 自然语言结果，直到用户在 Language 设置中明确选择支持值。

Core 不持有可变的进程级界面 locale。每个可能生成内容的 operation（操作）在自己的线性化点解析一次
concrete `zh-Hans` 或 `en` 并显式传入 Core：设置提交要么完整发生在快照前，要么完整发生在快照后；一个
用户 batch 只使用一个快照。new attempt 重新捕获；continuation、resume、replay、同一 external sync
window 和 automatic provider fallback 复用原快照。按钮是否显示为 Retry 不决定 operation identity。

每个用户触发的 attempt 只公开一个 `operation_id`。终态失败后的显式 Retry 创建新 `operation_id`，并以
`retry_of_operation_id` 关联前一次；resume、replay、rollback 和进程内 continuation 复用原 ID。内部重新
进入执行以 `run_sequence` 区分，远程调用以 `call_id` 区分，不再引入语义重叠的公开 `attempt_id`。可恢复
context 在首次副作用或远程调用前持久化，但只保存稳定 ID、operation 类型、concrete locale、revision、
规范 options、目标标识或 hash、format version 与恢复状态；可从资料库重建的用户正文、完整 prompt 和
secret 不为恢复目的重复持久化。

application-owned（应用自有）显示值在使用时按当前界面语言解析。`AppDisplayText`、`LocalizedMessage`、
catalog key 或翻译结果不得写入 session / recovery；只持久化稳定 domain code、结构化 payload 和必要原值，
恢复后再映射。Accessibility label/value/hint/action/announcement 同样按当前界面语言解析；
`accessibilityIdentifier` 是稳定英文自动化标识，不本地化。

application-owned 文案包括 AreaMatrix 自己的菜单、按钮、标签、错误、确认、状态和通知；它们必须走
String Catalog。OS-owned 文案包括系统 open/save panel、系统菜单和 macOS 自己提供的权限或服务 UI；
它们继续由 macOS 决定语言，应用不复制、不覆盖，也不承诺与应用界面语言一致。

`AppLanguage.system` 在启动、应用重新进入前台和系统 locale-change notification 到达时重新解析，并把结果
广播到全部窗口。显式 `zh-Hans` / `en` 不响应之后的系统语言变化。历史兼容别名可以只读解析；未知的
UserDefaults 原值按 `system` 运行但不隐式写回，下一次用户明确选择才保存 canonical 值。交给系统 panel、
notification 或 service 的应用文案在交付时冻结；仍由应用持有的 toast、banner、sheet 和进度文案继续响应
界面语言变化。

修改语言设置本身不触发 overview、AI 结果或用户文件重写。之后正常发生的 init/import/rename/repair/
external sync 等 operation 可以按新快照刷新其本来就会更新的 derived generated content；这不属于设置
保存的隐式重写。持久化生成物中的日期、数值、大小和货币必须按内容 locale 的固定规则生成，不能因设备
region、时区或重放机器而改变。生成格式使用 UTC 和显式 format contract version；恢复与重放复用原
operation context。搜索查询、搜索结果、slug、provider/model/endpoint 和技术诊断始终保留原文。

内容语言保存成功后，当前资料库的内置分类显示和只读语言摘要立即重投影到全部 clean window；有未保存
草稿的窗口保留草稿并进入 stale 状态。既有 overview 与 AI 结果不改变，允许不同文件暂时保留历史生成
语言。canonical repository 的 classifier 编辑器可以独立维护 `zh-Hans` 和 `en` map，不要求
`editing_locale` 等于当前内容 policy；policy 只选择展示/生成语言，保存只 patch dirty locale。
Overview provenance 将现状分类为尚未生成、已同步、需要重新生成、混合或未知。“需要重新生成”返回
locale mismatch、format mismatch、missing targets、obsolete targets 等稳定原因；混合表示存在多个可信
locale/format；任一现有目标缺少可信 provenance 时为未知。生成文件的当前 bytes 与 provenance hash 不符
同样为未知，普通增量生成不得静默覆盖，只有显式全库 regeneration 可在 preflight、journal 和 backup 保护下
替换。禁止通过扫描自然语言或当前设置补猜。AI operation 的 frozen locale 表示请求语言和
provenance，不代表可靠的语言检测；只有 provider metadata 或高置信度 advisory detector 才能提示语言不符，
原始 draft 仍逐字保留，不自动翻译或静默重试。

只有用户显式执行全库 overview regeneration 才会事务式替换 `.areamatrix/generated/**` 和已启用的合法
`AREAMATRIX.md` managed block。操作冻结 repository revision、目标集合、locale 与 format version，先完成
staging 和 durable journal；commit 前 revision 漂移或取消保持全旧，短 commit 开始后不可取消。普通错误
回滚为全旧；commit 崩溃后先验证 staged plan，合法时继续提交，否则从合法 backup 回滚，任一侧均无法
验证时持续阻断普通写入。恢复完成前资料库不可恢复正常写入，最终必须收敛为全旧或全新。该保证是稳定状态的事务
原子性，不虚构文件系统无法提供的跨多个用户可见文件瞬时原子替换。它不处理 AI、`README.md` 或用户内容。
目标集合同时覆盖当前 classifier categories 和 generated nodes 中的失效分类文件。失效文件只有在路径位于
`.areamatrix/generated/nodes/*.md`、是普通文件并纳入同一 journal/backup 时才删除；symlink、非普通文件、
越界路径或无法验证的目标全部 fail closed。

## 理由

1. **FS 用英文最稳**：跨平台同步（iCloud / Dropbox / git）、shell 操作、备份脚本都不用关心非 ASCII 字符
2. **DB 用英文 slug** = 用户改 locale 不影响 DB 查询
3. **UI 切换灵活**：locale 切换不动 FS，只换显示
4. **用户文件名保留**：用户起的名字是用户的资产，应用无权改
5. **跨用户协作**：仓库共享给英文同事时，目录结构他能看懂；文件名按用户原文保留
6. **避免编码踩坑**：HFS+ vs APFS 对 NFC/NFD 处理不同，全 ASCII 目录名规避了一类问题

语言切换也不改变稳定分类顺序、当前文件排序、selection、expanded state、scroll、focus、route、sheet 或
draft identity。`system` policy 只保存跟随关系；它在每台设备独立解析，界面 concrete locale 改变时只重投影
clean presentation，不增加 repository revision，已运行 operation 与 dirty classifier draft 继续使用冻结 locale。

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
- **为什么没选**：当前分类内置（6 个），用户自定义后续加入（仍用英文 slug + 显示名分离）

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
  - 当前仅支持 `zh-Hans` 和 `en`；新增资源语言前必须同时定义系统语言解析与 fallback
- **classifier.yaml 双名维护**：内部 `slug` + UI `display_name` × N 个 locale
  - 缓解：display_name 字段是 map，缺失 locale 自动 fallback 到 slug
- **错误消息本地化**：core 层 [error-codes.md](../api/error-codes.md) 中的 `code` 用英文，UI 层翻译展示
- **路径中包含中文文件名**：仍然存在（用户文件名）
  - 缓解：所有路径处理用 `PathBuf` / `URL`，不假设 ASCII

### 风险

- 用户改了 macOS preferred languages 但应用没自动跟随 → `AppLanguage.system` 每次只解析第一项，第一项不支持时直接回退 `en`
- 界面语言错误影响日期、数字或文件大小格式 → 资源 lookup 与 `Locale.autoupdatingCurrent` region 分开测试
- session / recovery 保存已翻译文案而产生陈旧语言 → 只持久化稳定 code 与结构化 payload，恢复后解析
- 用户文件名包含 NTFS / FAT 不允许的字符（`:`, `?`, `*` 等）→ 在导入时验证 + 转义建议
- 大小写敏感性：APFS 默认不敏感、ext4 敏感 → 跨平台同步时可能出冲突
  - 缓解：DB 中 path 列做 NFC 归一 + case-insensitive 索引（更正：未实现，见顶部现状说明）

## 何时重审

- 加日 / 韩 / 法 等 locale 时，整套 strings 流程要扩展
- 用户大量要求"目录改成中文" → 重审是否在 UI 层提供"目录别名"
- 跨平台同步（macOS ↔ Windows）出现 case 冲突频繁 → 决定统一 case 策略
- 加用户自定义分类时，slug 由用户输入或自动生成的策略

## Related

- [../api/classifier-yaml.md](../api/classifier-yaml.md)
- [../modules/classify.md](../modules/classify.md)
- [../product/glossary.md](../product/glossary.md)
