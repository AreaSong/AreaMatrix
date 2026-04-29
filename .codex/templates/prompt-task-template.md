# <task-label>: <task-title>

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> Manifest：`tasks/prompts/_shared/manifests/<phase>.md`

## 范围

### 必须阅读文档

- `docs/...`

### 允许路径

- `...`

## 核对清单

1. ...
2. ...
3. ...

## 完成标准

- ...

## 验证

```bash
...
```

## 验收提醒

任务完成后运行：

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py verify --task <task-label>
```

