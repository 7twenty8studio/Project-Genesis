// Browser acceptance checks for the guest page and Church Studio (VRS-18),
// against the stand-in server in mock.mjs: run them with web/e2e/run.sh.
// Accessibility (axe, WCAG 2.1 AA), dark mode, 320 px and 200% text,
// keyboard, the import review, Publish waiting for it, quotations never
// reaching guests, members only and unpublish applying on the next request,
// and the Studio's saving around Members only and Unpublish.
const { chromium } = require("playwright");
const fs = require("fs");
const AXE = fs.readFileSync(require.resolve("axe-core/axe.min.js"), "utf8");
const BASE = process.env.E2E_BASE ?? "http://localhost:3100";
const MOCK = process.env.E2E_MOCK ?? "http://localhost:54329";
const OUT = process.env.E2E_SHOTS ?? "build/e2e-shots";
fs.mkdirSync(OUT, { recursive: true });
const session = encodeURIComponent(JSON.stringify({ a: "leader-token", r: "r", e: Date.now() + 86400000, u: "u1", n: "Ana" }));
const problems = [];
const note = (m) => { console.log(m); };

async function axe(page, label) {
  await page.addScriptTag({ content: AXE });
  const result = await page.evaluate(async () => await window.axe.run(document, { runOnly: ["wcag2a", "wcag2aa", "wcag21aa", "best-practice"] }));
  for (const v of result.violations) {
    problems.push(`${label}: ${v.id} (${v.impact}) ${v.nodes.length}x: ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`);
  }
}
async function noSideScroll(page, label) {
  const w = await page.evaluate(() => [document.documentElement.scrollWidth, window.innerWidth]);
  if (w[0] > w[1] + 1) problems.push(`${label}: page scrolls sideways (${w[0]} > ${w[1]})`);
}

(async () => {
  const browser = await chromium.launch();
  for (const [locale, header] of [["en", "en-US"], ["es", "es-MX,es;q=0.9"], ["pt", "pt-BR,pt;q=0.9"]]) {
    for (const scheme of ["light", "dark"]) {
      const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, colorScheme: scheme, extraHTTPHeaders: { "Accept-Language": header } });
      const page = await ctx.newPage();
      page.on("console", (m) => m.type() === "error" && problems.push(`console ${locale}/${scheme}: ${m.text()}`));
      await page.goto(`${BASE}/s/livelivel1`);
      await page.getByRole("button", { name: /Matthew|Mateo|Mateus/ }).first().click();
      await page.waitForSelector("text=/labour|heavy laden/i", { timeout: 8000 }).catch(() => problems.push(`${locale}: KJV passage did not load`));
      await axe(page, `guest ${locale}/${scheme}`);
      await noSideScroll(page, `guest ${locale}/${scheme}`);
      await page.screenshot({ path: `${OUT}/guest-${locale}-${scheme}.png`, fullPage: true });
      await ctx.close();
    }
  }

  // A YouVersion Bible the pastor named opens in it, with its footnote and the publisher's link.
  {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const page = await ctx.newPage();
    await page.goto(`${BASE}/s/livelivel1`);
    await page.getByRole("button", { name: /Rom 8:28/ }).first().click();
    await page.waitForSelector("text=Stand-in footnote", { timeout: 8000 }).catch(() => problems.push("YouVersion: NIV passage did not load"));
    if (!(await page.getByRole("link", { name: "Footnote a" }).count())) problems.push("YouVersion: footnote marker missing");
    if (!(await page.getByText("Stand-in footnote").count())) problems.push("YouVersion: footnote text missing");
    if (!(await page.getByRole("link", { name: "biblica.com" }).count())) problems.push("YouVersion: publisher link missing");
    if (!(await page.locator("optgroup[label='From YouVersion'] option[value='NIV']").count())) problems.push("YouVersion: NIV not in the Bible menu");
    await axe(page, "guest YouVersion passage");
    await page.screenshot({ path: `${OUT}/guest-youversion.png`, fullPage: true });
    await ctx.close();
  }

  // Zoom: 320 px wide is a 1280 px window at 400%; text at 200%.
  {
    const ctx = await browser.newContext({ viewport: { width: 320, height: 640 } });
    const page = await ctx.newPage();
    await page.goto(`${BASE}/s/livelivel1`);
    await noSideScroll(page, "guest 320px");
    await page.addStyleTag({ content: "html{font-size:200%}" });
    await noSideScroll(page, "guest 320px text 200%");
    await page.screenshot({ path: `${OUT}/guest-320-text200.png`, fullPage: true });
    // Keyboard: Tab reaches Jump to links, passage buttons, Copy; Enter opens a passage.
    const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const p2 = await ctx2.newPage();
    await p2.goto(`${BASE}/s/livelivel1`);
    const seen = [];
    for (let i = 0; i < 25; i++) {
      await p2.keyboard.press("Tab");
      seen.push(await p2.evaluate(() => { const e = document.activeElement; const s = getComputedStyle(e); return `${e.tagName}:${(e.getAttribute("aria-label") || e.textContent || "").trim().slice(0, 30)}:${s.outlineStyle}`; }));
    }
    note("tab order: " + seen.join(" → "));
    if (!seen.some((s) => s.includes("Matthew"))) problems.push("keyboard: passage button not reachable");
    if (seen.some((s) => s.endsWith(":none") && !s.startsWith("BODY"))) problems.push("keyboard: an element without a focus ring: " + seen.filter((s) => s.endsWith(":none")).join(", "));
    await ctx.close();
    await ctx2.close();
  }

  // Members only: a guest learns only that it's for members; never stored.
  {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const page = await ctx.newPage();
    const r = await page.goto(`${BASE}/s/membmemb01`);
    const html = await page.content();
    if (html.includes("Members Night Secret") || html.includes("Only for members of Grace Church")) problems.push("members-only sermon shown to a guest");
    if (!/member/i.test(await page.locator("main").innerText())) problems.push("members-only page doesn't say it's for members");
    const cache = r.headers()["cache-control"] ?? "";
    if (!/no-store/.test(cache) || !/private|no-cache/.test(cache)) problems.push("members-only page may be stored: " + cache);
    const link = await page.goto(`${BASE}/s/livelivel1`);
    const linkCache = link.headers()["cache-control"] ?? "";
    if (!/no-store/.test(linkCache)) problems.push("guest page may be stored: " + linkCache);
    note(`cache-control: members ${cache} / link ${linkCache}`);
    await axe(page, "members only");
    await ctx.close();
  }

  // Studio as a leader.
  for (const [locale, header] of [["en", "en-US"], ["es", "es-ES"], ["pt", "pt-BR"]]) {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, extraHTTPHeaders: { "Accept-Language": header } });
    await ctx.addCookies([{ name: "vs_session", value: session, url: BASE }]);
    const page = await ctx.newPage();
    page.on("console", (m) => m.type() === "error" && problems.push(`studio console ${locale}: ${m.text()}`));
    page.on("pageerror", (e) => problems.push(`studio page error ${locale}: ${e.message}`));
    await page.goto(`${BASE}/studio`);
    await axe(page, `studio home ${locale}`);
    await page.screenshot({ path: `${OUT}/studio-home-${locale}.png`, fullPage: true });
    if (locale !== "en") { await ctx.close(); continue; }

    await page.goto(`${BASE}/studio/22222222-2222-4222-8222-222222222222`, { waitUntil: "networkidle" });
    await page.getByLabel("Paste text").fill("# Rest for the Weary\n\nJesus calls the tired.\n\nMatthew 11:28-30 (NIV) “Come to me, all you who are weary”\n\n- Come\n- Learn\n\nJo 99:99\n\n> John 3:16 (NIV)\n> For God so loved the world, that he gave his one and only Son\n\n> As John 10:11 (ESV) puts it, he is the good shepherd who lays down his life\n\nAmen.");
    await page.getByRole("button", { name: "Make the outline" }).click();
    await page.waitForSelector("text=Check the import");
    await axe(page, "studio outline + review");
    await page.screenshot({ path: `${OUT}/studio-outline.png`, fullPage: true });
    // Publish must wait for the review.
    await page.getByRole("tab", { name: "Publish" }).click();
    const publish = page.getByRole("button", { name: "Publish", exact: true });
    if (!(await publish.isDisabled())) problems.push("publish enabled before title and review");
    await page.getByRole("tab", { name: "Details" }).click();
    await page.getByLabel("Title").fill("Rest for the Weary");
    await page.getByRole("tab", { name: "Outline" }).click();
    // The review is saved with the draft: a fresh page (another computer) still has it, and Publish still waits.
    await page.waitForSelector("text=All changes saved", { timeout: 8000 });
    const saved = await (await fetch(MOCK + "/mock/sermon?id=22222222-2222-4222-8222-222222222222")).json();
    note("review saved with the draft: " + JSON.stringify((saved.draft_review?.items ?? []).map((i) => i.kind)));
    if (!saved.draft_review?.items?.some((i) => i.kind === "quotation")) problems.push("the uncertain ESV quotation isn't on the saved review");
    if (!saved.draft_blocks.some((b) => b.kind === "scripture" && b.ref.label === "NIV" && b.ref.raw === "John 3:16")) problems.push("NIV blockquote did not become a Scripture block");
    const other = await ctx.newPage();
    await other.goto(`${BASE}/studio/22222222-2222-4222-8222-222222222222`, { waitUntil: "networkidle" });
    if (!(await other.locator("text=Check the import").count())) problems.push("review not shown after reload");
    await other.close();
    for (let i = 0; i < 6; i++) {
      const keep = page.getByRole("button", { name: "Keep as written" });
      if (!(await keep.count())) break;
      await keep.first().click();
    }
    await page.getByRole("tab", { name: "Publish" }).click();
    await page.waitForSelector("text=All changes saved", { timeout: 8000 });
    await page.screenshot({ path: `${OUT}/studio-share-before.png`, fullPage: true });
    if (await publish.isDisabled()) problems.push("publish still disabled after review: " + (await page.locator("section").first().innerText()));
    else {
      await publish.click();
      await page.waitForSelector("text=/Published\\./", { timeout: 8000 }).catch(() => problems.push("publish didn't confirm"));
    }
    await axe(page, "studio share");
    await page.screenshot({ path: `${OUT}/studio-share.png`, fullPage: true });
    // On a wide screen the phone preview is always beside the editor.
    if (!(await page.getByRole("region", { name: "Preview" }).isVisible())) problems.push("desktop: the preview isn't beside the editor");
    await axe(page, "studio preview");
    await page.screenshot({ path: `${OUT}/studio-preview.png`, fullPage: false });
    // Keyboard on the section list (down the sidebar).
    await page.getByRole("tab", { name: "Details" }).click();
    await page.keyboard.press("ArrowDown");
    const active = await page.evaluate(() => document.activeElement?.textContent);
    if (active !== "Publish") problems.push(`tab arrows: focus went to ${active}`);
    // The published page is readable as a guest.
    const guest = await browser.newPage();
    const slug = (await page.locator("code").first().innerText()).split("/s/")[1];
    await guest.goto(`${BASE}/s/${slug}`);
    if (!(await guest.locator("h1").innerText()).includes("Rest for the Weary")) problems.push("published sermon not readable");
    if ((await guest.content()).includes("Come to me, all you who are weary")) problems.push("NIV quotation leaked to the guest page");
    if ((await guest.content()).includes("his one and only Son")) problems.push("NIV blockquote leaked to the guest page");
    await guest.close();
    // Unpublish and Members only work while saving fails, then the edit is saved on the new version.
    await fetch(MOCK + "/mock/fail-saves?on=1");
    await page.goto(`${BASE}/studio/33333333-3333-4333-8333-333333333333`, { waitUntil: "networkidle" });
    await page.getByRole("tab", { name: "Details" }).click();
    await page.getByLabel("Title").fill("Rest for the Weary, revised");
    await page.waitForSelector("text=Not saved", { timeout: 8000 });
    await page.getByRole("tab", { name: "Publish" }).click();
    await page.getByRole("button", { name: "Members only now" }).click();
    await page.waitForSelector("text=Now only church members can read it.", { timeout: 8000 }).catch(() => problems.push("members only waited on the failed save"));
    let live = await (await fetch(MOCK + "/mock/sermon?id=33333333-3333-4333-8333-333333333333")).json();
    if (live.live_audience !== "members") problems.push("members only didn't reach the database: " + live.live_audience);
    await page.getByRole("button", { name: "Unpublish" }).click();
    await page.waitForSelector("text=Unpublished. The link no longer opens it.", { timeout: 8000 }).catch(() => problems.push("unpublish waited on the failed save"));
    live = await (await fetch(MOCK + "/mock/sermon?id=33333333-3333-4333-8333-333333333333")).json();
    if (live.status !== "unpublished") problems.push("unpublish didn't reach the database: " + live.status);
    {
      const g = await browser.newPage();
      const r = await g.goto(`${BASE}/s/livelivel1`);
      if (r.status() !== 404 || (await g.content()).includes("Rest for the Weary")) problems.push(`unpublished sermon still shown on the next request (${r.status()})`);
      await g.close();
    }
    await fetch(MOCK + "/mock/fail-saves?on=0");
    const again = page.getByRole("button", { name: "Try again" });
    if (await again.count()) await again.click();
    await page.waitForSelector("text=All changes saved", { timeout: 8000 }).catch(() => problems.push("the edit wasn't saved after closing"));
    live = await (await fetch(MOCK + "/mock/sermon?id=33333333-3333-4333-8333-333333333333")).json();
    note(`after closing: title=${live.title} audience=${live.audience} status=${live.status} version=${live.draft_version}`);
    if (live.title !== "Rest for the Weary, revised" || live.audience !== "members") problems.push("edit after closing saved wrong: " + JSON.stringify({ t: live.title, a: live.audience }));
    // A stale tab: another leader saves a newer title, then this tab (with an older pending edit) unpublishes.
    await fetch(MOCK + "/mock/touch?publish=1&id=33333333-3333-4333-8333-333333333333&title=" + encodeURIComponent("Before"));
    await page.goto(`${BASE}/studio/33333333-3333-4333-8333-333333333333`, { waitUntil: "networkidle" });
    await fetch(MOCK + "/mock/touch?id=33333333-3333-4333-8333-333333333333&title=" + encodeURIComponent("Newer title from another tab"));
    await fetch(MOCK + "/mock/fail-saves?on=1");
    await page.getByRole("tab", { name: "Details" }).click();
    await page.getByLabel("Title").fill("Stale title");
    await page.waitForSelector("text=Not saved", { timeout: 8000 });
    await fetch(MOCK + "/mock/fail-saves?on=0");
    await page.getByRole("tab", { name: "Publish" }).click();
    const unpub = page.getByRole("button", { name: "Unpublish" });
    if (await unpub.count()) await unpub.click(); else await page.getByRole("button", { name: "Members only now" }).click();
    await page.waitForSelector("text=changed in another window", { timeout: 8000 }).catch(() => problems.push("stale tab not told the draft changed"));
    await page.waitForTimeout(2500);
    live = await (await fetch(MOCK + "/mock/sermon?id=33333333-3333-4333-8333-333333333333")).json();
    note(`stale tab after closing: title=${live.title} version=${live.draft_version}`);
    if (live.title !== "Newer title from another tab") problems.push("stale tab overwrote the newer draft: " + live.title);
    // A slow Unpublish with editing during it: the queued autosave uses the version Unpublish returns.
    await fetch(MOCK + "/mock/touch?publish=1&id=33333333-3333-4333-8333-333333333333&title=" + encodeURIComponent("Slow start"));
    await page.goto(`${BASE}/studio/33333333-3333-4333-8333-333333333333`, { waitUntil: "networkidle" });
    await fetch(MOCK + "/mock/slow-close?ms=3000");
    await page.getByRole("tab", { name: "Publish" }).click();
    await page.getByRole("button", { name: "Unpublish" }).click();
    await page.getByRole("tab", { name: "Details" }).click();
    await page.getByLabel("Title").fill("Typed while unpublishing");
    await page.waitForTimeout(5500);
    await fetch(MOCK + "/mock/slow-close?ms=0");
    const slowState = await page.locator("[role=status]").first().innerText();
    live = await (await fetch(MOCK + "/mock/sermon?id=33333333-3333-4333-8333-333333333333")).json();
    note(`slow unpublish: state=${slowState} title=${live.title} status=${live.status} version=${live.draft_version}`);
    if (!/All changes saved/.test(slowState) || live.title !== "Typed while unpublishing" || live.status !== "unpublished") problems.push("slow unpublish: " + slowState + " / " + live.title + " / " + live.status);
    await ctx.close();
  }
  // The home page and Studio's sign-in: every language, light and dark, phone and desktop.
  for (const [locale, header] of [["en", "en-US"], ["es", "es-MX"], ["pt", "pt-BR"]]) {
    for (const scheme of ["light", "dark"]) {
      for (const width of [390, 1280]) {
        const ctx = await browser.newContext({ viewport: { width, height: 844 }, colorScheme: scheme, extraHTTPHeaders: { "Accept-Language": header } });
        const page = await ctx.newPage();
        for (const path of ["/", "/studio"]) {
          await page.goto(`${BASE}${path}`);
          await axe(page, `${path} ${locale}/${scheme}/${width}`);
          await noSideScroll(page, `${path} ${locale}/${scheme}/${width}`);
          if (scheme === "light") await page.screenshot({ path: `${OUT}/${path === "/" ? "home" : "signin"}-${locale}-${width}.png`, fullPage: true });
        }
        if (await page.getByRole("link", { name: /Apple/ }).count()) problems.push("Apple sign-in shown before it's set up");
        await ctx.close();
      }
    }
  }

  // Appearance and Language: Cream first; a choice applies at once and is remembered.
  {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, colorScheme: "dark", extraHTTPHeaders: { "Accept-Language": "en-US" } });
    const page = await ctx.newPage();
    await page.goto(`${BASE}/`);
    if ((await page.getAttribute("html", "data-theme")) !== "cream") problems.push("first visit isn't Cream (even on a dark device)");
    await page.getByRole("button", { name: /Appearance and language/ }).click();
    await axe(page, "appearance menu");
    await page.screenshot({ path: `${OUT}/prefs-menu.png` });
    await page.getByLabel("Warm Dark").check();
    if ((await page.getAttribute("html", "data-theme")) !== "dark") problems.push("Warm Dark didn't apply at once");
    await page.getByLabel("Español").check();
    await page.waitForSelector("text=Comparte tu mensaje del domingo", { timeout: 8000 }).catch(() => problems.push("Español didn't apply at once"));
    await page.goto(`${BASE}/studio`);
    if ((await page.getAttribute("html", "data-theme")) !== "dark" || (await page.getAttribute("html", "lang")) !== "es") problems.push("choices not remembered on the next page");
    await axe(page, "studio sign-in, Warm Dark, Español");
    await page.screenshot({ path: `${OUT}/signin-es-dark.png`, fullPage: true });
    for (const look of ["daylight", "system"]) {
      await ctx.addCookies([{ name: "vs_theme", value: look, url: BASE }]);
      await page.goto(`${BASE}/`);
      await axe(page, `home ${look}`);
    }
    await ctx.close();
  }

  // Starting a church: the name form, a group from the app, then the new church opens.
  {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    await ctx.addCookies([{ name: "vs_session", value: session, url: BASE }]);
    const page = await ctx.newPage();
    await page.goto(`${BASE}/studio?new=1`);
    await axe(page, "start a church");
    await noSideScroll(page, "start a church");
    if (!(await page.getByText("Tuesday Bible Study").count())) problems.push("start a church: the person's own group isn't offered");
    await page.getByLabel("Church or ministry name").fill("Hope Chapel");
    await page.getByLabel("Your name").fill("Pat");
    await page.screenshot({ path: `${OUT}/start-church.png`, fullPage: true });
    await page.getByRole("button", { name: "Create" }).click();
    await page.waitForURL(/\/studio\/[0-9a-f-]{36}/, { timeout: 8000 }).catch(() => problems.push("start a church: didn't open its first draft"));
    await ctx.close();
  }

  // Phone-width Studio editor, not-found and members-only pages.
  {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    await ctx.addCookies([{ name: "vs_session", value: session, url: BASE }]);
    const page = await ctx.newPage();
    await page.goto(`${BASE}/studio/33333333-3333-4333-8333-333333333333`);
    await noSideScroll(page, "studio editor 390px");
    await axe(page, "studio editor 390px");
    await page.screenshot({ path: `${OUT}/studio-editor-phone.png`, fullPage: true });
    await page.getByRole("tab", { name: "Details" }).click();
    await noSideScroll(page, "studio details 390px");
    await page.screenshot({ path: `${OUT}/studio-details-phone.png`, fullPage: true });
    // Phones: Edit / Preview.
    await page.getByRole("button", { name: "Preview", exact: true }).click();
    if (!(await page.getByRole("region", { name: "Preview" }).isVisible()) || (await page.getByRole("tab", { name: "Details" }).isVisible())) problems.push("phone: Preview didn't replace the editor");
    await noSideScroll(page, "studio preview 390px");
    await page.screenshot({ path: `${OUT}/studio-preview-phone.png`, fullPage: true });
    await page.getByRole("button", { name: "Edit", exact: true }).click();
    if (!(await page.getByRole("tab", { name: "Details" }).isVisible())) problems.push("phone: Edit didn't bring the editor back");
    const guest = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const g = await guest.newPage();
    const r = await g.goto(`${BASE}/s/zzzzzzzzzz`);
    if (r.status() !== 404) problems.push(`not found answered ${r.status()}`);
    await axe(g, "not found");
    await g.goto(`${BASE}/studio`);
    await axe(g, "studio signed out");
    await g.screenshot({ path: `${OUT}/studio-signed-out.png`, fullPage: true });
    const cover = await g.goto(`${BASE}/s/livelivel1/cover?v=x`);
    note("guest cover without one: " + cover.status() + " " + cover.headers()["cache-control"]);
    await guest.close();
    await ctx.close();
  }
  await browser.close();
  console.log(problems.length ? "PROBLEMS:\n" + problems.join("\n") : "no problems");
  if (problems.length) process.exitCode = 1;
})();
