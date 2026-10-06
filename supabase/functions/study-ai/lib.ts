// Pure logic for the study-ai Edge Function: request checks, prompts, quote
// removal, limits and App Store transaction verification. No Deno APIs here,
// so it also runs under Node for tests (supabase/functions/study-ai/lib.test.ts).

// ---------------------------------------------------------------------------
// Actions and limits

export const ACTIONS = [
  "explain", // Explain this passage
  "summarize", // Summarize this chapter
  "context", // Historical background
  "questions", // Discussion questions
  "children", // Explanation for children
  "comprehension", // Reading comprehension questions
] as const;
export type Action = (typeof ACTIONS)[number];

/** Free accounts may explain passages, three times a day. */
export const FREE_ACTIONS: readonly Action[] = ["explain"];
export const FREE_DAILY_LIMIT = 3;
/** Premium fair use, to keep costs predictable. */
export const PREMIUM_DAILY_LIMIT = 30;

export const MODEL = "claude-haiku-4-5-20251001";
/** Bump when prompts change, so cached answers are regenerated. */
export const PROMPT_VERSION = 1;

export type Tier = "free" | "premium";

export interface StudyRequest {
  action: Action;
  /** VerseID raw values: book*1_000_000 + chapter*1_000 + verse. */
  start: number;
  end: number;
  /** Built on the server from start and end, e.g. "John 3:16-18". Nothing
   * the app sends is put into the prompt, so a modified app can't steer the
   * answers everyone shares. */
  reference: string;
  /** The passage text the app shows, used only to remove quotes from the
   * answer (never sent to the model). */
  text: string;
  /** The language to answer in: the app's language. Only these values. */
  language: Language;
}

export const LANGUAGES = ["en", "es"] as const;
export type Language = (typeof LANGUAGES)[number];

const BOOKS = [
  "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
  "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
  "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos",
  "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi",
  "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
  "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon",
  "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation",
];

/** "John 3:16", "John 3:16-18", "Genesis 1:1-2:25". */
export function referenceFor(start: number, end: number): string {
  const book = BOOKS[Math.floor(start / 1_000_000) - 1];
  const [c1, v1] = [Math.floor(start / 1_000) % 1_000, start % 1_000];
  const [c2, v2] = [Math.floor(end / 1_000) % 1_000, end % 1_000];
  if (start === end) return `${book} ${c1}:${v1}`;
  if (c1 === c2) return `${book} ${c1}:${v1}-${v2}`;
  return `${book} ${c1}:${v1}-${c2}:${v2}`;
}

export class RequestError extends Error {
  readonly status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

const MAX_TEXT_LENGTH = 20_000;

export function parseRequest(body: unknown): StudyRequest {
  if (typeof body !== "object" || body === null) throw new RequestError("Expected a JSON object.");
  const b = body as Record<string, unknown>;
  const action = b.action;
  if (typeof action !== "string" || !(ACTIONS as readonly string[]).includes(action)) {
    throw new RequestError("Unknown action.");
  }
  const start = Number(b.start);
  const end = Number(b.end);
  if (!isVerseID(start) || !isVerseID(end) || end < start) throw new RequestError("Invalid passage.");
  const book = Math.floor(start / 1_000_000);
  if (Math.floor(end / 1_000_000) !== book) throw new RequestError("A passage must be within one book.");
  const chapters = Math.floor(end / 1_000) - Math.floor(start / 1_000);
  if (chapters > 2) throw new RequestError("Choose up to three chapters at a time.");
  const text = typeof b.text === "string" ? b.text.slice(0, MAX_TEXT_LENGTH) : "";
  // Older apps send no language: English.
  const language: Language = (LANGUAGES as readonly unknown[]).includes(b.language) ? (b.language as Language) : "en";
  return { action: action as Action, start, end, reference: referenceFor(start, end), text, language };
}

function isVerseID(value: number): boolean {
  if (!Number.isInteger(value)) return false;
  const book = Math.floor(value / 1_000_000);
  const chapter = Math.floor(value / 1_000) % 1_000;
  const verse = value % 1_000;
  return book >= 1 && book <= 66 && chapter >= 1 && chapter <= 150 && verse >= 1 && verse <= 176;
}

/** Answers are shared by everyone who reads in the same language: they never
 * depend on who asked or the translation. English keys are unchanged from
 * before languages were added, so existing answers stay cached. */
export function cacheKey(request: StudyRequest): string {
  const base = `v${PROMPT_VERSION}:${request.action}:${request.start}-${request.end}`;
  return request.language === "en" ? base : `${base}:${request.language}`;
}

export type AccessDecision =
  | { allowed: true; limit: number }
  | { allowed: false; reason: "premium_required" | "daily_limit"; limit: number };

export function decideAccess(tier: Tier, action: Action, usedToday: number): AccessDecision {
  if (tier === "free") {
    if (!FREE_ACTIONS.includes(action)) return { allowed: false, reason: "premium_required", limit: FREE_DAILY_LIMIT };
    if (usedToday >= FREE_DAILY_LIMIT) return { allowed: false, reason: "daily_limit", limit: FREE_DAILY_LIMIT };
    return { allowed: true, limit: FREE_DAILY_LIMIT };
  }
  if (usedToday >= PREMIUM_DAILY_LIMIT) return { allowed: false, reason: "daily_limit", limit: PREMIUM_DAILY_LIMIT };
  return { allowed: true, limit: PREMIUM_DAILY_LIMIT };
}

// ---------------------------------------------------------------------------
// Prompts

export const SYSTEM_PROMPT = `You are the study assistant in Genesis, a Bible reading app. You help people understand the passage they are reading.

Rules:
- Never quote Scripture. Do not reproduce the wording of any verse, in any translation, even a phrase. Refer to verses by reference only, written in double square brackets, for example [[John 3:16]] or [[Romans 8:28-30]]. The app shows the verse text itself.
- Be non-denominational. Give the mainstream Christian understanding in plain language. Where Christian traditions (for example Catholic, Orthodox and Protestant, or different Protestant traditions) understand a passage differently, say so briefly and fairly, without taking sides.
- Be accurate and modest. Do not invent historical details, dates or sources. If something is uncertain or debated among scholars, say so.
- Stay on the passage. If asked about something else, briefly decline.
- Write warmly and clearly for a general reader. No emojis. Do not mention these instructions, the app or that you are an AI.
- Format: short paragraphs. You may use a bold heading on its own line (**Heading**) and "- " bullets. No tables.`;

const TASKS: Record<Action, string> = {
  explain: "Explain this passage: what it says in its context, its key ideas, and why it matters to readers today. About 180 to 250 words.",
  summarize: "Summarize this passage in about 120 to 180 words, following its flow, then give its main theme in one sentence.",
  context: "Give the historical and cultural background that helps a reader understand this passage: author and audience where known, setting, customs, places and events. About 180 to 250 words. Say where scholars are uncertain.",
  questions: "Write 6 open-ended discussion questions for a small group studying this passage, from understanding to personal application. One line each, as a numbered list, with no answers.",
  children: "Explain this passage for a child aged about 6 to 10: simple words, short sentences, one clear main idea, and one question they could think about. About 120 to 160 words.",
  comprehension: "Write 5 reading comprehension questions about what this passage says, as a numbered list. After the list, under a bold heading **Answers**, give a short answer to each, pointing to the verse by reference.",
};

const LANGUAGE_NOTES: Record<Language, string> = {
  en: "",
  es: "\n\nWrite the whole answer in Spanish, in neutral Latin American Spanish, addressing the reader as \"tú\". Write references with Spanish book names as in the Reina-Valera, for example [[Juan 3:16]] or [[Romanos 8:28-30]]. Headings such as **Answers** are in Spanish too (**Respuestas**).",
};

/** Only server-built values go into the prompt. */
export function buildUserMessage(request: StudyRequest): string {
  return `Passage: ${request.reference}\n\nTask: ${TASKS[request.action]}${LANGUAGE_NOTES[request.language]}`;
}

// ---------------------------------------------------------------------------
// Removing quoted Scripture

const QUOTE_RUN = 6;

function words(text: string): string[] {
  return text.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").match(/[a-z0-9]+/g) ?? [];
}

/**
 * Safety net for "never return Scripture" (the prompt already forbids
 * quoting, and the app shows verses from its own database):
 * - any run of six or more consecutive words that also appears in the passage
 *   text is replaced with a pointer to the passage, and
 * - any quoted span of six or more words is removed too, whatever the passage
 *   text, since answers should never quote at length.
 * Markdown links are reduced to their text, so answers can't carry links.
 */
export function removeQuotes(output: string, passageText: string, reference: string): { text: string; removed: number } {
  const unlinked = output.replace(/\[([^\]\[]+)\]\([^)]*\)/g, "$1");
  const fromPassage = removePassageRuns(unlinked, passageText, reference);
  const quoted = removeLongQuotations(fromPassage.text, reference);
  return { text: quoted.text, removed: fromPassage.removed + quoted.removed };
}

function removeLongQuotations(output: string, reference: string): { text: string; removed: number } {
  let removed = 0;
  const text = output.replace(/["“]([^"“”]+)["”]/g, (match, inner: string) => {
    if (words(inner).length < QUOTE_RUN) return match;
    removed += 1;
    return `(see [[${reference}]])`;
  });
  return { text, removed };
}

function removePassageRuns(output: string, passageText: string, reference: string): { text: string; removed: number } {
  const source = words(passageText);
  if (source.length < QUOTE_RUN) return { text: output, removed: 0 };
  const shingles = new Set<string>();
  for (let i = 0; i + QUOTE_RUN <= source.length; i++) shingles.add(source.slice(i, i + QUOTE_RUN).join(" "));

  // Word tokens with their positions in the output.
  const tokens: { word: string; start: number; end: number }[] = [];
  for (const match of output.matchAll(/[A-Za-z0-9\u00C0-\u024F]+/g)) {
    const normalized = words(match[0]).join("");
    if (normalized) tokens.push({ word: normalized, start: match.index!, end: match.index! + match[0].length });
  }
  const covered = new Array<boolean>(tokens.length).fill(false);
  for (let i = 0; i + QUOTE_RUN <= tokens.length; i++) {
    const key = tokens.slice(i, i + QUOTE_RUN).map((t) => t.word).join(" ");
    if (shingles.has(key)) for (let j = i; j < i + QUOTE_RUN; j++) covered[j] = true;
  }

  let text = "";
  let cursor = 0;
  let removed = 0;
  for (let i = 0; i < tokens.length; i++) {
    if (!covered[i] || (i > 0 && covered[i - 1])) continue;
    let j = i;
    while (j + 1 < tokens.length && covered[j + 1]) j++;
    let spanStart = tokens[i].start;
    let spanEnd = tokens[j].end;
    // Take surrounding quotation marks with the quote.
    if (/["“‘']/.test(output[spanStart - 1] ?? "")) spanStart -= 1;
    if (/["”’']/.test(output[spanEnd] ?? "")) spanEnd += 1;
    text += output.slice(cursor, spanStart) + `(see [[${reference}]])`;
    cursor = spanEnd;
    removed += 1;
  }
  text += output.slice(cursor);
  return { text, removed };
}

// ---------------------------------------------------------------------------
// App Store transactions (StoreKit 2 JWS), verified with Web Crypto.

export interface VerifiedTransaction {
  /** True when a family member shares the subscription (Family Sharing). */
  familyShared: boolean;
  bundleId: string;
  productId: string;
  originalTransactionId: string;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment: string;
}

export interface VerifyOptions {
  /** Apple Root CA - G3, DER. */
  appleRoot: Uint8Array;
  bundleId: string;
  productIds: readonly string[];
  now: Date;
  /** Accept Xcode's local StoreKit testing signature (development only). */
  allowXcode?: boolean;
}

export class VerificationError extends Error {}

// Apple marker extensions: the leaf certificate for App Store receipts, and
// the WWDR intermediate.
const APPLE_LEAF_OID = "1.2.840.113635.100.6.11.1";
const APPLE_INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

export async function verifyTransaction(jws: string, options: VerifyOptions): Promise<VerifiedTransaction> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new VerificationError("Not a JWS.");
  const header = JSON.parse(decodeText(base64UrlDecode(parts[0])));
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length === 0) {
    throw new VerificationError("Unexpected JWS header.");
  }
  const payload = JSON.parse(decodeText(base64UrlDecode(parts[1])));
  const certificates = (header.x5c as string[]).map((c) => parseCertificate(base64Decode(c)));
  const leaf = certificates[0];

  const isXcode = payload.environment === "Xcode";
  if (isXcode) {
    if (!options.allowXcode) throw new VerificationError("Xcode test transactions aren't accepted.");
  } else {
    if (certificates.length !== 3) throw new VerificationError("Expected a three-certificate chain.");
    const [, intermediate, root] = certificates;
    if (!equalBytes(root.der, options.appleRoot)) throw new VerificationError("The chain doesn't end at Apple's root.");
    if (!leaf.extensionOIDs.includes(APPLE_LEAF_OID)) throw new VerificationError("Leaf certificate isn't an App Store certificate.");
    if (!intermediate.extensionOIDs.includes(APPLE_INTERMEDIATE_OID)) throw new VerificationError("Intermediate isn't Apple's.");
    const signedAt = new Date(typeof payload.signedDate === "number" ? payload.signedDate : options.now.getTime());
    for (const cert of certificates) {
      if (signedAt < cert.notBefore || signedAt > cert.notAfter) throw new VerificationError("A certificate wasn't valid when this was signed.");
    }
    if (!(await verifyCertificateSignature(leaf, intermediate))) throw new VerificationError("Leaf certificate signature is invalid.");
    if (!(await verifyCertificateSignature(intermediate, root))) throw new VerificationError("Intermediate certificate signature is invalid.");
  }

  const key = await importPublicKey(leaf);
  const signature = base64UrlDecode(parts[2]);
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, toArrayBuffer(signature), toArrayBuffer(signed));
  if (!valid) throw new VerificationError("Signature is invalid.");

  const transaction: VerifiedTransaction = {
    familyShared: payload.inAppOwnershipType === "FAMILY_SHARED",
    bundleId: String(payload.bundleId ?? ""),
    productId: String(payload.productId ?? ""),
    originalTransactionId: String(payload.originalTransactionId ?? ""),
    expiresDate: typeof payload.expiresDate === "number" ? payload.expiresDate : undefined,
    revocationDate: typeof payload.revocationDate === "number" ? payload.revocationDate : undefined,
    appAccountToken: typeof payload.appAccountToken === "string" ? payload.appAccountToken.toLowerCase() : undefined,
    environment: String(payload.environment ?? ""),
  };
  if (transaction.bundleId !== options.bundleId) throw new VerificationError("Wrong app.");
  if (!options.productIds.includes(transaction.productId)) throw new VerificationError("Not a Premium product.");
  if (transaction.revocationDate) throw new VerificationError("The purchase was refunded or revoked.");
  if (!transaction.expiresDate || transaction.expiresDate <= options.now.getTime()) throw new VerificationError("The subscription has expired.");
  if (!transaction.originalTransactionId) throw new VerificationError("Missing transaction id.");
  return transaction;
}

// --- Minimal DER / X.509 reading -------------------------------------------

interface Node {
  tag: number;
  /** Offset of the tag byte. */
  start: number;
  /** Offset of the content. */
  contentStart: number;
  end: number;
}

function readNode(bytes: Uint8Array, offset: number): Node {
  const tag = bytes[offset];
  let length = bytes[offset + 1];
  let contentStart = offset + 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new VerificationError("Unsupported DER length.");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[offset + 2 + i];
    contentStart += count;
  }
  const end = contentStart + length;
  if (end > bytes.length) throw new VerificationError("Truncated DER.");
  return { tag, start: offset, contentStart, end };
}

function children(bytes: Uint8Array, node: Node): Node[] {
  const result: Node[] = [];
  let offset = node.contentStart;
  while (offset < node.end) {
    const child = readNode(bytes, offset);
    result.push(child);
    offset = child.end;
  }
  return result;
}

function oidString(bytes: Uint8Array): string {
  const parts: number[] = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let value = 0;
  for (let i = 1; i < bytes.length; i++) {
    value = value * 128 + (bytes[i] & 0x7f);
    if (!(bytes[i] & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

function parseTime(bytes: Uint8Array, node: Node): Date {
  const text = decodeText(bytes.slice(node.contentStart, node.end));
  if (node.tag === 0x17) {
    // UTCTime YYMMDDHHMMSSZ
    const year = Number(text.slice(0, 2));
    return new Date(Date.UTC(year >= 50 ? 1900 + year : 2000 + year, Number(text.slice(2, 4)) - 1, Number(text.slice(4, 6)), Number(text.slice(6, 8)), Number(text.slice(8, 10)), Number(text.slice(10, 12))));
  }
  // GeneralizedTime YYYYMMDDHHMMSSZ
  return new Date(Date.UTC(Number(text.slice(0, 4)), Number(text.slice(4, 6)) - 1, Number(text.slice(6, 8)), Number(text.slice(8, 10)), Number(text.slice(10, 12)), Number(text.slice(12, 14))));
}

export interface Certificate {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureAlgorithm: string;
  signature: Uint8Array;
  spki: Uint8Array;
  curve: string;
  notBefore: Date;
  notAfter: Date;
  extensionOIDs: string[];
}

export function parseCertificate(der: Uint8Array): Certificate {
  const root = readNode(der, 0);
  const [tbsNode, algorithmNode, signatureNode] = children(der, root);
  const algorithm = oidString(der.slice(children(der, algorithmNode)[0].contentStart, children(der, algorithmNode)[0].end));
  // BIT STRING: first content byte is the count of unused bits.
  const signature = der.slice(signatureNode.contentStart + 1, signatureNode.end);

  const fields = children(der, tbsNode);
  let index = fields[0].tag === 0xa0 ? 1 : 0; // optional [0] version
  index += 3; // serialNumber, signature algorithm, issuer
  const validity = children(der, fields[index]);
  index += 2; // validity, subject
  const spkiNode = fields[index];
  const spkiAlgorithm = children(der, children(der, spkiNode)[0]);
  const curve = spkiAlgorithm.length > 1 ? oidString(der.slice(spkiAlgorithm[1].contentStart, spkiAlgorithm[1].end)) : "";

  const extensionOIDs: string[] = [];
  const extensionsWrapper = fields.find((f) => f.tag === 0xa3);
  if (extensionsWrapper) {
    const sequence = children(der, extensionsWrapper)[0];
    for (const extension of children(der, sequence)) {
      const oidNode = children(der, extension)[0];
      extensionOIDs.push(oidString(der.slice(oidNode.contentStart, oidNode.end)));
    }
  }

  return {
    der,
    tbs: der.slice(tbsNode.start, tbsNode.end),
    signatureAlgorithm: algorithm,
    signature,
    spki: der.slice(spkiNode.start, spkiNode.end),
    curve,
    notBefore: parseTime(der, validity[0]),
    notAfter: parseTime(der, validity[1]),
    extensionOIDs,
  };
}

const CURVES: Record<string, { name: string; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const HASHES: Record<string, string> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};

function importPublicKey(cert: Certificate): Promise<CryptoKey> {
  const curve = CURVES[cert.curve];
  if (!curve) throw new VerificationError("Unsupported key type.");
  return crypto.subtle.importKey("spki", toArrayBuffer(cert.spki), { name: "ECDSA", namedCurve: curve.name }, false, ["verify"]);
}

async function verifyCertificateSignature(cert: Certificate, issuer: Certificate): Promise<boolean> {
  const hash = HASHES[cert.signatureAlgorithm];
  const curve = CURVES[issuer.curve];
  if (!hash || !curve) throw new VerificationError("Unsupported certificate signature.");
  const key = await importPublicKey(issuer);
  const signature = derSignatureToRaw(cert.signature, curve.size);
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, toArrayBuffer(signature), toArrayBuffer(cert.tbs));
}

/** ECDSA signatures in certificates are DER SEQUENCE { r, s }; Web Crypto wants r || s. */
export function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const sequence = readNode(der, 0);
  const [r, s] = children(der, sequence);
  const out = new Uint8Array(size * 2);
  const put = (node: Node, at: number) => {
    let value = der.slice(node.contentStart, node.end);
    while (value.length > size && value[0] === 0) value = value.slice(1);
    out.set(value, at + size - value.length);
  };
  put(r, 0);
  put(s, size);
  return out;
}

// --- Encoding helpers --------------------------------------------------------

function base64Decode(text: string): Uint8Array {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64UrlDecode(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  return base64Decode(padded);
}

function decodeText(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((value, i) => value === b[i]);
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}
