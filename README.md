# ci (plexus-ms/ci)

Reusable GitHub Actions workflows for Plexus apps (PLEXUS.md §5) — the Paved
Road's CI/CD building blocks, referenced by tag from every tenant repo:

| Workflow | What |
|---|---|
| `.github/workflows/ci.yml` | App CI: biome → typecheck → test → build & push image to the caller's GHCR namespace, tagged with the git SHA. |
| `.github/workflows/deploy.yml` | Mounts the stateless deploy verb (`plexus-ms/library` `scripts/deploy.sh`) on the push event; the tenant supplies host + SSH key. |

This repo deliberately has **no CI of its own** — it only houses workflows
called via `workflow_call`. GitHub requires callable workflows to live under
`.github/workflows/`; that is why they are not at the repo root.

Consumers pin a version tag:

```yaml
jobs:
  ci:
    uses: plexus-ms/ci/.github/workflows/ci.yml@v1
    with: { app: <name> }
```

Fix once → move the tag → every tenant picks it up (PLEXUS.md §6).
