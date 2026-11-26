// BNP Scorer's Cloud Functions: pushes sent when Firestore changes, so a
// scorer's phone sends nothing extra and nobody can fake a notification.
// Deploy from the repo root: firebase deploy --only functions (README "Push").
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions/v2";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { cloudMessaging, firestoreDevices } from "./adapters.js";
import { asksForTest, type DeviceDoc, newHighlight, sendHighlight, sendToDevices, testNotice } from "./push.js";

initializeApp();

// Next to Firestore (Mumbai), and capped so a runaway can never cost much.
setGlobalOptions({ region: "asia-south1", maxInstances: 5 });

/** Firestore timestamps as plain numbers, for comparing. */
function withMillis(data: Record<string, unknown> | undefined): Record<string, unknown> | undefined {
  if (!data) return data;
  const at = data.testRequestedAt;
  return { ...data, testRequestedAt: at instanceof Timestamp ? at.toMillis() : at };
}

/** Settings > Send me a test notification: the app marks its device. */
export const pushTest = onDocumentWritten("pushDevices/{deviceId}", async (event) => {
  const before = withMillis(event.data?.before.data());
  const after = withMillis(event.data?.after.data());
  if (!asksForTest(before, after)) return;
  const outcome = await sendToDevices(
    firestoreDevices(getFirestore()),
    cloudMessaging(getMessaging()),
    [{ id: event.params.deviceId, data: after as unknown as DeviceDoc }],
    testNotice,
  );
  logger.info("test push", { deviceId: event.params.deviceId, ...outcome });
});

/**
 * A ball that made a moment (a wicket, a milestone, the result): its scorer's
 * app published a `highlight` with it, sent here once to the match's
 * followers. Every other write ends at the first check.
 */
export const matchHighlight = onDocumentWritten("matches/{matchId}", async (event) => {
  const after = event.data?.after.data();
  const highlight = newHighlight(event.data?.before.data(), after);
  if (!highlight) return;
  const outcome = await sendHighlight(
    firestoreDevices(getFirestore()),
    cloudMessaging(getMessaging()),
    event.params.matchId,
    after?.ownerUid as string | undefined,
    highlight,
  );
  logger.info("match highlight", { matchId: event.params.matchId, kind: highlight.kind, ...outcome });
});

