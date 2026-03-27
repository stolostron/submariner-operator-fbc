# Update Catalog Template to Production Bundle URL

> **⚠️ DEPRECATED:** This manual workflow is rarely needed. The automatic conversion in `make update-bundle` handles 99% of cases.

**When:** After prod release completes (not immediately urgent, but before quay.io URLs expire)

**Why:** Bundle images are initially added with temporary quay.io workspace URLs. After production release,
these should be updated to permanent registry.redhat.io URLs in the template source to match the generated catalogs.

## Recommended: Use Automatic Conversion Instead

**For 99% of cases,** use the main [Update FBC Catalog](update-catalog.md) workflow - it automatically converts released bundles:

```bash
make update-bundle VERSION=0.22.1
```

The `update-bundle.sh` script automatically converts quay.io → registry.redhat.io via:

- `audit_bundle_urls()` - checks which bundles exist at registry.redhat.io using `skopeo inspect`
- `convert_released_bundles()` - updates catalog-template.yaml with registry.redhat.io URLs

After running, verify conversion completed:

```bash
grep -c "quay.io" catalog-template.yaml  # Should return 0 if all converted
```

**You only need the manual workflow below if:**

- You manually edited catalog-template.yaml (didn't use `make update-bundle`)
- You want to batch-convert multiple released bundles without triggering a full update
- Automatic conversion failed (very rare)

**Otherwise, stop here** - the automatic conversion handles this for you.

---

## Manual Workflow (Edge Cases Only)

### Prerequisites

**Release State:**

- Prod release completed in submariner-release-management
- Bundle already in catalog-template.yaml with quay.io URL

**Required Tools:**

- `curl`, `jq`, `yq`, `grep`, `awk`, `sed` (text processing)
- `skopeo` (registry inspection - used in Step 1)
- `gh` (GitHub CLI, authenticated)
- `make`, `git` (repository management)

## 1. Identify Bundle to Convert

```bash
VERSION=0.22.1
Y_STREAM="${VERSION%.*}"; Y_STREAM="${Y_STREAM#0.}"  # Extract Y-stream: 0.22.1 → 22

CURRENT_URL=$(yq '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v'$VERSION'") | .image' catalog-template.yaml)
[[ -z "$CURRENT_URL" ]] && { echo "✗ ERROR: Bundle submariner.v${VERSION} not found"; exit 1; }

BUNDLE_SHA=${CURRENT_URL##*@sha256:}
PROD_URL="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${BUNDLE_SHA}"

skopeo inspect "docker://${PROD_URL}" >/dev/null 2>&1 || { echo "✗ ERROR: Bundle not yet released"; exit 1; }
echo "✓ Verified: $PROD_URL"
```

## 2. Update catalog-template.yaml

**Reminder:** If in a new shell, re-run Step 1 to define variables (`VERSION`, `Y_STREAM`, `BUNDLE_SHA`).

Update the bundle image URL:

```bash
# FROM (quay.io pre-release URL):
image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-22@sha256:abc123...

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
sed -i "s|quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-${Y_STREAM}@sha256:${BUNDLE_SHA}|registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${BUNDLE_SHA}|g" catalog-template.yaml
```

## 3. Build, Validate, and Test Catalogs

Build, validate, and test catalogs (~2-5 min):

```bash
cd ~/konflux/submariner-operator-fbc
make build-catalogs validate-catalogs test
```

**Expected:** ~9 files (1 template + bundle files across supported catalog-* directories).
Template shows URL change (quay.io → registry.redhat.io); generated catalogs rebuilt from template.

## 4. Create PR

**Reminder:** If in a new shell, re-run Step 1 to define `VERSION`, `BUNDLE_SHA`, and other variables needed below.

Create branch and commit:

```bash
# Branch naming: <major>.<minor>-prod-url (example for 0.22.1: 22.1-prod-url)
git checkout -b 22.1-prod-url
git add catalog-template.yaml catalog-4-*/
git commit -s -m "Update catalog template to prod bundle URL for v0.22.1" \
  -m "Changes quay.io pre-release URL to registry.redhat.io production URL." \
  -m "Same SHA digest, prevents quay.io expiration."
git push origin 22.1-prod-url
```

Create pull request:

```bash
gh pr create --title "Update catalog template to prod bundle URL for v${VERSION}" \
  --body "Changes quay.io pre-release URL to registry.redhat.io production URL.

Same SHA digest (\`${BUNDLE_SHA:0:12}...\`), prevents future build failures from quay.io expiration.

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

`Bundle not found` → Verify prod release completed; check VERSION matches actual release

`SHAs don't match` → Verify correct bundle version; check template not manually edited with wrong SHA

`sed unchanged` → Verify Y_STREAM extraction correct; check quay.io URLs exist: `grep quay.io catalog-template.yaml`
