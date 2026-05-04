# v2 Plans

Plans are docs-change ledgers generated from `changes/*.yaml`.

They track:

- exact docs file and line ranges
- heading and excerpt used for drift detection
- what docs changed and why
- feature and docs dependencies
- existing / expected / test code impact
- task split and queue readiness

Use:

```bash
./dev workflow plan --version v2
./dev workflow plan --version v2 --write
```
