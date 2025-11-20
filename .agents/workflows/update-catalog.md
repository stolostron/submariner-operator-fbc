# Update FBC Catalog with New Bundle

**When:** After stage or prod release completes

## Prerequisites

- Stage or prod release completed and merged
- Cluster access: `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`

## 1. Get Bundle Image

```bash
# Replace: 0.X → 0.21, 0-X-Y → 0-21-2, 0-X → 0-21; choose stage or prod
REPO=https://raw.githubusercontent.com/dfarrell07/submariner-release-management
SNAPSHOT=$(curl -s \
  $REPO/refs/heads/main/releases/0.X/stage/submariner-0-X-Y-*.yaml \
  | grep "snapshot:" | head -1 | awk '{print $2}')
oc get snapshot $SNAPSHOT -n submariner-tenant \
  -o jsonpath='{.spec.components[?(@.name=="submariner-bundle-0-X")].containerImage}'
```

- Stage: `quay.io/redhat-user-workloads/.../submariner-bundle-0-X@sha256:...`
- Prod: `registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:...`

## 2. Edit catalog-template.yaml

### Scenario A: New patch (add 0.21.2 after 0.21.1)

Add channel entry at top of `stable-0.X` entries:

```yaml
      - name: submariner.v0.X.Y
        replaces: submariner.v0.X.Z
        skipRange: '>=0.X.0 <0.X.Y'
```

Add bundle at end of bundles section:

```yaml
  - name: submariner.v0.X.Y
    image: <bundle-image-from-step-1>
    schema: olm.bundle
```

### Scenario B: Update SHA (prod or re-release)

Update `image` in existing bundle:

```yaml
    image: <bundle-image-from-step-1>
```

### Scenario C: Replace version (rare, skip bad upstream release)

Skip problematic version, replace with next.

Update channel and bundle:

- Channel: `name` (v0.21.1 → v0.21.2), `skipRange` (<0.21.1 → <0.21.2)
- Bundle: `name` (v0.21.1 → v0.21.2), `image`

Build renames bundle files automatically.

## 3. Build, Validate, Commit

```bash
cd ~/konflux/submariner-operator-fbc
make build-catalogs validate-catalogs
git add catalog-template.yaml catalog-4-*/
git commit -s -m "Update catalog with bundle v0.X.Y"
git push origin main
```

Build updates relatedImages component SHAs from bundle.

## 4. Verify Snapshots

Wait for Konflux (~15-30 min), then verify all OCP versions:

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

All tests must show `TestPassed`. Record snapshot names for FBC release.

## Done When

- Catalogs built, validated, and pushed
- All 5 snapshots (4-16 through 4-20) show TestPassed
- Snapshot names recorded for FBC release step
