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

  async function listResumeFiles() {
    const entries = await fs.readdir(dataRoot, { withFileTypes: true });
    const files = ['data/active_resume.yml'];
    for (const entry of entries.filter((item) => item.isDirectory())) {
      const yamlFiles = await collectYamlFiles(path.join(dataRoot, entry.name));
      for (const filePath of yamlFiles) {
        if (/\/resume[^/]*\.ya?ml$/i.test(filePath.replace(/\\/g, '/'))) {
          files.push(path.relative(repoRoot, filePath).replace(/\\/g, '/'));
        }
      }
    }
    return files.sort((left, right) => left === 'data/active_resume.yml' ? -1 : left.localeCompare(right));
  }

  async function loadYamlIfPresent(filePath, fallback) {
    try { return yaml.load(await fs.readFile(filePath, 'utf8')) ?? fallback; }
    catch (error) { if (error.code === 'ENOENT') return fallback; throw error; }
  }

  async function resumeOptions(relativePath) {
    const segments = relativePath.replace(/\\/g, '/').split('/');
    let user = segments.length >= 3 ? segments[1] : '';
    const users = (await fs.readdir(dataRoot, { withFileTypes: true }))
      .filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
    if (!user && relativePath.replace(/\\/g, '/') === 'data/active_resume.yml') {
      const active = await loadYamlIfPresent(path.join(dataRoot, 'active_resume.yml'), {});
      user = String(active?.user ?? '');
    }
    if (!user) user = users[0] || '';
    const userRoot = path.join(dataRoot, user);
    const userFiles = await collectYamlFiles(userRoot);
    const resumes = userFiles.filter((file) => /\/resume[^/]*\.ya?ml$/i.test(file.replace(/\\/g, '/')))
      .map((file) => path.basename(file, path.extname(file))).sort();
    const jobFiles = {};
    for (const file of userFiles.filter((item) => /\/jobs[^/]*\.ya?ml$/i.test(item.replace(/\\/g, '/')))) {
      const key = path.basename(file, path.extname(file));
      const jobs = await loadYamlIfPresent(file, []);
      jobFiles[key] = Array.isArray(jobs) ? jobs.map((job) => String(job?.id ?? '')).filter(Boolean) : [];
    }
    const layoutsDir = path.join(userRoot, 'layouts');
    const summariesDir = path.join(userRoot, 'summaries');
    const layouts = (await collectYamlFiles(layoutsDir).catch(() => []))
      .map((file) => path.basename(file, path.extname(file))).sort();
    const summaries = (await collectYamlFiles(summariesDir).catch(() => []))
      .map((file) => path.basename(file, path.extname(file))).sort();
    const skills = await loadYamlIfPresent(path.join(userRoot, 'skills.yml'), []);
    const linksData = await loadYamlIfPresent(path.join(userRoot, 'links.yml'), {});
    return {
      user, users, resumes, layouts, summaries, jobFiles,
      skills: Array.isArray(skills) ? skills.map(({ id, label }) => ({ id, label })) : [],
      links: Array.isArray(linksData?.links) ? linksData.links.map(({ name, url }) => ({ name, url })) : [],
      themes: ['theme-default', 'theme-fern', 'theme-grey', 'theme-orange', 'theme-tapestry', 'theme-tradewind']
    };
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
    if (normalizedPath === 'data/active_resume.yml') {
      const user = String(parsed?.user ?? '').trim();
      const name = String(parsed?.name ?? '').trim();
      const errors = [];
      if (!user) errors.push('Active resume requires user');
      if (!name) errors.push('Active resume requires name');
      if (user && name) {
        const resumePath = path.join(dataRoot, user, `${name}.yml`);
        try { await fs.access(resumePath); } catch { errors.push(`Active resume does not exist: data/${user}/${name}.yml`); }
      }
      if (errors.length) return { valid: false, errors };
    }
    if (/\/jobs[^/]*\.ya?ml$/i.test(normalizedPath) && !Array.isArray(parsed)) {
      return { valid: false, errors: ['Job catalog YAML must contain a top-level array'] };
    }
    if (/\/jobs[^/]*\.ya?ml$/i.test(normalizedPath) && Array.isArray(parsed)) {
      const errors = [];
      const ids = new Map();
      parsed.forEach((job, index) => {
        if (!job || typeof job !== 'object' || Array.isArray(job)) {
          errors.push(`Job ${index + 1} must be a mapping`);
          return;
        }
        const id = String(job.id ?? '').trim();
        if (!id) errors.push(`Job ${index + 1} requires a non-empty id`);
        else if (ids.has(id)) errors.push(`Duplicate job id '${id}' at jobs ${ids.get(id)} and ${index + 1}`);
        else ids.set(id, index + 1);
        for (const field of ['title', 'company', 'desc']) {
          if (!String(job[field] ?? '').trim()) errors.push(`Job '${id || index + 1}' requires ${field}`);
        }
        for (const nested of ['location', 'dates']) {
          if (!job[nested] || typeof job[nested] !== 'object' || Array.isArray(job[nested])) {
            errors.push(`Job '${id || index + 1}' requires a ${nested} mapping`);
          }
        }
      });
      if (errors.length) return { valid: false, errors };
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
    const [jobs, summaries, resumes] = await Promise.all([listJobsFiles(), listSummaryFiles(), listResumeFiles()]);
    res.json({ jobs, summaries, resumes });
  } catch (error) {
    res.status(500).json({ error: error.message || 'Failed to list files' });
  }
  });

  app.get('/api/resume-options', async (req, res) => {
    try {
      const relativePath = String(req.query.path || '');
      if (!relativePath) return res.status(400).json({ error: 'Missing path query parameter' });
      normalizeWithinData(relativePath);
      return res.json(await resumeOptions(relativePath));
    } catch (error) {
      return res.status(400).json({ error: error.message || 'Failed to load resume options' });
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
