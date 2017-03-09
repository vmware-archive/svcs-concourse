#!/bin/bash
set -e

script_dir=$(dirname "$(readlink -f "$0")")

${script_dir}/openssl-create-ipsec-certs.sh

ls ${script_dir}/certs

exit 1
