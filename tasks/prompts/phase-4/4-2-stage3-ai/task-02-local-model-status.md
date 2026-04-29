# 4-2/task-02: C3-02 local-model-status

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现本地 AI 模型状态检测与状态展示合同，不在本任务中下载或训练模型。

## 绑定

- Core 能力：C3-02 local-model-status
- UX 页面：S3-02

## 核对清单

1. 返回本地模型是否可用、版本、路径、最后检查时间和不可用原因。
2. 区分未安装、路径不可读、版本不兼容和运行时不可用。
3. 状态检测不得阻塞主窗口交互。
4. UI 可基于真实状态给出启用、修复或降级提示。

## 完成标准

- S3-02 能展示真实本地模型状态和错误态。
- 本地模型不可用时不会影响非 AI 核心功能。

## 验证

```bash
./scripts/check-all.sh
```

