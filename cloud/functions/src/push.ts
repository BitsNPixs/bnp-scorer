// Sending pushes to people, without Firebase in the way: the Firestore and
// Cloud Messaging calls come in as small interfaces (adapters.ts), so every
// rule here is tested with fakes (test/push.test.ts).

/** The kinds a phone can turn on in Settings (the app's `PushKind`). */
export type PushKind = "follow" | "team" | "cup";

/**
 * A phone registered for push: `pushDevices/{id}`, written by the app
 * (`PushDevice.toJson`). The field names are a storage format.
 */
export interface DeviceDoc {
  ownerUid: string;
  token: string;
  platform: string;
  kinds?: Partial<Record<PushKind, boolean>>;
}

export interface Device {
  id: string;
  data: DeviceDoc;
}

/** What a person sees, and what a tap opens (`data.open`, read by the app). */
export interface Notice {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface DeviceStore {
  /** Every device registered to any of [uids]. */
  devicesOf(uids: string[]): Promise<Device[]>;
  remove(id: string): Promise<void>;
}

/** One outgoing push; mirrors the subset of Cloud Messaging we use. */
export interface OutgoingMessage {
  token: string;
  notification: { title: string; body: string };
  data: Record<string, string>;
  android: { priority: "high"; notification: { channelId: string } };
}

export interface SendResult {
  ok: boolean;
  /** Cloud Messaging's error code when not ok, e.g. `messaging/...`. */
  errorCode?: string;
}

export interface Sender {
  /** Sends each message on its own; results in the same order. */
  sendEach(messages: OutgoingMessage[]): Promise<SendResult[]>;
}

/** The Android channel the app made for pushes (DeviceNotifications). */
export const updatesChannel = "updates";

/** Codes that mean the token will never work again: forget the device. */
const goneCodes = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

export function isGone(result: SendResult): boolean {
  return !result.ok && result.errorCode !== undefined && goneCodes.has(result.errorCode);
}

/** Whether a device asked for [kind]. Missing means no. */
export function wants(device: DeviceDoc, kind: PushKind): boolean {
  return device.kinds?.[kind] === true;
}

export function messageFor(token: string, notice: Notice): OutgoingMessage {
  return {
    token,
    notification: { title: notice.title, body: notice.body },
    data: notice.data ?? {},
    android: { priority: "high", notification: { channelId: updatesChannel } },
  };
}

/** Firestore's `in` takes at most 30 values per query. */
export function chunks<T>(items: T[], size = 30): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

export interface Outcome {
  sent: number;
  failed: number;
  removed: string[];
}

/**
 * Sends [notice] to every phone of [uids] that wants [kind], except phones of
 * [skipUid] (whoever caused it, who already knows). Devices whose token is
 * gone are removed, so the list cleans itself.
 */
export async function sendToUsers(
  store: DeviceStore,
  sender: Sender,
  uids: string[],
  kind: PushKind,
  notice: Notice,
  skipUid?: string,
): Promise<Outcome> {
  const people = [...new Set(uids)].filter((uid) => uid && uid !== skipUid);
  if (people.length === 0) return { sent: 0, failed: 0, removed: [] };
  const devices: Device[] = [];
  for (const group of chunks(people)) devices.push(...(await store.devicesOf(group)));
  return sendToDevices(store, sender, devices.filter((d) => wants(d.data, kind)), notice);
}

/** Sends [notice] to [devices] as they are, removing any whose token is gone. */
export async function sendToDevices(
  store: DeviceStore,
  sender: Sender,
  devices: Device[],
  notice: Notice,
): Promise<Outcome> {
  if (devices.length === 0) return { sent: 0, failed: 0, removed: [] };
  // Cloud Messaging takes up to 500 messages per batch.
  const outcome: Outcome = { sent: 0, failed: 0, removed: [] };
  for (const group of chunks(devices, 500)) {
    const results = await sender.sendEach(group.map((d) => messageFor(d.data.token, notice)));
    for (const [i, result] of results.entries()) {
      if (result.ok) {
        outcome.sent++;
        continue;
      }
      outcome.failed++;
      if (isGone(result)) {
        await store.remove(group[i].id);
        outcome.removed.push(group[i].id);
      }
    }
  }
  return outcome;
}

/** The test notification Settings asks for. */
export const testNotice: Notice = {
  title: "BNP Scorer",
  body: "Updates reach this phone. You're all set.",
  data: { open: "test" },
};

/**
 * Whether a write to a device document asks for a test: `testRequestedAt`
 * newly set or changed. Timestamps compare by their string form.
 */
export function asksForTest(before: Record<string, unknown> | undefined, after: Record<string, unknown> | undefined): boolean {
  const now = after?.testRequestedAt;
  if (now === undefined || now === null) return false;
  return String(now) !== String(before?.testRequestedAt ?? "");
}
