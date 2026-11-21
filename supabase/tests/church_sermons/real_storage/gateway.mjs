// Stand-in for Supabase's gateway: /storage/v1 -> the real Storage API (:5000),
// /functions/v1 -> the real Edge Runtime (:54401), /rest/v1/rpc/sermon_cover_access
// -> a PostgREST-style call (JWT checked with the project secret, role switched,
// claims set) through psql.
import { createServer, request } from "node:http";
import { createHmac } from "node:crypto";
import { execFileSync } from "node:child_process";

const SECRET = "super-secret-jwt-token-with-at-least-32-characters-long";

function verify(token) {
  const [h, b, sig] = token.split(".");
  if (!sig || createHmac("sha256", SECRET).update(`${h}.${b}`).digest("base64url") !== sig) return null;
  const claims = JSON.parse(Buffer.from(b, "base64url").toString());
  return claims.exp > Date.now() / 1000 ? claims : null;
}

function proxy(req, res, port, path) {
  const up = request({ host: "127.0.0.1", port, path, method: req.method, headers: req.headers }, (r) => {
    res.writeHead(r.statusCode, r.headers);
    r.pipe(res);
  });
  req.pipe(up);
}

const quote = (s) => "'" + String(s).split("'").join("''") + "'";

createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  if (url.pathname.startsWith("/storage/v1/")) return proxy(req, res, 5000, req.url.slice("/storage/v1".length));
  if (url.pathname.startsWith("/functions/v1/sermon-cover")) return proxy(req, res, 54401, req.url.slice("/functions/v1".length));
  if (url.pathname === "/rest/v1/rpc/sermon_cover_access") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const claims = verify((req.headers.authorization ?? "").replace(/^Bearer /, ""));
      if (!claims) {
        res.writeHead(401, { "content-type": "application/json" });
        return res.end('{"message":"JWT invalid"}');
      }
      const args = JSON.parse(body || "{}");
      const role = claims.role === "authenticated" ? "authenticated" : claims.role === "service_role" ? "service_role" : "anon";
      const sql = [
        "begin;",
        `select set_config('request.jwt.claims', ${quote(JSON.stringify(claims))}, true), set_config('request.jwt.claim.sub', ${quote(claims.sub ?? "")}, true);`,
        `set local role ${role};`,
        `select coalesce(to_json(public.sermon_cover_access(${quote(args.p_name)}))::text, 'null');`,
        "commit;",
      ].join(" ");
      try {
        const out = execFileSync(process.env.PSQL, ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", process.env.PGPORT_, "-U", "authenticator", "-d", "dvtest", "-c", sql], { encoding: "utf8" });
        const lines = out.split("\n").filter((l) => l.trim() !== "" && !l.includes("|"));
        res.writeHead(200, { "content-type": "application/json" });
        res.end(lines.pop() ?? "null");
      } catch (e) {
        res.writeHead(400, { "content-type": "application/json" });
        res.end(JSON.stringify({ message: String(e.stderr || e.message) }));
      }
    });
    return;
  }
  res.writeHead(404);
  res.end();
}).listen(54400, () => console.log("gateway on 54400"));
