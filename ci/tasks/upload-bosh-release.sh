#!/bin/bash
set -e

management_dir=$1
credentials_dir=$2
addon_dir=$3

echo "Inputs"
echo "management_dir: ${management_dir}"
echo "addon_dir: ${addon_dir}"

pushd ${addon_dir}
addon=$(ls *.tgz)
echo "Addon: ${addon}"
popd

echo "Copying across add-on"
${management_dir}/ci/tasks/scp-to-opsman.sh ${credentials_dir} ${addon_dir} ${addon}

bosh_command='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'

${management_dir}/ci/tasks/ssh-on-opsman.sh ${credentials_dir} << EOF
set -e

${bosh_command} upload release ${addon}
EOF
