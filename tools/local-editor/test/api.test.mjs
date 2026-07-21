import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { createEditorApp } from '../server.mjs';
import { close, createFixture, listen, removeFixture } from './test_helpers.mjs';

test('lists editor files and rejects paths outside data', async (t) => {
  const root = await createFixture();
  const { server, baseUrl } = await listen(createEditorApp({ repoRoot: root }));
  t.after(async () => { await close(server); await removeFixture(root); });

  const files = await (await fetch(`${baseUrl}/api/files`)).json();
  assert.deepEqual(files.jobs, ['data/person/jobs.yml']);
  assert.deepEqual(files.summaries, ['data/person/summaries/summary.yml']);
  assert.deepEqual(files.resumes, ['data/active_resume.yml', 'data/person/resume_test.yml']);

  const options = await (await fetch(`${baseUrl}/api/resume-options?path=data/person/resume_test.yml`)).json();
  assert.deepEqual(options.layouts, ['layout']);
  assert.deepEqual(options.summaries, ['summary']);
  assert.deepEqual(options.jobFiles.jobs, ['original']);

  const traversal = await fetch(`${baseUrl}/api/file?path=${encodeURIComponent('../secret.yml')}`);
  assert.equal(traversal.status, 400);

  const missingActive = await fetch(`${baseUrl}/api/validate`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: 'data/active_resume.yml', data: { user: 'person', name: 'missing' } })
  });
  assert.equal(missingActive.status, 422);
  assert.match((await missingActive.json()).errors.join(' '), /does not exist/);
});

test('validates before saving, creates a backup, and writes atomically', async (t) => {
  const root = await createFixture();
  const backupRoot = path.join(root, 'backups');
  const validateCandidate = async ({ content }) => content.includes('invalid-title')
    ? { valid: false, errors: ['Title is invalid'] }
    : { valid: true, errors: [] };
  const app = createEditorApp({ repoRoot: root, backupRoot, validateCandidate });
  const { server, baseUrl } = await listen(app);
  t.after(async () => { await close(server); await removeFixture(root); });
  const filePath = path.join(root, 'data', 'person', 'jobs.yml');
  const original = await fs.readFile(filePath, 'utf8');

  const malformed = await fetch(`${baseUrl}/api/file`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: 'data/person/jobs.yml', content: '- broken: [yaml' })
  });
  assert.equal(malformed.status, 422);
  assert.equal(await fs.readFile(filePath, 'utf8'), original);

  const wrongShape = await fetch(`${baseUrl}/api/file`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: 'data/person/jobs.yml', content: 'id: not-an-array\n' })
  });
  assert.equal(wrongShape.status, 422);
  assert.match((await wrongShape.json()).errors[0], /top-level array/);
  assert.equal(await fs.readFile(filePath, 'utf8'), original);

  const duplicateIds = await fetch(`${baseUrl}/api/file`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      path: 'data/person/jobs.yml',
      content: '- &job\n  id: duplicate\n  title: One\n  company: Example\n  location: {}\n  dates: {}\n  desc: One\n- <<: *job\n  title: Two\n'
    })
  });
  assert.equal(duplicateIds.status, 422);
  assert.match((await duplicateIds.json()).errors.join(' '), /Duplicate job id/);

  const rejected = await fetch(`${baseUrl}/api/file`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: 'data/person/jobs.yml', content: '- id: rejected\n  title: invalid-title\n  company: Example\n  location: {}\n  dates: {}\n  desc: Description\n' })
  });
  assert.equal(rejected.status, 422);
  assert.equal(await fs.readFile(filePath, 'utf8'), original);

  const replacement = '- id: changed\n  title: Safe title\n  company: Example\n  location: {}\n  dates: {}\n  desc: Description\n';
  const saved = await fetch(`${baseUrl}/api/file`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: 'data/person/jobs.yml', content: replacement })
  });
  assert.equal(saved.status, 200);
  const result = await saved.json();
  assert.match(result.backupPath, /jobs\.yml$/);
  assert.equal(await fs.readFile(filePath, 'utf8'), replacement);
  assert.equal(await fs.readFile(path.resolve(root, result.backupPath), 'utf8'), original);
  assert.deepEqual((await fs.readdir(path.dirname(filePath))).filter((name) => name.endsWith('.tmp')), []);
});

test('validates structured data without saving it', async (t) => {
  const root = await createFixture();
  const app = createEditorApp({
    repoRoot: root,
    validateCandidate: async ({ content }) => ({ valid: content.includes('Updated'), errors: ['missing update'] })
  });
  const { server, baseUrl } = await listen(app);
  t.after(async () => { await close(server); await removeFixture(root); });

  const response = await fetch(`${baseUrl}/api/validate`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      path: 'data/person/summaries/summary.yml',
      data: { summary: { type: 'developer', text: 'Updated' } }
    })
  });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).valid, true);
});
