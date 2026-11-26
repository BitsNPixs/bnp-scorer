// The real Firestore and Cloud Messaging behind push.ts's interfaces.
import type { Firestore } from "firebase-admin/firestore";
import type { Message, Messaging } from "firebase-admin/messaging";

import type { Device, DeviceDoc, DeviceStore, OutgoingMessage, Sender, SendResult } from "./push.js";

export function firestoreDevices(db: Firestore): DeviceStore {
  const devices = db.collection("pushDevices");
  return {
    async devicesOf(uids: string[]): Promise<Device[]> {
      const snapshot = await devices.where("ownerUid", "in", uids).get();
      return snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() as DeviceDoc }));
    },
    async remove(id: string): Promise<void> {
      await devices.doc(id).delete();
    },
  };
}

export function cloudMessaging(messaging: Messaging): Sender {
  return {
    async sendEach(messages: OutgoingMessage[]): Promise<SendResult[]> {
      const batch = await messaging.sendEach(messages as Message[]);
      return batch.responses.map((r) => (r.success ? { ok: true } : { ok: false, errorCode: r.error?.code }));
    },
  };
}
