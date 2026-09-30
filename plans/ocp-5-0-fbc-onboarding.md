# Plan: Get the OCP 5.0 FBC building, testing and releasing

Status as of 2026-09-29. Covers what remains after the catalog and tooling work merged.

## Where things stand

- Merged: #76 (EC scenario docs) and #81 (OCP 5 tooling plus `catalog-5-0` with provisional Submariner 0.24).
- Open: #82 (this PR): `.tekton/submariner-fbc-5-0-{push,pull-request}.yaml` and the snapshot-loop doc update.
- All GitHub Actions checks on #82 pass. Only the Konflux check `submariner-fbc-5-0-on-pull-request` fails.

## Why #82's Konflux check fails

1. The new pipelines hard-code `serviceAccountName: build-pipeline-submariner-fbc-5-0`.
2. Pipelines-as-Code runs any matching pipeline file on the PR, whether or not a Component exists.
3. The first task (`init`) cannot start: `serviceaccounts "build-pipeline-submariner-fbc-5-0" not found`.
4. That service account is created once the `submariner-fbc-5-0` Application, Component and ImageRepository exist. They are defined in the
   tenant config in konflux-release-data (GitLab), which is not merged yet.

This is an ordering problem, not a defect in the PR. The 4.22 onboarding (#60) had its tenant config merged first and passed on the
first run. Do not merge #82 before the tenant config is live: the 5-0 push build would fail on `main`.

## Steps

### 1. Land the release-data changes (unblocks #82)

- Drafts live in `ocp-5-work/tenant` (2 commits) and `ocp-5-work/admission` (1 commit). Nothing is pushed yet.
- Fetch and rebase both onto current `origin/main` (their base `8c18efee29` dates from 2026-09-18).
- Run `tox` in both, and `tox -e tenants-config-test` for the tenant change.
- Push branches directly to the GitLab project (do not fork) and open two separate merge requests: tenant and managed admission.
- CODEOWNERS already covers both paths. `constraints/`, `prodsec/` and `exceptions/` need no change.
- Reviewers: the release-data docs say `tenants-config/` changes are not reviewed by release engineers. Approval comes from the
  CODEOWNERS team, so the submariner owners can approve the tenant merge request. The RPA lives under `config/`; its CODEOWNERS entry
  is also the submariner team.
- After merge, ArgoCD reconciles the tenant within minutes. The RPA applies on merge (`oc apply` in CI).
- No PaC Repository object is needed: the existing one for this git repo is shared by all the FBC components (it is why the 5-0 pipeline
  started at all). Do not expect a Konflux onboarding PR: the 4.22 Component had the same shape and no bot PR appeared (see #60), so the
  `.tekton/` files in #82 are the pipelines. If a bot PR does appear, reconcile it with #82 instead of adding a second pair.
- Verify live: Application, Component, ImageRepository, both ITS objects, both release plans, the service account and the image-push secret.

### 2. Confirm OpenShift CI cluster-profile access

- The 5.0 operator test uses the `deploy-fbc-operator` 0.3 install pipeline, which provisions clusters through the OpenShift CI profile
  `aws-konflux-prod`. Upstream requires requesting access to the shared cluster profiles.
- Nothing in konflux-release-data shows the submariner tenant has this access. Without it the non-optional `operator` scenario cannot
  provision a cluster.
- The public Konflux docs only say to pick a cluster profile that holds the cloud credentials for the `hypershift-hostedcluster-workflow`.
  The access request itself is in the internal OpenShift CI page linked from the 0.3 `MIGRATION.md`; it is not in these docs.
- Fallback if access is delayed: keep the `operator` scenario on the 0.1 EaaS path (as 4.22 does) and get the OCP 5.0 install evidence
  manually (step 5). EaaS provisioning may not offer a 5.0 cluster, so this fallback is unverified.
- Existing 4.x scenarios use the EaaS-based 0.1 path, which upstream says stops working when EaaS is retired. Track that separately.

### 3. Re-run and merge #82

- Comment `/retest` (or push an empty commit) once the service account exists.
- Check that these work: the `registry.redhat.io/openshift5/ose-operator-registry-rhel9:v5.0` base image pull, the
  `fbc-inject-lifecycle` task, and the `operator` scenario.
- All task digests are trusted today. `registry.redhat.io/` is allowed by the `fbc-standard` policy.
- The OCP target version comes from the parent (base) image, not from labels (ADR 0026), so the v5.0 base image is what routes the
  fragment to the 5.0 index.
- Merge #82 only after the Konflux check is green.

### 4. Release plumbing

- The stage and prod RPAs template `fromIndex` and `targetIndex` from the OCP version. ART's ACM and MCE 5.0 FBC releases already use the
  same pattern.
- The Submariner RPAs reuse the shared `fbc-stage` and `fbc-standard` policies. No policy change is needed.
- First prod release only: every bundle repository referenced by the fragment must have `fbc_opt_in` set in Pyxis, or the release
  fails. The bundle repository (`rhacm2/submariner-operator-bundle`) is the same one the 4.x catalogs already reference, so it is likely
  already opted in. That is not verifiable from the local `pyxis-repo-configs` clone, so confirm before the first prod release.
- Confirm the `v5.0` target index is being published before a prod release. ART's ACM and MCE 5.0 FBC RPAs exist, but the docs describe a
  separate pre-GA index path for content ahead of an OCP GA. Release to stage first and check the index.
- The fragment must be multi-arch for pre-GA use or multi-platform testing. The 5-0 pipelines build all four platforms.
- `submariner-release-management` accepts `OCP=5.0`. Add `5-0` to the active list in `scripts/lib/fbc-scope.sh` only after step 5.

### 5. Evidence before claiming OCP 5 support

A green catalog build only proves packaging.

- `deploy-operator` actually ran, with the approved bundle digest and channel.
- The provisioned cluster reports 5.0 (`oc get clusterversion version -o json`).
- The upstream pipeline skips installation for PR events or when there is no unreleased bundle. 0.24.0 and 0.24.1 are already released, so
  use the explicit-bundle QE install procedure on an observed 5.0.x cluster.
- Manual alternative (from the Konflux FBC docs): point a `CatalogSource` at the built fragment on a 5.0 test cluster and install through
  an OLM `Subscription`. Add an `ImageDigestMirrorSet` if the bundle's image pullspecs are not reachable.
- After deployment run
  `add-fbc-ocp-version.sh 5.0 --phase verify-live --expected-commit <merged SHA>` from `submariner-release-management`.
  It checks live resources, the four-platform catalogs and the snapshot tests.

## Known follow-ups (out of scope for #82)

- `fbc-fips-check`, `run-opm-command` and `validate-fbc` digests in every FBC pipeline (4.x and 5.0) expire on 2026-10-30. Newer trusted
  digests exist. Needs a repo-wide bump PR.
- The published `submariner.v0.24.0` bundle image is labeled `csv-version=0.24.1`, though its CSV is 0.24.0. `update-bundle` now checks
  that label, so re-running it for 0.24.0 would fail.
- The OCP 5 minimum Submariner stream (currently provisional 0.24) is still a rollout policy decision.

## Open decisions

- Is the submariner tenant already approved for the OpenShift CI profile, or does access need to be requested now?
- Who opens the GitLab merge requests (VPN and GitLab credentials are needed to push)?
