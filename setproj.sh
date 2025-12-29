#!/bin/bash
# Universal GCP context switcher for: genosis-prod
export PROJECT_ID="genosis-prod"
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
export CLOUDSDK_CORE_PROJECT="$PROJECT_ID"
export GCLOUD_PROJECT="$PROJECT_ID"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

echo -e "\033[0;32mSwitched to: $PROJECT_ID\033[0m"
echo "   Genosis Droid Foundry"
echo "   https://console.cloud.google.com/?project=$PROJECT_ID"
