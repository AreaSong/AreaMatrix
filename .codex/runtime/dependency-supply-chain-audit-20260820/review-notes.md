# 依赖、许可证与供应链审计记录

## 审计状态

- 审计 ID：`dependency-supply-chain-audit-20260820`；冻结 commit：`cf3647378d64885e8e6a44a2a5b60d8926668982`；范围：`5053` 文件。
- 3 个指定只读子代理已完成：Rust/Cargo/UniFFI；SwiftPM/Xcode/.NET/native；Python/Shell/Actions/assets/external capability。子代理未修改仓库、未安装依赖、未执行未知脚本，也未派生子代理。
- 主代理已回到声明文件、锁文件、构建脚本、实际调用方和发布路径复核候选 finding；历史同字节逐行证据只作为覆盖依据，不直接继承历史“PASS”。

## 人工审阅方法

1. 读取根目录与局部 `AGENTS.md`、治理 skill、`CODE_REVIEW.md`、`SECURITY.md`、依赖/CI 政策、许可证、构建/发布/品牌文档。
2. 固定 tracked + 审计启动时非忽略 untracked 文件范围，保存 SHA-256、类型、行数和既有 dirty worktree 状态。
3. 逐文件阅读证据与本轮供应链语义交叉审查：声明 -> lock -> 来源 -> 生成/构建 -> 实际调用 -> 打包/分发。
4. 二进制/生成物逐项核对 MIME、架构、哈希、生成链、项目引用和可分发范围；不可逐字阅读者才标 `NOT_APPLICABLE`。
5. 人工审阅后才使用 Cargo metadata、公开 PyPI/NuGet/OSV/GitHub ref 查询作辅助证据；没有运行 cargo update、swift package update、dotnet add、pip install 或未知脚本。

## 关键本地证据

- Cargo metadata：`/tmp/area_metadata_full.json`（198 packages）；`core/Cargo.lock` v4，registry checksum 逐包读取。
- Pillow：`scripts/brand/requirements.txt:1`，CI 安装/调用链 `governance-ci.yml:40-46` -> `validate_assets.py:90-106`；PyPI license expression `MIT-CMU`，sdist SHA-256 已写入 ledger。
- Windows：顶层 PackageReference 在 `AreaMatrix.Windows.csproj:21`；native DLL 由 `NativeCoreLibrary.cs:240-260` 环境变量/系统搜索加载，无 hash/signature/source manifest。
- macOS：canonical project 链接 CoreSDK XCFramework；XcodeGen project 仍引用 tracked `libarea_matrix_core.a`，哈希 `69ef0816...1db44`。
- Brand：`wordmark-outlines.json` 只记录 family=`Inter`/postScriptName=`Inter-Bold`，没有输入字体版本、来源 URL、许可证或 hash。
- 外部命令复核：已逐项登记实际调用的 `jq`、`tee`、`find`、`tail`、`grep`、`uname`、`tr`、`ln`、`sed`、`ps`、`pgrep`、`clear`、`which`；未发现 `xattr`、`plutil`、`rsync` 或 `file(1)` 的真实命令调用，故不把同名代码标识符/自然语言误记为依赖。

## Finding 复核规则

- P0/P1 只用于可影响构建/发布完整性、native loading 或用户文件路径的高置信问题；旧版本/个人偏好不单独构成漏洞。
- 外部 advisory 与本地调用路径分开标记；SC-020 保持 `BLOCKED`，没有把 RustSec 命中夸大为已利用漏洞。
- 法律不确定项写作“许可证合规风险，需合格法律/许可证 reviewer 确认”，不作无依据法律定论。

## 未决事项

- `PENDING/IN_PROGRESS` 文件数为 0，但发布/合规结论仍 BLOCKED；未知 native 来源、许可证复核、SBOM/notices、远端治理和外部 advisory 不能由静态覆盖消除。
- 最终 SHA-256 复算发现 `69` 个冻结范围文件在审计后变化；它们在 `scope.json.final_scope_validation.drift` 中保留期望值和当前值，本次不继承冻结版本的 PASS/FINDING 结论。
- 同一复算还发现 `6` 个新增非 runtime 文件（详见 `scope.json.final_scope_validation.post_freeze_non_runtime_paths`）；这些文件必须在后续稳定工作树上单独纳入范围后才能完成当前仓库审计。
- `scope.json.final_scope_validation` 是生成时快照；生成后独立只读复核若观察到更多并行变更，以上数字不代表当前工作树的稳定计数，必须重新冻结范围和哈希。
- 交付前独立只读复算（2026-08-19T22:14:09Z）已观察到冻结范围漂移增至至少 `72` 个；该结果仅作为阻断证据，不回写冻结台账，以免在并行写入期间制造虚假的稳定计数。
- SC-010 的 `supplemental_evidence_files` 指向审计时存在但被 Git 忽略的 XcodeGen 生成工程；该文件已按指定行读取，但不冒充冻结仓库文件覆盖记录。
- 任何后续修复必须在独立变更中完成，并重新生成锁定、SBOM、许可证通知、签名/哈希和 clean-environment 验证证据；本次审计不代替修复或发布审批。
