# Update Catalog Template to Production Bundle URL

**When:** After prod release completes (not immediately urgent, but before
quay.io URLs expire)

**Why:** Bundle images are initially added with temporary quay.io workspace
URLs. After production release, these must be updated to permanent
registry.redhat.io URLs to prevent build failures when workspace URLs expire.

**Priority:** Medium (complete within days/weeks after prod release, not immediately critical)

**Context:** Bundles added from Konflux stage/pre-release builds use temporary quay.io workspace URLs. The
`render-catalog.sh` script auto-converts these to registry.redhat.io during catalog builds. This workflow updates
the template source to match generated output, preventing future failures when temporary quay.io URLs expire.

## Automated Workflow (Recommended)

Use the `AUTO_CONVERT=true` flag to automatically convert released bundles:

```bash
make update-bundle VERSION=0.23.1 AUTO_CONVERT=true
```

**What the automation does:**

1. Scans catalog-template.yaml for bundles with quay.io URLs
2. Verifies each bundle is released (checks registry.redhat.io via skopeo with
   30s timeout)
3. Converts released bundles to production URLs (preserving SHA)
4. Skips unreleased bundles (warns if found)
5. Rebuilds and validates all catalogs
6. Creates commit with URL changes

**This is the preferred method.** The manual workflow below is only for
special cases or troubleshooting.

---

## Manual Workflow (Special Cases Only)

### Prerequisites

- Prod release completed in submariner-release-management
- Bundle already in catalog-template.yaml with quay.io URL

## 1. Get Production Bundle URL and SHA

```bash
# For version 0.21.2
VERSION=0.21.2
MINOR=${VERSION%.*}  # e.g., 0.21
Y_STREAM=${MINOR#*.}  # e.g., 21 (for bundle naming)

# Get prod bundle URL from release files
# NOTE: Replace 'dfarrell07' with your GitHub username or use 'stolostron' for official repo
REPO=https://raw.githubusercontent.com/dfarrell07/submariner-release-management
PROD_URL=$(curl -s \
  $REPO/refs/heads/main/releases/${MINOR}/prod/submariner-${VERSION//./-}-*.yaml \
  | grep "bundleImage:" | head -1 | awk '{print $2}')

if [[ -z "$PROD_URL" ]]; then
  echo "✗ ERROR: Could not find production bundle URL in release files"
  echo "  Checked: $REPO/refs/heads/main/releases/${MINOR}/prod/submariner-${VERSION//./-}-*.yaml"
  exit 1
fi

echo "Production bundle URL:"
echo "  $PROD_URL"

# Extract SHA from URL
PROD_SHA=${PROD_URL##*@sha256:}
echo "Production SHA: $PROD_SHA"

# Get current URL in catalog-template
CURRENT_URL=$(grep -A 1 "submariner.v${VERSION}" catalog-template.yaml \
  | grep "image:" | awk '{print $2}')

if [[ -z "$CURRENT_URL" ]]; then
  echo "✗ ERROR: Could not find bundle submariner.v${VERSION} in catalog-template.yaml"
  exit 1
fi

echo "Current template URL:"
echo "  $CURRENT_URL"

# Verify SHA matches
CURRENT_SHA=${CURRENT_URL##*@sha256:}
if [[ "$CURRENT_SHA" == "$PROD_SHA" ]]; then
  echo "✓ SHAs match - safe to update URL"
else
  echo "✗ ERROR: SHAs don't match!"
  echo "  Current: $CURRENT_SHA"
  echo "  Prod:    $PROD_SHA"
  exit 1
fi
```

## 2. Update catalog-template.yaml

Update the bundle image URL:

```bash
# FROM (quay.io pre-release URL):
image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21@sha256:abc123...

# TO (registry.redhat.io production URL with same SHA):
image: registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:abc123...
```

**Manual edit:**

```bash
vi catalog-template.yaml
# Find the bundle entry for the version
# Update the image URL to registry.redhat.io (keep same SHA)
```

**Or scripted:**

```bash
# Replace quay URL with registry.redhat.io URL (keeping SHA)
sed -i "s|quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-${Y_STREAM}@sha256:${PROD_SHA}|registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${PROD_SHA}|g" catalog-template.yaml
```

## 3. Build, Validate, and Test Catalogs

Build, validate, and test catalogs (~2-5 min):

```bash
cd ~/konflux/submariner-operator-fbc
make build-catalogs validate-catalogs test-scripts
```

**Expected changes** (`git status --short`):

```text
M  catalog-template.yaml
M  catalog-4-14/bundles/bundle-v${VERSION}.yaml
M  catalog-4-15/bundles/bundle-v${VERSION}.yaml
M  catalog-4-16/bundles/bundle-v${VERSION}.yaml
M  catalog-4-17/bundles/bundle-v${VERSION}.yaml
M  catalog-4-18/bundles/bundle-v${VERSION}.yaml
M  catalog-4-19/bundles/bundle-v${VERSION}.yaml
M  catalog-4-20/bundles/bundle-v${VERSION}.yaml
M  catalog-4-21/bundles/bundle-v${VERSION}.yaml
```

**Note:** Example commit `8be62a2` has 7 files (pre-4-20, pre-4-21). Current repo has
9 files: template + 8 catalogs (4-14 through 4-21).

**IMPORTANT:** Catalog bundles should have **NO substantive changes**:

- `catalog-template.yaml` - URL changes quay.io → registry.redhat.io (**source** change)
- `catalog-4-*/bundles/bundle-v${VERSION}.yaml` - **ONLY** formatting/reordering (**output** unchanged)

**Why no URL changes in built catalogs?** The build script auto-converts quay.io → registry.redhat.io
(`scripts/render-catalog.sh:145`). By updating the template now, the build becomes a no-op, preventing future
failures when quay.io URLs expire.

Verify minimal changes:

- `git diff` shows only formatting/reordering (no URL changes in built catalogs)
- Each bundle file: `2 insertions(+), 2 deletions(-)` - bundle image moved in relatedImages list:

  ```diff
   relatedImages:
  -  - image: registry.redhat.io/.../submariner-operator-bundle@sha256:...
     - image: registry.redhat.io/.../lighthouse-agent-rhel9@sha256:...
     ...
  +  - image: registry.redhat.io/.../submariner-operator-bundle@sha256:...
  ```

- If you see URL changes or content differences, stop and investigate.

## 4. Create PR

Create branch and commit:

```bash
# Branch naming: <major>.<minor>-prod-url (example for 0.21.2: 21.2-prod-url)
git checkout -b 21.2-prod-url
git add catalog-template.yaml catalog-4-*/
git commit -s -m "Update catalog template to prod bundle URL for v0.21.2" \
  -m "Changes quay.io pre-release URL to registry.redhat.io production URL." \
  -m "Same SHA digest, prevents quay.io expiration."
git push origin 21.2-prod-url
```

Create pull request:

```bash
gh pr create --title "Update catalog template to prod bundle URL for v${VERSION}" \
  --body "Changes quay.io pre-release URL to registry.redhat.io production URL.

Same SHA digest (\`${PROD_SHA:0:12}...\`), prevents future build failures from quay.io expiration.

Not immediately time-sensitive, but must be completed before quay.io URLs expire."
```

## 5. Verify and Merge

Wait for CI checks (~5-15 min):

```bash
gh pr checks
```

All checks should pass (FBC builds for 4-14 through 4-21).

Merge when passing:

```bash
gh pr merge --squash
```

## Notes

- **Must be completed eventually** - builds will fail once quay.io URLs expire
- Not immediately time-critical - quay.io URLs have retention period after prod release
- Can be batched with other catalog updates before expiration
- Only applies to current Konflux workflow - early bundles (0.17.x, 0.18.x) were added directly with
  registry.redhat.io URLs before Konflux and don't need this step

## Troubleshooting

### Bundle not found in production

**Error:** `Could not find production bundle URL in release files`

**Solutions:**

- Verify prod release completed in submariner-release-management
- Check REPO variable points to correct GitHub repo/branch
- Confirm VERSION matches an actual released version

### SHAs don't match

**Error:** `SHAs don't match! Current: ... Prod: ...`

**Solutions:**

- Verify you're updating the correct bundle version
- Check that template hasn't been manually edited with wrong SHA
- Confirm production release matches the bundle in template

### sed command doesn't match any URLs

**Error:** Template unchanged after sed command (Step 2)

**Solutions:**

- Verify Y_STREAM extraction is correct (should be "21" for version 0.21.2)
- Check template actually contains quay.io URLs (not already converted)
- Run `grep quay.io catalog-template.yaml` to verify URLs exist

## See Also

- [Update FBC Catalog with New Bundle](update-catalog.md) - Main workflow for adding/updating bundles (this workflow typically follows that one)
