import { createHmac } from "node:crypto";
const secret = "super-secret-jwt-token-with-at-least-32-characters-long";
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
export function jwt(claims) {
  const head = b64({ alg: "HS256", typ: "JWT" });
  const body = b64({ iss: "supabase", exp: Math.floor(Date.now() / 1000) + 3600, ...claims });
  return `${head}.${body}.${createHmac("sha256", secret).update(`${head}.${body}`).digest("base64url")}`;
}
if (process.argv[2]) console.log(jwt(JSON.parse(process.argv[2])));
