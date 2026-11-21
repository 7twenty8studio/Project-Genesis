// A cover picture made ready in the browser (VRS-18): turned the right way
// up, at most 2000 px on its long side, re-encoded as JPEG of at most 1 MB.
// Drawing it on a canvas leaves every bit of metadata behind (camera, place,
// time), so none of it is ever uploaded.

export const COVER_MAX_SIDE = 2000;
export const COVER_MAX_BYTES = 1_000_000;

/** The size to draw a picture at: its own, or scaled down to fit `max` on the long side. */
export function fitWithin(width: number, height: number, max = COVER_MAX_SIDE): { width: number; height: number } {
  const scale = Math.min(1, max / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

export class CoverUnreadable extends Error {}

export async function prepareCover(file: Blob): Promise<Blob> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch {
    throw new CoverUnreadable();
  }
  let side = COVER_MAX_SIDE;
  for (let attempt = 0; attempt < 6; attempt++) {
    const size = fitWithin(bitmap.width, bitmap.height, side);
    const canvas = document.createElement("canvas");
    canvas.width = size.width;
    canvas.height = size.height;
    const context = canvas.getContext("2d");
    if (!context) throw new CoverUnreadable();
    context.fillStyle = "#ffffff"; // Transparent PNGs get a white background, not black.
    context.fillRect(0, 0, size.width, size.height);
    context.drawImage(bitmap, 0, 0, size.width, size.height);
    for (const quality of [0.86, 0.78, 0.7, 0.6]) {
      const blob = await new Promise<Blob | null>((done) => canvas.toBlob(done, "image/jpeg", quality));
      if (blob && blob.size <= COVER_MAX_BYTES) {
        bitmap.close();
        return blob;
      }
    }
    side = Math.round(side * 0.8);
  }
  bitmap.close();
  throw new CoverUnreadable();
}
