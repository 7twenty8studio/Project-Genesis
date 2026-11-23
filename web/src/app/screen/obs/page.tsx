import type { Metadata } from "next";
import { ObsView } from "@/components/screenshare/ObsView";
import { cleanId } from "@/lib/screenshare/protocol";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Screen", robots: { index: false, follow: false } };

type Props = { searchParams: Promise<{ room?: string; device?: string; fit?: string; bg?: string; audio?: string; label?: string }> };

/**
 * An OBS browser source for one device: /screen/obs?room=…&device=…
 * Options: fit=cover (fill, cropping), bg=black (else clear), audio=1, label=1 (shows the ID while waiting).
 */
export default async function ScreenObs({ searchParams }: Props) {
  const params = await searchParams;
  const room = cleanId(params.room);
  const device = cleanId(params.device);
  if (!room || !device) return null;
  return (
    <ObsView
      room={room}
      device={device}
      fit={params.fit === "cover" ? "cover" : "contain"}
      background={params.bg === "black" ? "black" : "clear"}
      audio={params.audio === "1"}
      label={params.label === "1"}
    />
  );
}
