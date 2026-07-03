#!/usr/bin/env bash
# Configure the sandbox to mirror the real framework.
# Requires: gh CLI (gh auth login). Usage: bash scripts/setup.sh <owner>/<repo>
set -euo pipefail
REPO="${1:?Usage: bash scripts/setup.sh <owner>/<repo>}"

echo ">> 1/4 Environments (devtest, qa, prod)"
for env in devtest qa prod; do
  gh api -X PUT "repos/$REPO/environments/$env" >/dev/null
  echo "   created: $env"
done
echo "   NOTE: add required reviewers to qa and prod in Settings > Environments."

echo ">> 2/4 Branch ruleset (PR + CI Gate + linear history + no force-push/delete)"
# Errors are shown (no >/dev/null) so a 422 tells you exactly which rule failed.
gh api -X POST "repos/$REPO/rulesets" --input - <<'JSON'
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [ { "context": "CI Gate" } ] } },
    { "type": "non_fast_forward" },
    { "type": "deletion" },
    { "type": "required_linear_history" }
  ]
}
JSON
echo "   main-protection active."

echo ">> 3/4 Merge queue (separate ruleset; needs public repo or Enterprise Cloud)"
if gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null 2>/tmp/mq_err <<'JSON'
{
  "name": "merge-queue",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "merge_queue", "parameters": {
        "merge_method": "SQUASH",
        "max_entries_to_build": 5,
        "min_entries_to_merge": 1,
        "max_entries_to_merge": 5,
        "min_entries_to_merge_wait_minutes": 5,
        "check_response_timeout_minutes": 60,
        "grouping_strategy": "ALLGREEN" } }
  ]
}
JSON
then
  echo "   merge-queue active."
else
  echo "   SKIPPED merge queue: $(head -1 /tmp/mq_err)"
  echo "   (Private repos need GitHub Enterprise Cloud. Enable on the real org repo.)"
fi

echo ">> 4/4 Tag ruleset (protect v* release tags)"
gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null <<'JSON'
{
  "name": "release-tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [ { "type": "non_fast_forward" }, { "type": "deletion" } ]
}
JSON
echo "   release-tags active."

cat <<'NEXT'

Done. Finish in the UI:
  * Settings > General > Pull Requests: allow SQUASH only; auto-delete head branches ON.
  * Settings > Environments > qa, prod: add Required reviewers.
  * (Self-hosted) set repo variable RUNNER_LABELS = ["self-hosted","aca","linux"].
Re-running is safe: environments are idempotent; a ruleset whose name already
exists returns "name already in use" — delete it first if you want to recreate:
  gh api repos/<owner>/<repo>/rulesets           # find the id
  gh api -X DELETE repos/<owner>/<repo>/rulesets/<id>
NEXT
