const categorySelect = document.getElementById('categorySelect');
const fileSelect = document.getElementById('fileSelect');
const modeSelect = document.getElementById('modeSelect');
const editor = document.getElementById('editor');
const statusText = document.getElementById('statusText');
const reloadBtn = document.getElementById('reloadBtn');
const saveBtn = document.getElementById('saveBtn');

const structuredRoot = document.getElementById('structuredRoot');
const jobsEditor = document.getElementById('jobsEditor');
const summaryEditor = document.getElementById('summaryEditor');

const jobPickerInput = document.getElementById('jobPickerInput');
const jobPickerList = document.getElementById('jobPickerList');
const addJobBtn = document.getElementById('addJobBtn');
const removeJobBtn = document.getElementById('removeJobBtn');

const jobIdInput = document.getElementById('jobIdInput');
const jobIncludeInput = document.getElementById('jobIncludeInput');
const jobTitleInput = document.getElementById('jobTitleInput');
const jobCompanyInput = document.getElementById('jobCompanyInput');
const jobCityInput = document.getElementById('jobCityInput');
const jobStateInput = document.getElementById('jobStateInput');
const jobStartInput = document.getElementById('jobStartInput');
const jobEndInput = document.getElementById('jobEndInput');
const jobDescInput = document.getElementById('jobDescInput');

const summaryTypeInput = document.getElementById('summaryTypeInput');
const summaryTextInput = document.getElementById('summaryTextInput');

let filesByCategory = { jobs: [], summaries: [] };
let currentRawContent = '';
let currentStructuredData = null;
let currentJobIndex = -1;

function setStatus(text, isError = false) {
  statusText.textContent = text;
  statusText.style.color = isError ? '#b91c1c' : '#6b7280';
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const data = await response.json();

  if (!response.ok) {
    throw new Error(data.error || 'Request failed');
  }

  return data;
}

function refreshFileSelect() {
  const category = categorySelect.value;
  const files = filesByCategory[category] || [];

  fileSelect.innerHTML = '';

  if (!files.length) {
    const option = document.createElement('option');
    option.value = '';
    option.textContent = '(no files found)';
    fileSelect.appendChild(option);
    editor.value = '';
    return;
  }

  files.forEach((filePath) => {
    const option = document.createElement('option');
    option.value = filePath;
    option.textContent = filePath;
    fileSelect.appendChild(option);
  });
}

function toggleModeUI() {
  const rawMode = modeSelect.value === 'raw';
  editor.classList.toggle('hidden', !rawMode);
  structuredRoot.classList.toggle('hidden', rawMode);
}

function readIncludeValue(value) {
  if (value === 'true') return true;
  if (value === 'false') return false;
  return value;
}

function stringifyScalar(value) {
  if (value === undefined || value === null) return '';
  return String(value);
}

function ensureJobsData() {
  if (!Array.isArray(currentStructuredData)) {
    currentStructuredData = [];
  }
}

function ensureSummaryData() {
  if (!currentStructuredData || typeof currentStructuredData !== 'object' || Array.isArray(currentStructuredData)) {
    currentStructuredData = { summary: { type: '', text: '' } };
  }

  if (!currentStructuredData.summary || typeof currentStructuredData.summary !== 'object') {
    currentStructuredData.summary = { type: '', text: '' };
  }
}

function getSelectedJob() {
  ensureJobsData();
  const index = Number(currentJobIndex);
  if (Number.isNaN(index) || index < 0 || index >= currentStructuredData.length) {
    return null;
  }

  return currentStructuredData[index];
}

function renderJobSelector(preferredIndex) {
  ensureJobsData();
  const previousIndex = Number(currentJobIndex);
  const safePreferredIndex = Number.isInteger(preferredIndex) ? preferredIndex : previousIndex;

  jobPickerList.innerHTML = '';

  if (currentStructuredData.length === 0) {
    currentJobIndex = -1;
    jobPickerInput.value = '';
    jobPickerInput.placeholder = '(no jobs)';
    return;
  }

  jobPickerInput.placeholder = 'Type to find a job';

  currentStructuredData.forEach((job, index) => {
    const option = document.createElement('option');
    const title = stringifyScalar(job.title) || '(untitled)';
    const company = stringifyScalar(job.company);
    const label = company ? `${title} - ${company}` : title;
    option.value = label;
    option.setAttribute('data-index', String(index));
    jobPickerList.appendChild(option);
  });

  const clampedIndex = Math.min(
    Math.max(Number.isNaN(safePreferredIndex) ? 0 : safePreferredIndex, 0),
    currentStructuredData.length - 1
  );
  currentJobIndex = clampedIndex;

  const selectedJob = currentStructuredData[clampedIndex];
  const selectedTitle = stringifyScalar(selectedJob.title) || '(untitled)';
  const selectedCompany = stringifyScalar(selectedJob.company);
  jobPickerInput.value = selectedCompany ? `${selectedTitle} - ${selectedCompany}` : selectedTitle;
}

function syncJobSelectionFromPicker() {
  const typedLabel = jobPickerInput.value;
  const matchingOption = Array.from(jobPickerList.options).find((opt) => opt.value === typedLabel);
  if (!matchingOption) {
    return;
  }

  const index = Number(matchingOption.getAttribute('data-index'));
  if (Number.isNaN(index)) {
    return;
  }

  currentJobIndex = index;
  renderJobForm();
}

function renderJobForm() {
  const job = getSelectedJob();
  const disabled = !job;

  [
    jobPickerInput,
    jobIdInput,
    jobIncludeInput,
    jobTitleInput,
    jobCompanyInput,
    jobCityInput,
    jobStateInput,
    jobStartInput,
    jobEndInput,
    jobDescInput,
    removeJobBtn
  ].forEach((el) => {
    el.disabled = disabled;
  });

  if (!job) {
    jobIdInput.value = '';
    jobIncludeInput.value = 'true';
    jobTitleInput.value = '';
    jobCompanyInput.value = '';
    jobCityInput.value = '';
    jobStateInput.value = '';
    jobStartInput.value = '';
    jobEndInput.value = '';
    jobDescInput.value = '';
    return;
  }

  jobIdInput.value = stringifyScalar(job.id);
  jobIncludeInput.value = stringifyScalar(job.include || 'true');
  jobTitleInput.value = stringifyScalar(job.title);
  jobCompanyInput.value = stringifyScalar(job.company);
  jobCityInput.value = stringifyScalar(job.location?.city);
  jobStateInput.value = stringifyScalar(job.location?.state);
  jobStartInput.value = stringifyScalar(job.dates?.start);
  jobEndInput.value = stringifyScalar(job.dates?.end);
  jobDescInput.value = stringifyScalar(job.desc);
}

function renderSummaryForm() {
  ensureSummaryData();
  summaryTypeInput.value = stringifyScalar(currentStructuredData.summary.type);
  summaryTextInput.value = stringifyScalar(currentStructuredData.summary.text);
}

function renderStructuredEditor() {
  const category = categorySelect.value;
  jobsEditor.classList.toggle('hidden', category !== 'jobs');
  summaryEditor.classList.toggle('hidden', category !== 'summaries');

  if (category === 'jobs') {
    renderJobSelector();
    renderJobForm();
    return;
  }

  renderSummaryForm();
}

async function loadCurrentFile() {
  const filePath = fileSelect.value;
  if (!filePath) {
    editor.value = '';
    return;
  }

  try {
    setStatus(`Loading ${filePath}...`);
    const [rawData, structuredData] = await Promise.all([
      fetchJson(`/api/file?path=${encodeURIComponent(filePath)}`),
      fetchJson(`/api/file-structured?path=${encodeURIComponent(filePath)}`)
    ]);
    currentRawContent = rawData.content;
    currentStructuredData = structuredData.data;
    editor.value = currentRawContent;
    renderStructuredEditor();
    setStatus(`Loaded ${filePath}`);
  } catch (error) {
    setStatus(error.message, true);
  }
}

async function refreshFileLists() {
  try {
    setStatus('Loading file lists...');
    filesByCategory = await fetchJson('/api/files');
    refreshFileSelect();
    await loadCurrentFile();
  } catch (error) {
    setStatus(error.message, true);
  }
}

async function saveCurrentFile() {
  const filePath = fileSelect.value;
  if (!filePath) {
    setStatus('No file selected', true);
    return;
  }

  try {
    setStatus(`Saving ${filePath}...`);

    if (modeSelect.value === 'raw') {
      await fetchJson('/api/file', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: filePath, content: editor.value })
      });
      currentRawContent = editor.value;
    } else {
      await fetchJson('/api/file-structured', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: filePath, data: currentStructuredData })
      });
      const rawData = await fetchJson(`/api/file?path=${encodeURIComponent(filePath)}`);
      currentRawContent = rawData.content;
      editor.value = currentRawContent;
    }

    setStatus(`Saved ${filePath}`);
  } catch (error) {
    setStatus(error.message, true);
  }
}

categorySelect.addEventListener('change', async () => {
  refreshFileSelect();
  await loadCurrentFile();
});

modeSelect.addEventListener('change', () => {
  toggleModeUI();
});

fileSelect.addEventListener('change', loadCurrentFile);
reloadBtn.addEventListener('click', refreshFileLists);
saveBtn.addEventListener('click', saveCurrentFile);

jobPickerInput.addEventListener('change', syncJobSelectionFromPicker);
jobPickerInput.addEventListener('input', syncJobSelectionFromPicker);

addJobBtn.addEventListener('click', () => {
  ensureJobsData();
  currentStructuredData.push({
    id: '',
    title: '',
    company: '',
    include: true,
    location: { city: '', state: '' },
    dates: { start: '', end: '' },
    desc: ''
  });
  renderJobSelector(currentStructuredData.length - 1);
  renderJobForm();
});

removeJobBtn.addEventListener('click', () => {
  ensureJobsData();
  const index = Number(currentJobIndex);
  if (Number.isNaN(index) || index < 0 || index >= currentStructuredData.length) {
    return;
  }

  currentStructuredData.splice(index, 1);
  renderJobSelector(Math.max(0, index - 1));
  renderJobForm();
});

function updateCurrentJob(mutator) {
  const job = getSelectedJob();
  if (!job) return;
  const selectedIndex = Number(currentJobIndex);
  mutator(job);
  renderJobSelector(selectedIndex);
}

jobIdInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.id = jobIdInput.value;
}));

jobIncludeInput.addEventListener('change', () => updateCurrentJob((job) => {
  job.include = readIncludeValue(jobIncludeInput.value);
}));

jobTitleInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.title = jobTitleInput.value;
}));

jobCompanyInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.company = jobCompanyInput.value;
}));

jobCityInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.location = job.location || {};
  job.location.city = jobCityInput.value;
}));

jobStateInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.location = job.location || {};
  job.location.state = jobStateInput.value;
}));

jobStartInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.dates = job.dates || {};
  job.dates.start = jobStartInput.value;
}));

jobEndInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.dates = job.dates || {};
  job.dates.end = jobEndInput.value;
}));

jobDescInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.desc = jobDescInput.value;
}));

summaryTypeInput.addEventListener('input', () => {
  ensureSummaryData();
  currentStructuredData.summary.type = summaryTypeInput.value;
});

summaryTextInput.addEventListener('input', () => {
  ensureSummaryData();
  currentStructuredData.summary.text = summaryTextInput.value;
});

toggleModeUI();
refreshFileLists();
