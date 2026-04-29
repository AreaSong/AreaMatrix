# C2-12 classifier-correction

## 服务的 UX 页面

- S2-16 classifier-correct

## Core API

- 计划新增：`correct_file_category(repo_path, file_id, category, remember) -> FileEntry`

## 输入

- file_id、目标分类、是否记住规则。

## 输出

- 更新后的 FileEntry 和可选规则草稿。

## DB 变化

- 更新文件分类。
- 写 change log。

## 文件系统变化

- 按单文件改分类规则移动或只改索引。

## 错误码

- `Classify`
- `Conflict`
- `Io`
- `Db`

## 验收标准

- 纠错本身不等于保存全局规则。
- 记住规则必须进入规则保存/预览流程。
- 不覆盖目标目录同名文件。

## 延后范围

- AI 分类建议属于 Stage 3。
