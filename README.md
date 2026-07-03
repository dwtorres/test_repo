# trunkbased-sandbox

A lightweight repo to **test the GitHub settings** behind our trunk-based
Databricks framework — rulesets, merge queue, the required CI Gate, three
environments, and tag-driven prod — with **dummy runs** (pure `echo`, no
Databricks, no Azure, no secrets). It runs on `ubuntu-latest` as-is and flips to
self-hosted runners with one variable.

## What it mirrors

| Real framework | Sandbox stand-in |
|----------------|------------------|
| CI on PRs + in the merge queue | `ci.yml` (triggers `pull_request` + `merge_group`) |
| Single required check | `CI Gate` aggregate job |
| Trunk-based CD | `cd.yml`: push `main` → devtest, tag `v*` → prod, dispatch → qa |
| Two deploy components | `_deploy.yml` echoes `bundle deploy` **and** `repos update` |
| Environment approval gates | job `environment:` on qa/prod |
| prod tracks a tag | prod job checks out / "syncs" the tag |
| Runner labels (hosted↔self-hosted) | `vars.RUNNER_LABELS` (default `ubuntu-latest`) |

## Quick start

```bash
# 1. push this repo
git init -b main && git add -A && git commit -m "sandbox"
gh repo create <owner>/trunkbased-sandbox --private --source=. --push

# 2. configure environments + rulesets + merge queue
scripts/setup.sh <owner>/trunkbased-sandbox

# 3. in the UI: allow squash-only, add required reviewers to qa/prod,
#    (optional) set RUNNER_LABELS = ["self-hosted","aca","linux"]
```

## Tests you can run

1. **Required check + merge queue.** Open a PR → `CI Gate` runs → approve → add to
   the merge queue → it re-runs on `merge_group` and merges. Confirms the required
   check reports in **both** contexts (the #1 merge-queue gotcha).
2. **Gate blocks a bad PR.** On a branch, `touch BREAK`, open a PR → `unit` fails →
   `CI Gate` red → merge blocked. Delete `BREAK` → green.
3. **devtest auto-deploy.** Merge to `main` → `cd.yml` runs the devtest job (dummy).
4. **prod is gated + tag-driven.** `git tag v0.1.0 && git push --tags` → the prod
   job **waits for your reviewer**; approve → it "deploys" from the tag.
5. **qa promotion.** Actions → CD → *Run workflow* → environment `qa` → the qa job
   waits for its reviewer.
6. **Direct push is blocked.** `git push origin main` (without a PR) → rejected by
   the ruleset.

## Notes
- `actions/checkout@v7` is pinned to a major here for readability; **pin to a
  commit SHA** in the real repos.
- Everything deploy-related is `echo` only — safe to run repeatedly.
