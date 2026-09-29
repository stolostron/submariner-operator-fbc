# Add a new OCP version

Use the `add-fbc-ocp-version` skill in `submariner-release-management`. Its
[workflow](https://github.com/stolostron/submariner-release-management/blob/main/.agents/workflows/add-fbc-ocp-version.md)
covers planning, separate tenant/admission configuration, catalog preparation,
and readiness. Run its packaged `skills/add-fbc-ocp-version/scripts/run.sh` by
absolute path from any directory, or invoke the helper directly:

```bash
/path/to/submariner-release-management/scripts/add-fbc-ocp-version.sh \
  5.0 --min-supported-sub 0.24 --phase plan \
  --fbc-repo /path/to/submariner-operator-fbc \
  --release-data-repo /path/to/konflux-release-data
```

The minimum is inclusive. `drop-versions.json` remains a drop-through map:
`"5.0": "0.23"` includes 0.24 and newer; `"5.0": "0.24"` removes 0.24.
Choose the supported stream explicitly. The template must already contain its
bundles and a populated default channel.

Configuration must reconcile before expecting PAC builds. A bot PR is optional:
look for the actual PR and inspect its files; if none exists, the helper prepares
a pipeline pair from the preceding merged version. Preserve the chosen pipeline
structure and validate names, labels, service account, CEL paths, all four
platforms, and event-specific image tags/expiry. Do not assume two commits or a
particular bot branch name.

OCP 5.0 uses `registry.redhat.io/openshift5/ose-operator-registry-rhel9:v5.0`.
The major changes its registry namespace, not its RHEL generation. Both push and
PR pipelines need `INPUT_DIR=catalog-5-0` and that exact OPM base. Preserve base
image annotations because the release pipeline derives the index version from
them. Shared stage/prod admissions already use a templated OCP index version.

`make build-catalogs` renders in a staging directory and validates every catalog
before publishing output. `make test` and individual test scripts copy candidate
files, including uncommitted changes, into disposable Git repositories. The reset
helper refuses to operate on a normal checkout. `make validate-catalogs` fails if
any catalog fails, including a newly introduced major version.

Select the catalog/base explicitly for a local image test:

```bash
make test-image CATALOG=catalog-5-0 \
  OPM_IMAGE=registry.redhat.io/openshift5/ose-operator-registry-rhel9:v5.0
```

A local amd64 image test is separate from Konflux's four-platform build. Check
image CI's selected catalogs; its public upstream OPM test does not replace the
explicit authenticated OCP-base command above. The onboarding helper verifies
each published platform's catalog contents against the merged Git source.
Check
required PR checks at the exact head SHA and the merged push build and snapshot.
Verify bundle identity and completed test scenarios, not snapshot existence.
Actual OCP 5 support additionally requires evidence that operator installation
ran on a cluster reporting 5.0. New 5.x overlays use the reviewed upstream 0.3
install path and the image-push secret's `.dockerconfigjson` key. Profile access
and an executed install still need evidence; the generic ITS can skip released
bundles, and an aggregate pass alone is insufficient.
