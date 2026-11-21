import { createRemoteJWKSet, jwtVerify } from "jose";

import { MAX_BYTES, avatarKey, imageType, json, route, safeUid, teamLogoKey } from "./photos";

/** Google's public keys for Firebase ID tokens. Cached by jose per isolate. */
const firebaseKeys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

/** The signed-in Firebase account a request comes from, or null. */
export type Verify = (token: string, projectId: string) => Promise<string | null>;

/** Checks a Firebase ID token: Google's signature, this project, not expired. */
export const verifyFirebaseToken: Verify = async (token, projectId) => {
  try {
    const { payload } = await jwtVerify(token, firebaseKeys, {
      issuer: `https://securetoken.google.com/${projectId}`,
      audience: projectId,
      algorithms: ["RS256"],
    });
    return typeof payload.sub === "string" && payload.sub.length > 0 ? payload.sub : null;
  } catch {
    return null;
  }
};

/** The whole service, with the token check passed in so tests can replace it. */
export async function handle(request: Request, env: Env, verify: Verify): Promise<Response> {
  const url = new URL(request.url);
  const target = route(request.method, url.pathname);

  if (target.kind === "notFound") return json(404, { error: "not found" });

  if (target.kind === "image") {
    const object = await env.PHOTOS.get(target.key);
    if (object === null) return new Response("Not found", { status: 404 });
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("etag", object.httpEtag);
    // Every upload returns a new ?v=, so an address never changes content.
    headers.set("cache-control", "public, max-age=31536000, immutable");
    return new Response(request.method === "HEAD" ? null : object.body, { headers });
  }

  const auth = request.headers.get("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const uid = token ? await verify(token, env.FIREBASE_PROJECT_ID) : null;
  if (uid === null || !safeUid(uid)) return json(401, { error: "Sign in again." });

  const key = target.kind === "avatar" ? avatarKey(uid) : teamLogoKey(uid, target.teamId);

  if (target.method === "DELETE") {
    await env.PHOTOS.delete(key);
    return json(200, { removed: true });
  }

  const declared = Number(request.headers.get("content-length") ?? "0");
  if (!Number.isFinite(declared) || declared <= 0) return json(411, { error: "Send the photo's size." });
  if (declared > MAX_BYTES) return json(413, { error: "That photo is too large." });
  // Bounded by the size check above, so reading it whole is safe.
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length > MAX_BYTES) return json(413, { error: "That photo is too large." });
  const type = imageType(bytes);
  if (type === null) return json(415, { error: "Send a JPEG, PNG or WebP photo." });

  await env.PHOTOS.put(key, bytes, {
    httpMetadata: { contentType: type },
    customMetadata: { uid },
  });
  // The version busts caches when a photo is replaced.
  return json(200, { url: `${url.origin}/img/${key}?v=${Date.now()}` });
}

export default {
  async fetch(request, env): Promise<Response> {
    try {
      return await handle(request, env, verifyFirebaseToken);
    } catch (error) {
      console.error(JSON.stringify({ message: "photos request failed", error: String(error) }));
      return json(500, { error: "Something went wrong. Try again." });
    }
  },
} satisfies ExportedHandler<Env>;
