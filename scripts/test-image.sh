#!/bin/bash
# Validate and serve one image in a container owned by this invocation.
set -euo pipefail
image=${1:?image required}
grpcurl=${2:?grpcurl path required}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
cleanup() {
  if [ -s "$tmp/cid" ]; then podman rm -f "$(cat "$tmp/cid")" >/dev/null; fi
  rm -rf "$tmp"
}
trap cleanup EXIT
podman run --rm --entrypoint /bin/opm "$image" validate /configs
podman run --cidfile "$tmp/cid" -d -p 127.0.0.1::50051 "$image" >/dev/null
container=$(cat "$tmp/cid")
endpoint=$(podman port "$container" 50051/tcp)
for attempt in 1 2 3 4 5; do
  if "$grpcurl" -plaintext "$endpoint" list >/dev/null 2>&1; then break; fi
  [ "$attempt" -eq 5 ] || sleep 2
done
"$grpcurl" -plaintext "$endpoint" api.Registry.ListPackages > "$tmp/packages.json"
diff -u "$root/test/packageList.json" "$tmp/packages.json"
echo "Catalog validated; registry serves the expected packages."
