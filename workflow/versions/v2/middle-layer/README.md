# v2 Middle-layer

Middle-layer ledgers are feature-level implementation intent records.

They connect docs discussion to executable workflow planning:

```text
docs discussion
-> middle-layer/*.yaml
-> changes/*.yaml
-> plans
-> drafts
-> queue
-> promotion preview
```

Each feature ledger records Exact Docs line references, insertion points, related
feature links, code impact, dependencies, slice plan, risk boundaries, and
acceptance inputs. It is a review artifact and must not write live
`tasks/prompts/**` or `progress.json`.
