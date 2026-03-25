# Update FBC Catalog with New Bundle

**When:** After stage or prod release completes

## Prerequisites

**Access & Environment:**

- Konflux cluster access: `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`
- Off VPN (registry.redhat.io blocks RH VPN)
- Repo root: `cd ~/konflux/submariner-operator-fbc`
- GitHub repository write permissions (for creating PRs)
- Release completed in submariner-release-management

**Required Tools:**

- `oc` (OpenShift CLI)
- `gh` (GitHub CLI, authenticated: `gh auth login`)
- `make`, `curl`, `jq`, `yq`, `grep`, `awk`, `sed`
- `git` (for version control)

## Automated Workflow (Recommended)

For most use cases, use the automated script:

```bash
make update-bundle VERSION=0.22.1                          # UPDATE: rebuild with new SHA (most common)
make update-bundle VERSION=0.22.0                          # ADD: new Y-stream version
make update-bundle VERSION=0.22.1 REPLACE=0.22.0           # REPLACE: skip broken version
make update-bundle VERSION=0.22.1 SNAPSHOT=submariner-0-22-xxxxx  # SNAPSHOT: explicit build
```

**What the script does automatically:**

1. Finds latest passing snapshot from Konflux (or uses `SNAPSHOT=` parameter)
2. Detects scenario (UPDATE/ADD/REPLACE) based on catalog state
3. Updates `catalog-template.yaml` with bundle and channel entries
4. Rebuilds all OCP catalogs (one per supported version in drop-versions.json)
5. Runs `opm validate` on all catalogs
6. Formats YAML files
7. Creates signed commit with scenario metadata
8. Enforces mirror Y-stream constraint (only one unreleased Y-stream allowed due to 4KB limit)

**After the script completes successfully:**

The script creates a signed commit. Review and push:

```bash
git show  # Review the commit
```

Then continue to [Verify CI and Merge](#4-verify-ci-and-merge) for:

- Pushing changes
- Creating pull request
- Waiting for CI validation
- Merging when tests pass
- Post-merge Konflux snapshot verification

---

## Manual Workflow (Special Cases Only)

Use this only for edge cases or automation troubleshooting.

**Prerequisites:** Same as automated workflow (cluster access, VPN disconnect, repo root), plus:

- Ability to manually fetch snapshots from release files
- Comfort editing YAML files directly

## 1. Get Bundle Image and Snapshot

```bash
# Determine snapshot name from submariner-release-management release files
# Y-stream format: submariner-0-21-xxxxx (e.g., for any v0.21.x release, use Y-stream 0-21)
SNAPSHOT=submariner-0-21-xxxxx  # Replace with actual snapshot name from release commit

# Extract bundle image from snapshot
oc get snapshot $SNAPSHOT -n submariner-tenant \
  -o jsonpath='{.spec.components[?(@.name=="submariner-bundle-0-21")].containerImage}'
```

Note: Adjust component name `submariner-bundle-0-21` to match your version's Y-stream.

## 2. Edit catalog-template.yaml

All scenarios use this structure - adapt based on your case:

```yaml
# Channel entry (in stable-0.X channel)
- name: submariner.v0.X.Y
  replaces: submariner.v0.X.Z
  skipRange: '>=0.X.0 <0.X.Y'

# Bundle entry (end of file, before schema: olm.template.basic)
- name: submariner.v0.X.Y
  image: <bundle-image-from-step-1>
  schema: olm.bundle
```

**For NEW versions (ADD):** Add both entries above
**For UPDATES:** Change `image` SHA only
**For REPLACEMENTS:** Update `name` and `skipRange` to skip broken version
(e.g., 0.22.1 → 0.22.2 to skip problematic 0.22.1)

## 3. Build, Validate, Create PR

Build, validate, and test catalogs (~2-5 min):

```bash
cd ~/konflux/submariner-operator-fbc
make build-catalogs validate-catalogs test-scripts
```

Verify expected file changes (`git status --short`):

- **ADD**: ~17 files (1 template + bundle files + channel files across all catalog-* directories)
- **UPDATE**: ~9 files (1 template + bundle files across all catalog-* directories)
- **REPLACE**: Variable (depends on affected catalog versions)

**Note:** File counts vary based on OCP version compatibility (drop-versions.json filters bundles per version).
Mirror file updates (.tekton/images-mirror-set.yaml) add 1 file if Y-stream changes.

Create branch and commit:

```bash
# Branch naming: <major>.<minor>-stage or <major>.<minor>-prod
# Example for version 0.21.2: 21.2-stage
git checkout -b 21.2-stage
git add catalog-template.yaml catalog-4-*/
git commit -s -m "Update catalog with bundle v0.21.2 stage" -m "Snapshot: submariner-0-21-abc123"
git push origin 21.2-stage
```

Create pull request:

```bash
gh pr create --title "Update catalog with bundle v0.21.2 stage" \
  --body "Snapshot: submariner-0-21-abc123"
```

## 4. Verify CI and Merge

Wait for CI checks to complete (~5-15 min), then verify:

```bash
gh pr checks
```

CI tests FBC builds for all supported OCP versions with multiple
scenarios (operator, standard). All checks must pass.

Merge when passing:

```bash
gh pr merge --squash
```

## 5. Verify Konflux Snapshots

Wait for Konflux builds (~15-30 min after merge).

Verify OCP versions show `TestPassed`:

```bash
# Loop through all supported OCP versions (adjust range as versions are added/dropped)
for VERSION in 14 15 16 17 18 19 20 21; do
  SNAPSHOT=$(oc get snapshots -n submariner-tenant \
    --sort-by=.metadata.creationTimestamp \
    | grep "^submariner-fbc-4-$VERSION" | tail -1 | awk '{print $1}')
  echo "=== 4-$VERSION: $SNAPSHOT ==="
  oc get snapshot $SNAPSHOT -n submariner-tenant \
    -o jsonpath='{.metadata.annotations["test.appstudio.openshift.io/status"]}' \
    | jq -r '.[] | "\(.scenario): \(.status)"'
done
```

All scenarios should show `TestPassed`. The snapshot names from the output above will be
needed when creating the FBC release in submariner-release-management.

## Note: Automatic URL Conversion

The `update-bundle.sh` script automatically converts released bundles from quay.io to
registry.redhat.io URLs during every run (via `audit_bundle_urls()` and `convert_released_bundles()`
functions). Manual URL updates are rarely needed - only for bundles added before this feature
or if auto-conversion fails. See [update-prod-url.md](update-prod-url.md) for details.

## Important Constraints

### Mirror File Size Limit (4096 bytes)

`.tekton/images-mirror-set.yaml` is limited to 4096 bytes (Tekton task result limit).
**Only one unreleased Y-stream allowed in mirrors at a time.**

The `update-bundle` script handles this automatically:

- Detects your bundle's Y-stream
- **Released bundles** → auto-converts to registry.redhat.io (mirrors not needed)
- **Unreleased bundles from other Y-streams** → automatically removed with warning

The cleanup is atomic: if adding a v0.22.x bundle, all unreleased v0.23.x bundles are automatically removed
to ensure only one unreleased Y-stream exists at a time.

## Troubleshooting

### Snapshot not found

`No push-event snapshot found` → Verify release completed; check cluster login; use explicit `SNAPSHOT=submariner-X-Y-xxxxx`

### Network/Registry Access

`Failed to access registry.redhat.io` → Disconnect VPN; check firewall/connectivity

### OPM Validation Failures

`opm validate fails` → Check bundle version mismatches; verify image accessible; run `make validate-catalogs`

### SHA Mismatch

Template SHA ≠ catalogs → Re-run `make build-catalogs`; verify no manual edits to catalog-4-*

### Commit Creation Fails

No changes staged → Verify template modified; check catalogs rebuilt

### Mirror Y-stream Conflict

`Removing unreleased bundle from Y-stream 0-XX` → Expected behavior, no action needed (see [constraints](#mirror-file-size-limit-4096-bytes))
