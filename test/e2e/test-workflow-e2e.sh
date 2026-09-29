#!/bin/bash
# A read-only live snapshot lookup followed by a real update in a disposable repo.
# TEST_VERSION (default newest catalog bundle) and TEST_SNAPSHOT can pin test data.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"
for tool in oc skopeo yq jq; do command -v "$tool" >/dev/null; done
oc whoami >/dev/null
TEST_VERSION=${TEST_VERSION:-$(yq '.entries[] | select(.schema == "olm.bundle") | .name' catalog-template.yaml | sed 's/^submariner.v//' | sort -V | tail -1)}
[[ "$TEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Specify a stable TEST_VERSION' >&2; exit 1; }
stream=${TEST_VERSION%.*}
application="submariner-${stream//./-}"
component="submariner-bundle-${stream//./-}"
snapshot_file=$(mktemp)
trap 'rm -f "$snapshot_file"' EXIT
if [ -n "${TEST_SNAPSHOT:-}" ]; then
  oc get snapshot "$TEST_SNAPSHOT" -n submariner-tenant -o json > "$snapshot_file"
else
  oc get snapshots -n submariner-tenant -l "appstudio.openshift.io/application=$application" -o json |
    jq -e --arg app "$application" '
      [.items[] | select(.spec.application == $app and
        .metadata.labels["pac.test.appstudio.openshift.io/event-type"] == "push")]
      | sort_by(.metadata.creationTimestamp) | last // error("No push snapshot")' > "$snapshot_file"
fi
snapshot=$(jq -er '.metadata.name' "$snapshot_file")
image=$(jq -er --arg app "$application" --arg component "$component" '
  select(.spec.application == $app and .metadata.labels["pac.test.appstudio.openshift.io/event-type"] == "push")
  | [.spec.components[] | select(.name == $component)]
  | select(length == 1) | .[0].containerImage' "$snapshot_file")
actual_version=$(skopeo inspect --format '{{ index .Labels "csv-version" }}' "docker://$image")
[ "$actual_version" = "$TEST_VERSION" ] || { echo "Snapshot bundle is $actual_version, requested $TEST_VERSION" >&2; exit 1; }
# Never hide pending, failed, warning, or absent results in a successful E2E report.
jq -e '.metadata.annotations["test.appstudio.openshift.io/status"] | fromjson |
  type == "array" and length > 0 and all(.[]; .status == "TestPassed")' "$snapshot_file" >/dev/null || {
  echo "Snapshot $snapshot does not report completed TestPassed results:" >&2
  jq -r '.metadata.annotations["test.appstudio.openshift.io/status"]' "$snapshot_file" >&2
  exit 1
}
# Force a controlled UPDATE even if the candidate already has this digest. The
# dummy old reference is replaced before rendering; every rendered image is real.
TEST_VERSION="$TEST_VERSION" yq -e '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v" + strenv(TEST_VERSION))' catalog-template.yaml >/dev/null
TEST_VERSION="$TEST_VERSION" yq -i '(.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v" + strenv(TEST_VERSION)) | .image) = "quay.io/example/old@sha256:0000000000000000000000000000000000000000000000000000000000000000"' catalog-template.yaml
before=$(git rev-parse HEAD)
./scripts/update-bundle.sh --version "$TEST_VERSION" --snapshot "$snapshot"
[ "$(git rev-parse HEAD)" != "$before" ]
sha=${image##*@}
[ "$(TEST_VERSION="$TEST_VERSION" yq '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v" + strenv(TEST_VERSION)) | .image' catalog-template.yaml | sed 's/.*@//')" = "$sha" ]
count=0
for version in $(jq -r 'keys[]' drop-versions.json); do
  catalog="catalog-${version//./-}"
  test -d "$catalog"
  ./bin/opm validate "$catalog"
  cutoff=$(jq -r --arg version "$version" '.[$version]' drop-versions.json)
  # The map drops all patches through the cutoff Y-stream.
  if [ "$(printf '%s\n' "$cutoff" "$stream" | sort -V | tail -1)" = "$stream" ] && [ "$stream" != "$cutoff" ]; then
    test -s "$catalog/bundles/bundle-v$TEST_VERSION.yaml"
    [ "$(yq '.image' "$catalog/bundles/bundle-v$TEST_VERSION.yaml" | sed 's/.*@//')" = "$sha" ]
  else
    test ! -e "$catalog/bundles/bundle-v$TEST_VERSION.yaml"
  fi
  count=$((count + 1))
done
echo "PASS: real snapshot $snapshot, bundle $TEST_VERSION, $count validated catalogs, fixture commit"
