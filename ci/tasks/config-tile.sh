#!/bin/bash
set -ex

product="$1"
if [ -z "${product}" ]; then
  echo "Error: Must supply product name"
  exit 1
fi

function fn_om_linux_curl {
    local curl_method=${1}
    local curl_path=${2}
    local curl_data=${3}

     curl_cmd="om-linux --target https://opsman.$pcf_ert_domain -k \
            --username \"$pcf_opsman_admin\" \
            --password \"$pcf_opsman_admin_passwd\"  \
            curl \
            --request ${curl_method} \
            --path ${curl_path}"

    if [[ ! -z ${curl_data} ]]; then
       curl_cmd="${curl_cmd} \
            --data '${curl_data}'"
    fi

    echo ${curl_cmd} > /tmp/rqst_cmd.log
    exec_out=$(((eval $curl_cmd | tee /tmp/rqst_stdout.log) 3>&1 1>&2 2>&3 | tee /tmp/rqst_stderr.log) &>/dev/null)

    if [[ $(cat /tmp/rqst_stderr.log | grep "Status:" | awk '{print$2}') != "200" ]]; then
      echo "Error Call Failed ...."
      echo $(cat /tmp/rqst_stderr.log)
      exit 1
    else
      echo $(cat /tmp/rqst_stdout.log)
    fi
}

#############################################################
#################### GCP Auth  & functions ##################
#############################################################
echo $gcp_svc_acct_key > /tmp/blah
gcloud auth activate-service-account --key-file /tmp/blah
rm -rf /tmp/blah

gcloud config set project $gcp_proj_id
gcloud config set compute/region $gcp_region

# Setup OM Tool
sudo cp tool-om/om-linux /usr/local/bin
sudo chmod 755 /usr/local/bin/om-linux

# Set Vars

echo "=============================================================================================="
echo "Finding p-bosh @ https://opsman.$pcf_ert_domain ..."
echo "=============================================================================================="
# Get Director Guid
director_guid=$(fn_om_linux_curl "GET" "/api/v0/deployed/products" \
            | jq ".[] | select(.type == \"p-bosh\") | .guid" | tr -d '"' | grep "p-bosh-.*")

echo "=============================================================================================="
echo "Finding p-bosh nats credentials @ https://opsman.$pcf_ert_domain ..."
echo "=============================================================================================="
director_nats_password=$(fn_om_linux_curl "GET" "/api/v0/deployed/products/${director_guid}/credentials/.director.nats_credentials" \
            | jq ".credential .value .password" | xargs echo)


# Set JSON Config Template and insert Concourse Parameter Values
json_file_path="svcs-concourse/json_templates"
json_file_template="${json_file_path}/${product}-template.json"
json_file="${json_file_path}/${product}.json"

pip install jinja2

python -c "
import jinja2
import string
import random

char_set = string.letters + string.digits + '_'

def password_gen():
	return ''.join(random.SystemRandom().choice(char_set) for _ in range(20))

vals = {
    'password_gen': password_gen,
    'gcp_region': '${gcp_region}',
    'gcp_zone_1': '${gcp_zone_1}',
    'gcp_zone_2': '${gcp_zone_2}',
    'gcp_zone_3': '${gcp_zone_3}',
    'gcp_terraform_prefix': '${gcp_terraform_prefix}',
    'gcp_terraform_subnet_ert': '${gcp_terraform_subnet_ert}',
    'gcp_terraform_subnet_ops_manager': '${gcp_terraform_subnet_ops_manager}',
    'gcp_terraform_subnet_services_1': '${gcp_terraform_subnet_services_1}',
    'pcf_ert_domain': '${pcf_ert_domain}',
    'gcp_storage_access_key': '${gcp_storage_access_key}',
    'gcp_storage_secret_key': '${gcp_storage_secret_key}',
    'director_nats_password': '${director_nats_password}'
}

with open('${json_file_template}', 'r') as template_file:
    template = template_file.read()
    rendered = jinja2.Template(template).render(vals)
    with open('${json_file}', 'w') as rendered_file:
        rendered_file.write(rendered)
"

if [[ ! -f ${json_file} ]]; then
  echo "Error: cant find file=[${json_file}]"
  exit 1
fi


echo "=============================================================================================="
echo "Finding ${product} @ https://opsman.$pcf_ert_domain ..."
echo "=============================================================================================="
# Get Product Guid
product_guid=$(fn_om_linux_curl "GET" "/api/v0/staged/products" \
            | jq ".[] | select(.type == \"${product}\") | .guid" | tr -d '"' | grep "${product}-.*")

echo "=============================================================================================="
echo "Found ${product} deployment with guid of ${product_guid}"
echo "=============================================================================================="

# Set Networks & AZs
json_net_and_az=$(cat ${json_file} | jq .networks_and_azs)
if [ ! "${json_net_and_az}" = "null" ]; then
  echo "=============================================================================================="
  echo "Setting Availability Zones & Networks for: ${product_guid}"
  echo "=============================================================================================="
  fn_om_linux_curl "PUT" "/api/v0/staged/products/${product_guid}/networks_and_azs" "${json_net_and_az}"
fi

# Set Product Properties
json_properties=$(cat ${json_file} | jq .properties)
if [ ! "${json_properties}" = "null" ]; then
  echo "=============================================================================================="
  echo "Setting Properties for: ${product_guid}"
  echo "=============================================================================================="
  fn_om_linux_curl "PUT" "/api/v0/staged/products/${product_guid}/properties" "${json_properties}"
fi

# Set Product Errands
json_errands=$(cat ${json_file} | jq .errands)
if [ ! "${json_errands}" = "null" ]; then
  echo "=============================================================================================="
  echo "Setting Errands for: ${product_guid}"
  echo "=============================================================================================="
  fn_om_linux_curl "PUT" "/api/v0/staged/products/${product_guid}/errands" "${json_errands}"
fi

# Set Resource Configs
json_jobs_configs=$(cat ${json_file} | jq .jobs )
if [ ! "${json_jobs_configs}" = "null" ]; then
  echo "=============================================================================================="
  echo "Setting Resource Job Properties for: ${product_guid}"
  echo "=============================================================================================="
  json_job_guids=$(fn_om_linux_curl "GET" "/api/v0/staged/products/${product_guid}/jobs" | jq .)

  for job in $(echo ${json_jobs_configs} | jq . | jq 'keys' | jq .[] | tr -d '"'); do

   json_job_guid_cmd="echo \${json_job_guids} | jq '.jobs[] | select(.name == \"${job}\") | .guid' | tr -d '\"'"
   json_job_guid=$(eval ${json_job_guid_cmd})
   if [ -z "${json_job_guid}" ]; then
     echo "---------------------------------------------------------------------------------------------"
     echo "No job named ${job} in this deployment - ignoring"
     continue
   fi
   json_job_config_cmd="echo \${json_jobs_configs} | jq '.[\"${job}\"]' "
   json_job_config=$(eval ${json_job_config_cmd})
   echo "---------------------------------------------------------------------------------------------"
   echo "Setting ${json_job_guid} with --data=${json_job_config}..."
   fn_om_linux_curl "PUT" "/api/v0/staged/products/${product_guid}/jobs/${json_job_guid}/resource_config" "${json_job_config}"

  done
fi
