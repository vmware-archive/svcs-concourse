#!/bin/bash
set -ex

management_dir=$1
credentials_dir=$2
addon_dir=$3

pushd ${addon_dir}
ipsec_version=$(ls *.tgz | sed -r 's/ipsec-(.+).tgz/\1/')
echo "Addon: ${ipsec_version}"
popd

script_dir=$(dirname "$(readlink -f "$0")")

echo "Generating certs"
${script_dir}/openssl-create-ipsec-certs.sh
ls ./certs

echo "Filling in template"
pip install jinja2

python <<EOF
import jinja2

instance_certificate = open("./certs/pcf-ipsec-peer-cert.pem").read()
instance_private_key = open("./certs/pcf-ipsec-peer-key.pem").read()
ca_certificates = open("./certs/pcf-ipsec-ca-cert.pem").read()

vals = {
    'ipsec_version': '${ipsec_version}',
    'gcp_terraform_subnet_ops_manager': '${gcp_terraform_subnet_ops_manager}',
    'gcp_terraform_subnet_ert': '${gcp_terraform_subnet_ert}',
    'gcp_terraform_subnet_services_1': '${gcp_terraform_subnet_services_1}',
    'instance_certificate': instance_certificate,
    'instance_private_key': instance_private_key,
    'ca_certificates': ca_certificates
}

with open('${script_dir}/../../manifest_templates/ipsec-addon.yml', 'r') as template_file:
    template = template_file.read()
    rendered = jinja2.Template(template).render(vals)
    with open('ipsec-addon.yml', 'w') as rendered_file:
        rendered_file.write(rendered)

EOF

echo "Copy over template"
${management_dir}/ci/tasks/scp_to_opsman.sh ${credentials_dir} ipsec-addon.yml

echo "Updating runtime config (assuming already logged in to BOSH)"
bosh_command='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'
${management_dir}/ci/tasks/ssh_on_opsman.sh ${credentials_dir} << EOF
set -ex

${bosh_command} update runtime-config ipsec-addon.yml
EOF

exit 1
