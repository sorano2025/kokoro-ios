//
//  StarkCore
//
import Foundation

/// The dashboard, served from memory at `/`.
///
/// One file, no build step, no CDN: the phone has no network guarantee and the
/// page has to render from the device itself. Monospace, hairline rules and two
/// ink levels — dense enough to read the whole system at a glance on a phone
/// screen, with nothing on it that is not a number or a control.
enum Console {
  static let page = #"""
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>STARK</title>
  <style>
    :root {
      --bg: #000; --ink: #e8e8e8; --dim: #6a6a6a; --line: #232323;
      --ok: #7dd3a0; --warn: #e0c060; --bad: #e07a6a; --accent: #fff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; background: var(--bg); color: var(--ink);
      font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
      -webkit-font-smoothing: antialiased; padding: env(safe-area-inset-top) 0 env(safe-area-inset-bottom);
    }
    header {
      display: flex; align-items: baseline; gap: 10px; padding: 14px 14px 10px;
      border-bottom: 1px solid var(--line); position: sticky; top: 0; background: var(--bg); z-index: 5;
    }
    h1 { font-size: 13px; letter-spacing: .32em; margin: 0; font-weight: 500; }
    .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--dim); display: inline-block; }
    .dot.on { background: var(--ok); }
    .spacer { flex: 1; }
    nav { display: flex; gap: 0; border-bottom: 1px solid var(--line); overflow-x: auto; }
    nav button {
      background: none; border: 0; border-bottom: 1px solid transparent; color: var(--dim);
      font: inherit; padding: 9px 13px; letter-spacing: .12em; white-space: nowrap;
    }
    nav button.active { color: var(--accent); border-bottom-color: var(--accent); }
    section { display: none; padding: 14px; }
    section.active { display: block; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(104px, 1fr)); gap: 1px; background: var(--line); border: 1px solid var(--line); }
    .tile { background: var(--bg); padding: 10px 11px; }
    .tile b { display: block; font-size: 21px; font-weight: 400; letter-spacing: -.01em; }
    .tile span { color: var(--dim); font-size: 10px; letter-spacing: .14em; }
    .spark { display: flex; align-items: flex-end; gap: 2px; height: 34px; margin: 16px 0 4px; }
    .spark i { flex: 1; background: #303030; min-height: 1px; }
    .spark i.hot { background: var(--ink); }
    .row { border-bottom: 1px solid var(--line); padding: 11px 0; display: flex; gap: 10px; align-items: flex-start; }
    .row:last-child { border-bottom: 0; }
    .row .body { flex: 1; min-width: 0; }
    .muted { color: var(--dim); }
    .tag { border: 1px solid var(--line); padding: 1px 5px; color: var(--dim); font-size: 10px; letter-spacing: .1em; }
    .tag.ok { color: var(--ok); border-color: #244; }
    .tag.warn { color: var(--warn); border-color: #443; }
    .tag.bad { color: var(--bad); border-color: #533; }
    button.act, .field input, .field select, .field textarea {
      background: #0b0b0b; color: var(--ink); border: 1px solid var(--line); font: inherit; padding: 6px 9px;
    }
    button.act { letter-spacing: .1em; }
    button.act:active { background: var(--ink); color: #000; }
    .field { display: flex; flex-direction: column; gap: 4px; margin-bottom: 8px; }
    .field label { color: var(--dim); font-size: 10px; letter-spacing: .14em; }
    .field input, .field select, .field textarea { width: 100%; }
    .actions { display: flex; gap: 6px; flex-wrap: wrap; }
    pre { white-space: pre-wrap; word-break: break-word; margin: 6px 0 0; }
    #log { max-height: 62vh; overflow: auto; }
    #log div { border-bottom: 1px solid #121212; padding: 3px 0; }
    .lv-error { color: var(--bad); } .lv-warn { color: var(--warn); } .lv-debug { color: var(--dim); }
    .banner { border: 1px solid var(--line); padding: 10px; color: var(--dim); margin-bottom: 12px; }
  </style>

  <header>
    <span class="dot" id="pulse"></span><h1>STARK</h1>
    <span class="spacer"></span>
    <span class="muted" id="mode">—</span>
  </header>
  <nav>
    <button class="active" data-tab="stats">STATS</button>
    <button data-tab="queue">QUEUE</button>
    <button data-tab="links">LINKS</button>
    <button data-tab="model">MODEL</button>
    <button data-tab="voice">VOICE</button>
    <button data-tab="log">LOG</button>
  </nav>

  <section id="stats" class="active">
    <div class="grid" id="tiles"></div>
    <div class="spark" id="spark"></div>
    <div class="muted">sends per hour, last 24h</div>
    <div class="actions" style="margin-top:14px">
      <button class="act" onclick="post('/api/run').then(load)">RUN NOW</button>
      <button class="act" onclick="post('/api/engine/start').then(load)">START LOOP</button>
      <button class="act" onclick="post('/api/engine/stop').then(load)">STOP LOOP</button>
    </div>
    <div class="field" style="margin-top:14px">
      <label>PUBLISHING MODE</label>
      <select id="modeSelect" onchange="patch({mode:this.value}).then(load)">
        <option value="review">review — every draft waits for you</option>
        <option value="autoWithinGuardrails">auto — send what clears the guardrails</option>
        <option value="dryRun">dry run — draft only, never send</option>
      </select>
    </div>
    <div id="device" class="muted"></div>
  </section>

  <section id="queue">
    <div id="drafts"></div>
  </section>

  <section id="links">
    <div id="connections"></div>
    <h3 class="muted">ADD CONNECTION</h3>
    <div class="field"><label>KIND</label>
      <select id="cKind">
        <option value="mastodon">mastodon</option>
        <option value="telegram">telegram</option>
        <option value="discord">discord</option>
        <option value="webhook">webhook</option>
        <option value="generic">generic REST</option>
      </select>
    </div>
    <div class="field"><label>LABEL</label><input id="cLabel" placeholder="main account"></div>
    <div class="field"><label>ENDPOINT</label><input id="cEndpoint" placeholder="mastodon.social / channel id / url"></div>
    <div class="field"><label>TOKEN</label><input id="cToken" type="password" placeholder="stored in the keychain"></div>
    <button class="act" onclick="addConnection()">CONNECT</button>
    <h3 class="muted" style="margin-top:22px">PRODUCTS</h3>
    <div id="products"></div>
    <div class="field"><label>NAME</label><input id="pName"></div>
    <div class="field"><label>PITCH</label><input id="pPitch" placeholder="what it does, for whom"></div>
    <div class="field"><label>URL</label><input id="pURL"></div>
    <div class="field"><label>KEYWORDS</label><input id="pKeys" placeholder="comma separated"></div>
    <button class="act" onclick="addProduct()">SAVE PRODUCT</button>
  </section>

  <section id="model">
    <div id="modelStatus" class="banner"></div>
    <div id="models"></div>
  </section>

  <section id="voice">
    <div class="banner">Draft against arbitrary text. Nothing is posted.</div>
    <div class="field"><label>INCOMING MESSAGE</label><textarea id="tText" rows="5"></textarea></div>
    <button class="act" onclick="preview()">DRAFT</button>
    <pre id="tOut"></pre>
  </section>

  <section id="log"><div id="logLines"></div></section>

  <script>
    let token = localStorage.getItem('stark_token') || '';
    if (!token) { token = prompt('API token (shown in the app)') || ''; localStorage.setItem('stark_token', token); }
    const H = () => ({ 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' });
    const get = (p) => fetch(p, { headers: H() }).then(r => r.ok ? r.json() : Promise.reject(r.status));
    const post = (p, b) => fetch(p, { method: 'POST', headers: H(), body: b ? JSON.stringify(b) : null });
    const patch = (b) => fetch('/api/config', { method: 'PATCH', headers: H(), body: JSON.stringify(b) });
    const del = (p) => fetch(p, { method: 'DELETE', headers: H() });
    const esc = (s) => (s || '').replace(/[<>&]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c]));
    const ago = (iso) => { if (!iso) return '—'; const s = (Date.now() - new Date(iso)) / 1000;
      return s < 60 ? Math.round(s) + 's' : s < 3600 ? Math.round(s / 60) + 'm' : Math.round(s / 3600) + 'h'; };

    document.querySelectorAll('nav button').forEach(b => b.onclick = () => {
      document.querySelectorAll('nav button').forEach(x => x.classList.toggle('active', x === b));
      document.querySelectorAll('section').forEach(s => s.classList.toggle('active', s.id === b.dataset.tab));
      if (b.dataset.tab === 'model') loadModels();
    });

    async function load() {
      let s;
      try { s = await get('/api/stats'); } catch (e) { document.getElementById('mode').textContent = 'auth?'; return; }
      const m = s.metrics, c = m.counts, d = m.last24h;
      document.getElementById('pulse').className = 'dot' + (s.engineRunning ? ' on' : '');
      document.getElementById('mode').textContent = s.mode + ' · ' + (s.model.modelID || 'no model');
      document.getElementById('modeSelect').value = s.mode;
      document.getElementById('tiles').innerHTML = [
        ['QUEUE', m.queueDepth], ['SENT 24H', d.sent || 0], ['DRAFTED 24H', d.drafted || 0],
        ['BLOCKED 24H', d.blocked || 0], ['SENT ALL', c.sent || 0], ['TOK/S', m.tokensPerSecond.toFixed(1)],
        ['UPTIME', Math.round(m.uptimeSeconds / 60) + 'm'], ['LAST RUN', ago(s.lastRun)],
      ].map(([k, v]) => `<div class="tile"><b>${v}</b><span>${k}</span></div>`).join('');
      const peak = Math.max(1, ...m.sentByHour);
      document.getElementById('spark').innerHTML = m.sentByHour
        .map(v => `<i class="${v ? 'hot' : ''}" style="height:${Math.round(v / peak * 100)}%"></i>`).join('');
      document.getElementById('device').textContent =
        `mem budget ${s.device.memoryBudgetGB.toFixed(1)} GB · disk free ${s.device.freeDiskGB.toFixed(1)} GB`;
      renderConnections(s.connections);
      loadQueue(); loadProducts();
    }

    function health(h) {
      if (!h) return '<span class="tag">unchecked</span>';
      const cls = { ok: 'ok', degraded: 'warn', unauthorized: 'bad', offline: 'bad' }[h.state] || '';
      return `<span class="tag ${cls}">${h.state}</span>`;
    }

    function renderConnections(list) {
      document.getElementById('connections').innerHTML = list.length ? list.map(c => `
        <div class="row"><div class="body">
          <div>${esc(c.label)} <span class="muted">${c.kind}</span> ${health(c.health)} ${c.enabled ? '' : '<span class="tag">paused</span>'}</div>
          <div class="muted">${esc(c.health && c.health.accountHandle || c.endpoint)}${c.health && c.health.detail ? ' · ' + esc(c.health.detail) : ''}</div>
          <div class="actions" style="margin-top:6px">
            <button class="act" onclick="post('/api/connections/${c.id}/verify').then(load)">VERIFY</button>
            <button class="act" onclick="post('/api/connections/${c.id}/toggle').then(load)">${c.enabled ? 'PAUSE' : 'RESUME'}</button>
            <button class="act" onclick="del('/api/connections/${c.id}').then(load)">REMOVE</button>
          </div>
        </div></div>`).join('') : '<div class="muted">nothing connected yet</div>';
    }

    async function loadQueue() {
      const q = await get('/api/queue');
      document.getElementById('drafts').innerHTML = q.length ? q.map(dr => `
        <div class="row"><div class="body">
          <div><span class="tag ${dr.status === 'sent' ? 'ok' : dr.status === 'blocked' ? 'bad' : ''}">${dr.status}</span>
            <span class="muted">${esc(dr.item.authorHandle)} · ${dr.item.platform} · ${ago(dr.createdAt)} ago</span></div>
          <div class="muted" style="margin-top:5px">“${esc(dr.item.text.slice(0, 220))}”</div>
          ${dr.status === 'pending'
            ? `<textarea id="t_${dr.id}" rows="4" style="margin-top:6px">${esc(dr.finalText || dr.text)}</textarea>`
            : `<pre>${esc(dr.editedText || dr.text)}</pre>`}
          ${dr.verdict.reasons.length ? `<div class="muted">↳ ${dr.verdict.reasons.map(esc).join(' · ')}</div>` : ''}
          ${dr.status === 'pending' ? `<div class="actions" style="margin-top:6px">
            <button class="act" onclick="approve('${dr.id}')">APPROVE &amp; SEND</button>
            <button class="act" onclick="post('/api/queue/${dr.id}/reject').then(load)">REJECT</button>
          </div>` : ''}
        </div></div>`).join('') : '<div class="muted">queue empty</div>';
    }

    async function approve(id) {
      const el = document.getElementById('t_' + id);
      const r = await post('/api/queue/' + id + '/approve', { text: el ? el.value : null });
      if (!r.ok) alert((await r.json()).error || 'send failed');
      load();
    }

    async function loadProducts() {
      const p = await get('/api/products');
      document.getElementById('products').innerHTML = p.map(x => `
        <div class="row"><div class="body">
          <div>${esc(x.name)} <span class="muted">${esc(x.url)}</span></div>
          <div class="muted">${esc(x.pitch)}</div>
          <div class="actions" style="margin-top:6px"><button class="act" onclick="del('/api/products/${x.id}').then(load)">REMOVE</button></div>
        </div></div>`).join('');
    }

    async function loadModels() {
      const m = await get('/api/models');
      const s = m.status;
      document.getElementById('modelStatus').textContent =
        `${s.state}${s.modelID ? ' · ' + s.modelID : ''}${s.state === 'downloading' ? ' · ' + Math.round(s.progress * 100) + '%' : ''}${s.detail ? ' · ' + s.detail : ''}`;
      document.getElementById('models').innerHTML = m.catalog.map(x => {
        const fits = m.fits.includes(x.id);
        return `<div class="row"><div class="body">
          <div>${esc(x.name)} <span class="muted">${x.parameters} ${x.quantization} · ${x.diskGB} GB</span>
            ${fits ? '<span class="tag ok">fits</span>' : '<span class="tag warn">too big for this device</span>'}</div>
          <div class="muted">${esc(x.notes)} · ${esc(x.license)}</div>
          <div class="actions" style="margin-top:6px">
            <button class="act" onclick="post('/api/models/load',{id:'${x.id}'}).then(()=>setTimeout(loadModels,600))">LOAD</button>
          </div></div></div>`;
      }).join('');
    }

    async function addConnection() {
      const body = {
        kind: cKind.value, label: cLabel.value || cKind.value,
        endpoint: cEndpoint.value, token: cToken.value,
      };
      const r = await post('/api/connections', body);
      if (r.ok) { cToken.value = ''; cEndpoint.value = ''; cLabel.value = ''; load(); }
      else alert('could not add connection');
    }

    async function addProduct() {
      const body = {
        id: (crypto.randomUUID ? crypto.randomUUID() : 'p' + Date.now()), name: pName.value, pitch: pPitch.value, url: pURL.value,
        facts: [], limitations: [],
        keywords: pKeys.value.split(',').map(s => s.trim()).filter(Boolean),
        negativeKeywords: ['refund', 'scam', 'chargeback'],
      };
      if ((await post('/api/products', body)).ok) { pName.value = pPitch.value = pURL.value = pKeys.value = ''; load(); }
    }

    async function preview() {
      document.getElementById('tOut').textContent = 'thinking…';
      const r = await post('/api/draft', { text: document.getElementById('tText').value });
      const j = await r.json();
      document.getElementById('tOut').textContent = r.ok
        ? j.text + '\n\n— ' + j.verdict.decision + (j.verdict.reasons.length ? ' · ' + j.verdict.reasons.join(' · ') : '')
        : (j.error || 'failed');
    }

    const lines = document.getElementById('logLines');
    const events = new EventSource('/api/events?token=' + encodeURIComponent(token));
    events.addEventListener('log', e => {
      const l = JSON.parse(e.data);
      const div = document.createElement('div');
      div.className = 'lv-' + l.level;
      div.textContent = new Date(l.at).toLocaleTimeString() + ' [' + l.source + '] ' + l.message;
      lines.prepend(div);
      while (lines.children.length > 300) lines.lastChild.remove();
    });

    get('/api/logs').then(ls => ls.forEach(l => {
      const div = document.createElement('div');
      div.className = 'lv-' + l.level;
      div.textContent = new Date(l.at).toLocaleTimeString() + ' [' + l.source + '] ' + l.message;
      lines.append(div);
    }));

    load();
    setInterval(load, 6000);
  </script>
  """#
}
