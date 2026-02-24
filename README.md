# scoop-bucket

Central Scoop bucket for projects maintained under `trajano/*`.

This repository updates manifests from upstream GitHub releases using GitHub Actions.
It is generic: add more entries in `projects.json` and the same workflow will update them.

## Add this bucket to Scoop

Run these commands in PowerShell:

```powershell
scoop bucket add trajano https://github.com/trajano/scoop-bucket
scoop install trajano/aliae
```

To update installed apps:

```powershell
scoop update
scoop update aliae
```

## Current flow

- Scheduled workflow checks latest releases for configured source repositories.
- Manual workflow dispatch can update all projects or one project/version.

## Add a project

1. Add a new object to `projects.json` under `projects`.
2. Set:
   - `id`: short manifest id.
   - `sourceRepo`: owner/repo where releases are published.
   - `manifest`: output path in this bucket (for example `bucket/tool.json`).
   - `architectures`: each architecture with asset filename and release URL template.
3. Commit to `master`.
4. Run the workflow manually once to initialize the manifest.