# Update FBC Catalog with New Bundle

**When:** After stage or prod release completes

## Prerequisites

- Cluster access: `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`
- Disconnect from RH VPN (blocks registry.redhat.io access)

## 1. Get Bundle Image and Snapshot

```bash
# For version 0.21.2, replace: 0.X → 0.21, 0-X-Y → 0-21-2, 0-X → 0-21
# Change /stage/ to /prod/ if updating from prod release
REPO=https://raw.githubusercontent.com/dfarrell07/submariner-release-management
SNAPSHOT=$(curl -s \
  $REPO/refs/heads/main/releases/0.X/stage/submariner-0-X-Y-*.yaml \
  | grep "snapshot:" | head -1 | awk '{print $2}')
echo "Snapshot: $SNAPSHOT"
oc get snapshot $SNAPSHOT -n submariner-tenant \
  -o jsonpath='{.spec.components[?(@.name=="submariner-bundle-0-X")].containerImage}'
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

Skip problematic version by releasing next version in its place.

Update channel entry `name` and `skipRange`:

```yaml
      - name: submariner.v0.21.2        # was v0.21.1
        replaces: submariner.v0.21.0
        skipRange: '>=0.21.0 <0.21.2'   # was <0.21.1
```

Update bundle `name` and `image`:

```yaml
  - name: submariner.v0.21.2            # was v0.21.1
    image: <bundle-image-from-step-1>
    schema: olm.bundle
```

**Note:** Build automatically renames catalog files to match new version.

## 3. Build, Validate, Create PR

Build and validate catalogs (~2-5 min):

```bash
cd ~/konflux/submariner-operator-fbc
make build-catalogs validate-catalogs
```

Verify expected file changes (`git status --short`):

- Scenario A: 15 files (7 bundles + 7 channels + template)
- Scenario B: 8 files (7 bundles + template)
- Scenario C: variable

Create branch and commit:

```bash
# Branch: X.Y-stage or X.Y-prod (example: 21.2-stage)
git checkout -b X.Y-stage
git add catalog-template.yaml catalog-4-*/
git commit -s -m "Update catalog with bundle v0.X.Y stage" -m "Snapshot: submariner-0-X-xxxxx"
git push origin X.Y-stage
```

Create pull request:

```bash
gh pr create --title "Update catalog with bundle v0.X.Y stage" \
  --body "Snapshot: submariner-0-X-xxxxx"
```

## 4. Verify CI and Merge

Wait for CI checks to complete (~5-15 min), then verify:

```bash
gh pr checks
```

CI tests FBC builds for OCP versions 4-16 through 4-20 with multiple scenarios (operator, standard). All checks must pass.

Merge when passing:

```bash
gh pr merge --squash
```

## 5. Verify Konflux Snapshots

Wait for Konflux builds (~15-30 min after merge).

Verify OCP versions show `TestPassed`:

```bash
for VERSION in 16 17 18 19 20; do
  SNAPSHOT=$(oc get snapshots -n submariner-tenant \
    --sort-by=.metadata.creationTimestamp \
    | grep "^submariner-fbc-4-$VERSION" | tail -1 | awk '{print $1}')
  echo "=== 4-$VERSION: $SNAPSHOT ==="
  oc get snapshot $SNAPSHOT -n submariner-tenant \
    -o jsonpath='{.metadata.annotations.test\.appstudio\.openshift\.io/status}' \
    | jq -r '.[] | "\(.scenario): \(.status)"'
done
```

All scenarios should show `TestPassed`. Record snapshot names from output above for FBC release.

## Follow-up: Update to Production Bundle URL

After a prod release completes, update catalog-template.yaml from temporary quay.io URLs to permanent registry.redhat.io URLs. This must be done before quay.io URLs expire to prevent build failures. See:

- [Update Catalog Template to Production Bundle URL](update-prod-url.md)

Not time-critical immediately after release, but required eventually.
