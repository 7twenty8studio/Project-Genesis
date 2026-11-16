// LOCAL TESTS ONLY. run.sh serves dv-report with an import map that swaps
// _shared/appAttest.ts for this file, so the function trusts a throwaway test
// root (made by fakeDevice.ts) instead of Apple's. Production code has no way
// to change the root: it's a constant in appAttest.ts, and this file is never
// deployed (only supabase/functions/* is).
import * as real from "./appAttest.real.ts";
export * from "./appAttest.real.ts";

const root = Deno.readTextFileSync(Deno.env.get("DV_TEST_ATTEST_ROOT_PEM_FILE")!);

export function verifyAttestation(params: Parameters<typeof real.verifyAttestation>[0]) {
  return real.verifyAttestation({ ...params, rootPem: root });
}
