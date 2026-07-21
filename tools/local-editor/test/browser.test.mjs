import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import { chromium } from 'playwright-core';
import { createEditorApp } from '../server.mjs';
import { close, createFixture, listen, removeFixture } from './test_helpers.mjs';

const chromeCandidates = [
  process.env.VISUAL_CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser'
].filter(Boolean);

test('protects dirty edits, validates, and saves through the browser', async (t) => {
  let executablePath;
  for (const candidate of chromeCandidates) {
    try { await fs.access(candidate); executablePath = candidate; break; } catch { /* try next */ }
  }
  assert.ok(executablePath, 'Chrome/Chromium not found; set VISUAL_CHROME_BIN');

  const root = await createFixture();
  const app = createEditorApp({
    repoRoot: root,
    validateCandidate: async ({ content }) => content.includes('Rejected')
      ? { valid: false, errors: ['Rejected by test validator'] }
      : { valid: true, errors: [] }
  });
  const { server, baseUrl } = await listen(app);
  const browser = await chromium.launch({ executablePath, headless: true });
  t.after(async () => { await browser.close(); await close(server); await removeFixture(root); });

  const page = await browser.newPage();
  await page.goto(baseUrl);
  await page.selectOption('#modeSelect', 'raw');
  await page.fill('#editor', '- id: changed\n  title: Rejected\n');
  assert.match(await page.title(), /^\* /);

  page.once('dialog', (dialog) => dialog.dismiss());
  await page.selectOption('#categorySelect', 'summaries');
  assert.equal(await page.locator('#categorySelect').inputValue(), 'jobs');

  await page.click('#validateBtn');
  await page.waitForFunction(() => document.querySelector('#statusText').textContent.includes('Rejected'));
  assert.match(await page.locator('#statusText').textContent(), /Rejected by test validator/);

  await page.fill('#editor', '- id: changed\n  title: Accepted\n');
  await page.click('#saveBtn');
  await page.waitForFunction(() => document.querySelector('#statusText').textContent.includes('backup:'));
  assert.doesNotMatch(await page.title(), /^\* /);
});
