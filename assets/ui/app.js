let selectedId = null;
let jobs = [];
let authToken = sessionStorage.getItem('ic-token') || '';
let surface = 'user';

function isRemoteHost() {
  const h = location.hostname;
  return h !== 'localhost' && h !== '127.0.0.1';
}

async function api(path, opts = {}) {
  const headers = { 'Content-Type': 'application/json', ...(opts.headers || {}) };
  if (authToken) headers['Authorization'] = 'Bearer ' + authToken;
  const r = await fetch(path, { ...opts, headers });
  if (r.status === 401) {
    document.getElementById('login')?.classList.remove('hidden');
    throw new Error('auth required');
  }
  return r.json();
}

function stateClass(s) {
  if (s === 'done') return 'state-done';
  if (s === 'failed' || s === 'cancelled') return 'state-failed';
  if (s === 'blocked' || s === 'executing') return 'state-blocked';
  return '';
}

function friendlyState(s) {
  const map = {
    collecting: 'Needs your choices',
    ready: 'Ready',
    queued: 'Waiting in line',
    blocked: 'Waiting on another install',
    executing: 'Installing…',
    done: 'Finished',
    failed: 'Failed',
    cancelled: 'Cancelled',
  };
  return map[s] || s;
}

function renderList(el, items, filterFn) {
  el.innerHTML = '';
  items.filter(filterFn).forEach(j => {
    const d = document.createElement('div');
    d.className = 'item' + (j.id === selectedId ? ' selected' : '');
    const label = j.displayName || j.id;
    const st = surface === 'user' ? friendlyState(j.state) : j.state;
    d.innerHTML = `<div class="name">${escapeHtml(label)}</div>
      <div class="meta"><span class="${stateClass(j.state)}">${escapeHtml(st)}</span> · ${escapeHtml(j.statusMessage || '')}</div>`;
    d.onclick = () => selectJob(j.id);
    el.appendChild(d);
  });
}

function escapeHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

async function refresh() {
  const st = await api('/status');
  const busy = st.msiBusy ? 'another installer is running' : 'ready';
  document.getElementById('status').textContent =
    surface === 'user'
      ? `${st.jobs?.length || 0} in progress · ${busy}`
      : `MSI lane ${st.msiBusy ? 'busy' : 'free'} · ${st.jobs?.length || 0} active`;
  const all = await api('/jobs');
  jobs = all.jobs || [];
  const active = j => !['done','failed','cancelled'].includes(j.state);
  renderList(document.getElementById('queue'), jobs, active);
  const hist = await api('/catalog');
  renderList(document.getElementById('history'), hist.catalog || [], () => true);
}

async function selectJob(id) {
  selectedId = id;
  const j = jobs.find(x => x.id === id) || (await api('/jobs')).jobs?.find(x => x.id === id);
  if (surface === 'user') {
    const lines = [
      j?.displayName || id,
      friendlyState(j?.state || ''),
      j?.statusMessage || '',
      j?.errorMessage || '',
    ].filter(Boolean);
    document.getElementById('detail').textContent = lines.join('\n');
  } else {
    document.getElementById('detail').textContent = JSON.stringify(j || { id }, null, 2);
  }
  document.getElementById('pinDesktop').disabled = !j?.sourceManifest;
  document.getElementById('pinStart').disabled = !j?.sourceManifest;
  document.getElementById('cancelJob').disabled = !j || ['done','failed','cancelled'].includes(j.state);
  refresh();
}

async function pushSession() {
  await api('/session', {
    method: 'POST',
    body: JSON.stringify({
      installForAllUsers: document.getElementById('scope').value === 'perMachine',
      orgPolicyAccepted: document.getElementById('batchTerms')?.checked || false,
      lockElevationUntilClose: document.getElementById('lockElev').checked,
      grantElevation: document.getElementById('lockElev').checked,
    }),
  });
}

function wireControls() {
  document.getElementById('refresh').onclick = refresh;
  document.getElementById('lockElev').onchange = pushSession;
  document.getElementById('batchTerms')?.addEventListener('change', pushSession);
  document.getElementById('scope').onchange = pushSession;
  document.getElementById('installAll').onclick = async () => {
    const scope = document.getElementById('scope').value;
    for (const j of jobs) {
      if (j.state === 'collecting' || j.state === 'ready') {
        await api(`/jobs/${j.id}/commit`, {
          method: 'POST',
          body: JSON.stringify({ termsAccepted: true, scope }),
        });
      }
    }
    refresh();
  };
  document.getElementById('cancelJob').onclick = async () => {
    if (!selectedId) return;
    await api(`/jobs/${selectedId}/cancel`, { method: 'POST' });
    refresh();
  };
  document.getElementById('pinDesktop').onclick = async () => {
    if (!selectedId) return;
    await api(`/jobs/${selectedId}/shortcut`, { method: 'POST', body: JSON.stringify({ kind: 'desktop' }) });
    refresh();
  };
  document.getElementById('pinStart').onclick = async () => {
    if (!selectedId) return;
    await api(`/jobs/${selectedId}/shortcut`, { method: 'POST', body: JSON.stringify({ kind: 'startMenu' }) });
    refresh();
  };
  document.getElementById('loginBtn')?.addEventListener('click', () => {
    authToken = document.getElementById('tokenInput').value.trim();
    sessionStorage.setItem('ic-token', authToken);
    document.getElementById('login').classList.add('hidden');
    refresh();
  });
}

function bootSurface(name) {
  surface = name;
  if (name === 'admin' && isRemoteHost() && !authToken) {
    document.getElementById('login')?.classList.remove('hidden');
  }
  wireControls();
  pushSession().then(refresh).catch(() => {});
  setInterval(() => refresh().catch(() => {}), 2000);
}
