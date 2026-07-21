import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export async function createFixture() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'resume-editor-test-'));
  await fs.mkdir(path.join(root, 'data', 'person', 'summaries'), { recursive: true });
  await fs.mkdir(path.join(root, 'data', 'person', 'layouts'), { recursive: true });
  await fs.writeFile(path.join(root, 'data', 'active_resume.yml'), 'user: person\nname: resume_test\ngenerate_brief: false\n');
  await fs.writeFile(
    path.join(root, 'data', 'person', 'jobs.yml'),
    '- id: original\n  title: Original title\n  company: Example\n  location:\n    city: Detroit\n    state: MI\n  dates:\n    start: 2020\n    end: Present\n  desc: Original description\n  custom_field: retained\n',
    'utf8'
  );
  await fs.writeFile(path.join(root, 'data', 'person', 'layouts', 'layout.yml'), 'content: {center: [], right: []}\n');
  await fs.writeFile(path.join(root, 'data', 'person', 'skills.yml'), '- id: 1\n  label: Skill one\n');
  await fs.writeFile(path.join(root, 'data', 'person', 'links.yml'), 'links:\n  - name: Example\n    url: https://example.test\n');
  await fs.writeFile(
    path.join(root, 'data', 'person', 'resume_test.yml'),
    'name: test\nlayout: layout\npdf:\n  filename: pdf/test\n  source: test.pdf\n  useicons: true\ncontact_info:\n  name: Test Person\n  email: test@example.com\n  phone: 555\n  address:\n    street: Main\n    city: Detroit\n    state: MI\n    postal_code: 48201\nsummary:\n  file: summary\njobs_filename: jobs\njobs:\n  - file: jobs\n    id: original\n    section: experiences\nskills: []\nlinks: []\neducation: []\ncustom_section: retained\n',
    'utf8'
  );
  await fs.writeFile(
    path.join(root, 'data', 'person', 'summaries', 'summary.yml'),
    'summary:\n  type: developer\n  text: Original summary\n',
    'utf8'
  );
  return root;
}

export function listen(app) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, baseUrl: `http://127.0.0.1:${server.address().port}` });
    });
    server.on('error', reject);
  });
}

export function close(server) {
  return new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
}

export async function removeFixture(root) {
  await fs.rm(root, { recursive: true, force: true });
}
