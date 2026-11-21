// The rules of the photos service, apart from Cloudflare and Firebase, so
// they can be tested on their own.

/** The largest photo accepted. The app sends about 50 KB (512 px JPEG). */
export const MAX_BYTES = 512 * 1024;

/** A team id as the app makes them (`newId()`: base 36). */
const TEAM_ID = /^[a-z0-9]{1,40}$/;

/** What a request asks for. */
export type Route =
  | { kind: "avatar"; method: "PUT" | "DELETE" }
  | { kind: "teamLogo"; method: "PUT" | "DELETE"; teamId: string }
  | { kind: "image"; key: string }
  | { kind: "notFound" };

/** Reads the path and method. Image keys are only ever ones this service writes. */
export function route(method: string, pathname: string): Route {
  if (pathname === "/v1/avatar" && (method === "PUT" || method === "DELETE")) {
    return { kind: "avatar", method };
  }
  const logo = /^\/v1\/team-logo\/([^/]+)$/.exec(pathname);
  if (logo && (method === "PUT" || method === "DELETE") && TEAM_ID.test(logo[1])) {
    return { kind: "teamLogo", method, teamId: logo[1] };
  }
  const image = /^\/img\/((?:avatars\/[A-Za-z0-9]{1,128}|teams\/[A-Za-z0-9]{1,128}\/[a-z0-9]{1,40})\.img)$/.exec(pathname);
  if (image && (method === "GET" || method === "HEAD")) return { kind: "image", key: image[1] };
  return { kind: "notFound" };
}

/** Where a player's photo lives: one per account. */
export const avatarKey = (uid: string) => `avatars/${uid}.img`;

/** Where a team's logo lives: under the account that set it. */
export const teamLogoKey = (uid: string, teamId: string) => `teams/${uid}/${teamId}.img`;

/** A Firebase uid as used in keys; anything else is refused. */
export const safeUid = (uid: string) => /^[A-Za-z0-9]{1,128}$/.test(uid);

/** The image type from the first bytes, or null when it is not JPEG, PNG or WebP. */
export function imageType(bytes: Uint8Array): "image/jpeg" | "image/png" | "image/webp" | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (
    bytes.length >= 8 &&
    [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((b, i) => bytes[i] === b)
  ) {
    return "image/png";
  }
  if (
    bytes.length >= 12 &&
    String.fromCharCode(...bytes.subarray(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.subarray(8, 12)) === "WEBP"
  ) {
    return "image/webp";
  }
  return null;
}

/** A JSON reply. */
export const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
