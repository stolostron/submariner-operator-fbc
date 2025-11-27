# Update Catalog Template to Production Bundle URL

**When:** After prod release completes (must be done before quay.io URLs expire, but not time-critical)

**Why:** Prevents build failures from expired quay.io pre-release URLs by updating to permanent registry.redhat.io URLs

**Example:** See commit `8be62a2` - Updated 0.21.0 template to use released bundle URL

## Prerequisites

- Prod release completed in submariner-release-management
- Bundle already in catalog-template.yaml with quay.io URL

## 1. Get Production Bundle URL and SHA

```bash
# For version 0.21.2
VERSION=0.21.2
MINOR=${VERSION%.*}  # e.g., 0.21

# Get prod bundle URL from release files
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
sed -i "s|quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-${MINOR//./-}@sha256:${PROD_SHA}|registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${PROD_SHA}|g" catalog-template.yaml
```

## 3. Build and Validate Catalogs

Build catalogs (~2-5 min):

```bash
cd ~/konflux/submariner-operator-fbc
make build-catalogs validate-catalogs
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
```

**Note:** Example commit `8be62a2` has 7 files (pre-4-20). Current repo has 8 files: template +
7 catalogs (4-14 through 4-20).

**IMPORTANT:** Catalog bundles should have **NO substantive changes**:

- `catalog-template.yaml` - URL changes quay.io → registry.redhat.io (**source** change)
- `catalog-4-*/bundles/bundle-v${VERSION}.yaml` - **ONLY** formatting/reordering (**output** unchanged)

**Why no URL changes in built catalogs?**

Build script auto-converts all quay URLs → registry.redhat.io (`scripts/render-catalog.sh:137-141`):

| **Before this workflow**                     | **After this workflow**                                 |
|----------------------------------------------|-------------------------------------------------------- |
| catalog-template.yaml has **quay.io** URL    | catalog-template.yaml has **registry.redhat.io** URL    |
| Build sed **converts** → registry.redhat.io  | Build sed **no-op** → registry.redhat.io                |
| ✓ Output catalogs have registry.redhat.io    | ✓ Output catalogs have registry.redhat.io (unchanged)   |

This updates the source template to match what the build already produces, preventing future failures when quay.io URLs expire.

Verify minimal diff (expect 4 lines changed per file - reordering only):

```bash
git diff catalog-4-20/bundles/bundle-v${VERSION}.yaml
```

Expected output - bundle image moved in relatedImages list (formatting change only):

```diff
 relatedImages:
-  - image: registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:abc123...
-    name: ""
   - image: registry.redhat.io/rhacm2/lighthouse-agent-rhel9@sha256:...
     name: submariner-lighthouse-agent
   ...
+  - image: registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:abc123...
+    name: ""
   - image: registry.redhat.io/rhacm2/submariner-rhel9-operator@sha256:...
```

Each bundle file should show `2 insertions(+), 2 deletions(-)` - same content, different position.

If you see URL changes or content differences, something is wrong - stop and investigate.

## 4. Create PR

Create branch and commit:

```bash
# Branch: X.Y-prod-url (example: 21.2-prod-url)
git checkout -b ${VERSION}-prod-url
git add catalog-template.yaml catalog-4-*/
git commit -s -m "Update catalog template to prod bundle URL for v${VERSION}" \
  -m "Changes quay.io pre-release URL to registry.redhat.io production URL." \
  -m "Same SHA digest, prevents quay.io expiration."
git push origin ${VERSION}-prod-url
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

All checks should pass (FBC builds for 4-16 through 4-20).

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
