#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"
source scripts/lib/test-helpers.sh
source scripts/lib/catalog-functions.sh
source test/lib/mock-commands.sh
source test/lib/test-constants.sh
source_function_from_script find_snapshot scripts/update-bundle.sh
source_function_from_script create_commit scripts/update-bundle.sh
create_oc_mock "$TEST_SNAPSHOT_21_ABC123" "$TEST_BUNDLE_QUAY_21_ABC123" "$TEST_VERSION_21_2"
setup_mock_bin_dir
trap cleanup_mocks EXIT
create_skopeo_mock 0
export VERSION=$TEST_VERSION_21_2
export YSTREAM_DASH=$TEST_Y_STREAM_21
SNAPSHOT=""
find_snapshot >/dev/null
test "$SNAPSHOT" = "$TEST_SNAPSHOT_21_ABC123"
for status in '[]' '{}' 'broken' '[{"scenario":"standard","status":"BuildPLRInProgress"}]' '[{"scenario":"standard","status":"TestWarning"}]'; do
  export MOCK_TEST_STATUS=$status
  if (find_snapshot) >/dev/null 2>&1; then echo "Accepted incomplete result: $status" >&2; exit 1; fi
done
unset MOCK_TEST_STATUS
export VERSION=0.21.99
if (find_snapshot) >/dev/null 2>&1; then echo 'Accepted wrong bundle patch version' >&2; exit 1; fi
export VERSION=$TEST_VERSION_21_2
# Keep unrelated staged changes and unconfigured catalog directories out of commits.
echo unrelated > unrelated-file
git add unrelated-file
mkdir catalog-unrelated
echo retain > catalog-unrelated/note
echo '# update fixture' >> catalog-template.yaml
export SCENARIO=UPDATE
create_commit >/dev/null
test "$(git diff --cached --name-only)" = unrelated-file
! git ls-files --error-unmatch catalog-unrelated/note >/dev/null 2>&1
test "$(git show --format= --name-only HEAD)" = catalog-template.yaml
echo 'Snapshot readiness, bundle version, and scoped commit regressions passed'
