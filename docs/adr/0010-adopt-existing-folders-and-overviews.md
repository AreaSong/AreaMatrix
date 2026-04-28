# ADR-0010: 接管已有目录与专属概览文件

> AreaMatrix 支持把任意非空目录接管为资料库，并默认将自动概览写入 `.areamatrix/generated/`；不自动写入或覆盖 `README.md`。
>
> 状态：Accepted
> 日期：2026-04-28
> 影响范围：product / core / macos-app / overview / tree / storage
> 取代： [ADR-0007](0007-readme-granularity.md)

## 上下文

AreaMatrix 最初假设用户创建一个新的 `~/AreaMatrix/` 资料库，并由应用自动维护根目录与分类目录的 `README.md`。这个假设对“从零开始整理”成立，但对更真实的使用场景不够安全：

- 用户可能已经有一个目录，例如 `/1/1/1/`，里面有多年文件积累
- 该目录可能包含 GitHub 项目、已有 `README.md`、`.git/`、源码、文档和素材
- 用户希望 AreaMatrix 给这个目录加一层索引和导航，而不是改造它的原始结构
- 自动改写 `README.md` 会覆盖或污染项目自己的入口文档

## 决定

1. **任意目录都可作为资料库根**  
   用户可以选择空目录，也可以选择非空目录。非空目录进入 “Adopt existing folder（接管已有目录）” 流程。

2. **接管已有目录是只索引行为**  
   首次接管只创建 `.areamatrix/` 内部结构、初始化 SQLite、扫描现有文件并写入索引。不得移动、重命名、删除或覆盖已有用户文件。

3. **自动概览默认写入内部目录**  
   默认输出：

   ```text
   <repo>/.areamatrix/generated/root.md
   <repo>/.areamatrix/generated/categories/<slug>.md
   ```

4. **根目录可选 `AREAMATRIX.md`**  
   用户在设置中显式开启后，应用可以维护：

   ```text
   <repo>/AREAMATRIX.md
   ```

   若文件已有 AreaMatrix 标记块，只替换标记块；若没有标记块，只能在用户确认后追加托管段。

5. **永不自动写入或覆盖 `README.md`**  
   `README.md` 与 `*/README.md` 一律视为普通用户/项目文件。AreaMatrix 不把它作为自动输出目标，也不插入标记块。

## 理由

1. **贴近真实使用**：用户往往不是从空文件夹开始，而是想让现有文件夹变得可导航。
2. **安全边界清晰**：`.areamatrix/` 是应用内部空间；用户原目录结构是用户空间。
3. **避免破坏 GitHub 项目**：`README.md` 在代码仓库中有明确语义，应用不应抢占。
4. **仍保留外部可读性**：`.areamatrix/generated/*.md` 与可选 `AREAMATRIX.md` 都是普通 Markdown。
5. **利于卸载与迁移**：删除 `.areamatrix/` 不影响任何用户文件。

## 考虑过的备选

### A. 继续维护 `README.md`

- 优点：GitHub / VSCode 默认入口可见
- 缺点：容易覆盖或污染已有项目文档
- 为什么没选：与“接管已有目录不破坏内容”的原则冲突

### B. 完全不生成 Markdown 概览

- 优点：文件系统最干净
- 缺点：不用 App 就看不到任何导览
- 为什么没选：削弱本地优先和可迁移价值

### C. 每个目录生成 `AREAMATRIX.md`

- 优点：进入任何目录都有可见概览
- 缺点：仍会污染大量现有目录
- 为什么没选：默认只在 `.areamatrix/generated/` 生成，根目录入口交给用户选择

## 后果

### 正面

- 可以安全接管非空目录
- 不会误改用户或项目已有 `README.md`
- 资料库结构更适合代码仓库、研究资料、长期归档目录
- 概览产物边界清晰，便于过滤、重建和删除

### 负面 / 代价

- 默认概览不在目录根部直接可见，需要 App 或打开 `.areamatrix/generated/`
- `AREAMATRIX.md` 相比 `README.md` 不会被 GitHub 默认渲染为项目首页
- tree / reindex / watcher 需要明确过滤 AreaMatrix 自身生成文件

## 何时重审

- 大量用户明确希望根目录有默认可见概览
- `AREAMATRIX.md` 命名被证明不直观
- Stage 2/3 加入发布/导出功能，需要把概览同步到公开文档站

## Related

- [../product/prd.md](../product/prd.md)
- [../product/user-stories.md](../product/user-stories.md)
- [../ux/first-launch.md](../ux/first-launch.md)
- [../modules/overview-gen.md](../modules/overview-gen.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
