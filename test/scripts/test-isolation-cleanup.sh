#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"
scratch=$(mktemp -d)
trap 'chmod -R u+rwX "$scratch"; rm -rf "$scratch"' EXIT
mkdir -p "$scratch/source/test/"{lib,scripts} "$scratch/children"
cp test/lib/isolate.sh "$scratch/source/test/lib/"
cat > "$scratch/source/test/scripts/probe.sh" <<'PROBE'
#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"
mkdir read-only
printf retain > read-only/input
chmod 500 read-only
exit 7
PROBE
if TMPDIR="$scratch/children" bash "$scratch/source/test/scripts/probe.sh"; then
  echo 'Failed child unexpectedly succeeded' >&2
  exit 1
else
  test "$?" = 7
fi
[ -z "$(ls -A "$scratch/children")" ]
echo 'Failed isolated tests clean read-only files and preserve their exit status'
