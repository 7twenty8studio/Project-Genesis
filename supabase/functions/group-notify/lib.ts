// Pure helpers for group-notify (Apple Push Notification service).
// Kept free of Deno APIs so they can be tested with Node.

export class NotifyError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

/** Reads { announcementID } from the request body. */
export function parseNotifyRequest(body: unknown): { announcementID: string } {
  const id = (body as { announcementID?: unknown } | null)?.announcementID;
  if (typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) throw new NotifyError("announcementID is required.");
  return { announcementID: id.toLowerCase() };
}

function base64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The DER bytes of a PEM private key (the .p8 file from Apple). */
export function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) [A-Z ]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  if (!body) throw new NotifyError("APNS_KEY is empty.", 500);
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

/** A provider token for APNs: an ES256 JWT signed with the .p8 key. */
export async function apnsToken(pem: string, keyID: string, teamID: string, issuedAt: number): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64url(JSON.stringify({ iss: teamID, iat: issuedAt }));
  const signingInput = `${header}.${claims}`;
  // Web Crypto returns the raw r||s signature JWTs expect.
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)));
  return `${signingInput}.${base64url(signature)}`;
}

export interface Announcement {
  id: string;
  group_id: string;
  title: string;
  body: string;
}

/** The notification people see: the group's name, then the announcement. */
export function notificationPayload(groupName: string, announcement: Announcement): Record<string, unknown> {
  const clip = (text: string, length: number) => (text.length > length ? text.slice(0, length - 1) + "…" : text);
  return {
    aps: {
      alert: {
        title: clip(groupName, 60),
        subtitle: clip(announcement.title, 100),
        body: clip(announcement.body, 180),
      },
      sound: "default",
      "thread-id": `group-${announcement.group_id}`,
    },
    genesis: { groupID: announcement.group_id, announcementID: announcement.id },
  };
}

export function apnsHost(environment: string): string {
  return environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
}

/** Responses after which a device token should be forgotten. */
export function isDeadToken(status: number, reason: string | undefined): boolean {
  return status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" || reason === "DeviceTokenNotForTopic";
}
