#!/bin/bash
set -e

stemcells="$*"

sudo cp tool-om/om-linux /usr/local/bin
sudo chmod 755 /usr/local/bin/om-linux

for stemcell in ${stemcells}
do
  echo "=============================================================================================="
  echo " Uploading stemcell ${stemcell} to @ https://opsman.$pcf_ert_domain ..."
  echo "=============================================================================================="

  ##Upload p-mysql Tile

  om-linux --target https://opsman.$pcf_ert_domain -k \
         --username "$pcf_opsman_admin" \
         --password "$pcf_opsman_admin_passwd" \
        upload-stemcell \
        --stemcell ${stemcell}
done
