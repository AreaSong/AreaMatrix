# 4-3/task-11: C4-11 desktop-main-query

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Windows/Linux 主窗口真实数据查询闭环。

## 绑定

- Core 能力：C4-11 desktop-main-query
- UX 页面：S4-WIN-02, S4-LNX-02

## 核对清单

1. 主窗口列表、分类、搜索和空态复用 Core query 语义。
2. Windows 与 Linux UI 不依赖 macOS 专属桥接类型。
3. 仓库断开、DB 错误和文件缺失状态可展示。
4. 查询路径不会修改文件系统。

## 完成标准

- S4-WIN-02 和 S4-LNX-02 都由真实 Core 数据驱动。
- 跨平台主窗口行为和 macOS MVP 保持一致。

## 验证

```bash
./scripts/check-all.sh
```

