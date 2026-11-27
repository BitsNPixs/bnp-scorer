#!/bin/sh
# Builds and deploys the server to Cloud Run (README "API server").
# Needs the Google Cloud CLI and the Firebase CLI, both signed in with
# access to the project.
#   sh cloud/api/deploy.sh            build, deploy, and make sure the trigger exists
set -eu

PROJECT=bnp-scorer
REGION=asia-south1
SERVICE=bnp-api-projector
API=bnp-api
IMAGE=$REGION-docker.pkg.dev/$PROJECT/bnp-api/server:latest
ACCOUNT=bnp-api@$PROJECT.iam.gserviceaccount.com
READER=bnp-api-reader@$PROJECT.iam.gserviceaccount.com
ROOT=$(cd "$(dirname "$0")/../.." && pwd)

# Upload only what the image needs: the repo root holds far more.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/packages" "$STAGE/cloud"
for dir in packages/cricket_engine packages/match_view cloud/api; do
  rsync -a --exclude .dart_tool --exclude build "$ROOT/$dir" "$STAGE/$(dirname "$dir")/"
done

gcloud builds submit "$STAGE" --project "$PROJECT" --region "$REGION" \
  --config "$ROOT/cloud/api/cloudbuild.yaml" --substitutions "_IMAGE=$IMAGE"

# Private: only the Firestore trigger (and the owner, for a rebuild) may call
# it. Capped so a runaway can never cost much.
gcloud run deploy "$SERVICE" --project "$PROJECT" --region "$REGION" --image "$IMAGE" \
  --service-account "$ACCOUNT" --no-allow-unauthenticated \
  --max-instances 3 --memory 256Mi --set-env-vars "PROJECT_ID=$PROJECT,ROLE=projector"

# The public API: the same image, told to serve only, as an account that can
# read Firestore and nothing more. Anyone may call it.
if ! gcloud iam service-accounts describe "$READER" --project "$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create bnp-api-reader --project "$PROJECT" \
    --display-name "BNP Scorer public API (reads match copies)"
  sleep 10
  gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$READER" \
    --role roles/datastore.viewer --condition None --format none
fi
gcloud run deploy "$API" --project "$PROJECT" --region "$REGION" --image "$IMAGE" \
  --service-account "$READER" --allow-unauthenticated \
  --max-instances 3 --memory 256Mi --set-env-vars "PROJECT_ID=$PROJECT,ROLE=api"

# The list's "live" and "finished" filters need this index.
(cd "$ROOT" && firebase deploy --only firestore:indexes --project "$PROJECT")

NUMBER=$(gcloud projects describe "$PROJECT" --format 'value(projectNumber)')
CALLER=$NUMBER-compute@developer.gserviceaccount.com
gcloud run services add-iam-policy-binding "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --member "serviceAccount:$CALLER" --role roles/run.invoker --format none

# Every write to a match, deletes included, calls the service.
if ! gcloud eventarc triggers describe "$SERVICE-matches" --project "$PROJECT" --location "$REGION" >/dev/null 2>&1; then
  gcloud eventarc triggers create "$SERVICE-matches" --project "$PROJECT" --location "$REGION" \
    --destination-run-service "$SERVICE" --destination-run-region "$REGION" \
    --event-filters type=google.cloud.firestore.document.v1.written \
    --event-filters 'database=(default)' --event-filters 'namespace=(default)' \
    --event-filters-path-pattern 'document=matches/{matchId}' \
    --event-data-content-type application/protobuf --service-account "$CALLER"
fi

echo "Deployed. After a change to the view's shape, rebuild every match:"
echo "  sh cloud/api/rebuild.sh"
