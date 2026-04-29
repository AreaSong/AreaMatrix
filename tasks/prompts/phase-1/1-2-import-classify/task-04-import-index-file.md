# 1-2/task-04: C1-08 import-index-file

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现单文件 Index 导入闭环，只索引外部路径，不复制、不移动源文件。

## 绑定

- Core 能力：C1-08 import-index-file
- UX 页面：S1-17, S1-19, S1-20, S1-21, S1-27

## 核对清单

1. `import_file(mode=Indexed)` 保留源文件原路径。
2. DB 记录 `storage_mode=Indexed` 和 `source_path`。
3. 读取源文件 metadata/hash，但不写最终副本。
4. 源路径缺失时返回结构化错误。

## 完成标准

- Indexed 模式导入后源文件不变，资料库不生成副本。
- 列表和详情能展示 indexed 文件。
- 外部源丢失时能通过 `FileNotFound` 或等价状态反馈 UI。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace import_index_file
```
