#!/usr/bin/env node

import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from 'playwright-core';
import { PNG } from 'pngjs';

const THEMES = [
  'theme-default',
  'theme-fern',
  'theme-grey',
  'theme-orange',
  'theme-tapestry',
  'theme-tradewind'
];
const RESUME_USER = 'timothyfisher';
const RESUME_NAME = 'resume_dev_refined';
const MAX_CHANGED_PIXEL_FRACTION = Number(process.env.VISUAL_MAX_CHANGED_PIXELS || '0.03');
const MAX_MEAN_COLOR_DELTA = Number(process.env.VISUAL_MAX_COLOR_DELTA || '0.01');
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const VISUAL_FONT_DIRECTORY = path.resolve(
  SCRIPT_DIR,
  '..',
  'node_modules',
  '@fontsource',
  'roboto',
  'files'
);
const VISUAL_FONT_WEIGHTS = [400, 500, 700, 900];

function fontFaceRules() {
  return VISUAL_FONT_WEIGHTS.map((weight) => {
    const fontPath = path.join(VISUAL_FONT_DIRECTORY, `roboto-latin-${weight}-normal.woff2`);
    return `
      @font-face {
        font-family: VisualRegressionRoboto;
        src: url('${pathToFileURL(fontPath).href}') format('woff2');
        font-style: normal;
        font-weight: ${weight};
      }
    `;
  }).join('\n');
}

function parseArgs(argv) {
  const args = { update: false };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === '--update') {
      args.update = true;
    } else if (value.startsWith('--')) {
      const key = value.slice(2).replaceAll('-', '_');
      args[key] = argv[++index];
    }
  }
  for (const key of ['project_root', 'baseline_dir', 'output_dir', 'pdf_output_dir']) {
    if (!args[key]) throw new Error(`Missing required --${key.replaceAll('_', '-')}`);
    args[key] = path.resolve(args[key]);
  }
  return args;
}

function findChrome() {
  const configured = process.env.VISUAL_CHROME_BIN;
  const candidates = [
    configured,
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser'
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  for (const command of ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser']) {
    try {
      return execFileSync('which', [command], { encoding: 'utf8' }).trim();
    } catch {
      // Try the next supported executable.
    }
  }
  throw new Error('Chrome/Chromium not found. Set VISUAL_CHROME_BIN to its executable path.');
}

function runBuild(projectRoot, theme) {
  fs.rmSync(path.join(projectRoot, 'build'), { recursive: true, force: true });
  fs.rmSync(path.join(projectRoot, 'dist'), { recursive: true, force: true });
  const result = spawnSync(
    path.join(projectRoot, 'build_resume.bash'),
    ['--resume-user', RESUME_USER, '--resume-name', RESUME_NAME, '--theme', theme],
    {
      cwd: projectRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        ACTIVE_RESUME_GENERATE_BRIEF: 'false',
        RESUME_DEPLOYED_AT: '2026-07-20T20:15:30Z'
      }
    }
  );
  if (result.status !== 0) {
    throw new Error(`Build failed for ${theme}:\n${result.stdout}\n${result.stderr}`);
  }
}

async function preparePage(browser, htmlPath, viewport) {
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: 1,
    colorScheme: 'light',
    reducedMotion: 'reduce'
  });
  await context.route(/^https?:/, (route) => route.abort());
  const page = await context.newPage();
  await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'load' });
  await page.addStyleTag({
    content: `
      ${fontFaceRules()}
      *, *::before, *::after { animation: none !important; transition: none !important; }
      body, button, input, select, textarea {
        font-family: VisualRegressionRoboto, sans-serif !important;
      }
      .fa { visibility: hidden !important; width: 0 !important; margin: 0 !important; }
    `
  });
  await page.evaluate(() => document.fonts.ready);
  return { context, page };
}

async function captureScreenshot(browser, htmlPath, outputPath, viewport) {
  const { context, page } = await preparePage(browser, htmlPath, viewport);
  await page.screenshot({ path: outputPath, fullPage: true, animations: 'disabled' });
  await context.close();
}

function pixelDifference(expected, actual) {
  let total = 0;
  let changedPixels = 0;
  const pixelCount = expected.width * expected.height;
  for (let offset = 0; offset < expected.data.length; offset += 4) {
    let largestChannelDelta = 0;
    for (let channel = 0; channel < 3; channel += 1) {
      const delta = Math.abs(expected.data[offset + channel] - actual.data[offset + channel]);
      total += delta;
      largestChannelDelta = Math.max(largestChannelDelta, delta);
    }
    if (largestChannelDelta > 18) changedPixels += 1;
  }
  return {
    changedPixelFraction: changedPixels / pixelCount,
    meanColorDelta: total / (pixelCount * 3) / 255
  };
}

function compareScreenshot(baselinePath, actualPath) {
  if (!fs.existsSync(baselinePath)) {
    throw new Error(`Missing visual baseline ${baselinePath}. Run the visual updater.`);
  }
  const baseline = PNG.sync.read(fs.readFileSync(baselinePath));
  const actual = PNG.sync.read(fs.readFileSync(actualPath));
  if (baseline.width !== actual.width || baseline.height !== actual.height) {
    throw new Error(
      `${path.basename(actualPath)} dimensions changed: ` +
      `${baseline.width}x${baseline.height} -> ${actual.width}x${actual.height}`
    );
  }
  const difference = pixelDifference(baseline, actual);
  if (
    difference.changedPixelFraction > MAX_CHANGED_PIXEL_FRACTION ||
    difference.meanColorDelta > MAX_MEAN_COLOR_DELTA
  ) {
    throw new Error(
      `${path.basename(actualPath)} changed pixels ` +
      `${(difference.changedPixelFraction * 100).toFixed(2)}% (max ` +
      `${(MAX_CHANGED_PIXEL_FRACTION * 100).toFixed(2)}%), mean color delta ` +
      `${(difference.meanColorDelta * 100).toFixed(2)}% (max ` +
      `${(MAX_MEAN_COLOR_DELTA * 100).toFixed(2)}%)`
    );
  }
  return difference;
}

function storeOrCompare(args, filename) {
  const actualPath = path.join(args.output_dir, filename);
  const baselinePath = path.join(args.baseline_dir, filename);
  if (args.update) {
    fs.copyFileSync(actualPath, baselinePath);
    return { updated: true };
  }
  return compareScreenshot(baselinePath, actualPath);
}

function inspectPdf(args, pdfPath) {
  fs.mkdirSync(args.pdf_output_dir, { recursive: true });
  for (const filename of fs.readdirSync(args.pdf_output_dir)) {
    if (/^page-\d+\.png$/.test(filename)) {
      fs.rmSync(path.join(args.pdf_output_dir, filename));
    }
  }
  const python = process.env.VISUAL_PYTHON_BIN || 'python3';
  const result = spawnSync(
    python,
    [path.join(SCRIPT_DIR, 'check_visual_pdf.py'), pdfPath, args.pdf_output_dir],
    { encoding: 'utf8', env: process.env }
  );
  if (result.status !== 0) {
    throw new Error(`PDF inspection failed:\n${result.stdout}\n${result.stderr}`);
  }
  return JSON.parse(result.stdout);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  fs.mkdirSync(args.baseline_dir, { recursive: true });
  fs.rmSync(args.output_dir, { recursive: true, force: true });
  fs.mkdirSync(args.output_dir, { recursive: true });
  const browser = await chromium.launch({
    executablePath: findChrome(),
    headless: true,
    args: ['--disable-dev-shm-usage', '--font-render-hinting=none']
  });
  const comparisons = {};

  try {
    for (const theme of THEMES) {
      runBuild(args.project_root, theme);
      const artifactRoot = path.join(args.project_root, 'dist', RESUME_USER, RESUME_NAME);
      const screenPath = path.join(artifactRoot, 'index.html');
      const desktopFilename = `desktop-${theme}.png`;
      await captureScreenshot(
        browser,
        screenPath,
        path.join(args.output_dir, desktopFilename),
        { width: 1280, height: 900 }
      );
      comparisons[desktopFilename] = storeOrCompare(args, desktopFilename);

      if (theme === 'theme-default') {
        const mobileFilename = 'mobile-theme-default.png';
        await captureScreenshot(
          browser,
          screenPath,
          path.join(args.output_dir, mobileFilename),
          { width: 390, height: 844 }
        );
        comparisons[mobileFilename] = storeOrCompare(args, mobileFilename);

        const pdfHtmlPath = path.join(artifactRoot, 'pdf.html');
        const { context, page } = await preparePage(browser, pdfHtmlPath, { width: 816, height: 1056 });
        await page.emulateMedia({ media: 'print' });
        fs.rmSync(args.pdf_output_dir, { recursive: true, force: true });
        fs.mkdirSync(args.pdf_output_dir, { recursive: true });
        const generatedPdf = path.join(args.pdf_output_dir, 'resume.pdf');
        await page.pdf({
          path: generatedPdf,
          format: 'Letter',
          printBackground: true,
          preferCSSPageSize: true,
          margin: { top: '0', right: '0', bottom: '0', left: '0' }
        });
        await context.close();

        const pdfMetrics = inspectPdf(args, generatedPdf);
        const metricsPath = path.join(args.baseline_dir, 'pdf-metrics.json');
        if (args.update) {
          fs.writeFileSync(metricsPath, `${JSON.stringify(pdfMetrics, null, 2)}\n`);
        } else {
          const expectedMetrics = JSON.parse(fs.readFileSync(metricsPath, 'utf8'));
          if (pdfMetrics.page_count !== expectedMetrics.page_count) {
            throw new Error(
              `PDF page count changed: ${expectedMetrics.page_count} -> ${pdfMetrics.page_count}`
            );
          }
        }

        const printFilename = 'print-theme-default-page-1.png';
        fs.copyFileSync(path.join(args.pdf_output_dir, 'page-1.png'), path.join(args.output_dir, printFilename));
        comparisons[printFilename] = storeOrCompare(args, printFilename);
      }
    }
  } finally {
    await browser.close();
  }

  console.log(JSON.stringify({ mode: args.update ? 'update' : 'compare', comparisons }, null, 2));
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
