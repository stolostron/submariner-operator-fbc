# Update FBC Catalog with New Bundle

**When:** After stage or prod release completes

## Prerequisites

**Access & Environment:**

- Konflux cluster access: `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`
- Repo root: `cd ~/konflux/submariner-operator-fbc`
- GitHub repository write permissions (for creating PRs)
- Release completed in submariner-release-management
- Registry authentication: `podman login registry.redhat.io` (requires Red Hat subscription)

**Required Tools:**

- `oc` (OpenShift CLI)
- `gh` (GitHub CLI, authenticated: `gh auth login`)
- `podman` (Container runtime, for catalog rendering)
- `skopeo` (Container inspection, for bundle release verification)
- `make`, `curl`, `jq`, `yq`, `grep`, `awk`, `sed`
- `git` (for version control)
- `csplit`, `timeout` (typically pre-installed on Linux)
- Standard utilities: `find`, `cat`, `tar`, `sort` (with --version-sort), `tr`, `mkdir`, `chmod`, `mktemp` (pre-installed on Linux)

## Automated Workflow (Recommended)

For most use cases, use the automated script:

```bash
make update-bundle VERSION=0.22.1                          # UPDATE: rebuild with new SHA (most common)
make update-bundle VERSION=0.22.2                          # ADD: new version
make update-bundle VERSION=0.22.3 REPLACE=0.22.2           # REPLACE: skip broken 0.22.2, release 0.22.3
make update-bundle VERSION=0.22.1 SNAPSHOT=submariner-0-22-r6894  # SNAPSHOT: explicit build
```

**What the script does automatically:**

1. Finds latest passing snapshot from Konflux (or uses `SNAPSHOT=` parameter)
2. Detects scenario (UPDATE/ADD/REPLACE) based on catalog state
3. Updates `catalog-template.yaml` with bundle and channel entries
4. Rebuilds all OCP catalogs (one per supported version in drop-versions.json)
5. Runs `opm validate` on all catalogs
6. Formats YAML files
7. Creates signed-off commit with scenario metadata
8. Enforces mirror Y-stream constraint (only one unreleased Y-stream allowed due to 4KB limit)

**After the script completes successfully:**

The script creates a signed-off commit. Review and push:

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

**Prerequisites:** Same as automated workflow (cluster access, repo root), plus:

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
make build-catalogs validate-catalogs test
```

Verify expected file changes (`git status --short`):

- **ADD**: ~17 files (1 template + bundle files + channel files across all catalog-* directories)
- **UPDATE**: ~9 files (1 template + bundle files across all catalog-* directories)
- **REPLACE**: Variable (depends on affected catalog versions)

**Note:** File counts vary based on OCP version compatibility (drop-versions.json filters bundles per version).
Mirror file updates (.tekton/images-mirror-set.yaml) add 1 file if Y-stream changes.

Create branch and commit:

```bash
# Branch naming: 0.<minor>.<patch>-stage or 0.<minor>.<patch>-prod
# Example for version 0.21.2: 0.21.2-stage
git checkout -b 0.21.2-stage
git add catalog-template.yaml catalog-4-*/
git commit -s -m "Update catalog with bundle v0.21.2 stage" -m "Snapshot: submariner-0-21-abc123"
git push origin 0.21.2-stage
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

For each OCP version the PR rebuilds, require:

- All GitHub Actions checks pass.
- `submariner-fbc-<ocp>-on-pull-request` (the Konflux build) passes.
- `submariner-fbc-operator-<ocp>` passes.
- `submariner-fbc-standard-<ocp>` passes or reports warnings (shown as neutral). Read the
  report of any failure. Source-provenance violations are expected for a PR from a fork;
  anything else, such as a missing required build task, would also fail the release, so it
  blocks merge.

When every check above is satisfied, merge:

```bash
gh pr merge --squash
```

## 5. Verify Konflux Snapshots

Wait for Konflux push builds (~15-30 min after merge), then check the newest push
snapshot of every catalog with a pipeline. Run this from the repo root:

```bash
for OCP in $(ls .tekton/submariner-fbc-*-push.yaml | sed 's/.*submariner-fbc-\(.*\)-push.yaml/\1/'); do
  oc get snapshots -n submariner-tenant -o json -l \
    "appstudio.openshift.io/application=submariner-fbc-$OCP,pac.test.appstudio.openshift.io/event-type=push" |
    jq -r '.items | if length == 0 then "no push snapshot yet" else max_by(.metadata.creationTimestamp) | [
      .metadata.name, .metadata.labels["pac.test.appstudio.openshift.io/sha"][:8],
      ((.status.conditions // [])[] | select(.type == "AppStudioTestSucceeded") | .reason),
      (.metadata.annotations["test.appstudio.openshift.io/status"] // "[]" | fromjson[] |
        "\(.scenario | sub("submariner-fbc-"; "")): \(.status)\(if .completionTime then "" else " (running)" end)")
    ] | join("  ") end'
done
```

Expected for each: the SHA of the last commit that changed that catalog or its build files
(`.tekton`, `images-mirror-set.yaml`, `catalog.Dockerfile`; a merge that touches none leaves the
older SHA in place), `Passed`, `operator` = `TestPassed` (which alone does not prove an install;
see below), and `standard` = `TestPassed`, `TestWarning` or `BuildPLRInProgress`. The
release-management verifier accepts those three only when the aggregate result is `Passed` and
every scenario has a `completionTime`. A `BuildPLRInProgress` standard result is the normal push
outcome, but it counts only when the scenario is not `(running)`.

The OCP 5.0 `operator` scenario is optional while its install path is being enabled, so
`Passed` can appear next to `operator-5-0: TestFail`. That `TestFail` is the install test
failing to provision a cluster (until openshift/release#87176 merges, the tenant is not an owner
of the `aws-konflux-prod` cluster profile), not a catalog content problem; do not treat it as passing, and
see the [OCP 5 rollout runbook](https://github.com/stolostron/submariner-release-management/blob/main/plans/ocp-5-0-fbc-rollout.md)
for the gates before 5.0 is released.

Record the snapshot names for the FBC release in submariner-release-management. Its
[stage release workflow](https://github.com/stolostron/submariner-release-management/blob/main/.agents/workflows/create-fbc-stage-release.md)
re-verifies them. Passing snapshot tests don't prove an operator install: the 4.x install
tests request channel `stable`, which no catalog defines. QE verifies installation on the
intended `stable-0.X` channel.

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

Local `Failed to access registry.redhat.io` → run `podman login registry.redhat.io`; check connectivity.

`401`/`unauthorized` from registry.redhat.io in a Konflux integration test (for example
`get-unreleased-bundle`) → your local login doesn't apply. The registry credential must be
linked to the tenant's `konflux-integration-runner` service account; see
[accessing private repositories](https://konflux-ci.dev/docs/testing/integration/accessing-private-repositories/).
After fixing it, [rerun the scenario](https://konflux-ci.dev/docs/testing/integration/rerunning/)
on the same snapshot instead of rebuilding.

### Release Policy Reports a Missing Required Task

Conforma's FBC required tasks change over time
([current list](https://github.com/release-engineering/rhtap-ec-policy/blob/main/data/required_tasks.yml)).
Add the task to both push and PR pipelines of every active catalog, as upstream
`fbc-builder` wires it, then release from the new push snapshot. Retrying the rejected
snapshot fails again.

### OPM Validation Failures

`opm validate fails` → Check bundle version mismatches; verify image accessible; run `make validate-catalogs`

### SHA Mismatch

Template SHA ≠ catalogs → Re-run `make build-catalogs`; verify no manual edits to catalog-4-*

### Commit Creation Fails

No changes staged → Verify template modified; check catalogs rebuilt

### Mirror Y-stream Conflict

`Removing unreleased bundle from Y-stream 0-XX` → Expected behavior, no action needed (see [constraints](#mirror-file-size-limit-4096-bytes))
