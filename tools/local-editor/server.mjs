import express from 'express';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import yaml from 'js-yaml';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..', '..');
const dataRoot = path.join(repoRoot, 'data');
const publicDir = path.join(__dirname, 'public');

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

app.post('/api/file', async (req, res) => {
  try {
    const relativePath = String(req.body?.path || '');
    const content = String(req.body?.content ?? '');

    if (!relativePath) {
      return res.status(400).json({ error: 'Missing file path in request body' });
    }

    const absolutePath = normalizeWithinData(relativePath);
    await fs.writeFile(absolutePath, content, 'utf8');
    return res.json({ ok: true });
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

    const absolutePath = normalizeWithinData(relativePath);
    const content = yaml.dump(data, {
      lineWidth: -1,
      noRefs: true
    });
    await fs.writeFile(absolutePath, content, 'utf8');
    return res.json({ ok: true });
  } catch (error) {
    return res.status(400).json({ error: error.message || 'Failed to save structured file' });
  }
});

const port = Number(process.env.LOCAL_EDITOR_PORT || 4310);
app.listen(port, '127.0.0.1', () => {
  // eslint-disable-next-line no-console
  console.log(`Local YAML editor running at http://127.0.0.1:${port}`);
});
