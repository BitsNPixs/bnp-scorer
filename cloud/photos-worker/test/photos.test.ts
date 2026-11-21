import { describe, expect, it } from "vitest";

import { handle, type Verify } from "../src/index";
import { MAX_BYTES, avatarKey, imageType, route, teamLogoKey } from "../src/photos";

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]);
const WEBP = new TextEncoder().encode("RIFF\0\0\0\0WEBPVP8 ");

/** An in-memory stand-in for the R2 bucket binding. */
function fakeBucket() {
  const objects = new Map<string, { bytes: Uint8Array; type: string }>();
  const bucket = {
    objects,
    async put(key: string, bytes: Uint8Array, options: { httpMetadata: { contentType: string } }) {
      objects.set(key, { bytes, type: options.httpMetadata.contentType });
    },
    async delete(key: string) {
      objects.delete(key);
    },
    async get(key: string) {
      const found = objects.get(key);
      if (!found) return null;
      return {
        body: found.bytes,
        httpEtag: '"etag"',
        writeHttpMetadata(headers: Headers) {
          headers.set("content-type", found.type);
        },
      };
    },
  };
  return bucket;
}

/** Tokens are "token-<uid>"; anything else is not signed in. */
const verify: Verify = async (token) => (token.startsWith("token-") ? token.slice(6) : null);

function setup() {
  const bucket = fakeBucket();
  const env = { PHOTOS: bucket, FIREBASE_PROJECT_ID: "bnp-scorer" } as unknown as Env;
  const send = (method: string, path: string, init: { token?: string; body?: Uint8Array } = {}) =>
    handle(
      new Request(`https://photos.example${path}`, {
        method,
        headers: {
          ...(init.token ? { authorization: `Bearer ${init.token}` } : {}),
          ...(init.body ? { "content-length": String(init.body.length) } : {}),
        },
        body: init.body,
      }),
      env,
      verify,
    );
  return { bucket, send };
}

describe("routes", () => {
  it("knows the upload, delete and image paths, and nothing else", () => {
    expect(route("PUT", "/v1/avatar")).toEqual({ kind: "avatar", method: "PUT" });
    expect(route("DELETE", "/v1/team-logo/abc123")).toEqual({ kind: "teamLogo", method: "DELETE", teamId: "abc123" });
    expect(route("GET", "/img/avatars/u1.img")).toEqual({ kind: "image", key: "avatars/u1.img" });
    expect(route("GET", "/img/teams/u1/t9.img")).toEqual({ kind: "image", key: "teams/u1/t9.img" });
    expect(route("GET", "/v1/avatar").kind).toBe("notFound");
    expect(route("PUT", "/v1/team-logo/../x").kind).toBe("notFound");
    expect(route("GET", "/img/../secrets").kind).toBe("notFound");
    expect(route("GET", "/img/avatars/u1.png").kind).toBe("notFound");
  });

  it("keys a photo by the account, and a logo by account and team", () => {
    expect(avatarKey("u1")).toBe("avatars/u1.img");
    expect(teamLogoKey("u1", "t9")).toBe("teams/u1/t9.img");
  });
});

describe("image types", () => {
  it("are read from the first bytes, not trusted from the request", () => {
    expect(imageType(JPEG)).toBe("image/jpeg");
    expect(imageType(PNG)).toBe("image/png");
    expect(imageType(WEBP)).toBe("image/webp");
    expect(imageType(new TextEncoder().encode("<svg>"))).toBeNull();
    expect(imageType(new Uint8Array())).toBeNull();
  });
});

describe("uploads", () => {
  it("need a signed-in account", async () => {
    const { send, bucket } = setup();
    expect((await send("PUT", "/v1/avatar", { body: JPEG })).status).toBe(401);
    expect((await send("PUT", "/v1/avatar", { token: "forged", body: JPEG })).status).toBe(401);
    expect(bucket.objects.size).toBe(0);
  });

  it("store a player's photo under their own account and serve it back", async () => {
    const { send, bucket } = setup();
    const res = await send("PUT", "/v1/avatar", { token: "token-u1", body: JPEG });
    expect(res.status).toBe(200);
    const { url } = (await res.json()) as { url: string };
    expect(url).toMatch(/^https:\/\/photos\.example\/img\/avatars\/u1\.img\?v=\d+$/);
    expect(bucket.objects.get("avatars/u1.img")?.type).toBe("image/jpeg");

    const image = await send("GET", new URL(url).pathname);
    expect(image.status).toBe(200);
    expect(image.headers.get("content-type")).toBe("image/jpeg");
    expect(image.headers.get("cache-control")).toContain("immutable");
    expect(new Uint8Array(await image.arrayBuffer())).toEqual(JPEG);
  });

  it("put a team logo under the account that set it, so nobody overwrites another's", async () => {
    const { send, bucket } = setup();
    await send("PUT", "/v1/team-logo/t9", { token: "token-u1", body: PNG });
    await send("PUT", "/v1/team-logo/t9", { token: "token-u2", body: WEBP });
    expect(bucket.objects.get("teams/u1/t9.img")?.type).toBe("image/png");
    expect(bucket.objects.get("teams/u2/t9.img")?.type).toBe("image/webp");
  });

  it("refuse what is not a photo, too large, or of unknown size", async () => {
    const { send, bucket } = setup();
    expect((await send("PUT", "/v1/avatar", { token: "token-u1", body: new TextEncoder().encode("<svg/>") })).status).toBe(415);
    expect((await send("PUT", "/v1/avatar", { token: "token-u1", body: new Uint8Array(MAX_BYTES + 1) })).status).toBe(413);
    expect((await send("PUT", "/v1/avatar", { token: "token-u1" })).status).toBe(411);
    expect(bucket.objects.size).toBe(0);
  });

  it("remove only the caller's own photo", async () => {
    const { send, bucket } = setup();
    await send("PUT", "/v1/avatar", { token: "token-u1", body: JPEG });
    await send("PUT", "/v1/avatar", { token: "token-u2", body: JPEG });
    expect((await send("DELETE", "/v1/avatar", { token: "token-u1" })).status).toBe(200);
    expect([...bucket.objects.keys()]).toEqual(["avatars/u2.img"]);
    expect((await send("GET", "/img/avatars/u1.img")).status).toBe(404);
  });
});
