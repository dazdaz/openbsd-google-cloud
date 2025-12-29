# Authenticate with Google Cloud
gcloud auth login

# Set your default project
source ./setproj.sh

# Create the GCS bucket (if it doesn't exist)
gsutil mb -p genosis-prod gs://genosis-prod-images/

./01-build-openbsd-image.sh \
   --auto-install \
   --version 7.8 \
   --memory 2G \
   --cpus 2 \
   --disk-size 30G \
   --output ./build --verbose

./02-setup-gcp-service-account.sh setup

# This will create openbsd-7.8-<date>mbr.raw.gz and openbsd-7.8-uefi.raw.gz
# Don't use 7.8, use hyphens instead of periods in version numbers - dots, underscore and uppercase is not allowed for image name
./03-gcp-image-import.sh \
  --name openbsd-7-8-$(date +%Y%m%d) \
  --image-file build/artifacts/openbsd-7.8.raw.gz \
  --bucket genosis-prod-images \
  --project-id genosis-prod \
  --zone us-central1-a \
  --create-both \
  --family openbsd \
  --force

gcloud compute instances create openbsd-prod \
  --machine-type=n2-standard-2 \
  --image=openbsd-7-8-20251112-uefi \
  --boot-disk-size=30GB \
  --zone=us-central1-a \
  --project=genosis-prod


gcloud compute migration image-imports list --project=genosis-prod --location=us-central1

gcloud compute images list \
    --project=genosis-prod \
    --filter='family:openbsd'

gcloud compute migration image-imports describe openbsd-7-8-20251112-uefi \
  --project=genosis-prod \
  --location=us-central1

