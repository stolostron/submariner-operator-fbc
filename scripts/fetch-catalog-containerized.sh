#! /bin/bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ocp_version=${1:-}

if ! [[ ${ocp_version} =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "error: Must provide a positional argument corresponding to the target OCP X.Y version."
  exit 1
fi

package=${2:-}

if ! [[ ${package} =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
  echo "error: Must provide a valid operator package name (letters, digits, dots, and hyphens)."
  exit 1
fi

# Index image to pull from (set the OCP version tag as appropriate)
# Must be docker-auth'd https://access.redhat.com/articles/RegistryAuthentication
catalog_image=registry.redhat.io/redhat/redhat-operator-index:v${ocp_version}

# Extract only the requested package. Exporting the whole index also copies
# unrelated packages and its large cache, and can exhaust temporary storage.
TEMP_EXTRACT_DIR=$(mktemp -d -p .)
CONTAINER_ID=""
cleanup() {
  if [ -n "$CONTAINER_ID" ]; then podman rm "$CONTAINER_ID" >/dev/null; fi
  chmod -R u+rwX "$TEMP_EXTRACT_DIR"
  rm -rf "$TEMP_EXTRACT_DIR"
}
trap cleanup EXIT
podman pull "$catalog_image"
CONTAINER_ID=$(podman create "$catalog_image")
podman cp "$CONTAINER_ID:/configs/$package/." "$TEMP_EXTRACT_DIR"
chmod -R u+rwX "$TEMP_EXTRACT_DIR"
OPM_IMAGE="quay.io/operator-framework/opm:v1.65.0"
(cat "$TEMP_EXTRACT_DIR/package.json" "$TEMP_EXTRACT_DIR"/channels/*.json "$TEMP_EXTRACT_DIR"/bundles/*.json) | \
  podman run --rm -i -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "$OPM_IMAGE" \
  alpha convert-template basic -o=yaml - >"$TEMP_EXTRACT_DIR/catalog.yaml"
mv "$TEMP_EXTRACT_DIR/catalog.yaml" "${package}-catalog-config-${ocp_version}.yaml"
