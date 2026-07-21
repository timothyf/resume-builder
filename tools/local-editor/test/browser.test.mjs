import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import { chromium } from 'playwright-core';
import yaml from 'js-yaml';
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
  await page.fill('#editor', '- id: changed\n  title: Rejected\n  company: Example\n  location: {}\n  dates: {}\n  desc: Description\n');
  assert.match(await page.title(), /^\* /);

  page.once('dialog', (dialog) => dialog.dismiss());
  await page.selectOption('#categorySelect', 'summaries');
  assert.equal(await page.locator('#categorySelect').inputValue(), 'jobs');

  await page.click('#validateBtn');
  await page.waitForFunction(() => document.querySelector('#statusText').textContent.includes('Rejected'));
  assert.match(await page.locator('#statusText').textContent(), /Rejected by test validator/);

  await page.fill('#editor', '- id: changed\n  title: Accepted\n  company: Example\n  location: {}\n  dates: {}\n  desc: Description\n');
  await page.click('#saveBtn');
  await page.waitForFunction(() => document.querySelector('#statusText').textContent.includes('backup:'));
  assert.doesNotMatch(await page.title(), /^\* /);
});

test('duplicates and reorders complete jobs without losing unknown fields', async (t) => {
  let executablePath;
  for (const candidate of chromeCandidates) {
    try { await fs.access(candidate); executablePath = candidate; break; } catch { /* try next */ }
  }
  assert.ok(executablePath, 'Chrome/Chromium not found; set VISUAL_CHROME_BIN');
  const root = await createFixture();
  const { server, baseUrl } = await listen(createEditorApp({
    repoRoot: root,
    validateCandidate: async () => ({ valid: true, errors: [] })
  }));
  const browser = await chromium.launch({ executablePath, headless: true });
  t.after(async () => { await browser.close(); await close(server); await removeFixture(root); });

  const page = await browser.newPage();
  await page.goto(baseUrl);
  await page.waitForFunction(() => document.querySelector('#jobTitleInput').value === 'Original title');
  await page.click('#duplicateJobBtn');
  assert.equal(await page.locator('#jobIdInput').inputValue(), 'original-copy');
  await page.selectOption('#jobBriefInput', 'true');

  page.once('dialog', (dialog) => dialog.dismiss());
  await page.click('#removeJobBtn');
  assert.equal(await page.locator('#jobIdInput').inputValue(), 'original-copy');

  await page.click('#moveJobUpBtn');
  await page.click('#saveBtn');
  await page.waitForFunction(() => document.querySelector('#statusText').textContent.includes('backup:'));

  const jobs = yaml.load(await fs.readFile(`${root}/data/person/jobs.yml`, 'utf8'));
  assert.deepEqual(jobs.map((job) => job.id), ['original-copy', 'original']);
  assert.equal(jobs[0].brief, true);
  assert.equal(jobs[0].custom_field, 'retained');
  assert.equal(jobs[1].custom_field, 'retained');
});

test('edits active selection and catalog-backed resume fields without losing other sections', async (t) => {
  let executablePath;
  for (const candidate of chromeCandidates) {
    try { await fs.access(candidate); executablePath = candidate; break; } catch { /* try next */ }
  }
  assert.ok(executablePath, 'Chrome/Chromium not found; set VISUAL_CHROME_BIN');
  const root = await createFixture();
  const { server, baseUrl } = await listen(createEditorApp({
    repoRoot: root,
    validateCandidate: async () => ({ valid: true, errors: [] })
  }));
  const browser = await chromium.launch({ executablePath, headless: true });
  t.after(async () => { await browser.close(); await close(server); await removeFixture(root); });

  const page = await browser.newPage();
  await page.goto(baseUrl);
  await page.selectOption('#categorySelect', 'resumes');
  await page.waitForFunction(() => document.querySelector('#activeNameInput').value === 'resume_test');
  await page.selectOption('#activeBriefInput', 'true');
  await page.click('#saveBtn');
  await page.waitForFunction(() => document.querySelector('#statusText').textContent.includes('backup:'));

  await page.selectOption('#fileSelect', 'data/person/resume_test.yml');
  await page.waitForFunction(() => document.querySelector('#resumeNameInput').value === 'test');
  await page.selectOption('#resumeThemeInput', 'theme-orange');
  await page.fill('#resumeContactNameInput', 'Updated Person');
  await page.click('#addResumeJobBtn');
  await page.click('#addResumeLinkBtn');
  await page.click('#addResumeSkillGroupBtn');
  await page.locator('#resumeSkillsList input').fill('Leadership');
  await page.locator('#resumeSkillsList select').selectOption(['1']);
  await page.click('#addResumeEducationBtn');
  await page.locator('#resumeEducationList input').nth(0).fill('Example University');
  await page.locator('#resumeEducationList input').nth(1).fill('B.S. Testing');
  await page.click('#saveBtn');
  await page.waitForFunction(() => document.querySelector('#statusText').textContent.includes('backup:'));

  const active = yaml.load(await fs.readFile(`${root}/data/active_resume.yml`, 'utf8'));
  const resume = yaml.load(await fs.readFile(`${root}/data/person/resume_test.yml`, 'utf8'));
  assert.equal(active.generate_brief, true);
  assert.equal(resume.theme, 'theme-orange');
  assert.equal(resume.contact_info.name, 'Updated Person');
  assert.equal(resume.jobs.length, 2);
  assert.deepEqual(resume.links, [{ name: 'Example' }]);
  assert.deepEqual(resume.skills, [{ name: 'Leadership', skills: [1] }]);
  assert.equal(resume.education[0].name, 'Example University');
  assert.equal(resume.education[0].degree, 'B.S. Testing');
  assert.equal(resume.custom_section, 'retained');
});
