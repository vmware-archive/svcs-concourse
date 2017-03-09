#!/bin/bash
set -ex

management_dir=$1
credentials_dir=$2
om_dir=$3
addon_dir=$4

echo "Inputs"
echo "management_dir: ${management_dir}"
echo "addon_dir: ${addon_dir}"

echo "Setup gcp auth"
${management_dir}/ci/tasks/gcp-tools-setup.sh

pushd ${addon_dir}
addon=$(ls *.tgz)
echo "Addon: ${addon}"
popd

chmod 600 $credentials_dir/${terraform_prefix}.opsman_rsa
address=$(gcloud compute --format=json instances describe ${terraform_prefix}-ops-manager | jq -r .networkInterfaces[0].accessConfigs[0].natIP)

scp -o "StrictHostKeyChecking no" -i $credentials_dir/${terraform_prefix}.opsman_rsa ${addon_dir}/${addon} ubuntu@${address}:~

chmod +x $om_dir/om-linux
director_credentials=$($om_dir/om-linux -t https://opsman.$pcf_ert_domain -k \
            -u "$pcf_opsman_admin" \
            -p "$pcf_opsman_admin_passwd" \
            curl -p /api/v0/deployed/director/credentials/director_credentials
)

bosh_password=$(echo $director_credentials | jq -r ".credential.value.password")
bosh_command='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'

ssh -o "StrictHostKeyChecking no" -i $credentials_dir/${terraform_prefix}.opsman_rsa ubuntu@${address} << EOF
set -ex

echo "" | ${bosh_command} --ca-cert /var/tempest/workspaces/default/root_ca_certificate target 192.168.101.10 || true
echo "director
${bosh_password}" | ${bosh_command} login
${bosh_command} upload release ${addon}
EOF

