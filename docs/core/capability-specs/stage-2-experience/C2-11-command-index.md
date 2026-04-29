# C2-11 command-index

## 服务的 UX 页面

- S2-15 command-palette

## Core API

- 计划新增：`list_command_targets(repo_path) -> CommandIndex`

## 输入

- repo_path、当前 selection context。

## 输出

- 可执行命令、最近项目、smart lists、文件候选。

## DB 变化

- 读取 metadata；可记录 recent command。

## 文件系统变化

- 无。

## 错误码

- `Db`

## 验收标准

- 命令面板只列出当前上下文允许的动作。
- 危险动作仍必须跳转确认页。
- 不绕过权限或高风险确认。

## 延后范围

- 插件命令市场属于后续阶段。
