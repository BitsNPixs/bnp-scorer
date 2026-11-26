import { describe, expect, it } from "vitest";

import {
  asksForTest,
  highlightNotice,
  newHighlight,
  sendHighlight,
  chunks,
  type Device,
  type DeviceStore,
  messageFor,
  type OutgoingMessage,
  type Sender,
  type SendResult,
  sendToDevices,
  sendToUsers,
  wants,
} from "../src/push.js";

function device(
  id: string,
  ownerUid: string,
  kinds: Record<string, boolean> = { follow: true },
  follows: string[] = [],
): Device {
  return { id, data: { ownerUid, token: `token-${id}`, platform: "android", kinds, follows } };
}

/** Devices in memory; records removals and the uid groups it was asked for. */
class FakeStore implements DeviceStore {
  removed: string[] = [];
  queries: string[][] = [];
  constructor(public devices: Device[]) {}

  async devicesOf(uids: string[]): Promise<Device[]> {
    this.queries.push(uids);
    return this.devices.filter((d) => uids.includes(d.data.ownerUid));
  }

  async devicesFollowing(matchId: string): Promise<Device[]> {
    return this.devices.filter((d) => d.data.follows?.includes(matchId));
  }

  async remove(id: string): Promise<void> {
    this.removed.push(id);
    this.devices = this.devices.filter((d) => d.id !== id);
  }
}

/** Cloud Messaging that answers per token: ok unless [errors] names it. */
class FakeSender implements Sender {
  sent: OutgoingMessage[] = [];
  batches = 0;
  constructor(private errors: Record<string, string> = {}) {}

  async sendEach(messages: OutgoingMessage[]): Promise<SendResult[]> {
    this.batches++;
    this.sent.push(...messages);
    return messages.map((m) => (this.errors[m.token] ? { ok: false, errorCode: this.errors[m.token] } : { ok: true }));
  }
}

const notice = { title: "Lions v Tigers", body: "Wicket! Ravi 34 (22)", data: { open: "match:m1" } };

describe("sendToUsers", () => {
  it("sends to every phone of the people who want that kind", async () => {
    const store = new FakeStore([
      device("a1", "asha"),
      device("a2", "asha"),
      device("b1", "bala", { follow: false, team: true }),
      device("c1", "chitra"),
    ]);
    const sender = new FakeSender();
    const outcome = await sendToUsers(store, sender, ["asha", "bala"], "follow", notice);
    expect(sender.sent.map((m) => m.token)).toEqual(["token-a1", "token-a2"]);
    expect(outcome).toEqual({ sent: 2, failed: 0, removed: [] });
  });

  it("leaves out whoever caused it, and asks nothing for nobody", async () => {
    const store = new FakeStore([device("a1", "asha"), device("b1", "bala")]);
    const sender = new FakeSender();
    await sendToUsers(store, sender, ["asha", "bala", "asha"], "follow", notice, "asha");
    expect(sender.sent.map((m) => m.token)).toEqual(["token-b1"]);

    const empty = new FakeStore([device("a1", "asha")]);
    expect(await sendToUsers(empty, sender, ["asha"], "follow", notice, "asha")).toEqual({
      sent: 0,
      failed: 0,
      removed: [],
    });
    expect(empty.queries).toEqual([]);
  });

  it("asks Firestore in groups of 30, its limit for `in`", async () => {
    const uids = Array.from({ length: 65 }, (_, i) => `u${i}`);
    const store = new FakeStore([]);
    await sendToUsers(store, new FakeSender(), uids, "cup", notice);
    expect(store.queries.map((q) => q.length)).toEqual([30, 30, 5]);
  });
});

describe("sendToDevices", () => {
  it("forgets a phone whose token is gone, and keeps one that only failed", async () => {
    const store = new FakeStore([device("a1", "asha"), device("a2", "asha"), device("a3", "asha")]);
    const sender = new FakeSender({
      "token-a1": "messaging/registration-token-not-registered",
      "token-a2": "messaging/internal-error",
    });
    const outcome = await sendToDevices(store, sender, [...store.devices], notice);
    expect(outcome).toEqual({ sent: 1, failed: 2, removed: ["a1"] });
    expect(store.devices.map((d) => d.id)).toEqual(["a2", "a3"]);
  });

  it("sends at most 500 in one batch", async () => {
    const devices = Array.from({ length: 501 }, (_, i) => device(`d${i}`, "asha"));
    const sender = new FakeSender();
    await sendToDevices(new FakeStore(devices), sender, devices, notice);
    expect(sender.batches).toBe(2);
    expect(sender.sent).toHaveLength(501);
  });
});

describe("messages", () => {
  it("go on the app's updates channel at high priority, carrying what to open", () => {
    expect(messageFor("t", notice)).toEqual({
      token: "t",
      notification: { title: "Lions v Tigers", body: "Wicket! Ravi 34 (22)" },
      data: { open: "match:m1" },
      android: { priority: "high", notification: { channelId: "updates" } },
    });
    expect(messageFor("t", { title: "x", body: "y" }).data).toEqual({});
  });

  it("a kind counts only when turned on", () => {
    expect(wants(device("a", "u", { team: true }).data, "team")).toBe(true);
    expect(wants(device("a", "u", { team: false }).data, "team")).toBe(false);
    expect(wants({ ownerUid: "u", token: "t", platform: "ios" }, "cup")).toBe(false);
  });

  it("splits a list into groups", () => {
    expect(chunks([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunks([], 2)).toEqual([]);
  });
});

describe("test notifications", () => {
  it("are sent when the app sets or changes testRequestedAt, and not otherwise", () => {
    expect(asksForTest({}, { testRequestedAt: 1000 })).toBe(true);
    expect(asksForTest({ testRequestedAt: 1000 }, { testRequestedAt: 2000 })).toBe(true);
    expect(asksForTest({ testRequestedAt: 1000 }, { testRequestedAt: 1000 }), "a token refresh").toBe(false);
    expect(asksForTest(undefined, { token: "t" }), "a new registration").toBe(false);
    expect(asksForTest({ testRequestedAt: 1000 }, undefined), "a removal").toBe(false);
  });
});

describe("match highlights", () => {
  const wicket = { seq: 42, kind: "wicket", title: "WICKET! Ravi c Kumar b Arun 34 (22)", body: "Lions 87/4 (11.2 ov) v Tigers" };

  it("are new only when a seq appears that was not there before", () => {
    expect(newHighlight({}, { highlight: wicket })).toEqual(wicket);
    expect(newHighlight({ highlight: { ...wicket, seq: 30 } }, { highlight: wicket })).toEqual(wicket);
    expect(newHighlight({ highlight: wicket }, { highlight: wicket }), "a resent write").toBeNull();
    expect(newHighlight({ highlight: wicket }, { events: [] }), "an ordinary ball").toBeNull();
    expect(newHighlight(undefined, undefined), "a deleted match").toBeNull();
    expect(newHighlight({}, { highlight: { seq: "x", title: 1 } }), "malformed").toBeNull();
  });

  it("open the match when tapped", () => {
    expect(highlightNotice("m1", wicket)).toEqual({
      title: wicket.title,
      body: wicket.body,
      data: { open: "match:m1", kind: "wicket" },
    });
  });

  it("go to followers who want match updates, never to the scorer's own phones", async () => {
    const store = new FakeStore([
      device("f1", "asha", { follow: true }, ["m1"]),
      device("f2", "bala", { follow: false, team: true }, ["m1"]),
      device("f3", "chitra", { follow: true }, ["m2"]),
      device("s1", "scorer", { follow: true }, ["m1"]),
    ]);
    const sender = new FakeSender();
    const outcome = await sendHighlight(store, sender, "m1", "scorer", wicket);
    expect(sender.sent.map((m) => m.token)).toEqual(["token-f1"]);
    expect(sender.sent[0].data).toEqual({ open: "match:m1", kind: "wicket" });
    expect(outcome.sent).toBe(1);
  });
});

