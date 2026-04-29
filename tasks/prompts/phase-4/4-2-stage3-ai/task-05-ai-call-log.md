# 4-2/task-05: C3-05 ai-call-log

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 AI 调用日志能力，用于审计、隐私说明和问题排查。

## 绑定

- Core 能力：C3-05 ai-call-log
- UX 页面：S3-05

## 核对清单

1. 记录调用时间、provider、本地/远程、能力类型、状态、耗时和错误码。
2. 日志不得保存文件正文、密钥、完整 prompt 或可还原隐私内容。
3. 支持按时间、provider、能力类型和失败状态过滤。
4. 用户可清理 AI 调用日志，清理不影响文件元数据。

## 完成标准

- S3-05 可基于真实日志解释 AI 调用来源和结果。
- 日志内容满足最小化和脱敏要求。

## 验证

```bash
./scripts/check-all.sh
```

