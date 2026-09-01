# 全仓错误处理、并发、取消、重试与生命周期审计

- 审计 ID：`error-concurrency-lifecycle-audit-20260820`
- 启动时间：`2026-08-20T04:49:59+08:00`
- 收口时间：`2026-08-20T06:11:17+08:00`
- 冻结文件数：`5092`
- 文本文件/行：`4930` / `1533156`
- 生产代码、测试、文档、配置、bindings、live queue：未修改
- 既有工作树改动：保留，详见 `scope.json`

## 状态

`{"BLOCKED": 3510, "FINDING": 8, "NOT_APPLICABLE": 1509, "PASS": 65}`

守恒：`5092 = PASS + FINDING + NOT_APPLICABLE + BLOCKED`；`PENDING/IN_PROGRESS = 0`。

## 方法与边界

- 三个只读分区代理分别覆盖 Rust、Apple、Windows/Linux/workflow 线索；主代理回源复核每条候选。
- 检索命中、测试属性和代理自述不计作全文 PASS；部分范围文件整体标 `BLOCKED`。
- 二进制、symlink、确定性生成绑定、锁文件、静态 prompt 和既有审计材料逐项记录来源链后标 `NOT_APPLICABLE`。
- 全仓逐行覆盖未完成，最终结论 `BLOCKED / NOT-READY`。
- 按用户前置门禁未运行产品测试、lint、build 或压力脚本。

## 候选处置

- `Task.detached 普遍不可取消`：排除为独立 finding。docs/architecture/concurrency.md:59-76 明确规定同步 FFI 通过 detached 执行且只能在调用之间取消；只登记有具体过期回写/协调缺口的链路。
- `RepositoryOverviewRegenerationModel.prepare 可重复通过 guard`：排除。prepare 在首个 await 前同步将 phase=.loading；第二个 MainActor 调用看到 phase.isBusy=true。仅 load 缺 generation。
- `resumeInterruptedInitialization 绕过写协调器`：不登记（可达性 BLOCKED）。resume_scan_session 确实写 DB；已检查引用未发现 production 调用方，只有测试直接调用。但全仓调用图未逐行闭环，因此不把该检索结果升级为确定性排除。
- `Linux ConfigureAwait(false) 后更新绑定属性`：需外部验证/BLOCKED。当前 Linux csproj/view wrapper 未建立 GTK dispatcher 或 PropertyChanged UI subscriber；可见风险但尚无具体 UI sink，不能作为静态确认缺陷。
- `remote-governance expression 注入`：排除为安全 finding。workflow_dispatch 未声明 branch input，实际值来自管理员控制的 default_branch；虽然 Git ref 可含 shell metacharacters，未建立低权限输入到高权限 shell 的边界。仍建议用 env/printf 硬化。
- `CI 未设置 timeout-minutes`：排除为明确缺陷。GitHub 有平台默认上限且主要 workflow 有 concurrency cancellation；属于可靠性硬化，当前无项目合同或已证实 hung path。
- `Windows watcher 关闭泄漏`：排除。MainWindow_Closed 反订阅并 Dispose；WindowsWatcherDiagnostics.StopWatcher 解绑事件并释放 watcher。
- `task-loop timeout 留下子进程`：排除（已读范围）。Popen 使用新 session，idle/total timeout 进入 terminate_child，TERM 后升级 KILL 并清 current child/log state。

## 台账自检

- finalize_audit.py 内部 JSONL parse/count/path/status/conservation/finding/error-contract 校验：PASS。
- 冻结路径缺失：0。
- 冻结后哈希漂移：91，逐项见 `scope.json`。
- 冻结后新增：40；其中其他审计 runtime 34，非 runtime 6。
