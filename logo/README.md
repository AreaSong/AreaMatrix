# AreaMatrix Brand Assets

本目录存放 AreaMatrix 品牌视觉资产。**唯一启用版本在 `final/`**，其余为历史探索稿，不参与构建或对外引用。

## 目录结构

```text
logo/
├── final/                 # 权威源（canonical）
│   ├── areamatrix-app-icon.svg
│   ├── areamatrix-logo-lockup.svg
│   ├── app-icon/          # App Icon 各尺寸 PNG 导出
│   └── lockup/            # 横版 lockup PNG 导出
└── archive/               # 历史草稿，不启用
    ├── early-drafts/
    ├── v2/
    ├── v3/
    └── v4/
```

## 使用约定

| 场景 | 引用路径 |
|------|----------|
| App Icon（macOS / 未来 iOS） | `logo/final/areamatrix-app-icon.svg` 或 `logo/final/app-icon/` 中对应尺寸 |
| 横版 Logo（README、About、发布页） | `logo/final/areamatrix-logo-lockup.svg` 或 `logo/final/lockup/` |
| 应用 bundle 内资源 | 从 `final/` 派生复制到 `apps/macos/AreaMatrix/Resources/Assets.xcassets/`，不直接引用 `archive/` |

## 尺寸说明

`final/app-icon/` 中的 PNG 按边长命名（128、256、512、1024 等）。日常引用优先 1024 及以下；4096 / 8192 为高清母版导出，不打包进应用 bundle。

## archive/

`archive/` 内为设计迭代过程中的探索稿，仅供回溯参考。任何 README、UI、CI 或发布流程不得引用此目录。
