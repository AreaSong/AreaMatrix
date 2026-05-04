# v2 Queue Candidates

Queue candidates describe which workflow drafts could later become executable tasks.

Use:

```bash
./dev workflow queue --version v2
./dev workflow queue --version v2 --write
```

While v1 is still running, v2 can produce queue candidates but must not promote
them into live `tasks/prompts/**`.
