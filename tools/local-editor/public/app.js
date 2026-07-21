const categorySelect = document.getElementById('categorySelect');
const fileSelect = document.getElementById('fileSelect');
const modeSelect = document.getElementById('modeSelect');
const editor = document.getElementById('editor');
const statusText = document.getElementById('statusText');
const reloadBtn = document.getElementById('reloadBtn');
const revertBtn = document.getElementById('revertBtn');
const validateBtn = document.getElementById('validateBtn');
const saveBtn = document.getElementById('saveBtn');

const structuredRoot = document.getElementById('structuredRoot');
const jobsEditor = document.getElementById('jobsEditor');
const summaryEditor = document.getElementById('summaryEditor');
const resumeEditor = document.getElementById('resumeEditor');
const activeResumeFields = document.getElementById('activeResumeFields');
const resumeDefinitionFields = document.getElementById('resumeDefinitionFields');
const activeUserInput = document.getElementById('activeUserInput');
const activeNameInput = document.getElementById('activeNameInput');
const activeBriefInput = document.getElementById('activeBriefInput');
const resumeNameInput = document.getElementById('resumeNameInput');
const resumeThemeInput = document.getElementById('resumeThemeInput');
const resumeLayoutInput = document.getElementById('resumeLayoutInput');
const resumeJobsFileInput = document.getElementById('resumeJobsFileInput');
const resumeSummaryInput = document.getElementById('resumeSummaryInput');
const resumePdfIconsInput = document.getElementById('resumePdfIconsInput');
const resumePdfFilenameInput = document.getElementById('resumePdfFilenameInput');
const resumePdfSourceInput = document.getElementById('resumePdfSourceInput');
const resumeContactNameInput = document.getElementById('resumeContactNameInput');
const resumeContactEmailInput = document.getElementById('resumeContactEmailInput');
const resumeContactPhoneInput = document.getElementById('resumeContactPhoneInput');
const resumeContactStreetInput = document.getElementById('resumeContactStreetInput');
const resumeContactCityInput = document.getElementById('resumeContactCityInput');
const resumeContactStateInput = document.getElementById('resumeContactStateInput');
const resumeContactPostalInput = document.getElementById('resumeContactPostalInput');
const resumeJobsList = document.getElementById('resumeJobsList');
const addResumeJobBtn = document.getElementById('addResumeJobBtn');
const resumeLinksList = document.getElementById('resumeLinksList');
const addResumeLinkBtn = document.getElementById('addResumeLinkBtn');
const resumeSkillsList = document.getElementById('resumeSkillsList');
const addResumeSkillGroupBtn = document.getElementById('addResumeSkillGroupBtn');
const resumeEducationList = document.getElementById('resumeEducationList');
const addResumeEducationBtn = document.getElementById('addResumeEducationBtn');

const jobPickerInput = document.getElementById('jobPickerInput');
const jobPickerList = document.getElementById('jobPickerList');
const addJobBtn = document.getElementById('addJobBtn');
const duplicateJobBtn = document.getElementById('duplicateJobBtn');
const moveJobUpBtn = document.getElementById('moveJobUpBtn');
const moveJobDownBtn = document.getElementById('moveJobDownBtn');
const removeJobBtn = document.getElementById('removeJobBtn');

const jobIdInput = document.getElementById('jobIdInput');
const jobIncludeInput = document.getElementById('jobIncludeInput');
const jobBriefInput = document.getElementById('jobBriefInput');
const jobTitleInput = document.getElementById('jobTitleInput');
const jobCompanyInput = document.getElementById('jobCompanyInput');
const jobCityInput = document.getElementById('jobCityInput');
const jobStateInput = document.getElementById('jobStateInput');
const jobStartInput = document.getElementById('jobStartInput');
const jobEndInput = document.getElementById('jobEndInput');
const jobDescInput = document.getElementById('jobDescInput');

const summaryTypeInput = document.getElementById('summaryTypeInput');
const summaryTextInput = document.getElementById('summaryTextInput');

let filesByCategory = { jobs: [], summaries: [], resumes: [] };
let currentResumeOptions = null;
let currentRawContent = '';
let currentStructuredData = null;
let originalStructuredData = null;
let currentJobIndex = -1;
let dirty = false;
let selectedCategory = categorySelect.value;
let selectedFile = '';

function setStatus(text, isError = false) {
  statusText.textContent = text;
  statusText.style.color = isError ? '#b91c1c' : '#6b7280';
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const data = await response.json();

  if (!response.ok) {
    throw new Error(data.error || data.errors?.join('\n') || 'Request failed');
  }

  return data;
}

function setDirty(value = true) {
  dirty = value;
  document.title = `${dirty ? '* ' : ''}Local Resume YAML Editor`;
  saveBtn.disabled = !dirty;
}

function structuredSnapshot() {
  return JSON.stringify(currentStructuredData);
}

function refreshDirtyState() {
  const changed = modeSelect.value === 'raw'
    ? editor.value !== currentRawContent
    : structuredSnapshot() !== originalStructuredData;
  setDirty(changed);
}

function confirmDiscard() {
  return !dirty || window.confirm('Discard your unsaved changes?');
}

function currentPayload() {
  return modeSelect.value === 'raw'
    ? { path: fileSelect.value, content: editor.value }
    : { path: fileSelect.value, data: currentStructuredData };
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
  selectedFile = fileSelect.value;
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

function setOptionalValue(object, key, value, transform = (item) => item) {
  if (value === '') delete object[key];
  else object[key] = transform(value);
}

function uniqueJobId(sourceId = 'job') {
  const used = new Set(currentStructuredData.map((job) => stringifyScalar(job.id)));
  const base = `${sourceId || 'job'}-copy`;
  let candidate = base;
  let suffix = 2;
  while (used.has(candidate)) candidate = `${base}-${suffix++}`;
  return candidate;
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

function ensureResumeData() {
  if (!currentStructuredData || typeof currentStructuredData !== 'object' || Array.isArray(currentStructuredData)) {
    currentStructuredData = {};
  }
}

function populateSelect(select, values, selected, allowUnset = false) {
  select.innerHTML = '';
  if (allowUnset) select.add(new Option('(default)', ''));
  for (const value of values) select.add(new Option(value, value));
  if (selected !== undefined && selected !== null) select.value = String(selected);
}

function ensureResumeNested() {
  ensureResumeData();
  currentStructuredData.pdf ||= {};
  currentStructuredData.summary ||= {};
  currentStructuredData.contact_info ||= {};
  currentStructuredData.contact_info.address ||= {};
  currentStructuredData.jobs ||= [];
  currentStructuredData.links ||= [];
  currentStructuredData.skills ||= [];
  currentStructuredData.education ||= [];
}

function updateResume(mutator) {
  ensureResumeData();
  mutator(currentStructuredData);
  refreshDirtyState();
}

function renderResumeJobs() {
  ensureResumeNested();
  resumeJobsList.innerHTML = '';
  currentStructuredData.jobs.forEach((reference, index) => {
    const row = document.createElement('div');
    row.className = 'row resume-job-row';
    const fileSelect = document.createElement('select');
    populateSelect(fileSelect, Object.keys(currentResumeOptions?.jobFiles || {}), reference.file || currentStructuredData.jobs_filename);
    const idSelect = document.createElement('select');
    const populateIds = () => populateSelect(idSelect, currentResumeOptions?.jobFiles?.[fileSelect.value] || [], reference.id);
    populateIds();
    const sectionInput = document.createElement('input');
    sectionInput.placeholder = 'section';
    sectionInput.value = stringifyScalar(reference.section);
    const up = document.createElement('button'); up.type = 'button'; up.className = 'secondary'; up.textContent = '↑'; up.disabled = index === 0;
    const down = document.createElement('button'); down.type = 'button'; down.className = 'secondary'; down.textContent = '↓'; down.disabled = index === currentStructuredData.jobs.length - 1;
    const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'secondary'; remove.textContent = 'Remove';
    fileSelect.addEventListener('change', () => updateResume(() => { reference.file = fileSelect.value; reference.id = ''; populateIds(); }));
    idSelect.addEventListener('change', () => updateResume(() => { reference.id = idSelect.value; }));
    sectionInput.addEventListener('input', () => updateResume(() => { reference.section = sectionInput.value; }));
    up.addEventListener('click', () => { currentStructuredData.jobs.splice(index - 1, 0, currentStructuredData.jobs.splice(index, 1)[0]); renderResumeJobs(); refreshDirtyState(); });
    down.addEventListener('click', () => { currentStructuredData.jobs.splice(index + 1, 0, currentStructuredData.jobs.splice(index, 1)[0]); renderResumeJobs(); refreshDirtyState(); });
    remove.addEventListener('click', () => { currentStructuredData.jobs.splice(index, 1); renderResumeJobs(); refreshDirtyState(); });
    row.append(fileSelect, idSelect, sectionInput, up, down, remove);
    resumeJobsList.appendChild(row);
  });
}

function renderResumeLinks() {
  ensureResumeNested();
  resumeLinksList.innerHTML = '';
  currentStructuredData.links.forEach((reference, index) => {
    const row = document.createElement('div'); row.className = 'row';
    const select = document.createElement('select');
    populateSelect(select, (currentResumeOptions?.links || []).map((link) => link.name), reference.name);
    const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'secondary'; remove.textContent = 'Remove';
    select.addEventListener('change', () => updateResume(() => { reference.name = select.value; }));
    remove.addEventListener('click', () => { currentStructuredData.links.splice(index, 1); renderResumeLinks(); refreshDirtyState(); });
    row.append(select, remove); resumeLinksList.appendChild(row);
  });
}

function renderResumeSkills() {
  ensureResumeNested();
  resumeSkillsList.innerHTML = '';
  currentStructuredData.skills.forEach((group, index) => {
    const row = document.createElement('div'); row.className = 'row';
    const name = document.createElement('input'); name.placeholder = 'Group name'; name.value = stringifyScalar(group.name);
    const select = document.createElement('select'); select.multiple = true; select.size = Math.min(6, Math.max(3, currentResumeOptions?.skills?.length || 3));
    for (const skill of currentResumeOptions?.skills || []) {
      const option = new Option(`${skill.id}: ${skill.label}`, String(skill.id));
      option.selected = (group.skills || []).map(String).includes(String(skill.id));
      select.add(option);
    }
    const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'secondary'; remove.textContent = 'Remove';
    name.addEventListener('input', () => updateResume(() => { group.name = name.value; }));
    select.addEventListener('change', () => updateResume(() => {
      group.skills = Array.from(select.selectedOptions).map((option) => {
        const source = currentResumeOptions.skills.find((skill) => String(skill.id) === option.value);
        return source?.id ?? option.value;
      });
    }));
    remove.addEventListener('click', () => { currentStructuredData.skills.splice(index, 1); renderResumeSkills(); refreshDirtyState(); });
    row.append(name, select, remove); resumeSkillsList.appendChild(row);
  });
}

function renderResumeEducation() {
  ensureResumeNested();
  resumeEducationList.innerHTML = '';
  currentStructuredData.education.forEach((entry, index) => {
    entry.dates ||= {};
    const row = document.createElement('div'); row.className = 'resume-job-row';
    const name = document.createElement('input'); name.placeholder = 'School'; name.value = stringifyScalar(entry.name);
    const degree = document.createElement('input'); degree.placeholder = 'Degree'; degree.value = stringifyScalar(entry.degree);
    const start = document.createElement('input'); start.placeholder = 'Start'; start.value = stringifyScalar(entry.dates.start);
    const end = document.createElement('input'); end.placeholder = 'End'; end.value = stringifyScalar(entry.dates.end);
    const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'secondary'; remove.textContent = 'Remove';
    name.addEventListener('input', () => updateResume(() => { entry.name = name.value; }));
    degree.addEventListener('input', () => updateResume(() => { entry.degree = degree.value; }));
    start.addEventListener('input', () => updateResume(() => { entry.dates.start = start.value; }));
    end.addEventListener('input', () => updateResume(() => { entry.dates.end = end.value; }));
    remove.addEventListener('click', () => { currentStructuredData.education.splice(index, 1); renderResumeEducation(); refreshDirtyState(); });
    row.append(name, degree, start, end, remove); resumeEducationList.appendChild(row);
  });
}

async function renderResumeForm() {
  ensureResumeData();
  const active = fileSelect.value === 'data/active_resume.yml';
  activeResumeFields.classList.toggle('hidden', !active);
  resumeDefinitionFields.classList.toggle('hidden', active);
  currentResumeOptions = await fetchJson(`/api/resume-options?path=${encodeURIComponent(fileSelect.value)}`);
  if (active) {
    populateSelect(activeUserInput, currentResumeOptions.users, currentStructuredData.user);
    populateSelect(activeNameInput, currentResumeOptions.resumes, currentStructuredData.name);
    activeBriefInput.value = stringifyScalar(currentStructuredData.generate_brief !== false);
    return;
  }
  ensureResumeNested();
  resumeNameInput.value = stringifyScalar(currentStructuredData.name);
  populateSelect(resumeThemeInput, currentResumeOptions.themes, currentStructuredData.theme, true);
  populateSelect(resumeLayoutInput, currentResumeOptions.layouts, currentStructuredData.layout);
  populateSelect(resumeJobsFileInput, Object.keys(currentResumeOptions.jobFiles), currentStructuredData.jobs_filename);
  populateSelect(resumeSummaryInput, currentResumeOptions.summaries, currentStructuredData.summary.file);
  resumePdfIconsInput.value = stringifyScalar(currentStructuredData.pdf.useicons !== false);
  resumePdfFilenameInput.value = stringifyScalar(currentStructuredData.pdf.filename);
  resumePdfSourceInput.value = stringifyScalar(currentStructuredData.pdf.source);
  const contact = currentStructuredData.contact_info;
  resumeContactNameInput.value = stringifyScalar(contact.name);
  resumeContactEmailInput.value = stringifyScalar(contact.email);
  resumeContactPhoneInput.value = stringifyScalar(contact.phone);
  resumeContactStreetInput.value = stringifyScalar(contact.address.street);
  resumeContactCityInput.value = stringifyScalar(contact.address.city);
  resumeContactStateInput.value = stringifyScalar(contact.address.state);
  resumeContactPostalInput.value = stringifyScalar(contact.address.postal_code);
  renderResumeJobs();
  renderResumeLinks();
  renderResumeSkills();
  renderResumeEducation();
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
    const id = stringifyScalar(job.id) || '(no id)';
    const label = company ? `${id} · ${title} - ${company}` : `${id} · ${title}`;
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
  const selectedId = stringifyScalar(selectedJob.id) || '(no id)';
  jobPickerInput.value = selectedCompany
    ? `${selectedId} · ${selectedTitle} - ${selectedCompany}`
    : `${selectedId} · ${selectedTitle}`;
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
    jobBriefInput,
    jobTitleInput,
    jobCompanyInput,
    jobCityInput,
    jobStateInput,
    jobStartInput,
    jobEndInput,
    jobDescInput,
    duplicateJobBtn,
    moveJobUpBtn,
    moveJobDownBtn,
    removeJobBtn
  ].forEach((el) => {
    el.disabled = disabled;
  });

  if (!job) {
    jobIdInput.value = '';
    jobIncludeInput.value = 'true';
    jobBriefInput.value = '';
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
  jobIncludeInput.value = Object.prototype.hasOwnProperty.call(job, 'include')
    ? stringifyScalar(job.include)
    : '';
  jobBriefInput.value = Object.prototype.hasOwnProperty.call(job, 'brief')
    ? stringifyScalar(job.brief)
    : '';
  jobTitleInput.value = stringifyScalar(job.title);
  jobCompanyInput.value = stringifyScalar(job.company);
  jobCityInput.value = stringifyScalar(job.location?.city);
  jobStateInput.value = stringifyScalar(job.location?.state);
  jobStartInput.value = stringifyScalar(job.dates?.start);
  jobEndInput.value = stringifyScalar(job.dates?.end);
  jobDescInput.value = stringifyScalar(job.desc);
  moveJobUpBtn.disabled = currentJobIndex <= 0;
  moveJobDownBtn.disabled = currentJobIndex >= currentStructuredData.length - 1;
}

function renderSummaryForm() {
  ensureSummaryData();
  summaryTypeInput.value = stringifyScalar(currentStructuredData.summary.type);
  summaryTextInput.value = stringifyScalar(currentStructuredData.summary.text);
}

async function renderStructuredEditor() {
  const category = categorySelect.value;
  jobsEditor.classList.toggle('hidden', category !== 'jobs');
  summaryEditor.classList.toggle('hidden', category !== 'summaries');
  resumeEditor.classList.toggle('hidden', category !== 'resumes');

  if (category === 'jobs') {
    renderJobSelector();
    renderJobForm();
    return;
  }

  if (category === 'summaries') renderSummaryForm();
  else await renderResumeForm();
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
    originalStructuredData = structuredSnapshot();
    editor.value = currentRawContent;
    await renderStructuredEditor();
    setStatus(`Loaded ${filePath}`);
    setDirty(false);
    selectedFile = filePath;
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
      const result = await fetchJson('/api/file', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: filePath, content: editor.value })
      });
      currentRawContent = editor.value;
      setStatus(`Saved ${filePath}; backup: ${result.backupPath}`);
    } else {
      const result = await fetchJson('/api/file-structured', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: filePath, data: currentStructuredData })
      });
      const rawData = await fetchJson(`/api/file?path=${encodeURIComponent(filePath)}`);
      currentRawContent = rawData.content;
      editor.value = currentRawContent;
      originalStructuredData = structuredSnapshot();
      setStatus(`Saved ${filePath}; backup: ${result.backupPath}`);
    }
    setDirty(false);
  } catch (error) {
    setStatus(error.message, true);
  }
}

async function validateCurrentFile() {
  if (!fileSelect.value) return setStatus('No file selected', true);
  try {
    setStatus(`Validating ${fileSelect.value}...`);
    await fetchJson('/api/validate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(currentPayload())
    });
    setStatus(`${fileSelect.value} is valid`);
  } catch (error) {
    setStatus(error.message, true);
  }
}

categorySelect.addEventListener('change', async () => {
  if (!confirmDiscard()) {
    categorySelect.value = selectedCategory;
    return;
  }
  selectedCategory = categorySelect.value;
  refreshFileSelect();
  await loadCurrentFile();
});

modeSelect.addEventListener('change', () => {
  if (!confirmDiscard()) {
    modeSelect.value = modeSelect.value === 'raw' ? 'structured' : 'raw';
    return;
  }
  toggleModeUI();
  refreshDirtyState();
});

fileSelect.addEventListener('change', async () => {
  if (!confirmDiscard()) {
    fileSelect.value = selectedFile;
    return;
  }
  await loadCurrentFile();
});
reloadBtn.addEventListener('click', () => { if (confirmDiscard()) refreshFileLists(); });
revertBtn.addEventListener('click', () => { if (confirmDiscard()) loadCurrentFile(); });
validateBtn.addEventListener('click', validateCurrentFile);
saveBtn.addEventListener('click', saveCurrentFile);
editor.addEventListener('input', refreshDirtyState);
window.addEventListener('beforeunload', (event) => {
  if (!dirty) return;
  event.preventDefault();
  event.returnValue = '';
});

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
  refreshDirtyState();
});

removeJobBtn.addEventListener('click', () => {
  ensureJobsData();
  const index = Number(currentJobIndex);
  if (Number.isNaN(index) || index < 0 || index >= currentStructuredData.length) {
    return;
  }

  const job = currentStructuredData[index];
  const label = stringifyScalar(job.title) || stringifyScalar(job.id) || 'this job';
  if (!window.confirm(`Delete ${label}? This takes effect when you save.`)) return;
  currentStructuredData.splice(index, 1);
  renderJobSelector(Math.max(0, index - 1));
  renderJobForm();
  refreshDirtyState();
});

duplicateJobBtn.addEventListener('click', () => {
  const job = getSelectedJob();
  if (!job) return;
  const copy = structuredClone(job);
  copy.id = uniqueJobId(job.id);
  copy.title = `Copy of ${stringifyScalar(job.title) || 'untitled job'}`;
  currentStructuredData.splice(currentJobIndex + 1, 0, copy);
  renderJobSelector(currentJobIndex + 1);
  renderJobForm();
  refreshDirtyState();
});

function moveSelectedJob(offset) {
  const destination = currentJobIndex + offset;
  if (destination < 0 || destination >= currentStructuredData.length) return;
  const [job] = currentStructuredData.splice(currentJobIndex, 1);
  currentStructuredData.splice(destination, 0, job);
  renderJobSelector(destination);
  renderJobForm();
  refreshDirtyState();
}

moveJobUpBtn.addEventListener('click', () => moveSelectedJob(-1));
moveJobDownBtn.addEventListener('click', () => moveSelectedJob(1));

function updateCurrentJob(mutator) {
  const job = getSelectedJob();
  if (!job) return;
  const selectedIndex = Number(currentJobIndex);
  mutator(job);
  renderJobSelector(selectedIndex);
  refreshDirtyState();
}

jobIdInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.id = jobIdInput.value;
}));

jobIncludeInput.addEventListener('change', () => updateCurrentJob((job) => {
  setOptionalValue(job, 'include', jobIncludeInput.value, readIncludeValue);
}));

jobBriefInput.addEventListener('change', () => updateCurrentJob((job) => {
  setOptionalValue(job, 'brief', jobBriefInput.value, readIncludeValue);
}));

jobTitleInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.title = jobTitleInput.value;
}));

jobCompanyInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.company = jobCompanyInput.value;
}));

jobCityInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.location = job.location || {};
  job.location.city = jobCityInput.value || null;
}));

jobStateInput.addEventListener('input', () => updateCurrentJob((job) => {
  job.location = job.location || {};
  job.location.state = jobStateInput.value || null;
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
  refreshDirtyState();
});

summaryTextInput.addEventListener('input', () => {
  ensureSummaryData();
  currentStructuredData.summary.text = summaryTextInput.value;
  refreshDirtyState();
});

activeUserInput.addEventListener('change', async () => {
  updateResume((resume) => { resume.user = activeUserInput.value; resume.name = ''; });
  currentResumeOptions = await fetchJson(`/api/resume-options?path=${encodeURIComponent(`data/${activeUserInput.value}/resume.yml`)}`);
  populateSelect(activeNameInput, currentResumeOptions.resumes, '');
});
activeNameInput.addEventListener('change', () => updateResume((resume) => { resume.name = activeNameInput.value; }));
activeBriefInput.addEventListener('change', () => updateResume((resume) => { resume.generate_brief = activeBriefInput.value === 'true'; }));

resumeNameInput.addEventListener('input', () => updateResume((resume) => { resume.name = resumeNameInput.value; }));
resumeThemeInput.addEventListener('change', () => updateResume((resume) => setOptionalValue(resume, 'theme', resumeThemeInput.value)));
resumeLayoutInput.addEventListener('change', () => updateResume((resume) => { resume.layout = resumeLayoutInput.value; }));
resumeJobsFileInput.addEventListener('change', () => updateResume((resume) => { resume.jobs_filename = resumeJobsFileInput.value; renderResumeJobs(); }));
resumeSummaryInput.addEventListener('change', () => updateResume((resume) => { resume.summary.file = resumeSummaryInput.value; }));
resumePdfIconsInput.addEventListener('change', () => updateResume((resume) => { resume.pdf.useicons = resumePdfIconsInput.value === 'true'; }));
resumePdfFilenameInput.addEventListener('input', () => updateResume((resume) => { resume.pdf.filename = resumePdfFilenameInput.value; }));
resumePdfSourceInput.addEventListener('input', () => updateResume((resume) => { resume.pdf.source = resumePdfSourceInput.value; }));
resumeContactNameInput.addEventListener('input', () => updateResume((resume) => { resume.contact_info.name = resumeContactNameInput.value; }));
resumeContactEmailInput.addEventListener('input', () => updateResume((resume) => { resume.contact_info.email = resumeContactEmailInput.value; }));
resumeContactPhoneInput.addEventListener('input', () => updateResume((resume) => { resume.contact_info.phone = resumeContactPhoneInput.value; }));
resumeContactStreetInput.addEventListener('input', () => updateResume((resume) => { resume.contact_info.address.street = resumeContactStreetInput.value; }));
resumeContactCityInput.addEventListener('input', () => updateResume((resume) => { resume.contact_info.address.city = resumeContactCityInput.value; }));
resumeContactStateInput.addEventListener('input', () => updateResume((resume) => { resume.contact_info.address.state = resumeContactStateInput.value; }));
resumeContactPostalInput.addEventListener('input', () => updateResume((resume) => { resume.contact_info.address.postal_code = resumeContactPostalInput.value; }));
addResumeJobBtn.addEventListener('click', () => {
  updateResume((resume) => {
    const file = resume.jobs_filename || Object.keys(currentResumeOptions?.jobFiles || {})[0] || '';
    resume.jobs.push({ file, id: currentResumeOptions?.jobFiles?.[file]?.[0] || '', section: 'experiences' });
  });
  renderResumeJobs();
});
addResumeLinkBtn.addEventListener('click', () => {
  updateResume((resume) => resume.links.push({ name: currentResumeOptions?.links?.[0]?.name || '' }));
  renderResumeLinks();
});
addResumeSkillGroupBtn.addEventListener('click', () => {
  updateResume((resume) => resume.skills.push({ name: '', skills: [] }));
  renderResumeSkills();
});
addResumeEducationBtn.addEventListener('click', () => {
  updateResume((resume) => resume.education.push({ name: '', degree: '', dates: { start: '', end: '' } }));
  renderResumeEducation();
});

toggleModeUI();
setDirty(false);
refreshFileLists();
