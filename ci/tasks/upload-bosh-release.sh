#!/bin/bash
set -ex

management_dir=$1
credentials_dir=$2
om_dir=$3
addon_dir=$4

echo "Inputs"
echo "management_dir: ${management_dir}"
echo "addon_dir: ${addon_dir}"

pushd ${addon_dir}
addon=$(ls *.tgz)
echo "Addon: ${addon}"
popd

echo "Copying across add-on"
${management_dir}/ci/tasks/scp_to_opsman.sh ${credentials_dir} ${addon_dir} ${addon}

chmod +x $om_dir/om-linux
director_credentials=$($om_dir/om-linux -t https://opsman.$pcf_ert_domain -k \
            -u "$pcf_opsman_admin" \
            -p "$pcf_opsman_admin_passwd" \
            curl -p /api/v0/deployed/director/credentials/director_credentials
)

bosh_password=$(echo $director_credentials | jq -r ".credential.value.password")
bosh_command='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'

${management_dir}/ci/tasks/ssh_on_opsman.sh ${credentials_dir} << EOF
set -e

echo "" | ${bosh_command} --ca-cert /var/tempest/workspaces/default/root_ca_certificate target 192.168.101.10 || true
echo "director
${bosh_password}" | ${bosh_command} login
${bosh_command} upload release ${addon}
EOF
