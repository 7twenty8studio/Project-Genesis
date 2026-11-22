"use server";
// The launch-day giveaway (20261127000000). Entering needs no account; the
// host page's calls go as the signed-in person, and the database only
// accepts Versely's ops admins (genesis_is_ops_admin). Nothing here trusts
// the browser.
import { config } from "@/config";
import { currentSession } from "@/lib/auth";
import { tidyEmail, tidyName, type Board, type Purpose } from "@/lib/giveaway";
import { RpcError, rpc } from "@/lib/supabase";

export type Result<T> = { ok: true; value: T } | { ok: false; code: string };

function failure(error: unknown): { ok: false; code: string } {
  if (error instanceof RpcError) return { ok: false, code: error.status === 401 ? "not_signed_in" : error.code };
  return { ok: false, code: "network" };
}

/** Enters the visitor and returns their number (the same one again for the same email). */
export async function enterGiveaway(firstName: string, email: string, wantsNews: boolean): Promise<Result<number>> {
  if (typeof firstName !== "string" || typeof email !== "string") return { ok: false, code: "invalid_name" };
  try {
    const value = await rpc<number>("giveaway_enter", {
      p_event: config.giveawayEvent,
      p_first_name: tidyName(firstName).slice(0, 40),
      p_email: tidyEmail(email).slice(0, 254),
      p_wants_news: wantsNews === true,
    });
    return { ok: true, value };
  } catch (error) {
    return failure(error);
  }
}

async function asHost<T>(fn: string, args: Record<string, unknown>): Promise<Result<T>> {
  const session = await currentSession();
  if (!session) return { ok: false, code: "not_signed_in" };
  try {
    return { ok: true, value: await rpc<T>(fn, args, session.accessToken) };
  } catch (error) {
    return failure(error);
  }
}

export async function loadBoard(): Promise<Result<Board>> {
  return asHost<Board>("giveaway_board", { p_event: config.giveawayEvent });
}

export async function drawNumber(purpose: Purpose): Promise<Result<{ id: number; number: number; name: string }>> {
  if (purpose !== "volunteer" && purpose !== "raffle") return { ok: false, code: "invalid_purpose" };
  return asHost("giveaway_draw", { p_event: config.giveawayEvent, p_purpose: purpose });
}

export async function markNoShow(id: number): Promise<Result<boolean>> {
  if (!Number.isInteger(id)) return { ok: false, code: "not_found" };
  return asHost("giveaway_no_show", { p_draw: id });
}

export async function setEntriesOpen(open: boolean): Promise<Result<boolean>> {
  return asHost("giveaway_set_open", { p_event: config.giveawayEvent, p_open: open === true });
}
