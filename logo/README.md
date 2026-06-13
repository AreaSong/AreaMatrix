# AreaMatrix Brand Assets

本目录存放 AreaMatrix 品牌视觉资产。**唯一启用版本在 `final/`**，其余为历史探索稿，不参与构建或对外引用。

## 目录结构

```text
logo/
├── final/                 # 权威源（canonical）
│   ├── areamatrix-app-icon-dark.svg
│   ├── areamatrix-app-icon-light.svg
│   ├── areamatrix-logo-lockup.svg
│   ├── areamatrix-logo-lockup-light.svg
│   ├── areamatrix-logo-lockup-dark.svg
│   ├── areamatrix-logo-mark-light.svg
│   ├── areamatrix-logo-mark-dark.svg
│   ├── areamatrix-logo-mark-mono-dark.svg
│   ├── areamatrix-logo-mark-mono-light.svg
│   ├── app-icon/          # App Icon 各尺寸 PNG 导出
│   ├── lockup/            # 横版 lockup PNG 导出
│   └── mark/              # 单独 logo mark PNG 导出
└── archive/               # 历史草稿，不启用
    ├── early-drafts/
    ├── v2/
    ├── v3/
    └── v4/
```

## 使用约定

| 场景 | 引用路径 |
|------|----------|
| App Icon 深色设计 | `logo/final/areamatrix-app-icon-dark.svg` 或 `logo/final/app-icon/*-dark-*` |
| App Icon 浅色设计 | `logo/final/areamatrix-app-icon-light.svg` 或 `logo/final/app-icon/*-light-*` |
| 横版 Logo 深色背景版本 | `logo/final/areamatrix-logo-lockup-dark.svg` 或 `logo/final/lockup/*-dark-*` |
| 横版 Logo 浅色背景版本 | `logo/final/areamatrix-logo-lockup-light.svg` 或 `logo/final/lockup/*-light-*` |
| 横版 Logo 默认设计 | `logo/final/areamatrix-logo-lockup.svg` 或 `logo/final/lockup/areamatrix-logo-lockup-1600x520.png` |
| 单独 Logo Mark 深色设计 | `logo/final/areamatrix-logo-mark-dark.svg` 或 `logo/final/mark/*-dark-*` |
| 单独 Logo Mark 浅色设计 | `logo/final/areamatrix-logo-mark-light.svg` 或 `logo/final/mark/*-light-*` |
| 单色 Mark 深色设计 | `logo/final/areamatrix-logo-mark-mono-dark.svg` 或 `logo/final/mark/*-mono-dark-*` |
| 单色 Mark 浅色设计 | `logo/final/areamatrix-logo-mark-mono-light.svg` 或 `logo/final/mark/*-mono-light-*` |
| 应用 bundle 内资源 | 从 `final/` 派生复制到 `apps/macos/AreaMatrix/Resources/Assets.xcassets/`，不直接引用 `archive/` |

## 尺寸说明

`final/app-icon/` 中的 PNG 按设计版本和边长命名（例如
`areamatrix-app-icon-dark-1024.png`、`areamatrix-app-icon-light-1024.png`）。
日常引用优先 1024 及以下；4096 / 8192 为高清母版导出，不打包进应用 bundle。
macOS asset catalog 内仍使用 Xcode 约定的 `app-icon-*` 文件名，由深色设计版本派生。

macOS app 另有 `apps/macos/AreaMatrix/Resources/AppIcon.icon`，这是 Xcode
Icon Composer 格式的 App Icon 输入。它使用 `areamatrix-app-icon-light-1024.png`
作为默认外观，使用 `areamatrix-app-icon-dark-1024.png` 作为深色外观；
传统 `AppIcon.appiconset` 保留为可构建兼容资源，不在其中硬塞 `luminosity`
变体，因为当前 Xcode 会把传统 macOS 多尺寸槽位里的深色重复项判为未分配资源。

`final/lockup/` 中的 PNG 当前导出为 `1600x520`，对应 macOS asset catalog 中
的 `AreaMatrixLogoLockup*` 资源。`AreaMatrixLogoLockup` 是自动深浅色适配资源：
浅色界面默认使用浅色背景版本，深色界面使用深色背景版本；`AreaMatrixLogoLockupDark`
和 `AreaMatrixLogoLockupLight` 用于需要强制指定背景版本的场景。

`final/mark/` 中的 PNG 按设计版本和边长命名。`dark` / `light` 是彩色 mark
的深浅设计版本；`mono-dark` / `mono-light` 是单色版本。对应 macOS asset catalog
中的 `AreaMatrixLogoMark*` 资源；`AreaMatrixLogoMark` 会随系统深浅色自动切换：
浅色界面默认使用深色设计，深色界面使用浅色设计。

## archive/

`archive/` 内为设计迭代过程中的探索稿，仅供回溯参考。任何 README、UI、CI 或发布流程不得引用此目录。
