# AreaMatrix Native Icons

本目录保存从 canonical opaque icon 和透明 Symbol 生成的原生平台图标。

- `macos/AreaMatrix.icns` 与 `.iconset`：macOS 通用交付包；应用工程继续使用 Icon Composer 和 Asset Catalog。
- `ios/AreaMatrixAppIcon.appiconset/`：iPhone、iPad 和 App Store marketing 图标。
- `android/res/`：Android adaptive icon 前景、背景和 XML。
- `windows/AreaMatrix.ico`：包含 `16/24/32/48/64/128/256` 尺寸。

修改品牌源文件后运行 `python3 scripts/brand/export_assets.py --refresh`，再运行 `python3 scripts/brand/validate_assets.py`。
