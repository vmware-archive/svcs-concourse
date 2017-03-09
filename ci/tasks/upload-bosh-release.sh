#!/bin/bash
set -e

management_dir=$1
addon_dir=$2

echo "Inputs"
echo "management_dir: ${management_dir}"
echo "addon_dir: ${addon_dir}"

echo "Setup gcp auth"
management_dir/ci/tasks/gcp-tools-setup.sh

pushd addon_dir
addon=$(ls *.tgz)
echo "Addon: ${addon}"

gcloud compute copy-files ${addon} ${terraform_prefix}-ops-manager

popd

exit 1
