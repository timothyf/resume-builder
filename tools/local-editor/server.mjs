import express from 'express';
import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import yaml from 'js-yaml';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const publicDir = path.join(__dirname, 'public');
const execFileAsync = promisify(execFile);

export function createEditorApp(options = {}) {
  const repoRoot = path.resolve(options.repoRoot || path.resolve(__dirname, '..', '..'));
  const dataRoot = path.join(repoRoot, 'data');
  const backupRoot = path.resolve(options.backupRoot || path.join(repoRoot, '.local-editor-backups'));
  const validatorScript = path.resolve(__dirname, '..', '..', 'scripts', 'validate_supported_resumes.rb');
  const app = express();
  app.use(express.json({ limit: '2mb' }));
  app.use(express.static(publicDir));

  function normalizeWithinData(relativePath) {
  const cleaned = relativePath.replace(/\\/g, '/').replace(/^\/+/, '');
  const absolutePath = path.resolve(repoRoot, cleaned);
  const relativeToData = path.relative(dataRoot, absolutePath);

  if (relativeToData.startsWith('..') || path.isAbsolute(relativeToData)) {
    throw new Error('Path is outside of data directory');
  }

  return absolutePath;
  }

  async function collectYamlFiles(dirPath) {
  const entries = await fs.readdir(dirPath, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && /\.ya?ml$/i.test(entry.name))
    .map((entry) => path.join(dirPath, entry.name));
  }

  async function listJobsFiles() {
  const entries = await fs.readdir(dataRoot, { withFileTypes: true });
  const userDirs = entries.filter((entry) => entry.isDirectory()).map((entry) => entry.name);

  const files = [];
  for (const userDir of userDirs) {
    const userPath = path.join(dataRoot, userDir);
    const yamlFiles = await collectYamlFiles(userPath);
    for (const filePath of yamlFiles) {
      if (/\/jobs[^/]*\.ya?ml$/i.test(filePath.replace(/\\/g, '/'))) {
        files.push(path.relative(repoRoot, filePath).replace(/\\/g, '/'));
      }
    }
  }

  return files.sort();
  }

  async function listSummaryFiles() {
  const entries = await fs.readdir(dataRoot, { withFileTypes: true });
  const userDirs = entries.filter((entry) => entry.isDirectory()).map((entry) => entry.name);

  const files = [];
  for (const userDir of userDirs) {
    const summariesDir = path.join(dataRoot, userDir, 'summaries');
    try {
      const yamlFiles = await collectYamlFiles(summariesDir);
      for (const filePath of yamlFiles) {
        files.push(path.relative(repoRoot, filePath).replace(/\\/g, '/'));
      }
    } catch (error) {
      if (error && error.code !== 'ENOENT') {
        throw error;
      }
    }
  }

  return files.sort();
  }

  function candidateContent(body) {
    if (Object.prototype.hasOwnProperty.call(body || {}, 'content')) return String(body.content ?? '');
    if (Object.prototype.hasOwnProperty.call(body || {}, 'data')) {
      return yaml.dump(body.data, { lineWidth: -1, noRefs: true });
    }
    throw new Error('Missing content or structured data in request body');
  }

  async function validateCandidate(relativePath, content) {
    let parsed;
    try {
      parsed = yaml.load(content);
    } catch (error) {
      return { valid: false, errors: [`Invalid YAML: ${error.message}`] };
    }

    const normalizedPath = relativePath.replace(/\\/g, '/');
    if (/\/jobs[^/]*\.ya?ml$/i.test(normalizedPath) && !Array.isArray(parsed)) {
      return { valid: false, errors: ['Job catalog YAML must contain a top-level array'] };
    }
    if (/\/summaries\/[^/]+\.ya?ml$/i.test(normalizedPath)) {
      const summary = parsed?.summary;
      if (!summary || typeof summary !== 'object' || Array.isArray(summary)) {
        return { valid: false, errors: ['Summary YAML must contain a summary mapping'] };
      }
      if (!String(summary.type ?? '').trim() || !String(summary.text ?? '').trim()) {
        return { valid: false, errors: ['Summary type and text are required'] };
      }
    }

    const temporaryRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'resume-editor-validation-'));
    try {
      await fs.cp(dataRoot, path.join(temporaryRoot, 'data'), { recursive: true });
      await fs.symlink(path.join(repoRoot, 'source'), path.join(temporaryRoot, 'source'), 'dir');
      const stagedPath = normalizeWithinData(relativePath);
      const stagedRelativePath = path.relative(dataRoot, stagedPath);
      const stagedCandidate = path.join(temporaryRoot, 'data', stagedRelativePath);
      await fs.mkdir(path.dirname(stagedCandidate), { recursive: true });
      await fs.writeFile(stagedCandidate, content, 'utf8');

      if (options.validateCandidate) {
        return await options.validateCandidate({ relativePath, content, temporaryRoot });
      }

      await execFileAsync(process.env.LOCAL_EDITOR_RUBY_BIN || 'ruby', [validatorScript], {
        cwd: repoRoot,
        env: { ...process.env, RESUME_PROJECT_ROOT: temporaryRoot, RESUME_SKIP_PDF_COPY: '1' }
      });
      return { valid: true, errors: [] };
    } catch (error) {
      const output = [error.stderr, error.stdout, error.message].filter(Boolean).join('\n').trim();
      const errors = output.split('\n').map((line) => line.trim()).filter(Boolean);
      return { valid: false, errors: errors.length ? errors : ['Validation failed'] };
    } finally {
      await fs.rm(temporaryRoot, { recursive: true, force: true });
    }
  }

  async function backupAndWrite(relativePath, content) {
    const absolutePath = normalizeWithinData(relativePath);
    const existing = await fs.readFile(absolutePath, 'utf8');
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupPath = path.join(backupRoot, stamp, path.relative(dataRoot, absolutePath));
    await fs.mkdir(path.dirname(backupPath), { recursive: true });
    await fs.writeFile(backupPath, existing, 'utf8');

    const temporaryPath = `${absolutePath}.local-editor-${process.pid}.tmp`;
    try {
      await fs.writeFile(temporaryPath, content, 'utf8');
      await fs.rename(temporaryPath, absolutePath);
    } finally {
      await fs.rm(temporaryPath, { force: true });
    }
    return path.relative(repoRoot, backupPath).replace(/\\/g, '/');
  }

  app.get('/api/files', async (_req, res) => {
  try {
    const [jobs, summaries] = await Promise.all([listJobsFiles(), listSummaryFiles()]);
    res.json({ jobs, summaries });
  } catch (error) {
    res.status(500).json({ error: error.message || 'Failed to list files' });
  }
  });

  app.get('/api/file', async (req, res) => {
  try {
    const relativePath = String(req.query.path || '');
    if (!relativePath) {
      return res.status(400).json({ error: 'Missing path query parameter' });
    }

    const absolutePath = normalizeWithinData(relativePath);
    const content = await fs.readFile(absolutePath, 'utf8');
    return res.json({ path: relativePath, content });
  } catch (error) {
    return res.status(400).json({ error: error.message || 'Failed to load file' });
  }
  });

  app.get('/api/file-structured', async (req, res) => {
  try {
    const relativePath = String(req.query.path || '');
    if (!relativePath) {
      return res.status(400).json({ error: 'Missing path query parameter' });
    }

    const absolutePath = normalizeWithinData(relativePath);
    const content = await fs.readFile(absolutePath, 'utf8');
    const data = yaml.load(content);
    return res.json({ path: relativePath, data });
  } catch (error) {
    return res.status(400).json({ error: error.message || 'Failed to load structured file' });
  }
  });

  app.post('/api/validate', async (req, res) => {
    try {
      const relativePath = String(req.body?.path || '');
      if (!relativePath) return res.status(400).json({ error: 'Missing file path in request body' });
      normalizeWithinData(relativePath);
      const result = await validateCandidate(relativePath, candidateContent(req.body));
      return res.status(result.valid ? 200 : 422).json(result);
    } catch (error) {
      return res.status(400).json({ error: error.message || 'Failed to validate file' });
    }
  });

  app.post('/api/file', async (req, res) => {
  try {
    const relativePath = String(req.body?.path || '');
    const content = String(req.body?.content ?? '');

    if (!relativePath) {
      return res.status(400).json({ error: 'Missing file path in request body' });
    }

    normalizeWithinData(relativePath);
    const validation = await validateCandidate(relativePath, content);
    if (!validation.valid) return res.status(422).json(validation);
    const backupPath = await backupAndWrite(relativePath, content);
    return res.json({ ok: true, backupPath });
  } catch (error) {
    return res.status(400).json({ error: error.message || 'Failed to save file' });
  }
  });

  app.post('/api/file-structured', async (req, res) => {
  try {
    const relativePath = String(req.body?.path || '');
    const data = req.body?.data;

    if (!relativePath) {
      return res.status(400).json({ error: 'Missing file path in request body' });
    }

    normalizeWithinData(relativePath);
    const content = candidateContent({ data });
    const validation = await validateCandidate(relativePath, content);
    if (!validation.valid) return res.status(422).json(validation);
    const backupPath = await backupAndWrite(relativePath, content);
    return res.json({ ok: true, backupPath });
  } catch (error) {
    return res.status(400).json({ error: error.message || 'Failed to save structured file' });
  }
  });

  return app;
}

export function startEditorServer(options = {}) {
  const port = Number(options.port ?? process.env.LOCAL_EDITOR_PORT ?? 4310);
  const server = createEditorApp(options).listen(port, '127.0.0.1', () => {
    const address = server.address();
    console.log(`Local YAML editor running at http://127.0.0.1:${address.port}`);
  });
  return server;
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) startEditorServer();
