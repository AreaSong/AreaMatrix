# 安装与首次运行

> AreaMatrix 目前从源码构建。本指南说明所需环境、构建入口和首次启动后的安全选择。
>
> 阅读时长：约 6 分钟。

## 环境要求

- macOS 14 Sonoma 或更高版本。
- Xcode 15 或更高版本，并已安装命令行工具。
- Rust stable 1.75 或更高版本。
- Apple Silicon 或 Intel Mac。

## 获取源码

```bash
git clone <AreaMatrix repository URL>
cd AreaMatrix
```

仓库地址应替换为实际来源。不要从不可信来源运行构建脚本或安装产物。

## 构建 Core 与绑定

```bash
./dev build core
./dev bindings update \
  --udl core/area_matrix.udl \
  --out-dir apps/macos/AreaMatrix/Bridge/UniFFI
```

`bindings update` 会更新 Swift 使用的 UniFFI 绑定。不要手工编辑生成绑定中的业务逻辑。

## 构建 macOS 应用

```bash
xcodebuild \
  -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -destination 'generic/platform=macOS' \
  build CODE_SIGNING_ALLOWED=NO
```

也可以在 Xcode 中打开 `apps/macos/AreaMatrix.xcodeproj`，选择 `AreaMatrix` scheme 后运行。

## 首次启动

首次启动会引导选择资料库目录：

- 选择空目录时，可以创建新的资料库结构。
- 选择非空目录时，进入接管确认。
- 选择已经初始化的资料库时，应用读取配置和元数据后打开工作区。

接管非空目录前，确认界面应说明：应用只创建 `.areamatrix/` 内部状态，不移动、不重命名、不删除、不覆盖已有文件。

## 安装包状态

仓库尚未提供完成 Developer ID 签名、公证和干净 Mac 验证的正式安装包。从源码构建只证明本机工程可以构建和运行，不等同于正式分发验证完成。

## 下一步

- 新建或打开资料库：[创建和打开资料库](repositories.md)
- 使用已有目录：[接管已有目录](adopting-existing-folders.md)
- 开始导入：[导入文件](importing-files.md)

## Related

- [用户指南](README.md)
- [开发环境搭建](../development/setup.md)
- [构建与运行](../development/build.md)
- [发布流程](../development/release.md)
