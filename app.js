(function () {
  const E = window.Engine;
  const { POS, POS_NAME, BASE_NAME, HITS, LEVELS, pt, dist } = E;
  const NS = 'http://www.w3.org/2000/svg';
  const TYPE_COLOR = { field: 'var(--field)', cover: 'var(--cover)', cutoff: 'var(--cutoff)', backup: 'var(--backup)', other: 'var(--other)' };
  const BASE_ORDER = ['H', '1', '2', '3', 'H'];

  let savedLevel = null;
  try { savedLevel = localStorage.getItem('level'); } catch (e) { /* storage unavailable */ }
  const state = {
    level: LEVELS[savedLevel] ? savedLevel : 'll',
    runners: { 1: false, 2: false, 3: false }, outs: 0, hit: 'gb_SS', revealed: false, focus: '', guess: null,
  };
  let G = E.field(state.level);
  let res = null;
  let animId = null;

  const $ = (id) => document.getElementById(id);
  const svg = $('field');
  const S = (p) => ({ x: p.x, y: -p.y }); // feet -> svg coords

  function el(tag, attrs, parent) {
    const n = document.createElementNS(NS, tag);
    for (const k in attrs) n.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(n);
    return n;
  }
  // Actors (dots) are drawn at a fixed size and scaled to the field.
  const move = (node, p) => {
    const s = S(p);
    node.setAttribute('transform', `translate(${s.x.toFixed(2)},${s.y.toFixed(2)}) scale(${G.dot.toFixed(3)})`);
  };
  const lerp = (a, b, t) => pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  const clamp01 = (t) => Math.max(0, Math.min(1, t));
  const ease = (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2);
  const pts = (list) => list.map((p) => { const s = S(p); return `${s.x.toFixed(1)},${s.y.toFixed(1)}`; }).join(' ');

  // Point at fraction t along a polyline.
  function alongPath(path, t) {
    if (path.length === 1) return path[0];
    const segs = [];
    let total = 0;
    for (let i = 1; i < path.length; i++) { const d = dist(path[i - 1], path[i]); segs.push(d); total += d; }
    let want = t * total;
    for (let i = 0; i < segs.length; i++) {
      if (want <= segs[i] || i === segs.length - 1) return lerp(path[i], path[i + 1], segs[i] ? clamp01(want / segs[i]) : 1);
      want -= segs[i];
    }
    return path[path.length - 1];
  }

  // ---------- Field drawing ----------
  const L = {};
  function drawField() {
    svg.innerHTML = '';
    const d = G.dot;
    const k = G.k;
    const halfW = G.line * Math.SQRT1_2 + 30 * d;
    const top = G.center + 16 * d;
    const bottom = 55 * d;
    svg.setAttribute('viewBox', `${-halfW} ${-top} ${2 * halfW} ${top + bottom}`);

    const defs = el('defs', {}, svg);
    const stripes = el('pattern', { id: 'mow', width: 24 * d, height: 24 * d, patternUnits: 'userSpaceOnUse', patternTransform: 'rotate(45)' }, defs);
    el('rect', { width: 24 * d, height: 24 * d, fill: '#2f7a3a' }, stripes);
    el('rect', { width: 12 * d, height: 24 * d, fill: '#2a7034' }, stripes);
    const m = el('marker', { id: 'arrow', viewBox: '0 0 10 10', refX: 8, refY: 5, markerWidth: 5, markerHeight: 5, orient: 'auto-start-reverse' }, defs);
    el('path', { d: 'M0,0 L10,5 L0,10 z', fill: '#facc15' }, m);
    // Infield dirt stays in fair territory (plus a strip past the foul lines for the bags).
    const clip = el('clipPath', { id: 'fair' }, defs);
    const a = 16 * k;
    el('polygon', { points: `0,${a} -1000,${a - 1000} 1000,${a - 1000}` }, clip);

    const arc = (r) => {
      const list = [pt(0, 0)];
      for (let deg = -45; deg <= 45; deg += 3) list.push(G.polar(deg, r(deg)));
      return pts(list);
    };
    el('polygon', { points: arc((deg) => G.fenceAt(deg)), fill: '#9a6b3c' }, svg); // warning track
    el('polygon', { points: arc((deg) => G.fenceAt(deg) - 11 * d), fill: 'url(#mow)' }, svg);
    const fence = [];
    for (let deg = -45; deg <= 45; deg += 3) fence.push(G.polar(deg, G.fenceAt(deg)));
    el('polyline', { points: pts(fence), fill: 'none', stroke: '#e5e7eb', 'stroke-width': 2 * d }, svg);

    // Fence distance markers
    // Labels sit just outside the fence (corner ones a little in from the pole), clear of
    // players chasing balls into the corners.
    for (const deg of [-45, 0, 45]) {
      const at = deg === 0 ? 0 : Math.sign(deg) * 39;
      const p = G.polar(at, G.fenceAt(at) + 9 * d);
      const t = el('text', { x: S(p).x, y: S(p).y, class: 'tag', 'font-size': 8 * d, 'stroke-width': 0 }, svg);
      t.textContent = `${Math.round(G.fenceAt(deg))}'`;
    }

    const dirt = '#c08552';
    el('circle', { cx: 0, cy: -G.MOUND.y, r: 95 * k, fill: dirt, 'clip-path': 'url(#fair)' }, svg);
    el('polygon', { points: pts([pt(0, 15 * k), pt(50 * k, 63.6 * k), pt(0, 112 * k), pt(-50 * k, 63.6 * k)]), fill: '#2f7a3a' }, svg);
    el('circle', { cx: 0, cy: 0, r: 13 * k, fill: dirt }, svg);
    el('circle', { cx: 0, cy: -G.MOUND.y, r: 9 * k, fill: dirt }, svg);
    el('rect', { x: -3 * k, y: -G.MOUND.y - 0.6, width: 6 * k, height: 1.2, fill: '#fff' }, svg);

    const c = G.polar(45, G.line);
    el('line', { x1: 0, y1: 0, x2: -c.x, y2: -c.y, stroke: '#fff', 'stroke-width': 1.2 * d }, svg);
    el('line', { x1: 0, y1: 0, x2: c.x, y2: -c.y, stroke: '#fff', 'stroke-width': 1.2 * d }, svg);
    el('path', { d: 'M0,4 L3,1 L3,-2 L-3,-2 L-3,1 Z', fill: '#fff', transform: `scale(${d})` }, svg); // home plate

    L.hot = el('g', {}, svg);
    for (const b of ['1', '2', '3']) {
      const s = S(G.BASES[b]);
      const g2 = el('g', { class: 'base-hot' }, L.hot);
      el('circle', { cx: s.x, cy: s.y, r: 13 * d, fill: 'transparent' }, g2);
      const bag = 3.5 * d;
      el('rect', { x: s.x - bag, y: s.y - bag, width: 2 * bag, height: 2 * bag, fill: '#fff', transform: `rotate(45 ${s.x} ${s.y})` }, g2);
      g2.addEventListener('click', (e) => {
        if (isGuessing()) return;
        e.stopPropagation();
        state.runners[b] = !state.runners[b];
        changed();
      });
    }

    L.trails = el('g', {}, svg);
    L.throws = el('g', {}, svg);
    L.guess = el('g', {}, svg);
    L.runners = el('g', {}, svg);
    L.fielders = el('g', {}, svg);
    L.ball = el('circle', { r: 3, fill: '#fff', stroke: '#b91c1c', 'stroke-width': 0.8, visibility: 'hidden' }, svg);

    L.f = {};
    for (const p of POS) {
      const g3 = el('g', { class: 'actor' }, L.fielders);
      const circ = el('circle', { r: 8.5, fill: '#1e3a8a', stroke: '#fff', 'stroke-width': 2 }, g3);
      const t = el('text', { 'font-size': p.length > 1 ? 6.5 : 7.5, fill: '#fff' }, g3);
      t.textContent = p;
      g3.addEventListener('click', (e) => {
        if (!state.revealed) return;
        e.stopPropagation();
        setFocus(state.focus === p ? '' : p);
      });
      L.f[p] = { g: g3, circ };
    }
  }

  svg.addEventListener('click', (e) => {
    if (!isGuessing()) return;
    const m = svg.createSVGPoint();
    m.x = e.clientX;
    m.y = e.clientY;
    const q = m.matrixTransform(svg.getScreenCTM().inverse());
    state.guess = pt(q.x, -q.y);
    drawGuess();
    renderPanel();
  });

  const isGuessing = () => !!state.focus && !state.revealed;

  function drawGuess() {
    L.guess.innerHTML = '';
    if (!state.guess) return;
    const g = el('g', {}, L.guess);
    move(g, state.guess);
    el('circle', { r: 9, fill: 'rgba(250,204,21,0.25)', stroke: '#facc15', 'stroke-width': 1.5, 'stroke-dasharray': '3 2' }, g);
    const t = el('text', { class: 'tag', y: 2.5, 'font-size': 8 }, g);
    t.textContent = '?';
  }

  // ---------- Runners ----------
  function runnerNodes() {
    L.runners.innerHTML = '';
    const list = [];
    const add = (id, base) => {
      const g = el('g', { class: 'actor' }, L.runners);
      el('circle', { r: 6.5, fill: 'var(--runner)', stroke: '#fff', 'stroke-width': 1.5 }, g);
      const t = el('text', { 'font-size': 5, fill: '#fff' }, g);
      t.textContent = id;
      move(g, G.runnerPt(base));
      list.push({ id, g, base });
    };
    add('B', 'H');
    for (const b of ['1', '2', '3']) if (state.runners[b]) add('R' + b, b);
    return list;
  }

  function runnerPath(m, scoredIndex) {
    if (m.endPt) return [G.runnerPt(m.from), m.endPt];
    const i = m.from === 'H' ? 0 : BASE_ORDER.indexOf(m.from);
    const j = m.to === 'H' ? 4 : BASE_ORDER.indexOf(m.to);
    const path = [];
    for (let k = i; k <= j; k++) path.push(G.runnerPt(BASE_ORDER[k]));
    // Runners who score walk off toward the dugout; the one being thrown at stays at the plate.
    if (m.to === 'H' && m.from !== 'H' && !res.played.includes(m.id)) path.push(pt((-16 - 12 * scoredIndex) * G.dot, -14 * G.dot));
    return path;
  }

  // ---------- Board state ----------
  function resetBoard() {
    cancelAnimationFrame(animId);
    state.revealed = false;
    res = null;
    L.trails.innerHTML = '';
    L.throws.innerHTML = '';
    L.ball.setAttribute('visibility', 'hidden');
    for (const p of POS) {
      move(L.f[p].g, G.HOME_POS[p]);
      L.f[p].circ.setAttribute('stroke', '#fff');
    }
    L.runnerList = runnerNodes();
    drawGuess();
    svg.classList.toggle('guessing', isGuessing());
    $('showBtn').textContent = '▶ Show me!';
    applyDim();
    renderSituation();
    renderPanel();
  }

  function reveal() {
    cancelAnimationFrame(animId);
    res = E.solve(state);
    state.revealed = true;
    svg.classList.remove('guessing');
    $('showBtn').textContent = '↻ Replay';
    L.trails.innerHTML = '';
    L.throws.innerHTML = '';
    L.runnerList = runnerNodes();

    const fielders = POS.map((p) => ({ p, from: G.HOME_POS[p], to: res.A[p].to }));
    POS.forEach((p) => {
      L.f[p].circ.setAttribute('stroke', TYPE_COLOR[res.A[p].type]);
      move(L.f[p].g, G.HOME_POS[p]);
    });
    let scored = 0;
    const runs = res.runners.map((m) => {
      const node = L.runnerList.find((n) => n.id === m.id);
      const path = runnerPath(m, m.to === 'H' && !res.played.includes(m.id) ? scored++ : 0);
      return { m, node, path };
    });
    const isFly = res.hit.kind === 'fly' || res.hit.kind === 'gap';
    const throwPath = res.throwPath;

    // Throw line (hidden until the throw starts)
    const throwG = el('g', { opacity: 0 }, L.throws);
    const start = res.carry ? 1 : 0;
    if (throwPath.length - start > 1) {
      el('polyline', {
        points: pts(throwPath.slice(start)), fill: 'none', stroke: '#facc15', 'stroke-width': 1.8 * G.dot,
        'stroke-dasharray': `${5 * G.dot} ${3 * G.dot}`, 'marker-end': 'url(#arrow)', 'stroke-linejoin': 'round',
      }, throwG);
    }

    // Throws that might happen (what the backups are lined up for)
    for (const alt of res.altThrows) {
      el('polyline', {
        points: pts(alt), fill: 'none', stroke: '#e5e7eb', 'stroke-width': 1.2 * G.dot, opacity: 0.7,
        'stroke-dasharray': `${1.5 * G.dot} ${3 * G.dot}`, 'stroke-linecap': 'round',
      }, throwG);
    }

    L.ball.setAttribute('visibility', 'visible');
    const setBall = (p, r) => {
      const s = S(p);
      L.ball.setAttribute('cx', s.x);
      L.ball.setAttribute('cy', s.y);
      L.ball.setAttribute('r', r * G.dot);
    };
    const t0 = performance.now();
    const D = 3600;
    function frame(now) {
      const ms = now - t0;
      // Batted ball (grows in the air on fly balls)
      const hb = clamp01(ms / 750);
      if (ms < 2000 || throwPath.length < 2) {
        setBall(lerp(pt(0, 0), res.ball, isFly ? hb : ease(hb)), isFly ? 3 + 4 * Math.sin(Math.PI * hb) : 3);
      }
      const fu = ease(clamp01((ms - 150) / 1850));
      for (const f of fielders) move(L.f[f.p].g, lerp(f.from, f.to, fu));
      const ru = clamp01((ms - 150) / 2500);
      for (const r of runs) if (r.node) move(r.node.g, alongPath(r.path, ease(ru)));
      if (throwPath.length > 1 && ms >= 1900) {
        throwG.setAttribute('opacity', clamp01((ms - 1900) / 300));
        setBall(alongPath(throwPath, clamp01((ms - 2000) / 1300)), 3);
      }
      if (ms < D) animId = requestAnimationFrame(frame);
      else finish(fielders, runs);
    }
    animId = requestAnimationFrame(frame);
    applyDim();
    renderPanel();
  }

  function finish(fielders, runs) {
    // Movement trails so you can see who went where
    for (const f of fielders) {
      if (dist(f.from, f.to) < 4) continue;
      el('line', {
        x1: f.from.x, y1: -f.from.y, x2: f.to.x, y2: -f.to.y, 'data-p': f.p,
        stroke: TYPE_COLOR[res.A[f.p].type], 'stroke-width': G.dot, 'stroke-dasharray': `${2 * G.dot} ${2.5 * G.dot}`, opacity: 0.55,
      }, L.trails);
    }
    for (const r of runs) {
      if (r.path.length > 1 && dist(r.path[0], r.path[r.path.length - 1]) > 2) {
        el('polyline', { points: pts(r.path), fill: 'none', stroke: '#ef4444', 'stroke-width': G.dot, 'stroke-dasharray': `${2 * G.dot} ${2 * G.dot}`, opacity: 0.6 }, L.trails);
      }
      if (!r.node) continue;
      const played = res.played.includes(r.m.id);
      if (r.m.out || played) {
        const t = el('text', { class: 'tag', y: -9 }, r.node.g);
        t.textContent = r.m.out ? 'OUT' : 'THROW HERE';
        if (r.m.out) r.node.g.classList.add('dim');
      }
      if (played) el('circle', { r: 9.5, fill: 'none', stroke: '#facc15', 'stroke-width': 1.2 }, r.node.g);
    }
    applyDim();
  }

  function applyDim() {
    const f = state.revealed ? state.focus : '';
    for (const p of POS) L.f[p].g.classList.toggle('dim', !!f && p !== f);
    for (const line of L.trails.querySelectorAll('line')) line.setAttribute('opacity', !f || line.dataset.p === f ? 0.55 : 0.12);
  }

  // ---------- Text ----------
  function runnersText() {
    const on = ['1', '2', '3'].filter((b) => state.runners[b]);
    if (!on.length) return 'Bases empty';
    if (on.length === 3) return 'Bases loaded';
    return `Runner${on.length > 1 ? 's' : ''} on ${on.map((b) => BASE_NAME[b]).join(' & ')}`;
  }

  function renderSituation() {
    $('sitText').textContent = `${runnersText()} · ${HITS[state.hit].text}`;
    $('levelDetail').textContent = LEVELS[state.level].detail;
    const od = $('outDots');
    od.innerHTML = 'OUTS ';
    for (let i = 0; i < 2; i++) {
      const d = document.createElement('i');
      if (i < state.outs) d.className = 'on';
      od.appendChild(d);
    }
    document.querySelectorAll('#levelBtns .chip').forEach((b) => b.classList.toggle('on', b.dataset.l === state.level));
    document.querySelectorAll('#runnerBtns .chip').forEach((b) => b.classList.toggle('on', state.runners[b.dataset.b]));
    document.querySelectorAll('#outBtns .chip').forEach((b) => b.classList.toggle('on', +b.dataset.o === state.outs));
    document.querySelectorAll('#hitBtns .chip').forEach((b) => b.classList.toggle('on', b.dataset.h === state.hit));
  }

  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  function renderPanel() {
    const box = $('answer');
    const f = state.focus;
    if (!state.revealed) {
      let my = '';
      if (f) {
        my = `<div class="mycard"><div class="score">You're the ${esc(POS_NAME[f])}</div>${
          state.guess ? 'Guess placed! Tap again to move it, or hit <b>Show me</b>.' : 'Tap the field where you should go when the ball is hit.'}</div>`;
      }
      box.innerHTML = `${my}<div class="think"><h2>Think first</h2><ol>
        <li><b>How many outs?</b> ${state.outs === 2 ? 'Two — just get one out!' : 'Less than two.'}</li>
        <li><b>Where are the runners?</b> Is there a force play?</li>
        <li><b>If the ball is hit to me,</b> where do I throw? <b>If it's not,</b> where do I go — cover a base, back someone up, or be the cutoff?</li>
      </ol></div>`;
      return;
    }

    let my = '';
    if (f) {
      const a = res.A[f];
      let score = '';
      if (state.guess) {
        // Allow more slop on bigger fields.
        const tol = 25 * (G.center / 300);
        const d = dist(state.guess, a.to);
        score = d < tol ? '🎯 Right on!' : d < 2.2 * tol ? '👍 Close!' : '🤔 Not quite — watch where you go.';
      }
      my = `<div class="mycard">${score ? `<div class="score">${score}</div>` : ''}<b>${esc(POS_NAME[f])}:</b> ${esc(a.job)}</div>`;
    }
    const tips = res.tips.length ? `<ul class="tips">${res.tips.map((t) => `<li>${esc(t)}</li>`).join('')}</ul>` : '';
    const jobs = POS.map((p) => {
      const a = res.A[p];
      return `<li data-p="${p}" class="${p === f ? 'sel' : ''}"><span class="dot" style="--c:${TYPE_COLOR[a.type]}">${p}</span><span class="job">${esc(a.job)}</span></li>`;
    }).join('');
    const runners = res.runners.map((m) => {
      const who = m.id === 'B' ? 'Batter' : `Runner on ${BASE_NAME[m.from]}`;
      let what;
      if (m.out) what = 'Out when the ball is caught';
      else if (m.to === m.from) what = m.note || 'Stays';
      else what = `${m.to === 'H' ? 'Heads home' : `Goes to ${BASE_NAME[m.to]}`}${m.note ? ` — ${m.note}` : ''}`;
      return `<li><span class="dot runner-dot">${m.id}</span><span class="job"><b>${who}:</b> ${esc(what)}</span></li>`;
    }).join('');

    box.innerHTML = `${my}<p class="headline">${esc(res.headline)}</p><p class="why">${esc(res.why)}</p>${tips}
      <h3>Everyone's job</h3><ul class="jobs" id="jobList">${jobs}</ul>
      <h3>Runners</h3><ul class="jobs">${runners}</ul>${sourcesHtml(res.rules)}`;
    $('jobList').querySelectorAll('li').forEach((li) => li.addEventListener('click', () => setFocus(state.focus === li.dataset.p ? '' : li.dataset.p)));
  }

  // "Where this comes from": the published-source check for each rule this play used.
  const VERDICT = { confirmed: 'Matches sources', partly: 'Varies by coach', judgment: 'Our choice', contradicted: 'Differs from sources' };
  function sourcesHtml(ids) {
    const all = window.SOURCES || {};
    const items = ids.filter((id) => all[id]).map((id) => {
      const x = all[id];
      const links = (x.links || []).map((l) => `<a href="${esc(l.url)}" target="_blank" rel="noopener">${esc(l.name)}</a>`).join(' · ');
      return `<li><span class="verdict v-${x.verdict}">${VERDICT[x.verdict] || x.verdict}</span> <b>${esc(x.rule)}</b>
        <div class="src-note">${esc(x.note)}</div>${links ? `<div class="src-links">${links}</div>` : ''}</li>`;
    }).join('');
    return items ? `<details class="sources"><summary>Where this comes from (${ids.filter((id) => all[id]).length})</summary><ul>${items}</ul></details>` : '';
  }

  function setFocus(p) {
    state.focus = p;
    $('focusSel').value = p;
    if (!state.revealed) {
      state.guess = null;
      drawGuess();
      svg.classList.toggle('guessing', isGuessing());
    }
    applyDim();
    renderPanel();
  }

  function changed() {
    state.guess = null;
    resetBoard();
  }

  function setLevel(l) {
    state.level = l;
    try { localStorage.setItem('level', l); } catch (e) { /* storage unavailable */ }
    G = E.field(l);
    cancelAnimationFrame(animId);
    drawField();
    changed();
  }

  // ---------- Controls ----------
  function chip(label, data, onClick) {
    const b = document.createElement('button');
    b.className = 'chip';
    b.textContent = label;
    Object.assign(b.dataset, data);
    b.addEventListener('click', onClick);
    return b;
  }

  function buildControls() {
    for (const [l, lv] of Object.entries(LEVELS)) {
      $('levelBtns').appendChild(chip(lv.name, { l }, () => setLevel(l)));
    }
    for (const b of ['1', '2', '3']) {
      $('runnerBtns').appendChild(chip(BASE_NAME[b], { b }, () => { state.runners[b] = !state.runners[b]; changed(); }));
    }
    for (const o of [0, 1, 2]) {
      $('outBtns').appendChild(chip(String(o), { o }, () => { state.outs = o; changed(); }));
    }
    const groups = {};
    for (const [key, h] of Object.entries(HITS)) (groups[h.group] ||= []).push([key, h]);
    for (const [name, items] of Object.entries(groups)) {
      const wrap = document.createElement('div');
      wrap.className = 'hitgroup';
      wrap.innerHTML = `<h3>${name}</h3>`;
      const seg = document.createElement('div');
      seg.className = 'seg';
      for (const [key, h] of items) seg.appendChild(chip(h.label, { h: key }, () => { state.hit = key; changed(); }));
      wrap.appendChild(seg);
      $('hitBtns').appendChild(wrap);
    }
    const sel = $('focusSel');
    sel.innerHTML = '<option value="">Everyone (no quiz)</option>' + POS.map((p) => `<option value="${p}">${p} — ${POS_NAME[p]}</option>`).join('');
    sel.addEventListener('change', () => setFocus(sel.value));

    $('showBtn').addEventListener('click', reveal);
    $('randomBtn').addEventListener('click', randomize);
    document.addEventListener('keydown', (e) => {
      if (['SELECT', 'BUTTON'].includes(e.target.tagName)) return;
      if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); reveal(); }
      if (e.key === 'r') randomize();
    });
  }

  function randomize() {
    for (const b of ['1', '2', '3']) state.runners[b] = Math.random() < 0.4;
    state.outs = Math.floor(Math.random() * 3);
    const keys = Object.keys(HITS);
    state.hit = keys[Math.floor(Math.random() * keys.length)];
    changed();
  }

  drawField();
  buildControls();
  resetBoard();
})();
