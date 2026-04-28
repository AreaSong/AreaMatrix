# 0-2/task-02: Build Scripts 与 CI 校准

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-0.md`

## 范围

补齐 `scripts/` 构建入口，并校准 GitHub Actions 与文档中的构建流程。

## 核对清单

1. `scripts/build-core.sh` 按文档完成 Rust 双架构构建、lipo 和 Swift bindings 输出。
2. `scripts/update-bindings.sh` 只负责重新生成 bindings 或委托 build 脚本。
3. 可选新增 `scripts/check-all.sh`，串联 prompt、Rust、Swift 检查。
4. `.github/workflows/core-ci.yml` 和 `macos-ci.yml` 与实际路径一致。

## 完成标准

- 文档中的命令能对应到真实脚本。
- CI 不引用不存在或错误的工作目录。

## 验证

```bash
bash -n scripts/build-core.sh
bash -n scripts/update-bindings.sh
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
```

