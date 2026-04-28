# 2-2/task-03: Overview Generation

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-2.md`

## 范围

实现 `.areamatrix/generated/` 自动概览，以及可选根目录 `AREAMATRIX.md`。

## 核对清单

1. 导入、删除、重命名、移动后触发概览再生成。
2. 默认只写 `.areamatrix/generated/`。
3. 可选 `AREAMATRIX.md` 时保留用户区域。
4. 不读取改写或覆盖用户已有 `README.md`。
5. 中英 locale 输出与文档一致。

## 完成标准

- 概览生成不破坏用户文件。
- 生成内容有测试覆盖。

## 验证

```bash
cd core
cargo test --workspace overview
```

