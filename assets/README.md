# AreaMatrix Assets

本目录只放项目级静态资产和视觉原型，不承载应用源码、构建产物或运行状态。

## 目录

- `brand/`：AreaMatrix 品牌资产。`brand/final/` 是权威可引用版本，`brand/archive/` 只保留历史探索稿。
- `prototypes/`：landing 页面、workspace mockup 等视觉原型。它们用于展示、讨论和回溯，不是产品、架构或 API 源事实。

## 约定

- 新增品牌素材优先放入 `brand/`，并同步更新 [brand/README.md](brand/README.md)。
- 新增视觉原型优先放入 `prototypes/`，并在原型目录内说明用途、入口和是否仍有效。
- 构建输出、导出缓存、截图草稿和个人工具产物不要放入本目录。
- 应用 bundle 资源应从权威资产派生到对应平台目录，不直接依赖历史探索稿。
