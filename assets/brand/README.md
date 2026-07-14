# AreaMatrix Brand Assets

本目录保存 AreaMatrix 品牌资产。`final/` 是唯一可用于产品、文档、发布和宣传的权威目录；`archive/` 只用于设计回溯。

## 目录结构

```text
assets/brand/
├── brand-manifest.json       # 机器可读交付矩阵
├── wordmark-outlines.json    # Inter Bold 字标轮廓数据
├── final/
│   ├── *.svg                 # canonical 矢量源文件
│   ├── app-icon/             # 常规、opaque、maskable PNG
│   ├── favicon/              # 16/32/48 PNG 与 ICO
│   ├── lockup/               # 横向 Logo PNG
│   ├── mark/                 # 彩色与单色 Mark PNG
│   ├── native/               # macOS/iOS/Android/Windows 图标
│   ├── print/                # SVG/PDF/CMYK TIFF
│   ├── social/               # 1200x630 社交预览
│   ├── stacked/              # 竖向 Logo PNG
│   ├── symbol/               # 透明彩色 Symbol PNG
│   └── wordmark/             # 纯字标 PNG
└── archive/                  # 历史探索稿，禁止正式引用
```

## 资产矩阵

| 类型 | 内容 |
|---|---|
| App Icon | 深浅 SVG；`16/32/48/64/128/180/192/256/512/1024/4096/8192` PNG |
| Small Icon | 深浅 SVG；用于 `16/32/48` 导出 |
| Opaque Icon | 深浅 SVG；不透明 `180/1024` PNG |
| Maskable Icon | 深浅 SVG；全出血 `192/512` PNG |
| Logo Mark | 彩色与单色深浅 SVG；`256/512/1024` PNG |
| Logo Symbol | 透明彩色深浅 SVG；`256/512/1024` PNG |
| Horizontal Lockup | 默认、深色、浅色、outlined、mono SVG 与 `1600x520` PNG |
| Wordmark | 深浅 outlined SVG 与 `1200x336` PNG |
| Stacked Logo | 深浅 SVG 与 `1024x1024` PNG |
| Favicon | `16/32/48` PNG 与多尺寸 ICO |
| Social Preview | 默认、深色、浅色 SVG 与 `1200x630` PNG |
| Native | `.icns`、iOS AppIcon、Android adaptive icon、Windows ICO |
| Print | 浅色/深色背景 outlined SVG、PDF、300 DPI CMYK TIFF |
| Overview | `1600x1200` 品牌资产总览 |

## 应用内资源

macOS 应用使用以下两套资源：

- `apps/macos/AreaMatrix/Resources/AppIcon.icon`：Icon Composer 深浅 App Icon。
- `apps/macos/AreaMatrix/Resources/Assets.xcassets/`：兼容 AppIcon、Lockup、Mark 和 Mono Mark。

Windows 工程使用 `apps/windows/AreaMatrix/Resources/AreaMatrix.ico`。这些文件均为 `final/` 的受控副本，校验工具会检查 SHA-256 是否一致。

## 生成与校验

补齐缺失文件并同步应用副本：

```bash
python3 scripts/brand/export_assets.py
```

SVG 发生变化后全量重建：

```bash
python3 scripts/brand/export_assets.py --refresh
```

检查尺寸、透明度、SVG XML、ICO/ICNS、iOS slots、CMYK TIFF 和应用副本漂移：

```bash
python3 scripts/brand/validate_assets.py
```

补充 SVG 源由 `scripts/brand/build_source_assets.py` 从 canonical 几何和固化的字标轮廓生成。重新定稿字形时，才需要使用 `generate_wordmark_outlines.swift` 和明确授权的字体文件。

## 使用规范

完整颜色、字体、留白、最小尺寸、背景选择、禁止用法和授权边界见 [品牌视觉规范](../../docs/ux/brand-assets.md)。跨环境使用横向 Logo 时优先选择 `outlined` 文件，避免字体替换。

`archive/` 中的任何文件不得被 README、UI、CI 或发布流程引用。
