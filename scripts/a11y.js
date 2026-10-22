// Browser accessibility check for the docs site (npm run a11y).
// Serves docs/ on a local port, loads every page in light and dark theme with Chromium, lets
// docs.js build the header / sidebar / outline, then runs axe-core with the WCAG 2.1 AA rules.
// Exits non-zero on any violation. Third-party requests (Google Fonts) are blocked so the
// result doesn't depend on the network; the fallback system fonts are close enough for contrast.

import { createServer } from 'node:http';
import { readFile, readdir } from 'node:fs/promises';
import { extname, join, normalize, resolve } from 'node:path';
import { chromium } from 'playwright';
import { AxeBuilder } from '@axe-core/playwright';

const ROOT = resolve(import.meta.dirname, '..', 'docs');
const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];
const THEMES = ['light', 'dark'];
const TYPES = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.json': 'application/json',
};

// Every page in docs/ and its folders, minus the redirect stubs left at old URLs (vision.html …).
const pages = [];
for (const f of (await readdir(ROOT, { recursive: true })).filter(f => f.endsWith('.html')).sort()) {
  if (!/http-equiv="refresh"/.test(await readFile(join(ROOT, f), 'utf8'))) pages.push(f.split('\\').join('/'));
}

const server = createServer(async (req, res) => {
  let path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (path.endsWith('/')) path += 'index.html';
  const file = normalize(join(ROOT, path));
  if (!file.startsWith(ROOT)) { res.writeHead(403).end(); return; }
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream' }).end(body);
  } catch (e) {
    res.writeHead(404).end();
  }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch();
let failures = 0;
try {
  for (const theme of THEMES) {
    const context = await browser.newContext({ colorScheme: theme });
    await context.addInitScript(t => { try { localStorage.setItem('hht-docs-theme', t); } catch (e) {} }, theme);
    await context.route(url => !url.href.startsWith(origin), route => route.abort());
    for (const p of pages) {
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', e => errors.push(e.message));
      await page.goto(`${origin}/${p}`, { waitUntil: 'load' });
      const { violations } = await new AxeBuilder({ page }).withTags(TAGS).analyze();
      const label = `${p} [${theme}]`;
      if (errors.length) {
        failures++;
        console.log(`✗ ${label}: page error: ${errors.join('; ')}`);
      }
      if (violations.length) {
        failures++;
        console.log(`✗ ${label}`);
        for (const v of violations) {
          console.log(`  ${v.id} (${v.impact}): ${v.help}`);
          for (const n of v.nodes.slice(0, 5)) {
            console.log(`    ${n.target.join(' ')}`);
            const why = n.any[0]?.message || n.all[0]?.message || n.none[0]?.message;
            if (why) console.log(`      ${why}`);
          }
          if (v.nodes.length > 5) console.log(`    … ${v.nodes.length - 5} more`);
        }
      } else if (!errors.length) {
        console.log(`✓ ${label}`);
      }
      await page.close();
    }
    await context.close();
  }
} finally {
  await browser.close();
  server.close();
}

if (failures) {
  console.log(`\n${failures} page/theme combination(s) failed WCAG 2.1 AA checks.`);
  process.exit(1);
}
console.log(`\nAll ${pages.length} pages pass WCAG 2.1 AA in light and dark theme.`);
