#!/bin/bash
set -euo pipefail
# shellcheck source=test/lib/isolate.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"

# A 5-only map must generate a populated template, in an arbitrary directory name.
jq '{"5.0": "0.23"}' drop-versions.json > drop-versions.json.new
mv drop-versions.json.new drop-versions.json
./scripts/generate-catalog-template.sh >/dev/null
test -s catalog-template-5-0.yaml
DEFAULT_CHANNEL=$(yq '.entries[] | select(.schema == "olm.package").defaultChannel' catalog-template-5-0.yaml)
export DEFAULT_CHANNEL
yq -e '.entries[] | select(.schema == "olm.channel" and .name == strenv(DEFAULT_CHANNEL)) | .entries | length > 0' catalog-template-5-0.yaml >/dev/null

# A drop-through stream includes every patch number, not just patches <= 99.
prune_definition=$(sed -n '/^is_version_too_old()/,/^}/p' scripts/generate-catalog-template.sh)
eval "$prune_definition"
is_version_too_old 5.0 0.23.100
if is_version_too_old 5.0 0.24.0; then echo 'Inclusive stream was pruned' >&2; exit 1; fi

# Retry failed render stdout must not contaminate the eventual YAML stream.
retry_definition=$(sed -n '/^retry_command()/,/^}/p' scripts/render-catalog.sh)
eval "$retry_definition"
attempts=$(mktemp)
flaky() {
  if [ ! -s "$attempts" ]; then echo attempted > "$attempts"; echo 'partial: ['; return 1; fi
  echo 'schema: olm.package'
}
result=$(retry_command flaky 2>/dev/null)
[ "$result" = 'schema: olm.package' ]
rm -f "$attempts"

# Invalid new catalogs must be included in validation even when old catalogs pass.
mkdir -p catalog-5-0
printf 'broken: [\n' > catalog-5-0/package.yaml
if ./bin/opm validate catalog-5-0 >/dev/null 2>&1; then echo 'Invalid 5.0 catalog passed' >&2; exit 1; fi
if bash test/scripts/test-build.sh >/dev/null 2>&1; then echo 'Configured 5.0 catalog was skipped' >&2; exit 1; fi

# A render failure cannot destroy the candidate or unrelated untracked directories.
before=$(sha256sum catalog-5-0/package.yaml)
mkdir -p catalog-untracked
printf 'keep\n' > catalog-untracked/note
backup=$(mktemp)
cp -p bin/opm "$backup"
printf '#!/bin/bash\necho "injected render failure" >&2\nexit 1\n' > bin/opm
chmod +x bin/opm
if ./build/build.sh >/dev/null 2>&1; then echo 'Build accepted render failure' >&2; exit 1; fi
mv "$backup" bin/opm
[ "$(sha256sum catalog-5-0/package.yaml)" = "$before" ]
[ "$(cat catalog-untracked/note)" = keep ]
rm -rf catalog-untracked
./scripts/reset-test-environment.sh >/dev/null
# Reset must restore the candidate baseline, not another checkout's HEAD.
echo 'OCP major-version safety regressions passed'
