# ADR-0006: 完整支持 iCloud Drive

> 资料库可放在 iCloud Drive 中，应用通过 NSFileCoordinator/NSFilePresenter 处理占位符与并发。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：apps/macos/Watcher / core/storage
> 关联 ADR：[0003 真相源](0003-source-of-truth-strategy.md)、[0005 FSEvents](0005-fsevents-listener.md)

## 上下文

很多 macOS 用户希望资料能跨设备同步（iPhone / iPad / 多 Mac）。iCloud Drive 是最自然的选择，但带来挑战：

- **占位符文件**：未下载的文件在 FS 看到的是 0 字节占位（`com.apple.icloud.placeholder`），打开会触发下载
- **延迟下载**：访问占位符 → iCloud 下载 → FSEvents 触发"修改"事件
- **冲突文件**：同名 `.icloud` 后缀文件、`Conflicted Copy of <name>` 复制版本
- **后台同步**：用户在 iPhone 改了文件，本地 FS 在用户不知情时被改

需要决定：

1. 是否支持 iCloud 路径作为仓库
2. 如果支持，怎么处理占位符（下载？跳过？）
3. 如何避免与 iCloud 后台同步的冲突

## 决定

**完整支持 iCloud Drive**：

- 用户可以选择 `~/Library/Mobile Documents/com~apple~CloudDocs/AreaMatrix/` 作为仓库
- 所有文件 IO 通过 **NSFileCoordinator** 协调，避免与 iCloud 守护进程并发
- 实现 **NSFilePresenter** 对占位符和并发变更敏感
- **占位符策略**：访问元数据（hash / size）时按需下载；用户未点击的文件不强制下载
- **冲突文件**：`<name> (Conflicted Copy of <Mac>).pdf` 自动识别 → 在 UI 标 `🟠 conflict`，用户决定保留哪个

## 理由

1. **用户预期**：Mac 用户视 iCloud 为标配，不支持 = 失去大量目标用户
2. **本地优先与云同步不矛盾**：iCloud 是 Apple 提供的同步层，应用仍是本地优先
3. **NSFileCoordinator 是 Apple 官方机制**：与 Finder、Pages、Keynote 等使用同一套机制，兼容性最好
4. **占位符按需下载**：避免用户首次配置就下载几 GB 数据
5. **冲突可见**：让用户知道有冲突而不是悄悄选一个

## 考虑过的备选

### A. 不支持 iCloud（仅本地路径）

- 优点：实现最简单
- 缺点：失去跨设备同步能力，用户体验差
- **为什么没选**：Mac 用户期望太强烈

### B. 支持 iCloud 但禁止占位符

启动时强制下载所有文件。

- 优点：避免占位符问题
- 缺点：用户磁盘占满风险高、首次配置时间极长
- **为什么没选**：用户体验差

### C. 集成 CloudKit 自己同步

不靠 iCloud Drive，自己用 CloudKit API 同步元数据 + 文件。

- 优点：完全控制同步行为、可以跨账号共享
- 缺点：
  - 实现复杂（需要 Apple Developer Program + CloudKit container 配置）
  - 用户需要登录 iCloud 账号且授权
  - 与 iCloud Drive 是两套体系，重复造轮子
- **为什么没选**：MVP 阶段实现成本太高，未来 Stage 3 可重审

### D. 支持但靠"用户避免冲突"

不做特殊处理，告诉用户"不要在多设备同时编辑"。

- 优点：实现简单
- 缺点：冲突无法消灭，迟早出现 Conflicted Copy
- **为什么没选**：把问题转嫁给用户，体验差

### E. 用 Dropbox / Google Drive 第三方同步

- 优点：跨平台
- 缺点：依赖用户已购买的服务，每个 SDK 不同
- **为什么没选**：MVP 聚焦 macOS + Apple 生态。Stage 3+ 可加

## 后果

### 正面

- 跨设备使用体验好
- 与 iOS 端（未来）天然打通
- 兼容 Apple 整体生态（Files App、Spotlight 等）

### 负面 / 代价

- **实现复杂度**：所有 FS 操作都要包 NSFileCoordinator，代码量增加 10-20%
- **延迟不可控**：占位符触发下载时延依赖 iCloud 速度
- **测试困难**：iCloud 行为难以本地模拟，需要真机 + iCloud 账号
- **冲突处理 UI**：需要专门的"冲突解决"界面（Stage 2）
- **错误模式增加**：`ICloudError`（未登录、配额不足、网络断）
- **FSEvents 噪声**：iCloud 后台拉取会产生大量事件（缓解：去抖 + InFlight 过滤）

### 风险

- iCloud 账号未登录时仓库无法访问 → 给清晰错误提示
- iCloud 服务故障时本地数据可能不一致 → 软删除保留 30 天
- 用户多 Mac 用同一仓库导致频繁冲突 → UI 提示"建议同时只在一台设备编辑"
- macOS 重大升级改变 iCloud API 行为（缓解：CI beta 测试 + 用户提前通知）

## 何时重审

- iCloud 冲突频率 > 10% 用户报告 → 评估更激进的本地写入策略
- Apple 推出新的 cloud sync API 比 NSFileCoordinator 更适合 → 评估迁移
- 加 iOS 端时，iOS 上 iCloud 行为不同（沙盒）→ 单独评估
- 用户开始要求多 cloud（Dropbox / Google Drive）→ 抽象 ICloudCoordinator 为通用 CloudCoordinator

## Related

- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [0003-source-of-truth-strategy.md](0003-source-of-truth-strategy.md)
- [0005-fsevents-listener.md](0005-fsevents-listener.md)
