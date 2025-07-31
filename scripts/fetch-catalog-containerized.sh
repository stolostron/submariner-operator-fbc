#! /bin/bash

set -ex

if [[ $(basename "${PWD}") != "submariner-operator-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

ocp_version=${1}

if ! [[ ${ocp_version} =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "error: Must provide a positional argument corresponding to the target OCP X.Y version."
  exit 1
fi

package=${2}

if [[ -z ${package} ]]; then
  echo "error: Must provide a second positional argument operator package name."
  exit 1
fi

# Index image to pull from (set the OCP version tag as appropriate)
# Must be docker-auth'd https://access.redhat.com/articles/RegistryAuthentication
catalog_image=registry.redhat.io/redhat/redhat-operator-index:v${ocp_version}

# Pull the catalog from the image
./scripts/image_extract.sh "${catalog_image}" "${TEMP_EXTRACT_DIR}"

# The image_extract.sh script extracts the image to a directory named after the image ID.
# We need to determine that directory name.
DIR_NAME=$(echo "${catalog_image}" | sed -e 's/[^a-zA-Z0-9._-]/_/g')
EXTRACTED_CATALOG_PATH="${TEMP_EXTRACT_DIR}/${DIR_NAME}"

OPM_IMAGE="quay.io/operator-framework/opm:latest"

podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
  alpha convert-template basic -o=yaml ./"${EXTRACTED_CATALOG_PATH}/configs/${package}/catalog.json" >"${package}-catalog-config-${ocp_version}.yaml"

rm -rf ./"${EXTRACTED_CATALOG_PATH}"
