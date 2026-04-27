# ADR-0002: FFI 工具选择 UniFFI

> 用 **UniFFI**（Mozilla）作为 Rust ↔ Swift / Kotlin / Python 的 FFI 工具。
>
> 状态：Accepted
> 日期：2026-04-26
> 影响范围：core / macos-app / 未来 android-app
> 关联 ADR：[0001 桌面技术栈](0001-tech-stack.md)

## 上下文

在 [ADR-0001](0001-tech-stack.md) 中已确定"Rust core + 各平台原生 Shell"。Rust 与 Swift 之间需要稳定、可维护的 FFI 通道。需求：

- **多语言支持**：Swift（macOS / iOS）+ 未来 Kotlin（Android）+ Python（CLI / 测试）
- **类型安全**：复杂类型（struct / enum / Option / Result）跨语言映射
- **错误透明传递**：Rust `Result<T, E>` 在 Swift 端表现为 `throws`
- **维护成本可控**：手写 C ABI 不可接受
- **异步支持**：未来要支持 Rust async ↔ Swift async/await

## 决定

采用 **UniFFI 0.28+**。Rust 端用 `uniffi` crate 暴露接口，UDL 文件定义跨语言契约，CI 自动生成 Swift / Kotlin bindings。

## 理由

1. **多语言一次定义多端生成**：UDL 一份 → Swift / Kotlin / Python / Ruby 四端 binding
2. **官方支持复杂类型**：struct / enum / record / interface / Option / Result / sequence / map
3. **错误自然映射**：Rust `[Error]` → Swift `throws` / Kotlin `throws` / Python `raise`
4. **生产环境验证**：Mozilla 在 Firefox Sync / Firefox Login / Glean 中大规模使用
5. **活跃维护**：每月有 release，issue 响应快
6. **支持 async**（0.25 起）：未来扩展时不用换工具

## 考虑过的备选

### A. swift-bridge

- 优点：Rust ↔ Swift 体验最丝滑、支持 async、性能稍优
- 缺点：
  - 仅支持 Swift，未来 Android 还要换工具
  - 社区比 UniFFI 小一个数量级
  - 类型映射不如 UniFFI 完整（如 enum with associated values 受限）
- **为什么没选**：单语言锁定与"未来跨端"冲突

### B. cbindgen + 手写 Swift wrapper

- 优点：性能最优、控制力最强
- 缺点：
  - 全手写 Swift 包装层，每加一个 Rust 函数要改 3 个地方
  - 复杂类型（enum、Option）要手动处理 tag
  - 每加一个平台要重做整套包装层
- **为什么没选**：维护成本不可接受，2-3 人小团队会被耗死

### C. flapigen-rs

- 优点：支持 Java / Swift / C++
- 缺点：
  - DSL 不如 UDL 直观
  - 文档少、社区小
  - 长期维护性存疑（commit 频率低）
- **为什么没选**：UniFFI 已覆盖同类需求且更活跃

### D. 直接 C ABI（`#[no_mangle] extern "C"`）

- 优点：零依赖、最稳定
- 缺点：
  - 所有类型必须降为 C 兼容（指针 / 长度 / 标签联合体）
  - String / Vec / Result 全部要手动序列化
  - 改一个签名 = 改 N 处代码
- **为什么没选**：开发效率太低，bug 风险高

### E. Mozilla Glean SDK 内部 FFI

- 优点：Mozilla 生产级
- 缺点：内部使用，不对外发布
- **为什么没选**：UniFFI 本身就是从 Glean 抽出来的对外版本

## 后果

### 正面

- UDL 一处改动，多端 binding 自动同步
- 错误处理跨语言一致，Swift 端可以直接 `try await`
- 文档齐全，新人加入按官方 user guide 即可上手
- 添加 Android 端时无需改 Rust 代码，只需多生成一份 Kotlin binding

### 负面 / 代价

- **0.x 版本**：UniFFI 仍未到 1.0，可能有破坏性变更
- **生成代码不可读**：debug 时要看生成的 Swift 文件，不如手写直观
- **构建步骤增加**：CI 中多一步 `uniffi-bindgen generate`
- **特殊 trait 有限制**：不支持 lifetime、不支持泛型、Trait object 限制多
- **callback 传 Swift → Rust 受限**：复杂回调需要包装为 Object

### 风险

- UniFFI 0.x 升级到 1.0 时可能要重构（缓解：版本锁定 + 升级时跑全量测试）
- 性能瓶颈场景（如 100MB 文件 hash）若发现 FFI 调用开销显著 → 改批量 API（缓解：[FFI 设计文档](../architecture/ffi-design.md)已规定）

## 何时重审

- UniFFI 6 个月以上无更新 → 评估迁移到 swift-bridge + 手写 Kotlin
- 性能 profile 显示 FFI 调用是瓶颈 → 评估部分热点改 cbindgen 直通
- 出现 swift-bridge 等价的多语言方案 → 重新对比

## Related

- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../api/core-api.md](../api/core-api.md)
- [0001-tech-stack.md](0001-tech-stack.md)
