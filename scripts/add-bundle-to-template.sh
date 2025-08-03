#!/bin/bash

set -e

catalog_template_path=${1}
bundle_image=${2}
bundle_version=${3}
bundle_name="submariner.${bundle_version}"
bundle_channels=${4}

if [[ -z "${catalog_template_path}" || -z "${bundle_image}" || -z "${bundle_version}" || -z "${bundle_channels}" ]]; then
  echo "error: Missing arguments. Usage: add-bundle-to-template.sh <catalog_template_path> <bundle_image> <bundle_version> <bundle_channels>"
  exit 1
fi

# Add bundle entry
yq '.entries += {"name": "'"${bundle_name}"'", "image": "'"${bundle_image}"'", "schema": "olm.bundle"}' -i "${catalog_template_path}"

# Add bundle to channels
for channel in ${bundle_channels//,/ }; do
  echo "  Adding to channel: ${channel}"

  # Check if channel exists, create if not
  if [[ -z $(yq '.entries[] | select(.schema == "olm.channel") | select(.name == "'"${channel}"'")' "${catalog_template_path}") ]]; then
    echo "  Creating new ${channel} channel ..."
    yq '.entries += {"name": "'"${channel}"'", "package": "submariner", "schema": "olm.channel", "entries": []}' -i "${catalog_template_path}"
  fi

  # Add bundle to channel entries
  entries_in_channel=$(yq '.entries[] | select(.schema == "olm.channel") | select(.name == "'"${channel}"'").entries | length' "${catalog_template_path}")

  if [[ "${entries_in_channel}" == "0" ]]; then
    # No previous version to replace
    echo "    adding first version to entries (no replaces version)"
    yq '.entries[] |= select(.schema == "olm.channel") |= select(.name == "'"${channel}"'").entries += {"name": "'"${bundle_name}"'", "skipRange": ">= ${bundle_version#v} <${bundle_version#v}"}' -i "${catalog_template_path}"
  else
    replaces_version=$(yq '.entries[] | select(.schema == "olm.channel") | select(.name == "'"${channel}"'").entries[-1].name' "${catalog_template_path}")
    echo "    replaces_version is: ${replaces_version}"
    yq '.entries[] |= select(.schema == "olm.channel") |= select(.name == "'"${channel}"'").entries += {"name": "'"${bundle_name}"'", "replaces": "'"${replaces_version}"'", "skipRange": ">= ${bundle_version#v} <${bundle_version#v}"}' -i "${catalog_template_path}"
  fi
done

# Verify that the bundle is added to the catalog-template.yaml
if ! yq e '.entries[] | select(.schema == "olm.bundle") | select(.image == "'"${bundle_image}"'")' "${catalog_template_path}" > /dev/null; then
    echo "Error: Bundle '"${bundle_image}"' was NOT found in catalog-template.yaml. Test failed."
    exit 1
fi

echo "Verification: Bundle '"${bundle_image}"' successfully found in catalog-template.yaml."

# Verify that the bundle is added to the correct channels
for channel in ${bundle_channels//,/ }; do
    echo "Verifying bundle '"${bundle_name}"' presence in channel '"${channel}"'..."
    if ! yq e '.entries[] | select(.schema == "olm.channel") | select(.name == "'"${channel}"'").entries[] | select(.name == "'"${bundle_name}"'")' "${catalog_template_path}" > /dev/null; then
        echo "Error: Bundle '"${bundle_name}"' was NOT found in channel '"${channel}"'. Test failed."
        exit 1
    fi
    echo "Verification: Bundle '"${bundle_name}"' successfully found in channel '"${channel}"'."
done