#! /bin/bash

set -e

if [[ $(basename "${PWD}") != "submariner-operator-product-fbc" ]]; then
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
catalog_image=registry.redhat.io/redhat/redhat-operator-index:v${ocp_version}

# Pull the catalog from the image
opm migrate -o=yaml "${catalog_image}" ./catalog-migrate

# Convert package to basic template
opm alpha convert-template basic -o=yaml "./catalog-migrate/${package}/catalog.yaml" >"catalog-template-v${ocp_version}.yaml"
rm -r catalog-migrate/
