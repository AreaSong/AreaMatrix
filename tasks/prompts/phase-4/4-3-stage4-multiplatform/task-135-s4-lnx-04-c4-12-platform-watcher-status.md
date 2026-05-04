# 4-3/task-135: S4-LNX-04 + C4-12 platform-watcher-status

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

实现 S4-LNX-04 watcher-status 中由 C4-12 platform-watcher-status 支撑的页面功能点。

## 绑定

- UX 页面：S4-LNX-04 watcher-status
- Core 能力：C4-12 platform-watcher-status
- 阶段：Stage 4 Multiplatform

## 核对清单

1. 只处理 S4-LNX-04 页面中的 C4-12 功能点。
2. 读取页面规格、Stage 4 Multiplatform control map、Core API 和 C4-12 能力规格。
3. 只接入 C4-12 对应的 CoreBridge / 状态 / 错误映射，不实现本页其他 Core 功能点。
4. 不顺手实现相邻页面、相邻平台或同页其他能力。

## 完成标准

- S4-LNX-04 中 C4-12 对应的用户可见功能可被触发和验收。
- 没有使用 mock、fixture 或静态状态伪造真实 Core 闭环。
- 未触碰 control map 之外的 Core 能力。

## 验证

```bash
./dev check all
```
