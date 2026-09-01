# AreaMatrix 品牌视觉规范

> 本文定义 AreaMatrix Logo、颜色、字标、留白、最小尺寸和交付文件的使用规则。
>
> 阅读时长：约 6 分钟。

---

## 品牌资产源事实

可对外引用的品牌资产统一位于 `assets/brand/final/`。SVG 是可缩放源文件，PNG、ICO、ICNS、PDF 和 TIFF 是由 SVG 派生的交付文件。历史探索稿位于 `assets/brand/archive/`，不得用于产品、文档、发布或宣传。

机器可读的交付矩阵位于 `assets/brand/brand-manifest.json`，字体输入、派生 hash 和 archive 证据状态位于
`assets/brand/provenance.json`。manifest 明确只允许 `assets/brand/final/` 进入产品或发布包，并排除
`assets/brand/archive/`。修改 SVG 后运行：

```bash
python3 scripts/brand/export_assets.py --refresh
python3 scripts/brand/validate_assets.py
```

## 标志构成

AreaMatrix 标志由矩阵面板、归档轨迹和四个节点构成：

- 矩阵面板表达可扫描、可导航的资料结构。
- 青绿色轨迹表达文件进入资料库后的可追踪路径。
- 琥珀和珊瑚节点表达分类、确认与最终落位。
- `AreaMatrix` 字标采用 Inter Bold `Version 3.019;git-0a5106e0b` 的轮廓字形；精确输入对象固定到
  `linagora/tmail-flutter@0e6c107f63e4fd35615605b718963ffa6b2897a4:assets/fonts/Inter/Inter-Bold.ttf`，
  `rsms/inter@0a5106e0bde18df09374066bf3a7998e3546307d` 是上游谱系。许可证为 OFL-1.1，跨环境分发应使用
  `outlined` 文件。

## 标准颜色

| Token | 色值 | 用途 |
|---|---:|---|
| Deep Ink | `#0A201E` | 深色背景、暗色 App Icon 底色 |
| Forest Ink | `#173A33` | 浅色背景主文字、深色端点 |
| Trace Teal | `#15B49F` | 主轨迹、Matrix 字标 |
| Trace Mint | `#37CAB6` | 主轨迹中间色 |
| Signal Amber | `#F1B84E` | 分类与确认节点 |
| Signal Coral | `#E96D5A` | 终点与强调节点 |
| Paper | `#F4FBF8` | 深色背景文字和浅色图形 |
| Mist | `#EEF7F3` | 浅色展示背景 |
| Grid | `#CFE3DD` | 矩阵点阵与辅助轨迹 |

不得把主标志整体改成未经定义的单一品牌色。单色场景只能使用正式 `mono` 文件。

## 资产选择

| 场景 | 推荐文件 |
|---|---|
| macOS App Icon | `native/macos/AreaMatrix.icns` 或现有 Icon Composer 资源 |
| Windows 可执行文件 | `native/windows/AreaMatrix.ico` |
| iPhone、iPad、App Store | `native/ios/AreaMatrixAppIcon.appiconset/` |
| Android adaptive icon | `native/android/res/` |
| 浅色页面横向 Logo | `areamatrix-logo-lockup-outlined-light.svg` |
| 深色页面横向 Logo | `areamatrix-logo-lockup-outlined-dark.svg` |
| 仅允许单色的浅色背景 | `areamatrix-logo-lockup-mono-dark.svg` |
| 仅允许单色的深色背景 | `areamatrix-logo-lockup-mono-light.svg` |
| 紧凑导航或头像 | `areamatrix-logo-symbol-dark.svg` 或 `areamatrix-logo-symbol-light.svg` |
| 只有文字的页眉 | `areamatrix-wordmark-dark.svg` 或 `areamatrix-wordmark-light.svg` |
| 方形宣传版式 | `areamatrix-logo-stacked-dark.svg` 或 `areamatrix-logo-stacked-light.svg` |
| GitHub、社交分享 | `social/areamatrix-social-preview-*.png` |
| 印刷与制作 | `print/` 下的 outlined SVG、PDF 或 CMYK TIFF |

文件名中的 `dark` 和 `light` 表示该资产的设计变体，不足以单独判断背景。使用前应按照上表选择，并通过实际背景对比检查可读性。

## 留白与最小尺寸

- Logo 四周至少保留 Logo Mark 宽度的 `12.5%` 作为安全留白。
- 横向 Lockup 不得小于 `160px` 宽；印刷不得小于 `42mm` 宽。
- 独立 Mark 或 Symbol 不得小于 `24px`；印刷不得小于 `8mm`。
- `16/32/48px` 必须使用 small App Icon 源文件生成的导出，不得缩放完整复杂图标代替。
- Social Preview 必须保持 `1200x630`，不得裁掉轨迹端点或字标。

## 背景与对比

- 浅色背景使用深色文字和浅色图标设计；深色背景使用反白文字和深色图标设计。
- 彩色 Symbol 保持透明背景，不得人为添加不规则底板。
- App Icon、opaque icon 和 maskable icon 的透明规则不同，不得互相替换。
- 照片或复杂纹理上使用 Logo 时，应先提供足够对比的完整色块区域。

## 禁止用法

- 不拉伸、压缩、旋转或改变 Logo Mark 与字标的比例。
- 不移动、删除或重新着色轨迹节点。
- 不给 outlined 字标替换字体，也不对字距做局部调整。
- 不把 archive 中的探索稿用于正式界面或分发。
- 不覆盖用户内容来展示品牌素材。
- 不暗示 AreaMatrix Logo 已注册为商标。
- 联名、外部再分发和商业授权需由 AreaMatrix 维护者确认。

## 派生与验证

`assets/brand/final/` 是权威资产目录。macOS Asset Catalog、Icon Composer 和 Windows 工程中的品牌文件是受控副本，由 manifest 校验哈希一致性。导出工具需要 macOS 自带的 `sips`、`iconutil`，并使用 Pillow 处理 PNG、ICO 和 CMYK TIFF。

Pillow 版本固定在 `scripts/brand/requirements.txt`。新环境可通过以下命令准备独立工具环境：

```bash
python3 -m venv .brand-venv
.brand-venv/bin/pip install --only-binary=:all: --require-hashes \
  --requirement scripts/brand/requirements.txt
```

`scripts/brand/generate_wordmark_outlines.swift` 只用于品牌字形重新定稿。日常导出不需要字体文件，因为最终 SVG
已经保存为路径。`assets/brand/provenance.json` 的技术证据不能替代合格许可证复核；在复核字体分发义务和最终
发布包之前，品牌 provenance 必须保持 `releaseEligible: false`。archive 资产因来源和授权未建立而保持
`evidence-blocked`，不得通过复制、改名或重新导出进入 `final/`。

## Related

- [README](README.md)
- [../README.md](../README.md)
- [../../assets/brand/README.md](../../assets/brand/README.md)
