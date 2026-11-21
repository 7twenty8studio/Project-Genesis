// pdf.js reads PDFs in a worker; Studio loads it from /pdf.worker.min.mjs.
// Copied from the installed pdfjs-dist before every dev run and build, so
// the worker always matches the library.
import { copyFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
copyFileSync(join(here, "../node_modules/pdfjs-dist/build/pdf.worker.min.mjs"), join(here, "../public/pdf.worker.min.mjs"));
