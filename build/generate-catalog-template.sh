#! /bin/bash

set -ex

if [[ $(basename "${PWD}") != "submariner-operator-product-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

echo "Using drop version Submariner-Product map:"
jq '.' drop-versions.json

ocp_versions=$(jq -r 'keys[]' drop-versions.json)

shouldPrune() {
  oldest_version="$(jq -r ".[\"${1}\"]" drop-versions.json).99"

  [[ "$(printf "%s\n%s\n" "${2}" "${oldest_version}" | sort --version-sort | tail -1)" == "${oldest_version}" ]]

  return $?
}

for version in ${ocp_versions}; do
  cp catalog-template.yaml "catalog-template-${version//./-}.yaml"
done

# Prune old X.Y channels
echo "# Pruning channels:"
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
    #channel_entriess=$(yq '.entries[] | select(.schema == "olm.channel") | select(.name == "'"${channel}"'").entries' "catalog-template-${ocp_version//./-}.yaml")
    #echo "###### CHANNEL entries for ${channel}: ${channel_entriess}" # TODO: remove
    channel_entries=$(yq '.entries[] | select(.schema == "olm.channel") | select(.name == "'"${channel}"'").entries | length' "catalog-template-${ocp_version//./-}.yaml")
    if [[ "${channel_entries}" == "1" ]]; then
      echo "  - OCP: ${ocp_version} CHANNEL: ${channel} - removing replaces as there is only 1 entry"
      yq '.entries[] |= select(.schema == "olm.channel") |= select(.name == "'"${channel}"'").entries[0] |= del(.replaces)' -i "catalog-template-${ocp_version//./-}.yaml"
    fi
  done
done
echo

# Prune old bundles
echo "# Pruning bundles:"
for bundle_image in $(yq '.entries[] | select(.schema == "olm.bundle").image' catalog-template.yaml); do
  bundle_version=$(skopeo inspect --override-os=linux --override-arch=amd64 "docker://${bundle_image}" | jq -r ".Labels.version")
  echo "  Found version: ${bundle_version}"
  pruned=0
  for ocp_version in ${ocp_versions}; do
    if shouldPrune "${ocp_version}" "${bundle_version#v}"; then
      echo "  - Pruning bundle ${bundle_version} from OCP ${ocp_version} ..."
      echo "    (image ref: ${bundle_image})"
      yq '.entries[] |= select(.schema == "olm.bundle") |= del(select(.image == "'"${bundle_image}"'"))' -i "catalog-template-${ocp_version//./-}.yaml"
    else
      ((pruned += 1))
    fi
  done
  #if ((pruned == $(jq 'keys | length' drop-versions.json))); then
  #  echo "  Nothing pruned--exiting."
  #  break
  #fi
done
