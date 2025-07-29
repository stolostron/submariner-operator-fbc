#!/bin/bash

set -ex

bundle_image=${1}

if [[ -z "${bundle_image}" ]]; then
  echo "error: the bundle image must be provided as a positional argument."
  exit 1
fi

if [[ "${bundle_image}" == "DUMMY_BUNDLE_IMAGE" ]]; then
  bundle_json='{
    "Digest": "sha256:d404c010f2134b00000000000000000000000000000000000000000000000000",
    "Labels": {
      "version": "v0.0.1",
      "operators.operatorframework.io.bundle.channels.v1": "alpha"
    }
  }'
else
  bundle_json=$(skopeo inspect --override-os=linux --override-arch=amd64 "docker://${bundle_image}")
fi

bundle_digest=$(echo "${bundle_json}" | jq -r ".Digest")
bundle_version=$(echo "${bundle_json}" | jq -r ".Labels.version")
bundle_channels=$(echo "${bundle_json}" | jq -r '.Labels["operators.operatorframework.io.bundle.channels.v1"]')

# Output as key-value pairs for easy parsing by other scripts
echo "BUNDLE_DIGEST=${bundle_digest}"
echo "BUNDLE_VERSION=${bundle_version}"
echo "BUNDLE_CHANNELS=${bundle_channels}"
echo "BUNDLE_IMAGE=${bundle_image}"
