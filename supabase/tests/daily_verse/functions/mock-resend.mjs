// A local stand-in for the Resend API, for the integration tests only: it records
// each request to DV_EMAIL_LOG (default /tmp/dvb/emails.jsonl) and sends nothing.
//   node supabase/tests/daily_verse/functions/mock-resend.mjs   # listens on 54399
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { createServer } from "node:http";

const log = process.env.DV_EMAIL_LOG ?? "/tmp/dvb/emails.jsonl";
mkdirSync(dirname(log), { recursive: true });
createServer((req, res) => {
  let body = "";
  req.on("data", (chunk) => (body += chunk));
  req.on("end", () => {
    appendFileSync(log, JSON.stringify({ at: new Date().toISOString(), url: req.url, body }) + "\n");
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ id: "mock" }));
  });
}).listen(Number(process.env.PORT ?? 54399), "0.0.0.0", () => console.log(`mock Resend on ${process.env.PORT ?? 54399}, logging to ${log}`));
