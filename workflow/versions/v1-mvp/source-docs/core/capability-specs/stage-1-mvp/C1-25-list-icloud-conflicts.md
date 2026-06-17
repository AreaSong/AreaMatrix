# C1-25 list-icloud-conflicts

## 服务的 UX 页面

- S1-36 icloud-conflict-list
- S1-25 icloud-conflict-min
- S1-29 settings-integrations

## Core API

- 计划新增：`list_icloud_conflicts(repo_path) -> sequence<ICloudConflictPair>`
- 计划新增：`mark_icloud_conflict_resolved(repo_path, conflict_id, resolution)`

## 输入

- `repo_path`

## 输出

- 冲突组列表：原始版本、conflicted copy、修改时间、状态。

## DB 变化

- 可选写入 conflict 状态表或 change log。
- 不自动改写 `files` 记录，除非用户明确执行 resolution。

## 文件系统变化

- 只读扫描 iCloud conflicted copy。
- 列表页不删除、不移动任何冲突副本。

## 错误码

- `ICloudPlaceholder`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 空态、加载失败、识别不确定状态均可结构化表达。
- Resolve 入口只处理单项，不在列表页静默合并。
- 不确定冲突必须标记 `Needs review`。

## 延后范围

- 可视化 diff 增强属于 Stage 2 的 C2-17。
