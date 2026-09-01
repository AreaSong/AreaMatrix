# AreaMatrix 性能与稳定性审计笔记

> 状态：初始化中。这里只记录人工阅读批次、调用链复核、候选排除和辅助验证边界。

## 审计约束

- 不修改业务代码，不提交、不推送。
- 不接触真实用户资料库、真实 iCloud 文件、真实凭据或外部服务。
- 自动化仅用于建清单、定位、统计和辅助证据；不得替代人工逐行阅读。
- `coverage.jsonl` 为追加式状态账本，以每个路径最后一条记录为当前结论。

## 工作树快照

- 冻结时间：2026-08-20T04:23:57+08:00。
- 冻结 commit：`cf3647378d64885e8e6a44a2a5b60d8926668982`；文件数 5062。
- 启动时 dirty 路径保存在 `scope.json`。后续并行任务持续改动工作树；对于冻结时 clean 的 tracked 文件，审阅者可读取该 commit blob，并且账本导入会校验 blob SHA/行数与 inventory 一致。启动时已 dirty 且之后继续漂移、无法精确重建冻结字节的路径保留 `BLOCKED`。

## 人工审阅批次

- 2026-08-21 主线程 scripts 续批：逐行复核 `workflow_baseline.py:1-381`、`workflow_init.py:1-275`、`workflow_projection.py:1-392`，并复核 `check-secrets.sh:1-73` 的 canonical finding 归并。

## 高风险候选与排除

- `scripts/dev_tools/workflow_projection.py:74-134`：每个投影 task 都重新解析完整 progress 和全部 manifests，静态复杂度为 O(T×(P+M))。冻结仓库的 progress 为 894814 bytes、manifests 合计约 506500 bytes，但实际 promotion task 数仅 v-template=5、v2=1，v1 没有 promotion.yaml；这是低频显式治理命令，当前缺乏可感知影响证据，因此不记 finding。若未来单版本 task 数显著增长，应改为每次 collect 只加载一次 progress/manifests 并加规模测试。
- `scripts/dev_tools/workflow_baseline.py:54-62,77-169,257-317`：同一文档多个 baseline range 会重复整文件读取；当前 v2 只有 5 个文档条目/16 个 change range，属于低频 doctor/preview/write，未达到 finding 标准。

## 主代理复核记录

- `PERF-MAC-007` 补充复核：冻结快照中 `CoreBridge.validateRepoPath` / `validateInitializedRepoPath` 在 actor 上先同步跨 UniFFI，再由 `RepoPathValidationSnapshot.init` 同步读取 volume capacity/internal metadata；`CoreObservabilityBridge.flushObservability` 同步进入 Rust `runtime_api::flush` 的 1ms sleep 循环，deadline 可达 5000ms；`CoreRemoteProviderConfiguring.testRemoteProvider` 的网络段虽为 async，但前后 prepare/complete 均同步执行 DB 状态读写，取消分支仍执行同步清理。三条均属于既有“共享 CoreBridge actor 被同步 FFI/IO 占用”的同一根因，已合并到 canonical finding，不另行拆号。
- `PERF-WF-003`：逐行比对冻结 `index.json`、对应 `summary.json`、`runner.py`、`state.py` 和 `console.py`。`record_summary` 会在每次 retry 更新 summary，但仅 PASS 后显式 `update_run_index`，或正常/捕获到 `TaskLoopError` 的 finalize 才刷新 index；SIGKILL/主机故障等路径无法 finalize。冻结历史有 6 个 run 的 index retries 低于 summary（3/5、2/4、12/13、6/7、29/30、0/5），故不是单个历史文件噪声，按 P3/HIGH 记录为状态监控与恢复可靠性 finding。
- `PERF-RUST-020`：冻结 `external_runtime.rs` 中 `wait_for_child` 的 deadline 仅覆盖直接子进程。父进程在预算内退出后，代码仍无期限 `join` stdin writer 与 stdout reader；后台后代若继承 pipe，成功路径不会清理 Unix process group，非 Unix process-group helper 还是空实现。现有 descendant 测试让父 shell `wait`，只覆盖 timeout kill，未覆盖“父成功退出、后代持有 pipe”。该缺口同时影响 classification/summary/tags/semantic search 的 30 秒 runtime 合同。
- `PERF-RUST-021`：冻结 `get_local_model_status -> inspect_local_model -> directory_size` 每次显式 Check/Retry/Health 都递归扫描整个模型目录并逐文件 metadata；Swift `Task.detached(...).value` 仅避免 MainActor 同步阻塞，取消不会下传已进入的同步 Rust。UI 没有自动打开即扫描，因此按 P2 而非 P1；但不同恢复入口可创建独立 model 并发扫描同一路径，现有测试均为两个左右 metadata 文件的小 fixture。
- `PERF-RUST-022`：冻结 sync conflict detection 会先全量 active-row + 完整文件 SHA-256，再 WalkDir 全仓寻找 conflicted copy；`snapshots_by_path` 只用于 copy 本身，原文件仍对 snapshots 线性 `find`，形成 C×F。完整 conflict 数组写入单一 repo_config JSON；每次 preview/resolve 又整包 parse、线性定位并在 resolve 后整包序列化，连续处理 C 项累计 O(C²)。macOS/iOS detached FFI 不传播取消；Windows/Linux 所谓 async native client 只在同步调用前检查 token。现有 detection fixture 最大 3 个冲突，resolve 为单项。

## 辅助验证

人工逐行审阅完成前不运行 benchmark、测试或 lint。
