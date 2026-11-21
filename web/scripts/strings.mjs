// Lists every English string the web shows through t(…), for messages.ts and its test.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const ROOT = new URL("../src/", import.meta.url).pathname;
const files = [];
(function walk(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path);
    else if (/\.(ts|tsx)$/.test(name) && !name.endsWith(".test.ts") && !name.startsWith("messages")) files.push(path);
  }
})(ROOT);

const unescape = (s) => JSON.parse(`"${s}"`);
export function strings() {
  const found = new Set();
  for (const file of files) {
    const source = readFileSync(file, "utf8").replace(/^\s*\/\/(?! translatable returns).*$/gm, "");
    for (const m of source.matchAll(/\bt\(\s*"((?:[^"\\]|\\.)*)"/g)) found.add(unescape(m[1]));
    // Messages chosen in code and translated where shown (refusalMessage, problemText).
    if (/\/\/ translatable returns/.test(source)) for (const m of source.matchAll(/return "((?:[^"\\]|\\.)*)";/g)) found.add(unescape(m[1]));
  }
  return [...found].sort();
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(strings(), null, 1));
