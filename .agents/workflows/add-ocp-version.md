# Add Support for New OCP Version

**When:** Red Hat releases new OCP version and ACM announces support

**Prerequisites:** konflux-release-data MR for new OCP version must be merged first. This triggers the
Konflux bot to automatically create a PR in this repo with `.tekton/` pipeline files for the new component.

## Setup

**Note:** Run Setup and all steps in the same shell session (variables are not persisted).

```bash
cd ~/konflux/submariner-operator-fbc
git fetch origin

# Set versions (edit these)
NEW=4-21               # New OCP version (hyphenated)
NEW_DOT=4.21           # New OCP version (dotted)
MIN_SUB=0.22           # Minimum Submariner version for this OCP
```

## 1. Checkout Bot's PR Branch

After konflux-release-data MR merges, the Konflux bot creates a PR with `.tekton/` files for the new
component. The bot's PR is incomplete (missing `build-args`) - we'll fix it before merging.

```bash
# Check for bot PR (may take a few minutes after konflux-release-data merge)
gh pr list --search "submariner-fbc-${NEW}"

# Get the bot's branch name and checkout
BOT_BRANCH="konflux-submariner-fbc-${NEW}"
git checkout "$BOT_BRANCH"
git log --oneline -2  # Should show bot's commit on top
```

**Note:** If the bot PR doesn't appear after ~10 minutes, check that the konflux-release-data MR was
merged and ArgoCD has synced the new Application/Component resources.

## 2. Update drop-versions.json

Add entry mapping OCP version to minimum Submariner version:

```bash
# View current entries
cat drop-versions.json

# Add new entry (insert before closing brace)
# Example: "4.21": "0.22"
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

**Why:** The bot creates basic `.tekton/` files but doesn't know which catalog directory to build or which OPM
version to use. Without `build-args`, the build fails with "missing INPUT_DIR build argument".

Add this block after `value: catalog.Dockerfile` and before `pipelineSpec:` in both `.tekton/` files:

```yaml
  - name: build-args
    value:
    - INPUT_DIR=catalog-4-21        # ← Use your ${NEW} value
    - OPM_IMAGE=registry.redhat.io/openshift4/ose-operator-registry-rhel9:v4.21  # ← Use your ${NEW_DOT}
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
make validate-catalogs test-scripts

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
# <your-fix> Fix 4.21 FBC: add build-args, catalog, and drop-versions entry
# <bot-commit> Red Hat Konflux kflux-prd-rh02 update submariner-fbc-4-21
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

- Version range: `"4-14 through 4-21"` → update to include new version
- Version loop: `for VERSION in 14 15 16 17 18 19 20 21` → add new version number

**[`update-prod-url.md`](update-prod-url.md):**

- Expected files list: `M  catalog-4-21/bundles/...` block → add new catalog line
- Catalog count: `"8 catalogs (4-14 through 4-21)"` → update count and range
- Version range: `"4-14 through 4-21"` → update to include new version

Commit as separate PR or include with other changes.

**See also:** [Update FBC Catalog workflow](update-catalog.md) for ongoing catalog maintenance after new OCP version is added.

## Done When

- Fixed PR merged (bot's tekton files + your fix commit)
- Catalog directory exists on main branch:

  ```bash
  gh api repos/stolostron/submariner-operator-fbc/contents/catalog-${NEW} --jq '.name'
  # Should show: catalog-4-21 (or your NEW version)
  ```

- Konflux snapshots building for new OCP version (~15-30 min after PR merge):

  ```bash
  oc get snapshots -n submariner-tenant --sort-by=.metadata.creationTimestamp | grep "submariner-fbc-${NEW}" | tail -1
  # Should show snapshot name
  ```

- Workflow docs in this repo updated with new OCP version

**Next:** Update submariner-release-management version loops for release workflows.
