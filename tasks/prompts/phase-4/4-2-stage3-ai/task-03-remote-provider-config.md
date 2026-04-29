# 4-2/task-03: C3-03 remote-provider-config

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现远程 AI provider 配置合同，包括启用确认、凭据引用和连接测试。

## 绑定

- Core 能力：C3-03 remote-provider-config
- UX 页面：S3-03

## 核对清单

1. 远程 provider 默认 disabled，必须通过显式配置开启。
2. API key 或 token 不以明文写入普通配置或日志。
3. 连接测试只发送最小探测请求，不发送用户文件内容。
4. 关闭远程 provider 后后续 AI 调用必须回到本地或不可用状态。

## 完成标准

- S3-03 能完成真实远程 provider 配置、测试和关闭。
- 隐私承诺和最小发送原则可被测试证明。

## 验证

```bash
./scripts/check-all.sh
```

