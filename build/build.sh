#!/bin/bash
# Build into a sibling staging directory; publish only after every catalog validates.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stage=$(mktemp -d "$root/.catalog-build.XXXXXX")
lock="$root/.catalog-build.lock"
if ! mkdir "$lock" 2>/dev/null; then
  rm -rf "$stage"
  echo "Another catalog build holds $lock" >&2
  exit 1
fi
versions=()
committed=false
cleanup() {
  local status=$? version rollback_failed=false
  trap '' INT TERM
  if ! "$committed"; then
    for version in "${versions[@]}"; do
      # Filesystem state is authoritative, including a signal immediately after mv.
      if [ -e "$stage/previous-$version" ]; then
        if ! rm -rf "$root/catalog-$version" || ! mv "$stage/previous-$version" "$root/catalog-$version"; then
          rollback_failed=true
        fi
      elif [ -f "$stage/absent-$version" ]; then
        rm -rf "$root/catalog-$version" || rollback_failed=true
      fi
    done
  fi
  if "$rollback_failed"; then
    echo "Rollback failed; originals retained in $stage; lock retained at $lock" >&2
    return 1
  fi
  rm -rf "$stage"
  rmdir "$lock"
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$stage/scripts" "$stage/bin"
cp "$root/catalog-template.yaml" "$root/drop-versions.json" "$stage/"
cp "$root/scripts/"{generate-catalog-template,render-catalog,format-yaml}.sh "$stage/scripts/"
cp "$root/bin/opm" "$stage/bin/opm"
cd "$stage"
./scripts/generate-catalog-template.sh
./scripts/render-catalog.sh
./scripts/format-yaml.sh
mapfile -t versions < <(jq -r 'keys[] | gsub("\\."; "-")' drop-versions.json)
for version in "${versions[@]}"; do
  ./bin/opm validate "catalog-$version"
done
# All fallible render/validation work finished. Preserve unrelated/unmapped paths.
for version in "${versions[@]}"; do
  if [ -e "$root/catalog-$version" ]; then
    mv "$root/catalog-$version" "$stage/previous-$version"
  else
    touch "$stage/absent-$version"
  fi
  mv "$stage/catalog-$version" "$root/catalog-$version"
done
committed=true
echo "Validated and published ${#versions[@]} catalogs."
