# Plan Sync

本命令供兼容发现；Agent 须静默执行 skill `areamatrix-plan-sync`，勿要求用户输入本斜杠。

按该 skill 完成：不少于 3 步的任务建 `.cursor/plans/` 文件、步骤完成即更新状态、全部完成后删除 plan 文件；不写 `tasks/` 与 workflow execution。
