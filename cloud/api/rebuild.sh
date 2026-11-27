#!/bin/sh
# Stores the copies of every published match again, a page at a time: run it
# once after the first deploy, and after any change to what a view holds.
set -eu

URL=$(gcloud run services describe bnp-api-projector --project bnp-scorer --region asia-south1 --format 'value(status.url)')
TOKEN=$(gcloud auth print-identity-token)
PAGE=""
while :; do
  if [ -n "$PAGE" ]; then
    OUT=$(curl -sS -f -X POST -G --data-urlencode "pageToken=$PAGE" -H "Authorization: Bearer $TOKEN" "$URL/rebuild")
  else
    OUT=$(curl -sS -f -X POST -H "Authorization: Bearer $TOKEN" "$URL/rebuild")
  fi
  echo "$OUT"
  PAGE=$(printf '%s' "$OUT" | sed -n 's/.*"nextPageToken":"\([^"]*\)".*/\1/p')
  [ -n "$PAGE" ] || break
done
