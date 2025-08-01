#! /bin/bash

set -e

if [[ $(basename "${PWD}") != "submariner-operator-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

echo "This script generates a set of catalog templates, one for each supported OCP version."
echo "The templates are generated from the base catalog-template.yaml file, and then pruned"
echo "based on the versions defined in drop-versions.json."
echo
echo "Using drop version Submariner map:"
echo "    (Keys are OCP versions, values are the minimum Submariner version to include for that OCP version.)"
jq '.' drop-versions.json

ocp_versions=$(jq -r 'keys[]' drop-versions.json)

shouldPrune() {
  oldest_version="$(jq -r ".[\"${1}\"]" drop-versions.json).99"

  [[ "$(printf "%s\n%s\n" "${2}" "${oldest_version}" | sort --version-sort | tail -1)" == "${oldest_version}" ]]

  return $?
}

for version in ${ocp_versions}; do
  cp catalog-template.yaml "catalog-template-${version//./-}.yaml"
  # OPM does not like comments, will fail with a JSON parsing error, so remove them
  grep -v '^#' "catalog-template-${version//./-}.yaml" > "catalog-template-${version//./-}.yaml.tmp"
  mv "catalog-template-${version//./-}.yaml.tmp" "catalog-template-${version//./-}.yaml"
done

# Prune old X.Y channels
echo
echo "# Pruning channels and bundles..."
echo "Based on the drop-versions.json map, we will now prune channels and bundles that are not supported for each OCP version."
for channel in $(yq '.entries[] | select(.schema == "olm.channel").name' catalog-template.yaml); do
  echo "  Found channel: ${channel}"
  for ocp_version in ${ocp_versions}; do
    # Special case, acm-2.6 channel was only there until OCP 4.14
    if [ "${ocp_version}" != "4.14" ] && [ "${channel}" == "acm-2.6" ]; then
      echo "  - Pruning channel from OCP ${ocp_version}: ${channel} ..."
      yq '.entries[] |= select(.schema == "olm.channel") |= del(select(.name == "'"${channel}"'"))' -i "catalog-template-${ocp_version//./-}.yaml"

      continue
    fi

    if shouldPrune "${ocp_version}" "${channel#*\-}"; then
      echo "  - Pruning channel from OCP ${ocp_version}: ${channel} ..."
      yq '.entries[] |= select(.schema == "olm.channel") |= del(select(.name == "'"${channel}"'"))' -i "catalog-template-${ocp_version//./-}.yaml"

      continue
    fi

    # Prune old bundles from channels
    for entry in $(yq '.entries[] | select(.schema == "olm.channel") | select(.name == "'"${channel}"'").entries[].name' catalog-template.yaml); do
      version=${entry#*\.v}
      if shouldPrune "${ocp_version}" "${version}"; then
        echo "  - Pruning entry from OCP ${ocp_version}: ${entry}"
        yq '.entries[] |= select(.schema == "olm.channel") |= select(.name == "'"${channel}"'").entries[] |= del(select(.name == "'"${entry}"'"))' -i "catalog-template-${ocp_version//./-}.yaml"
      fi

    done

    # If Only one entry in this channel, make sure no "replaces" field (as there is nothing to replace)
    channel_entries=$(yq '.entries[] | select(.schema == "olm.channel") | select(.name == "'"${channel}"'").entries | length' "catalog-template-${ocp_version//./-}.yaml")
    if [[ "${channel_entries}" == "1" ]]; then
      echo "  - Channel ${channel} for OCP ${ocp_version} has only one bundle, removing the 'replaces' field."
      yq '.entries[] |= select(.schema == "olm.channel") |= select(.name == "'"${channel}"'").entries[0] |= del(.replaces)' -i "catalog-template-${ocp_version//./-}.yaml"
    fi
  done
done
echo

# Prune old bundles
echo "# Removing unsupported bundle versions from OCP catalog templates:"
echo "  This step iterates through each bundle and removes it from specific OCP catalog templates"
echo "  if its version is older than the minimum supported Submariner version for that OCP."
for bundle_image in $(yq '.entries[] | select(.schema == "olm.bundle").image' catalog-template.yaml); do
  bundle_version=$(skopeo inspect --override-os=linux --override-arch=amd64 "docker://${bundle_image}" | jq -r ".Labels.version")
  echo "  Processing bundle version: ${bundle_version}"
  pruned_count=0
  for ocp_version in ${ocp_versions}; do
    if shouldPrune "${ocp_version}" "${bundle_version#v}"; then
      echo "  - Pruning bundle ${bundle_version} from OCP ${ocp_version} ..."
      echo "    (image ref: ${bundle_image})"
      yq '.entries[] |= select(.schema == "olm.bundle") |= del(select(.image == "'"${bundle_image}"'"))' -i "catalog-template-${ocp_version//./-}.yaml"
      ((pruned_count++))
    else
      echo "    - Keeping bundle ${bundle_version} for OCP ${ocp_version}."
    fi
  done
  if [[ ${pruned_count} -gt 0 ]]; then
    echo "  Finished processing ${bundle_version}. It was pruned from ${pruned_count} OCP versions."
  else
    echo "  Finished processing ${bundle_version}. It was not pruned from any OCP versions."
  fi
done
