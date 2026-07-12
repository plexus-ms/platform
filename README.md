# itops (plexus-ms/itops)

The Paved Road's shared ITOps building blocks (§ 7 PLX), referenced by
version tag from every tenant repo. Three artifact classes, one layering rule —
shared logic cores with thin, disposable mounts:

| Layer | Where | What |
|---|---|---|
| **Verbs** — the portable logic core | `scripts/` | Plain bash, hand-runnable with no forge at all: `./scripts/deploy.sh deploy@host app image`. All CI/CD logic lives here — this is what passes the degradation test. |
| **Wrappers** — thin GitHub mounts | `.github/workflows/` | `workflow_call` workflows that mount a verb on the forge's events: checkout, secrets plumbing, one invocation. Forge-specific, logic-free, disposable. |
| **Ansible collection** — the shared platform roles | `ansible/` | `plexus.itops`: base hardening, docker, caddy ingress, per-app deploy, alloy observability. Tenants bind these to their own inventory — a tenant playbook is to the roles what a wrapper is to a verb. |

One version tag (`v1`, …) governs all three classes atomically: a wrapper always
runs the verb from its own commit (`github.job_workflow_sha`), and tenants pin
the collection to the same tag. **Every change under `ansible/` must bump
`galaxy.yml` `version`** — SCM installs record that version, so a moved git tag
alone is a silent no-op on reinstall (`--force` also works).

| Workflow | What |
|---|---|
| `.github/workflows/ci.yml` | App CI: check → test → build & push image to the caller's GHCR namespace, tagged with the git SHA. |
| `.github/workflows/deploy.yml` | Mounts the deploy verb (`scripts/deploy.sh`) on the push event; the tenant supplies host + SSH key. |

This repo deliberately has **no CI of its own** — GitHub requires callable
workflows to live under `.github/workflows/`, which is why the wrappers are not
at the repo root.

Consumers pin the version tag:

```yaml
# .github/workflows/ci.yml (tenant app)
jobs:
  ci:
    uses: plexus-ms/itops/.github/workflows/ci.yml@v1
    with: { app: <name> }
```

```yaml
# infra/requirements.yml (tenant platform)
collections:
  - name: https://github.com/plexus-ms/itops.git#/ansible/
    type: git
    version: v1
```

Fix once → move the tag (+ bump `galaxy.yml`) → every tenant picks it up
(§ 8 PLX).
