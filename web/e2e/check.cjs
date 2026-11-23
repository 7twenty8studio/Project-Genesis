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
    if (locale === "en") {
      const picker = page.locator("header select, main select").first();
      if ((await picker.inputValue().catch(() => "")) === "") problems.push("church picker not shown with two churches");
      else await picker.locator("xpath=ancestor::div[1]").screenshot({ path: `${OUT}/church-picker.png` });
    }
    if (locale !== "en") { await ctx.close(); continue; }

    await page.goto(`${BASE}/studio/22222222-2222-4222-8222-222222222222`, { waitUntil: "networkidle" });
    await page.getByLabel("Paste text").fill("# Rest for the Weary\n\nJesus calls the tired.\n\nMatthew 11:28-30 (NIV) “Come to me, all you who are weary”\n\n- Come\n- Learn\n\nJo 99:99\n\n> John 3:16 (NIV)\n> For God so loved the world, that he gave his one and only Son\n\n> As John 10:11 (ESV) puts it, he is the good shepherd who lays down his life\n\nAmen.");
    await page.getByRole("button", { name: "Make the outline" }).click();
    await page.waitForSelector("text=Check the import");
    await axe(page, "studio outline + review");
    await page.screenshot({ path: `${OUT}/studio-outline.png`, fullPage: true });
    // Drag and drop: the first card dragged by its grip below the second, then moved back with its arrow.
    {
      const order = () => page.locator("ol[aria-label='Outline'] > li").evaluateAll((cards) => cards.map((c) => c.dataset.block));
      const before = await order();
      const grip = await page.locator(`[data-drag-handle='${before[0]}']`).boundingBox();
      const second = await page.locator(`li[data-block='${before[1]}']`).boundingBox();
      await page.mouse.move(grip.x + grip.width / 2, grip.y + grip.height / 2);
      await page.mouse.down();
      await page.mouse.move(grip.x + grip.width / 2, second.y + second.height - 4, { steps: 12 });
      await page.mouse.up();
      const after = await order();
      if (after[0] !== before[1] || after[1] !== before[0]) problems.push("drag and drop didn't move the card: " + JSON.stringify(after.slice(0, 2)));
      else await page.locator(`#move-up-${before[0]}`).click();
      if (JSON.stringify(await order()) !== JSON.stringify(before)) problems.push("the outline didn't go back after Move up");
    }
    // Publish must wait for the review.
    await page.getByRole("tab", { name: "Publish" }).click();
    const publish = page.getByRole("button", { name: "Publish", exact: true });
    if (!(await publish.isDisabled())) problems.push("publish enabled before title and review");
    // It says why, and Fix this puts the cursor in the field.
    const why = page.getByTestId("publish-blockers");
    if (!/Publish is off until you finish/.test(await why.innerText().catch(() => ""))) problems.push("publish doesn't say why it's off");
    const titleFix = why.locator("li", { hasText: "Give the sermon a title." }).getByRole("button", { name: "Fix this" });
    if (await titleFix.count()) {
      await titleFix.click();
      await page.waitForTimeout(200);
      if ((await page.evaluate(() => document.activeElement?.getAttribute("data-fix"))) !== "title") problems.push("Fix this didn't open the title");
    } else problems.push("no Fix this for the missing title");
    await page.getByRole("tab", { name: "Details" }).click();
    // The preview's long sermon (its hidden screen-reader text included) never stretches the page past the editor.
    const extra = await page.evaluate(() => document.documentElement.scrollHeight - (document.querySelector("main").getBoundingClientRect().bottom + scrollY));
    if (extra > 40) problems.push(`the page runs ${Math.round(extra)}px past the editor on Details`);
    await page.getByLabel("Title").fill("Rest for the Weary");
    // Date and Series sit side by side with their boxes level (the series hint goes under its box).
    {
      const date = await page.getByLabel("Date", { exact: true }).boundingBox();
      const series = await page.getByLabel("Series (optional)").boundingBox();
      if (date && series && Math.abs(date.y - series.y) > 1 && Math.abs(date.x - series.x) > 1) problems.push(`date and series boxes not level: ${date.y} vs ${series.y}`);
      await page.screenshot({ path: `${OUT}/studio-details.png`, fullPage: true });
    }
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
    const slug = (await page.locator("code").first().innerText()).split("/s/")[1];
    // Invite members: the group's code, shared as in the app, and a new one on request.
    {
      const home = await page.context().newPage();
      await home.goto(`${BASE}/studio`);
      const code = home.getByTestId("invite-code");
      if ((await code.innerText()) !== "GRACE-12345") problems.push("invite code not shown: " + (await code.innerText()));
      await home.getByRole("button", { name: "New Code" }).click();
      await home.getByText("New code made. The old one no longer works.").waitFor({ timeout: 8000 }).catch(() => problems.push("invite: no new code"));
      if ((await code.innerText()) !== "NEWCO-DE789") problems.push("new invite code not shown: " + (await code.innerText()));
      await axe(home, "invite members");
      await home.getByRole("heading", { name: "Invite members" }).locator("xpath=..").screenshot({ path: `${OUT}/invite-members.png` });
      await home.close();
    }
    // Locations and Times: a place without a name is refused, then saved and shown on the sermon page.
    {
      const home = await page.context().newPage();
      await home.goto(`${BASE}/studio`);
      await home.getByRole("button", { name: "Add a place" }).click();
      await home.getByLabel("Street address").fill("1 Hill Rd");
      await home.getByLabel("City").fill("Austin");
      await home.getByLabel("State or province").fill("TX");
      await home.getByLabel("ZIP or postal code").fill("78701");
      await home.getByLabel("Country").fill("United States");
      // The first time: Wednesdays at 7:00 PM, from the lists. Then a second one, once, on a date.
      await home.locator("#place-0-time-0-when").selectOption("wed");
      await home.locator("#place-0-time-0-time").selectOption("19:00");
      await home.getByRole("button", { name: "Add a time" }).click();
      await home.locator("#place-0-time-1-repeat").selectOption("once");
      await home.locator("#place-0-time-1-when").fill("2099-12-24");
      await home.locator("#place-0-time-1-time").selectOption("18:30");
      await home.locator("#place-0-time-1-note").fill("Candlelight");
      await home.getByRole("button", { name: "Save locations" }).click();
      await home.getByText("Give each place a name and each one-time gathering a date.").waitFor({ timeout: 8000 }).catch(() => problems.push("locations: a place without a name wasn't refused"));
      await home.getByLabel("Name", { exact: true }).fill("Main Campus");
      await home.getByRole("button", { name: "Save locations" }).click();
      await home.getByText("Saved. Every sermon page shows it now.").waitFor({ timeout: 8000 }).catch(() => problems.push("locations: not saved"));
      await axe(home, "locations editor");
      await home.screenshot({ path: `${OUT}/locations-editor.png`, fullPage: true });
      await home.close();
    }
    // The published page is readable as a guest.
    const guest = await browser.newPage();
    await guest.goto(`${BASE}/s/${slug}`);
    if (!(await guest.locator("h1").innerText()).includes("Rest for the Weary")) problems.push("published sermon not readable");
    await guest.getByRole("link", { name: "Locations and Times" }).click();
    const shown = await guest.locator("#locations").innerText();
    for (const want of ["Wednesdays · 7:00 PM", "December 24, 2099 · 6:30 PM (Candlelight)", "1 Hill Rd", "Austin, TX 78701", "United States"])
      if (!shown.includes(want)) problems.push(`locations: "${want}" not shown on the sermon page`);
    if (!(await guest.locator("#locations").innerText()).includes("Join us")) problems.push("no invitation without a next sermon");
    const directions = await guest.locator("#locations a").first().getAttribute("href");
    if (!directions?.includes("query=1%20Hill%20Rd%2C%20Austin%2C%20TX%2078701%2C%20United%20States")) problems.push("directions link wrong: " + directions);
    await axe(guest, "sermon with locations");
    await guest.screenshot({ path: `${OUT}/sermon-locations.png`, fullPage: true });
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
  // Fill-in-the-blank handouts: no key before reveal (not even in the page source), answers kept in the browser per revision,
  // Check and Show together after reveal, Practice Again keeps the saved answers; Studio's Make Blank and Reveal Answers.
  {
    const HB = "77777777-7777-4777-8777-777777777777";
    await fetch(MOCK + `/mock/reveal?id=${HB}&on=0`);
    const source = await (await fetch(`${BASE}/s/handout001`)).text();
    if (/Seeing|Giver/.test(source)) problems.push("handout: an answer is in the page before reveal");
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const page = await ctx.newPage();
    page.on("pageerror", (e) => problems.push(`handout page error: ${e.message}`));
    await page.goto(`${BASE}/s/handout001`);
    const blank1 = page.getByRole("textbox", { name: "Blank 1" });
    if (!(await blank1.count())) problems.push("handout: blank 1 not shown");
    if (!(await page.getByRole("textbox", { name: "Blank 3, Your own words" }).count())) problems.push("handout: open blank not shown");
    if (await page.getByRole("button", { name: "Check Answers" }).count()) problems.push("handout: Check Answers before reveal");
    if (await page.getByRole("button", { name: "Show Answers" }).count()) problems.push("handout: Show Answers before reveal");
    await blank1.fill("seeing");
    await page.getByRole("textbox", { name: "Blank 2" }).fill("Taker");
    await axe(page, "handout before reveal");
    await noSideScroll(page, "handout before reveal");
    await page.screenshot({ path: `${OUT}/handout-hidden.png`, fullPage: true });
    await page.reload();
    if ((await page.getByRole("textbox", { name: "Blank 1" }).inputValue()) !== "seeing") problems.push("handout: answer not kept in the browser");
    await fetch(MOCK + `/mock/reveal?id=${HB}&on=1`);
    await page.reload();
    await page.getByRole("button", { name: "Check Answers" }).click();
    if (!(await page.getByText("✓ Correct").count())) problems.push("handout: a right answer isn't marked correct");
    if (!(await page.getByText("Not yet").count())) problems.push("handout: a wrong answer isn't marked");
    await page.getByRole("button", { name: "Show Answers" }).click();
    if (!(await page.getByText("(Answer: Giver)").count())) problems.push("handout: Show Answers didn't show the key");
    await axe(page, "handout revealed");
    await page.screenshot({ path: `${OUT}/handout-revealed.png`, fullPage: true });
    await page.getByRole("button", { name: "Practice Again" }).click();
    if ((await page.getByRole("textbox", { name: "Blank 1" }).inputValue()) !== "") problems.push("handout: Practice Again didn't start fresh");
    await page.getByRole("textbox", { name: "Blank 1" }).fill("x");
    await page.getByRole("button", { name: "Back to My Answers" }).click();
    if ((await page.getByRole("textbox", { name: "Blank 1" }).inputValue()) !== "seeing") problems.push("handout: practice changed the saved answers");
    const kept = await page.evaluate(() => Object.keys(localStorage).filter((k) => k.startsWith("versely.handout.handout001.")));
    if (kept.join() !== "versely.handout.handout001.1") problems.push("handout: answers not saved per revision: " + kept.join());
    await ctx.close();

    // Studio: Make Blank on selected words, an imported handout's lines, Publish waiting for answers, Reveal Answers.
    await fetch(MOCK + `/mock/reveal?id=${HB}&on=0`);
    const sctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    await sctx.addCookies([{ name: "vs_session", value: session, url: BASE }]);
    const sp = await sctx.newPage();
    sp.on("pageerror", (e) => problems.push(`studio handout page error: ${e.message}`));
    await sp.goto(`${BASE}/studio/${HB}`, { waitUntil: "networkidle" });
    if (!(await sp.getByLabel("Answer").first().count())) problems.push("studio handout: blanks not listed");
    await sp.getByRole("button", { name: "Paste or import an outline" }).click();
    await sp.getByLabel("Paste text").fill("Gratitude\n\n- Gratitude starts with ______ God the _____\n\n> A quotation with ____ stays as written");
    const addMode = sp.getByLabel(/Add after/);
    if (await addMode.count()) await addMode.check();
    await sp.getByRole("button", { name: "Make the outline" }).click();
    await sp.waitForTimeout(400);
    if ((await sp.getByText("Type the answer, or make it an open blank.").count()) < 2) problems.push("studio handout: imported blank lines don't wait for answers");
    await sp.getByRole("tab", { name: "Publish" }).click();
    if (!(await sp.getByText("Give every blank its answer, or make it an open blank.").count())) problems.push("studio handout: Publish doesn't say the blanks need answers");
    await sp.getByRole("button", { name: "Fix this" }).first().click();
    await sp.waitForTimeout(300);
    const empty = sp.locator("input[aria-invalid=true]");
    const n = await empty.count();
    for (let i = 0; i < n; i++) await empty.first().fill(i === 0 ? "Knowing" : "Sustainer");
    await sp.waitForTimeout(1800);
    await sp.getByRole("tab", { name: "Publish" }).click();
    if (await sp.getByText("Give every blank its answer, or make it an open blank.").count()) problems.push("studio handout: still blocked after giving answers");
    if (!(await sp.getByTestId("answers-section").count())) problems.push("studio handout: no Answers section");
    await sp.getByRole("button", { name: "Reveal Answers" }).click();
    await sp.getByText("Members can check their answers now.").waitFor({ timeout: 5000 }).catch(() => problems.push("studio handout: Reveal Answers didn't take"));
    await axe(sp, "studio handout publish");
    await sp.screenshot({ path: `${OUT}/studio-handout.png`, fullPage: true });
    await sp.locator("section[aria-labelledby=publish-title]").getByRole("button", { name: /^Publish/ }).click();
    await sp.getByText("Published.", { exact: false }).first().waitFor({ timeout: 5000 }).catch(() => problems.push("studio handout: republish didn't finish"));
    const view = await (await fetch(`${BASE}/s/handout001`)).text();
    if (/Knowing|Sustainer/.test(view)) problems.push("studio handout: a republished revision didn't start hidden");
    // Make Blank on selected words keeps them as the answer.
    await sp.getByRole("tab", { name: "Outline" }).click();
    const para = sp.getByRole("textbox", { name: "Paragraph" }).first();
    await para.fill("Give thanks always");
    await para.evaluate((el) => el.setSelectionRange(5, 11));
    await sp.locator("ol[aria-label='Outline'] > li", { has: para }).getByRole("button", { name: "Make Blank" }).click();
    if ((await para.inputValue()) !== "Give [[thanks]] always") problems.push("studio handout: Make Blank made " + (await para.inputValue()));
    if ((await sp.locator("ol[aria-label='Outline'] > li", { has: para }).getByLabel("Answer", { exact: true }).inputValue()) !== "thanks") problems.push("studio handout: Make Blank's answer isn't the selected words");
    await sctx.close();
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

  // Email and password: the app's account signs in here too; refusals say why; Forgot Password answers the same either way.
  {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, extraHTTPHeaders: { "Accept-Language": "en-US" } });
    const page = await ctx.newPage();
    const form = () => page.getByTestId("email-signin");
    const status = async () => (await page.getByTestId("signin-status").count()) ? await page.getByTestId("signin-status").innerText() : "";
    await page.goto(`${BASE}/studio`);
    await form().getByLabel("Email").fill("pastor@example.com");
    await form().getByLabel("Password").fill("wrong-password");
    await form().getByRole("button", { name: "Sign in with email" }).click();
    await page.waitForURL(/signin=wrong/);
    if (!/don't match a Versely account/.test(await status())) problems.push("wrong password: no message");
    await axe(page, "sign-in, wrong password");
    await page.screenshot({ path: `${OUT}/signin-email-wrong.png`, fullPage: true });
    await form().getByLabel("Email").fill("unconfirmed@example.com");
    await form().getByLabel("Password").fill("whatever");
    await form().getByRole("button", { name: "Sign in with email" }).click();
    await page.waitForURL(/signin=unconfirmed/);
    if (!/Confirm your email/.test(await status())) problems.push("unconfirmed email: no message");
    await form().getByLabel("Email").fill("someone@example.com");
    await form().getByRole("button", { name: "Forgot password?" }).click();
    await page.waitForURL(/signin=reset/);
    if (!/reset its password/.test(await status())) problems.push("forgot password: no message");
    await form().getByLabel("Email").fill("pastor@example.com");
    await form().getByLabel("Password").fill("right-password");
    await form().getByRole("button", { name: "Sign in with email" }).click();
    await page.waitForURL((u) => u.pathname === "/studio" && !u.search.includes("signin"));
    if (!(await page.getByRole("button", { name: "Sign out" }).count())) problems.push("email sign-in didn't open Studio");
    // A members-only sermon: signing in with email there comes back to it.
    await ctx.clearCookies();
    await page.goto(`${BASE}/s/membmemb01`);
    await form().getByLabel("Email").fill("pastor@example.com");
    await form().getByLabel("Password").fill("right-password");
    await form().getByRole("button", { name: "Sign in with email" }).click();
    await page.waitForURL(/\/s\/membmemb01$/);
    await page.waitForSelector("text=Members Night Secret", { timeout: 8000 }).catch(() => problems.push("email sign-in on a members-only sermon didn't come back to it"));
    // Another site's form can't sign anyone in.
    const forged = await fetch(`${BASE}/auth/password`, { method: "POST", redirect: "manual", headers: { Origin: "https://evil.example", "Content-Type": "application/x-www-form-urlencoded" }, body: "email=pastor%40example.com&password=right-password&next=%2Fstudio" });
    if ((forged.headers.get("set-cookie") ?? "").includes("vs_session=") || !/signin=failed/.test(forged.headers.get("location") ?? "")) problems.push("a form on another site signed someone in");
    note("email sign-in: wrong, unconfirmed, reset, signed in, members-only, forged origin checked");
    await ctx.close();
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

  // Starting a church: the name form, a group from the app, then the new church's page opens (no empty draft).
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
    await page.waitForURL(/\/studio\?church=[0-9a-f-]{36}/, { timeout: 8000 }).catch(() => problems.push("start a church: didn't open the new church"));
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
  // Roles (owner, admin, preacher, member): the owner's People list, then a preacher's own view and stepping down.
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    await ctx.addCookies([{ name: "vs_session", value: session, url: BASE }]);
    const page = await ctx.newPage();
    await page.goto(`${BASE}/studio`);
    if (!(await page.getByTestId("your-role").innerText()).includes("Owner")) problems.push("roles: the owner's role isn't shown");
    const peopleList = page.getByTestId("church-people");
    await peopleList.waitFor({ timeout: 8000 }).catch(() => problems.push("roles: no People section for the owner"));
    await page.getByLabel("Role for Dan").selectOption("preacher");
    await page.getByText("Dan is now Preacher.").waitFor({ timeout: 8000 }).catch(() => problems.push("roles: Dan wasn't made a preacher"));
    await page.getByLabel("Role for Dan").selectOption("member");
    await page.getByText("Dan is now Member.").waitFor({ timeout: 8000 }).catch(() => problems.push("roles: Dan wasn't made a member again"));
    await axe(page, "church people");
    await peopleList.screenshot({ path: `${OUT}/church-people.png` });
    // Closing the church: owner only, the name typed to confirm.
    {
      const close = page.getByTestId("close-church");
      await close.getByRole("button", { name: "Close this church…" }).click();
      const confirm = close.getByRole("button", { name: "Close church", exact: true });
      await close.getByLabel("Type Grace Church to confirm").fill("Grace");
      if (await confirm.isEnabled()) problems.push("close church: enabled before the name was typed");
      await close.getByLabel("Type Grace Church to confirm").fill("grace church");
      if (!(await confirm.isEnabled())) problems.push("close church: the typed name wasn't accepted");
      await axe(page, "close church");
      await close.screenshot({ path: `${OUT}/close-church.png` });
      await confirm.click();
      await page.waitForURL(/\/studio$/, { timeout: 8000 }).catch(() => problems.push("close church: didn't go back to Studio"));
    }
    // The editor says who started it and lets the owner hand it over.
    await page.goto(`${BASE}/studio/33333333-3333-4333-8333-333333333333`);
    if (!(await page.getByTestId("sermon-who").count())) problems.push("roles: the editor doesn't say who started the sermon");
    await page.getByRole("tab", { name: "Publish" }).click();
    const owner = page.getByTestId("sermon-owner");
    if (!(await owner.count())) problems.push("roles: no hand-over section for the owner");
    else await owner.screenshot({ path: `${OUT}/sermon-owner.png` });
    await ctx.close();

    const preacherSession = encodeURIComponent(JSON.stringify({ a: "preacher-token", r: "r", e: Date.now() + 86400000, u: "00000000-0000-4000-8000-0000000000a3", n: "Cara" }));
    const pctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    await pctx.addCookies([{ name: "vs_session", value: preacherSession, url: BASE }]);
    const p = await pctx.newPage();
    await p.goto(`${BASE}/studio`);
    if (!(await p.getByTestId("your-role").innerText()).includes("Preacher")) problems.push("preacher: role line missing");
    if (await p.getByTestId("church-people").count()) problems.push("preacher: sees People");
    if (await p.getByTestId("close-church").count()) problems.push("preacher: can close the church");
    if (await p.getByRole("button", { name: "Save locations" }).count()) problems.push("preacher: sees Locations and Times");
    if (await p.getByRole("button", { name: "New Code" }).count()) problems.push("preacher: can make a new invite code");
    if (!(await p.getByTestId("invite-code").count())) problems.push("preacher: can't see the invite code");
    if (!(await p.getByText("View only").count())) problems.push("preacher: others' published sermons aren't marked View only");
    await axe(p, "preacher studio");
    await noSideScroll(p, "preacher studio");
    await p.screenshot({ path: `${OUT}/studio-preacher.png`, fullPage: true });
    await p.getByRole("button", { name: "Step down as preacher" }).click();
    await p.getByRole("button", { name: "Stop being a preacher" }).click();
    await p.waitForURL(/\/studio$/, { timeout: 8000 }).catch(() => problems.push("preacher: step down didn't go back to Studio"));
    await pctx.close();
  }
  await browser.close();
  console.log(problems.length ? "PROBLEMS:\n" + problems.join("\n") : "no problems");
  if (problems.length) process.exitCode = 1;
})();
