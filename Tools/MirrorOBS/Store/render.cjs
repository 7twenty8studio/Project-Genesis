// Renders the Mirror OBS store images from store.html (Playwright, Inter installed).
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const b = await chromium.launch();
  const out = process.argv[2] || path.resolve(__dirname, '..');
  const url = 'file://' + path.join(__dirname, 'store.html');
  let p = await b.newPage({ viewport: { width: 1100, height: 1100 }, deviceScaleFactor: 1 });
  await p.goto(url); await p.evaluate(() => document.fonts.ready);
  await (await p.$('#icon')).screenshot({ path: path.join(out, 'icon-1024.png') });
  await p.close();
  p = await b.newPage({ viewport: { width: 1300, height: 1000 }, deviceScaleFactor: 3 });
  await p.goto(url); await p.evaluate(() => document.fonts.ready);
  for (let i = 1; i <= 5; i++) await (await p.$('#s' + i)).screenshot({ path: path.join(out, `screenshot-${i}-6.9in.png`) });
  await p.close();
  p = await b.newPage({ viewport: { width: 1300, height: 1000 }, deviceScaleFactor: 2 });
  await p.goto(url); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(300);
  await (await p.$('#header')).screenshot({ path: path.join(out, 'header-2400x1200.png') });
  await b.close();
})();
