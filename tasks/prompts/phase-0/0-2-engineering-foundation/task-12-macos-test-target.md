# 0-2/task-12: macOS test target 空壳

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

macOS test target 空壳。

## 绑定

- 无特定 UX/Core 绑定；工程骨架或稳定性任务。

## 核对清单

1. 创建最小测试 target。
2. 测试只验证 app shell/bridge 可加载。
3. 不伪造页面闭环通过。

## 完成标准

- xcodebuild test 可运行或明确记录环境限制。

## 验证

```bash
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```
