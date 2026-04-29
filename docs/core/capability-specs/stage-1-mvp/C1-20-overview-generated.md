# C1-20 overview-generated

## 服务的 UX 页面

- S1-27 settings-repository
- S1-30 settings-advanced

## Core API

- `init_repo`
- `import_file`
- `update_config`
- 内部：overview regeneration

## 输入

- `OverviewOutput`
- 触发节点或分类。

## 输出

- `.areamatrix/generated/*.md`。
- 可选 `AREAMATRIX.md`，仅当配置显式允许。

## DB 变化

- 无强制写入；可通过 change log 记录 generated overview 更新。

## 文件系统变化

- 默认只写 `.areamatrix/generated/`。
- 不覆盖 `README.md`。
- 根 `AREAMATRIX.md` 只能由 `RootAreaMatrixFile` 配置开启。

## 错误码

- `PermissionDenied`
- `Io`
- `Config`

## 验收标准

- 默认导入后 generated overview 更新。
- 用户已有 `README.md` 不被触碰。
- 切换 overview 输出配置后行为与文档一致。

## 延后范围

- 多层 README 粒度和用户模板系统属于 Stage 2+。
