#!/bin/bash

set -e

catalog_template_path=${1}
bundle_version=${2}

if [[ -z "${catalog_template_path}" || -z "${bundle_version}" ]]; then
  echo "error: Missing arguments. Usage: remove-bundle.sh <catalog_template_path> <bundle_version>"
  exit 1
fi

bundle_name="submariner.${bundle_version}"
bundle_image=$(yq e '.entries[] | select(.schema == "olm.bundle") | select(.name == "'"${bundle_name}"'").image' "${catalog_template_path}")

if [[ -z "${bundle_image}" ]]; then
  echo "error: Bundle with version ${bundle_version} not found in ${catalog_template_path}"
  exit 1
fi

# Remove bundle entry
yq e 'del(.entries[] | select(.image == "'"${bundle_image}"'"))' -i "${catalog_template_path}"

# Remove bundle from channels
yq e '(.entries[] | select(.schema == "olm.channel").entries) |= del(.[] | select(.name == "'"${bundle_name}"'"))' -i "${catalog_template_path}"

# Remove empty channels
yq e 'del(.entries[] | select(.schema == "olm.channel" and .entries | length == 0))' -i "${catalog_template_path}"
