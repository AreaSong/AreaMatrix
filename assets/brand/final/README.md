# AreaMatrix Final Brand Assets

本目录是 AreaMatrix 可对外引用的完整品牌交付包。

## 内容

- 根目录 SVG：App Icon、small、opaque、maskable、Mark、Symbol、Lockup、outlined、mono、Wordmark 和 Stacked 源文件。
- `app-icon/`：深浅两套常规、opaque 和 maskable PNG。
- `mark/`、`symbol/`：彩色与单色图形 PNG。
- `lockup/`、`wordmark/`、`stacked/`：常用 Logo 组合 PNG。
- `favicon/`：`16/32/48` PNG 和多尺寸 ICO。
- `social/`：`1200x630` 的默认、深色和浅色分享图。
- `native/`：macOS、iOS、Android 和 Windows 原生图标交付。
- `print/`：outlined SVG、矢量 PDF 和 300 DPI CMYK TIFF。
- `areamatrix-brand-overview.png`：`1600x1200` 品牌资产总览。

## 生成与校验

```bash
python3 scripts/brand/export_assets.py --refresh
python3 scripts/brand/validate_assets.py
```

品牌使用规则见 [`docs/ux/brand-assets.md`](../../../docs/ux/brand-assets.md)。
