# Third-Party Notices

本文件是 AreaMatrix 源码和技术构建材料中的第三方归属索引。它说明仓库已登记的来源、版本和许可证文本位置，
不等于法律意见、许可证签核、发布批准或对所有最终制品内容的完整证明。

## Project License

AreaMatrix 自有代码按仓库根目录的 [PolyForm Noncommercial 1.0.0](LICENSE) 发布。第三方组件不自动继承
该项目许可证；每个组件仍受其自身许可证和适用归属义务约束。

## Registered Third-Party Materials

| Material | Version / source | License evidence | Scope |
|---|---|---|---|
| Pillow | `12.3.0`, PyPI, hash-locked in `scripts/brand/requirements.txt` | [MIT-CMU text](licenses/MIT-CMU-Pillow.txt) | Brand tooling and CI only; not app/Core runtime |
| Inter Bold input | `Version 3.019;git-0a5106e0b`; exact blob `linagora/tmail-flutter@0e6c107f63e4fd35615605b718963ffa6b2897a4:assets/fonts/Inter/Inter-Bold.ttf`; `rsms/inter@0a5106e0bde18df09374066bf3a7998e3546307d` upstream lineage | [OFL-1.1 text](licenses/OFL-1.1-Inter.txt) | Historical input for outlined wordmark; final package contains outlines; qualified license review remains required |
| Contributor Covenant | 2.1, commit recorded in `CODE_OF_CONDUCT.md` | [CC BY 4.0 text](licenses/CC-BY-4.0-Contributor-Covenant.txt) | Adapted community document |
| Mozilla consequence ladder reference | Commit recorded in `CODE_OF_CONDUCT.md` | [MPL-2.0 text](licenses/MPL-2.0-Mozilla-Inclusion.txt) | Adapted community document reference |
| Rust/Cargo metadata | Exact versions and checksums from `core/Cargo.lock` | Package-level license expressions are emitted into artifact-specific SBOM/notices | Current checkout target projection; not artifact contents |

## Brand Asset Boundary

`assets/brand/final/` is the only brand root eligible for product or release packaging. The 16 files under
`assets/brand/archive/` are historical design material. Their per-file hashes are frozen in
[`assets/brand/provenance.json`](assets/brand/provenance.json), but owner, original source and authorization are
not established; every archive entry is therefore `evidence-blocked` and excluded from release materials.

## Artifact-Specific Release Materials

For each concrete release artifact, `scripts/dev_tools/supply_chain.py` generates:

- CycloneDX 1.5 `sbom.cdx.json` bound to the artifact SHA-256 and current-checkout target-filtered Cargo metadata;
- artifact-specific `THIRD_PARTY_NOTICES.md` with the release hash and component table;
- `source-offer.json` describing the source snapshot and technical offer;
- every regular file under repository `licenses/`, copied under the same path and bound by a SHA-256 entry in
  `release-manifest.json`; and
- `release-manifest.json` binding the material hashes and brand provenance hash.

Generation always records `legalReviewComplete: false`. The release workflow remains blocked until a qualified
external review record, scoped to `licenses`, `notices`, and `source-offer`, matches the exact release and artifact
hash and the `release-manifest.json` hash. A generated inventory or a repository-level notice must never be presented
as that review record. The generated dependency table is based on the current checkout's locked, target-filtered Cargo
metadata and, for Windows targets, `packages.lock.json`; it is not an inspection of the artifact contents. NuGet
`NOASSERTION` entries mean the lock file does not carry license metadata. These records do not prove artifact-to-commit
provenance, absence of additional components or archived brand assets, signing, notarization, legal approval, or
source-offer sufficiency.

## Review Status

Technical attribution and hash evidence are maintained in the repository. License compatibility, attribution sufficiency,
source-offer terms, final package inspection and distribution approval remain external review obligations.

## Related

- [Dependency policy](docs/development/dependency-policy.md)
- [Release process](docs/development/release.md)
- [Brand provenance](assets/brand/provenance.json)
