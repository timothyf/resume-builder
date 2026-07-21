import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export async function createFixture() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'resume-editor-test-'));
  await fs.mkdir(path.join(root, 'data', 'person', 'summaries'), { recursive: true });
  await fs.writeFile(
    path.join(root, 'data', 'person', 'jobs.yml'),
    '- id: original\n  title: Original title\n  company: Example\n',
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
