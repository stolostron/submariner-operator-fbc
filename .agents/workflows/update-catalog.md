# Update FBC Catalog with New Bundle

**When:** After stage or prod release completes

## Prerequisites

Before running any workflow (automated or manual):

1. **Cluster Access:** Login to Konflux (read-only access sufficient)

   ```bash
   oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/
   ```

2. **Network:** Disconnect from RH VPN (blocks registry.redhat.io)
3. **Repository:** Run from root: `cd ~/konflux/submariner-operator-fbc`
4. **Release Complete:** Verify Submariner release completed in submariner-release-management

## Automated Workflow (Recommended)

For most use cases, use the automated script:

```bash
make update-bundle VERSION=0.21.2                          # UPDATE: rebuild with new SHA (most common)
make update-bundle VERSION=0.22.0                          # ADD: new Y-stream version
make update-bundle VERSION=0.21.2 REPLACE=0.21.1           # REPLACE: skip broken version
make update-bundle VERSION=0.21.2 AUTO_CONVERT=true        # CONVERT: quay.io → registry.redhat.io
make update-bundle VERSION=0.21.2 SNAPSHOT=submariner-0-21-xxxxx  # SNAPSHOT: explicit build
```

**What the script does automatically:**

1. Finds latest passing snapshot from Konflux (or uses `SNAPSHOT=` parameter)
2. Detects scenario (UPDATE/ADD/REPLACE) based on catalog state
3. Updates `catalog-template.yaml` with bundle and channel entries
4. Rebuilds all 8 OCP catalogs (4-14 through 4-21)
5. Runs `opm validate` on all catalogs
6. Formats YAML files
7. Creates signed commit with scenario metadata

**After the script completes successfully:**

The script will create a signed commit. Review the changes:

```bash
git show  # Review the commit created by the script
git status --short  # Verify expected files changed (9 files for UPDATE, 17 for ADD)
```

Then continue to [Step 4: Verify CI and Merge](#4-verify-ci-and-merge) for:

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
# Version notation:
#   0.X.Y = Semver (e.g., 0.21.2) - used in bundle/channel names
#   0-X-Y = Dashed (e.g., 0-21-2) - used in URLs and snapshot names
#   0-X   = Y-stream (e.g., 0-21) - used in component names
# Example for version 0.21.2:
REPO=https://raw.githubusercontent.com/dfarrell07/submariner-release-management
SNAPSHOT=$(curl -s \
  $REPO/refs/heads/main/releases/0.21/stage/submariner-0-21-2-*.yaml \
  | grep "snapshot:" | head -1 | awk '{print $2}')
echo "Snapshot: $SNAPSHOT"
oc get snapshot $SNAPSHOT -n submariner-tenant \
  -o jsonpath='{.spec.components[?(@.name=="submariner-bundle-0-21")].containerImage}'
```

Copy snapshot name above for commit message in Step 3.

## 2. Edit catalog-template.yaml

### Scenario A: Add new version

Add as first entry in `stable-0.X` channel:

```yaml
      - name: submariner.v0.X.Y
        replaces: submariner.v0.X.Z
        skipRange: '>=0.X.0 <0.X.Y'
```

Add as last entry before `schema: olm.template.basic`:

```yaml
  - name: submariner.v0.X.Y
    image: <bundle-image-from-step-1>
    schema: olm.bundle
```

### Scenario B: Update SHA

Update `image` in existing bundle:

```yaml
    image: <bundle-image-from-step-1>
```

### Scenario C: Replace version

Skip problematic version by releasing next version in its place (e.g., 0.21.1 has critical bug, release 0.21.2 to replace it).

Update both channel AND bundle entries (they must reference the same version):

**Channel entry** - Update `name` and `skipRange`:

```yaml
      - name: submariner.v0.21.2        # was v0.21.1
        replaces: submariner.v0.21.0
        skipRange: '>=0.21.0 <0.21.2'   # was <0.21.1
```

**Bundle entry** - Update `name` and `image` (must match channel entry name):

```yaml
  - name: submariner.v0.21.2            # was v0.21.1
    image: <bundle-image-from-step-1>
    schema: olm.bundle
```

**Note:** Build automatically renames catalog files to match new version.

## 3. Build, Validate, Create PR

Build, validate, and test catalogs (~2-5 min):

```bash
cd ~/konflux/submariner-operator-fbc
make build-catalogs validate-catalogs test-scripts
```

Verify expected file changes (`git status --short`):

- Scenario A (ADD): ~17 files (8 bundles + 8 channels + template)
- Scenario B (UPDATE): ~9 files (8 bundles + template)
- Scenario C (REPLACE): Variable (depends on affected catalogs)

Note: File count may vary if older OCP versions prune the bundle.

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

CI tests FBC builds for OCP versions 4-14 through 4-21 with multiple
scenarios (operator, standard). All checks must pass.

Merge when passing:

```bash
gh pr merge --squash
```

## 5. Verify Konflux Snapshots

Wait for Konflux builds (~15-30 min after merge).

Verify OCP versions show `TestPassed`:

```bash
for VERSION in 14 15 16 17 18 19 20 21; do
  SNAPSHOT=$(oc get snapshots -n submariner-tenant \
    --sort-by=.metadata.creationTimestamp \
    | grep "^submariner-fbc-4-$VERSION" | tail -1 | awk '{print $1}')
  echo "=== 4-$VERSION: $SNAPSHOT ==="
  oc get snapshot $SNAPSHOT -n submariner-tenant \
    -o jsonpath='{.metadata.annotations.test\.appstudio\.openshift\.io/status}' \
    | jq -r '.[] | "\(.scenario): \(.status)"'
done
```

All scenarios should show `TestPassed`. The snapshot names from the output above will be
needed when creating the FBC release in submariner-release-management.

## Follow-up: Update to Production Bundle URL

After a prod release completes, update catalog-template.yaml from temporary
quay.io URLs to permanent registry.redhat.io URLs. This must be done before
quay.io URLs expire to prevent build failures. See:

- [Update Catalog Template to Production Bundle URL](update-prod-url.md)

Not time-critical immediately after release, but required eventually.

## Troubleshooting

### Snapshot not found

**Error:** `No push-event snapshot found for version X.Y`

**Solutions:**

- Verify the release completed in submariner-release-management
- Check you're logged into the correct Konflux cluster
- Provide explicit snapshot: `make update-bundle VERSION=X.Y.Z SNAPSHOT=submariner-X-Y-xxxxx`

### Network/Registry Access Issues

**Error:** `Failed to access registry.redhat.io`

**Solutions:**

- Disconnect from RH VPN (it blocks registry.redhat.io)
- Check network connectivity
- Verify you're not behind a firewall blocking registry access

### OPM Validation Failures

**Error:** `opm validate` fails on generated catalogs

**Solutions:**

- Check for bundle version mismatches (see README TODOs)
- Verify bundle image is accessible
- Run `make validate-catalogs` to see specific errors
- Check catalog-template.yaml for syntax errors

### SHA Mismatch

**Error:** Template SHA doesn't match catalogs

**Solutions:**

- Ensure you ran `make build-catalogs` after template changes
- Check that `scripts/render-catalog.sh` completed successfully
- Verify no manual edits to generated catalog-4-* files

### Commit Creation Fails

**Error:** Cannot create commit (no changes staged)

**Solutions:**

- Verify template was actually modified
- Check that catalogs were rebuilt
- Ensure you're in the repository root
- Run `git status` to see actual changes
