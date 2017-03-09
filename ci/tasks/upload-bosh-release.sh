#!/bin/bash
set -e

echo "$1"
echo "$2"

echo "Hard-coding to gcp right now"
$1/ci/tasks/gcp-tools-setup.sh

# gcloud compute copy-files

echo "Just testing a gcloud command"
gcloud compute instances list

exit 1
