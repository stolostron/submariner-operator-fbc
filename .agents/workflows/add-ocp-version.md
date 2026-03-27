# Add Support for New OCP Version

**When:** Red Hat releases new OCP version and ACM announces support

## Prerequisites

**External Dependency:**

- konflux-release-data PR for new OCP version must be merged first
- This triggers the Konflux bot to automatically create a PR in this repo with `.tekton/` pipeline files

**Required Tools:**

- `gh` (GitHub CLI, authenticated: `gh auth login`)
- `oc` (OpenShift CLI, logged into Konflux cluster)
- `make`, `jq`, `yq`, `grep`, `vim` (or preferred editor)
- `git` (configured for signed-off commits)
- Network access to registry.redhat.io (for catalog generation)

**Optional Tools** (for troubleshooting):

- `yamllint`, `skopeo`

## Setup

**Note:** Run Setup and all steps in the same shell session (variables are not persisted).

```bash
cd ~/konflux/submariner-operator-fbc
git fetch origin

# Set versions (edit these)
NEW=4-22               # New OCP version (hyphenated)
NEW_DOT=4.22           # New OCP version (dotted)
MIN_SUB=0.23           # Minimum Submariner version for this OCP
```

## 1. Checkout Bot's PR Branch

After konflux-release-data PR merges, the Konflux bot creates a PR with `.tekton/` files for the new
component. The bot's PR doesn't populate `build-args` (infrastructure automation limitation) - we must add these before merging.

```bash
# Check for bot PR (may take a few minutes after konflux-release-data merge)
gh pr list --search "submariner-fbc-${NEW}"

# Get the bot's branch name and checkout
BOT_BRANCH="konflux-submariner-fbc-${NEW}"
git checkout "$BOT_BRANCH"
git log --oneline -2  # Should show bot's commit on top
```

**Note:** If the bot PR doesn't appear after ~10 minutes, check that the konflux-release-data PR was
merged and ArgoCD has synced the new Application/Component resources.

## 2. Update drop-versions.json

Add entry mapping OCP version to minimum Submariner version:

```bash
# View current entries
cat drop-versions.json

# Add new entry (insert before closing brace)
# Example: "4.22": "0.23"
```

Edit `drop-versions.json` to add the new OCP version entry.

## 3. Build Catalogs

Generate catalog directory for the new OCP version:

```bash
make build-catalogs

# Verify new catalog was created
ls -d catalog-${NEW}/ || { echo "ERROR: catalog-${NEW} not created"; exit 1; }
echo "✓ catalog-${NEW} created"
```

**Note:** This step requires network access to registry.redhat.io. If network unavailable, copy from
previous catalog (e.g., `catalog-4-20`) and include only bundles >= MIN_SUB version.

## 4. Fix Tekton Build Args

**Reminder:** Ensure `${NEW}` and `${NEW_DOT}` variables from Setup are still defined
(run `echo $NEW` to verify). If starting a new shell, re-run Setup section.

**Why:** The bot creates basic `.tekton/` files but doesn't know which catalog directory to build or which OPM
version to use. Without `build-args`, the build fails with "missing INPUT_DIR build argument".

Add this block after `value: catalog.Dockerfile` and before `pipelineSpec:` in both `.tekton/` files:

```yaml
  - name: build-args
    value:
    - INPUT_DIR=catalog-4-22        # ← Use your ${NEW} value
    - OPM_IMAGE=registry.redhat.io/openshift4/ose-operator-registry-rhel9:v4.22  # ← Use your ${NEW_DOT}
```

Edit and verify:

```bash
# Edit both files
vim .tekton/submariner-fbc-${NEW}-push.yaml .tekton/submariner-fbc-${NEW}-pull-request.yaml

# Verify
grep -A4 "build-args" .tekton/submariner-fbc-${NEW}-push.yaml
```

## 5. Validate, Test, and Commit

```bash
make validate-catalogs test

# Commit fix ON TOP of bot's commit
git add drop-versions.json catalog-${NEW}/ .tekton/submariner-fbc-${NEW}-*.yaml
git commit -s -m "Fix ${NEW_DOT} FBC: add build-args, catalog, and drop-versions entry

- Add INPUT_DIR=catalog-${NEW} and OPM_IMAGE build-args (critical)
- Generate and commit catalog-${NEW}/ directory
- Add \"${NEW_DOT}\": \"${MIN_SUB}\" to drop-versions.json"

# Push to bot's branch (updates the PR)
git push origin "$BOT_BRANCH"
```

Verify the PR now has 2 commits:

```bash
git log --oneline -2
# Should show:
# <your-fix> Fix 4.22 FBC: add build-args, catalog, and drop-versions entry
# <bot-commit> Red Hat Konflux kflux-prd-rh02 update submariner-fbc-4-22
```

## 6. Merge the Fixed PR

Wait for CI checks (~5-15 min), then verify:

```bash
gh pr checks
```

CI tests FBC builds for all OCP versions (4-14 through new version) with multiple scenarios. All checks must pass.

Merge when passing:

```bash
gh pr merge --squash
```

## 7. Update Workflow Docs (this repo)

Update OCP version references in workflow files:

**[`update-catalog.md`](update-catalog.md):**

- Version loop: Search for `for VERSION in 14 15` and add your new version number to the end of that list

**[`update-prod-url.md`](update-prod-url.md):**

- Update all hardcoded version ranges: Search for `"4-14 through 4-21"` and update to include new version
  (appears in multiple locations describing file counts and CI checks)

Commit as separate PR or include with other changes.

**See also:** [Update FBC Catalog workflow](update-catalog.md) for ongoing catalog maintenance after new OCP version is added.

## Troubleshooting

`Bot PR missing` (>10min) → Verify konflux-release-data merged and ArgoCD synced; check bot watching repo:
`gh api repos/stolostron/submariner-operator-fbc/pulls --jq '.[].user.login'`

`Build fails` → Verify `drop-versions.json` updated before building; validate syntax: `jq . drop-versions.json`

`CI fails` → Check syntax: `yamllint .tekton/submariner-fbc-${NEW}-*.yaml`; verify INPUT_DIR matches catalog directory;
check OPM_IMAGE exists: `skopeo list-tags docker://registry.redhat.io/openshift4/ose-operator-registry-rhel9`

`Snapshots missing` (>45min) → Check Konflux UI; verify pipeline: `oc get pipelineruns -n submariner-tenant | grep submariner-fbc-${NEW}`

## Done When

- Fixed PR merged (bot's tekton files + your fix commit)
- Catalog directory exists on main branch:

  ```bash
  gh api repos/stolostron/submariner-operator-fbc/contents/catalog-${NEW} --jq '.name'
  # Should show: catalog-4-22 (or your NEW version)
  ```

- Konflux snapshots building for new OCP version (~15-30 min after PR merge):

  ```bash
  oc get snapshots -n submariner-tenant --sort-by=.metadata.creationTimestamp | grep "submariner-fbc-${NEW}" | tail -1
  # Should show snapshot name
  ```

- Workflow docs in this repo updated with new OCP version

**Next:** Update submariner-release-management version loops for release workflows.
