# 4-3/task-01: C4-01 cross-platform-ffi-contract

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

整理并实现多端共享的 Core FFI 合同基线，确保 iOS、Windows、Linux 不各自发明 API。

## 绑定

- Core 能力：C4-01 cross-platform-ffi-contract
- UX 页面：S4-X-02

## 核对清单

1. UDL 暴露的类型、错误码和异步语义可被多端消费。
2. 平台专属能力通过 capability flags 表达，不进入 Core 平台分支。
3. 生成绑定流程对 iOS、Windows、Linux 有明确命令入口。
4. 破坏性 API 变化必须同步更新文档、manifest 和调用端。

## 完成标准

- 多端任务都有统一 FFI 合同可依赖。
- Core 不引入 macOS/iOS/Windows/Linux 专属依赖。

## 验证

```bash
./scripts/check-all.sh
```

