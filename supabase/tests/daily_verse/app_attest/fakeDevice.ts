// LOCAL TESTS ONLY: plays the part of an iPhone's App Attest for dv-report's
// end-to-end test. Makes a throwaway root → intermediate CA (openssl), then per
// key a credential certificate carrying the nonce extension, the CBOR
// attestation object, and assertions — the same bytes Apple's
// DCAppAttestService produces (formats in Apple's "Validating apps that connect
// to your server"). Never used by the app or the deployed function.
import { createHash, generateKeyPairSync, sign, type KeyObject } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const sha = (b: Buffer | string) => createHash("sha256").update(b).digest();

// ---- minimal CBOR encoder (maps with text keys, byte/text strings, arrays)
function head(major: number, n: number): Buffer {
  if (n < 24) return Buffer.from([(major << 5) | n]);
  if (n < 256) return Buffer.from([(major << 5) | 24, n]);
  if (n < 65536) return Buffer.from([(major << 5) | 25, n >> 8, n & 255]);
  const b = Buffer.alloc(5); b[0] = (major << 5) | 26; b.writeUInt32BE(n, 1); return b;
}
type C = string | Buffer | C[] | { [k: string]: C };
export function cbor(v: C): Buffer {
  if (typeof v === "string") { const s = Buffer.from(v, "utf8"); return Buffer.concat([head(3, s.length), s]); }
  if (Buffer.isBuffer(v)) return Buffer.concat([head(2, v.length), v]);
  if (Array.isArray(v)) return Buffer.concat([head(4, v.length), ...v.map(cbor)]);
  const entries = Object.entries(v);
  return Buffer.concat([head(5, entries.length), ...entries.flatMap(([k, x]) => [cbor(k), cbor(x)])]);
}

function openssl(args: string[], cwd: string) {
  execFileSync("openssl", args, { cwd, stdio: ["ignore", "ignore", "pipe"] });
}

export class FakeCA {
  readonly dir: string;
  readonly rootPem: string;
  readonly rootFile: string;
  private serial = Math.floor(Math.random() * 1e6);
  /** A new CA, or the one already made in `existingDir`. */
  constructor(existingDir?: string) {
    this.dir = existingDir ?? mkdtempSync(join(tmpdir(), "dv-attest-"));
    const d = this.dir;
    this.rootFile = join(d, "root.pem");
    if (existingDir) {
      this.rootPem = readFileSync(this.rootFile, "utf8");
      return;
    }
    openssl(["ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "root.key"], d);
    openssl(["req", "-x509", "-new", "-key", "root.key", "-sha384", "-days", "30", "-subj", "/CN=Test App Attestation Root CA/O=Test", "-out", "root.pem",
      "-addext", "basicConstraints=critical,CA:true", "-addext", "keyUsage=critical,keyCertSign"], d);
    openssl(["ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "int.key"], d);
    openssl(["req", "-new", "-key", "int.key", "-subj", "/CN=Test App Attestation CA 1/O=Test", "-out", "int.csr"], d);
    writeFileSync(join(d, "int.ext"), "basicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,keyCertSign\n");
    openssl(["x509", "-req", "-in", "int.csr", "-CA", "root.pem", "-CAkey", "root.key", "-set_serial", "100", "-sha384", "-days", "30",
      "-extfile", "int.ext", "-outform", "DER", "-out", "int.der"], d);
    this.rootPem = readFileSync(this.rootFile, "utf8");
  }
  get intermediate(): Buffer { return readFileSync(join(this.dir, "int.der")); }

  /** A credential certificate for `pub`, issued by the intermediate, with `nonce` in 1.2.840.113635.100.8.2. */
  leaf(pub: KeyObject, nonce: Buffer): Buffer {
    const n = this.serial++;
    const d = this.dir;
    writeFileSync(join(d, `leaf${n}.pub.pem`), pub.export({ type: "spki", format: "pem" }));
    // The CSR's key is ignored: -force_pubkey puts the device key in the certificate.
    openssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `tmp${n}.key`], d);
    openssl(["req", "-new", "-key", `tmp${n}.key`, "-subj", `/CN=device-key-${n}/O=Test`, "-out", `leaf${n}.csr`], d);
    writeFileSync(join(d, `leaf${n}.ext`), `1.2.840.113635.100.8.2=DER:3024a1220420${nonce.toString("hex")}\n`);
    openssl(["x509", "-req", "-in", `leaf${n}.csr`, "-CA", "int.der", "-CAform", "DER", "-CAkey", "int.key", "-set_serial", String(1000 + n),
      "-sha256", "-days", "3", "-force_pubkey", `leaf${n}.pub.pem`, "-extfile", `leaf${n}.ext`, "-outform", "DER", "-out", `leaf${n}.der`], d);
    return readFileSync(join(d, `leaf${n}.der`));
  }
}

const AAGUID = { production: Buffer.concat([Buffer.from("appattest"), Buffer.alloc(7)]), development: Buffer.from("appattestdevelop") };

/** One App Attest key on one "device". */
export class FakeDevice {
  private readonly priv: KeyObject;
  private readonly pub: KeyObject;
  readonly keyIdBytes: Buffer;
  private counter = 0;
  private readonly ca: FakeCA;
  private readonly appId: string;
  constructor(ca: FakeCA, appId: string) {
    this.ca = ca;
    this.appId = appId;
    const pair = generateKeyPairSync("ec", { namedCurve: "P-256" });
    this.priv = pair.privateKey;
    this.pub = pair.publicKey;
    const spki = this.pub.export({ type: "spki", format: "der" });
    this.keyIdBytes = sha(spki.subarray(spki.length - 65)); // SHA-256 of the uncompressed point
  }
  get keyId(): string { return this.keyIdBytes.toString("base64"); }

  /** DCAppAttestService.attestKey(keyId, clientDataHash: SHA256(challenge)). */
  attest(challenge: string, environment: "production" | "development" = "production"): string {
    const authData = Buffer.concat([
      sha(this.appId), Buffer.from([0x40]), Buffer.alloc(4), AAGUID[environment],
      Buffer.from([0, 32]), this.keyIdBytes,
    ]);
    const nonce = sha(Buffer.concat([authData, sha(challenge)]));
    const leaf = this.ca.leaf(this.pub, nonce);
    return cbor({ fmt: "apple-appattest", attStmt: { x5c: [leaf, this.ca.intermediate], receipt: Buffer.alloc(200, 1) }, authData }).toString("base64");
  }

  /** DCAppAttestService.generateAssertion(keyId, clientDataHash: SHA256(challenge + "\n" + body)). */
  assert(challenge: string, body: Buffer, counter = ++this.counter): string {
    const counterBytes = Buffer.alloc(4); counterBytes.writeUInt32BE(counter);
    const authenticatorData = Buffer.concat([sha(this.appId), Buffer.from([0x40]), counterBytes]);
    const clientDataHash = sha(Buffer.concat([Buffer.from(challenge + "\n"), body]));
    const nonce = sha(Buffer.concat([authenticatorData, clientDataHash]));
    const signature = sign("sha256", nonce, this.priv); // DER, as the Secure Enclave returns it
    return cbor({ signature, authenticatorData }).toString("base64");
  }
}
