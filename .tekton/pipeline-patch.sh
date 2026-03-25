#! /bin/bash

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

for konflux_file in "${dir}"/volsync-fbc-*.yaml; do
  echo "Updating $(basename "${konflux_file}") ..."

  # Enable hermetic builds (isolated, reproducible build environment)
  has_hermetic=$(yq -o yaml '.spec.params | any_c(.name == "hermetic")' "${konflux_file}")
  if [[ ${has_hermetic} == false ]]; then
    yq '.spec.params |= . + [{"name":"hermetic","value":"true"}]' -i "${konflux_file}"
  fi

  # Configure multi-arch for production push pipelines (PR pipelines build for validation only)
  if [[ "${konflux_file}" =~ "push" ]]; then
    echo "  Patching pipeline for multi-arch ..."
    yq '.spec.params[] |= select(.name == "build-platforms").value = ["linux/x86_64", "linux/ppc64le", "linux/s390x", "linux/arm64"]' -i "${konflux_file}"
  fi

  # Add image build-arg
  has_build_args=$(yq -o yaml '.spec.params | any_c(.name == "build-args")' "${konflux_file}")
  catalog_version=$(jq -r 'keys[0]' "${dir}/../drop-versions.json")

  if [[ ${has_build_args} == false ]]; then
    version=$(echo "${konflux_file}" | grep -oE "[0-9]-[0-9]+")
    for next_version in $(jq -r 'keys[]' "${dir}/../drop-versions.json"); do
      if [[ "${version//-/.}" == "${next_version}" ]]; then
        catalog_version=${next_version}
      fi
    done

    echo "  CATALOG version is: ${catalog_version} ..."

    # OCP 4.14 uses RHEL 8-based operator-registry; 4.15+ use RHEL 9
    if [[ "${catalog_version}" == "4.14" ]]; then
      yq '.spec.params |= . + [
        {
          "name":"build-args",
          "value":[
            "OPM_IMAGE=registry.redhat.io/openshift4/ose-operator-registry:v'"${version//-/.}"'",
            "INPUT_DIR=catalog-'"${catalog_version//./-}"'"
          ]
        }]' -i "${konflux_file}"
    else
      yq '.spec.params |= . + [
        {
          "name":"build-args",
          "value":[
            "OPM_IMAGE=registry.redhat.io/openshift4/ose-operator-registry-rhel9:v'"${version//-/.}"'",
            "INPUT_DIR=catalog-'"${catalog_version//./-}"'"
          ]
        }]' -i "${konflux_file}"
    fi
  fi
done
