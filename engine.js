// Situation engine. Coordinates are in feet: home plate is (0,0), +x toward
// first base / right field, +y toward center field.
(function (root) {
  const pt = (x, y) => ({ x, y });
  const add = (a, b) => pt(a.x + b.x, a.y + b.y);
  const sub = (a, b) => pt(a.x - b.x, a.y - b.y);
  const mul = (a, k) => pt(a.x * k, a.y * k);
  const len = (a) => Math.hypot(a.x, a.y);
  const dist = (a, b) => len(sub(a, b));
  const unit = (a) => mul(a, 1 / (len(a) || 1));
  // Point d feet from a toward b.
  const along = (a, b, d) => add(a, mul(unit(sub(b, a)), d));
  // Point d feet past `to`, continuing the line from `from` (where a backup stands).
  const beyond = (from, to, d) => add(to, mul(unit(sub(to, from)), d));
  const DEG = Math.PI / 180;
  // Angle in degrees from the center-field line (negative = left field).
  const polar = (deg, r) => pt(r * Math.sin(deg * DEG), r * Math.cos(deg * DEG));
  const angleOf = (p) => Math.atan2(p.x, p.y) / DEG;

  // Field sizes. `ofDepth` is how deep outfielders play as a fraction of the fence.
  // `doubleCut`: big enough field that gap balls need a relay man AND a trail man.
  const LEVELS = {
    ll: {
      name: 'Little League', detail: "60' bases · 46' mound · 200' fence",
      bases: 60, mound: 46, line: 200, center: 200, ofDepth: 0.8, doubleCut: false,
    },
    u14: {
      name: '13U / 14U', detail: "80' bases · 54' mound · ~300' fence",
      bases: 80, mound: 54, line: 290, center: 310, ofDepth: 0.84, doubleCut: true,
    },
    hs: {
      name: 'High School', detail: "90' bases · 60'6\" mound · 330' lines, 390' center",
      bases: 90, mound: 60.5, line: 330, center: 390, ofDepth: 0.84, doubleCut: true,
    },
  };

  const POS = ['P', 'C', '1B', '2B', 'SS', '3B', 'LF', 'CF', 'RF'];
  const POS_NAME = {
    P: 'Pitcher', C: 'Catcher', '1B': 'First Baseman', '2B': 'Second Baseman', SS: 'Shortstop',
    '3B': 'Third Baseman', LF: 'Left Fielder', CF: 'Center Fielder', RF: 'Right Fielder',
  };
  const BASE_NAME = { 1: '1st', 2: '2nd', 3: '3rd', H: 'home' };
  const toBase = (b) => (b === 'H' ? 'home' : `to ${BASE_NAME[b]}`);

  const HITS = {
    gb_P: { kind: 'ground', to: 'P', group: 'Ground ball', label: 'P', text: 'Ground ball back to the pitcher' },
    gb_1B: { kind: 'ground', to: '1B', group: 'Ground ball', label: '1B', text: 'Ground ball to first base' },
    gb_2B: { kind: 'ground', to: '2B', group: 'Ground ball', label: '2B', text: 'Ground ball to second base' },
    gb_SS: { kind: 'ground', to: 'SS', group: 'Ground ball', label: 'SS', text: 'Ground ball to shortstop' },
    gb_3B: { kind: 'ground', to: '3B', group: 'Ground ball', label: '3B', text: 'Ground ball to third base' },
    bunt: { kind: 'bunt', group: 'Bunt', label: 'Bunt', text: 'Bunt down the third-base line' },
    fly_LF: { kind: 'fly', to: 'LF', group: 'Fly ball (caught)', label: 'LF', text: 'Fly ball to left field' },
    fly_CF: { kind: 'fly', to: 'CF', group: 'Fly ball (caught)', label: 'CF', text: 'Fly ball to center field' },
    fly_RF: { kind: 'fly', to: 'RF', group: 'Fly ball (caught)', label: 'RF', text: 'Fly ball to right field' },
    single_LF: { kind: 'single', to: 'LF', group: 'Base hit (single)', label: 'LF', text: 'Base hit to left field' },
    single_CF: { kind: 'single', to: 'CF', group: 'Base hit (single)', label: 'CF', text: 'Base hit to center field' },
    single_RF: { kind: 'single', to: 'RF', group: 'Base hit (single)', label: 'RF', text: 'Base hit to right field' },
    gap_LC: { kind: 'gap', to: 'CF', side: 'L', group: 'Gap hit (double)', label: 'Left-center', text: 'Double into the left-center gap' },
    gap_RC: { kind: 'gap', to: 'CF', side: 'R', group: 'Gap hit (double)', label: 'Right-center', text: 'Double into the right-center gap' },
  };

  // Build the geometry for one level. Infield spots come from a 90-ft template
  // scaled by k; outfield spots are fractions of the fence distance.
  function makeField(key) {
    const L = LEVELS[key];
    const k = L.bases / 90;
    const fenceAt = (deg) => {
      const a = Math.min(45, Math.abs(deg));
      return L.line + (L.center - L.line) * Math.cos(2 * a * DEG);
    };
    const inFence = (p, margin) => {
      const r = fenceAt(angleOf(p)) - margin;
      return len(p) > r ? mul(unit(p), r) : p;
    };
    const s = (x, y) => pt(x * k, y * k);
    const of = (deg, f) => polar(deg, f * fenceAt(deg));
    const b = L.bases / Math.SQRT2;
    const BASES = { 1: pt(b, b), 2: pt(0, 2 * b), 3: pt(-b, b), H: pt(0, 0) };
    const MOUND = pt(0, L.mound);
    // Visual size of dots relative to the original 300-ft drawing.
    const dot = (L.line * Math.SQRT1_2 + 30) / 250;
    const flyF = Math.min(L.ofDepth + 0.07, 0.95);
    const HOME_POS = {
      P: pt(0, L.mound - 2.5 * k), C: pt(0, -6), '1B': s(70, 88), '2B': s(38, 140), SS: s(-38, 140),
      '3B': s(-68, 86), LF: of(-32, L.ofDepth), CF: of(0, L.ofDepth), RF: of(32, L.ofDepth),
    };
    const BALL = {
      gb_P: s(-4, 48), gb_1B: s(60, 94), gb_2B: s(30, 128), gb_SS: s(-30, 128), gb_3B: s(-60, 94), bunt: s(-14, 26),
      fly_LF: of(-32, flyF), fly_CF: of(0, flyF), fly_RF: of(32, flyF),
      single_LF: of(-31, 0.6), single_CF: of(0, 0.6), single_RF: of(31, 0.6),
      gap_LC: of(-21, 0.94), gap_RC: of(21, 0.94),
    };
    const coverPt = (base) => (base === 'H' ? pt(0, -3) : along(BASES[base], MOUND, 3 * dot));
    const runnerPt = (base) => (base === 'H' ? mul(pt(-13, 3), dot) : beyond(pt(0, b), BASES[base], 15 * dot));
    return { ...L, key, k, dot, BASES, MOUND, HOME_POS, BALL, fenceAt, inFence, polar, coverPt, runnerPt };
  }

  const FIELDS = {};
  const field = (key) => (FIELDS[key] ||= makeField(key));

  // Current field for the solve in progress.
  let G;

  // Who covers a base on an infield ground ball fielded by F.
  function infieldCoverer(base, F) {
    if (base === '1') return F === '1B' ? 'P' : '1B';
    if (base === '2') {
      if (F === 'P') return 'SS';
      return F === 'SS' || F === '3B' ? '2B' : 'SS';
    }
    if (base === '3') return '3B';
    return 'C';
  }

  const anyRunners = (r) => r[1] || r[2] || r[3];

  function solve(sit) {
    G = field(sit.level || 'll');
    const h = HITS[sit.hit];
    const r = { 1: !!sit.runners[1], 2: !!sit.runners[2], 3: !!sit.runners[3] };
    const outs = sit.outs;
    const A = {};
    // First assignment wins, so specific jobs are set before general ones.
    const set = (p, to, job, type) => {
      if (!A[p]) A[p] = { to, job, type };
    };
    const res = {
      A, hit: h, ball: G.BALL[sit.hit], throwPath: [], altThrows: [], carry: false, rules: [], runners: [], target: null,
      headline: '', why: '', tips: [], played: [],
    };
    KINDS[h.kind](h, res.ball, r, outs, set, res);
    res.rules.unshift({ ll: 'D1', u14: 'D2', hs: 'D3' }[G.key]);
    res.rules = [...new Set(res.rules)];
    POS.forEach((p) => set(p, G.HOME_POS[p], 'Stay ready in your spot', 'other'));
    let played = res.runners.filter((m) => res.target && m.to === res.target && !m.out);
    // Several runners heading home: the throw is for the trailing one.
    if (res.target === 'H' && played.length > 1) played = [played.reduce((a, b) => (a.from < b.from ? a : b))];
    res.played = played.map((m) => m.id);
    if (res.dp) res.played.push('B');
    return res;
  }

  // ---------- Ground balls ----------
  function ground(h, ball, r, outs, set, res) {
    const { BASES, HOME_POS, k: K } = G;
    const F = h.to;
    const f2 = r[1];
    const f3 = r[1] && r[2];
    const fH = r[1] && r[2] && r[3];
    let target;
    let dp = false;

    if (outs === 2) {
      const opts = ['1'];
      if (f2) opts.push('2');
      if (f3) opts.push('3');
      if (fH) opts.push('H');
      target = opts.reduce((a, b) => (dist(ball, BASES[b]) < dist(ball, BASES[a]) ? b : a));
      res.why = opts.length > 1
        ? `Two outs — you only need ONE out to end the inning. Take the closest force play: ${BASE_NAME[target]}.`
        : 'Two outs — throw the batter out at 1st to end the inning.';
    } else if (fH) {
      target = 'H';
      dp = true;
      res.why = 'Bases loaded with less than 2 outs — get the force at home to stop the run. The catcher then throws to 1st for a double play.';
    } else if (f2) {
      target = '2';
      dp = true;
      res.why = 'Runner on 1st with less than 2 outs — turn two! Get the lead runner at 2nd, then throw to 1st.';
    } else {
      target = '1';
      res.why = r[2] || r[3]
        ? 'The only force play is at 1st. Look the runner back to their base first (freeze them with your eyes), then throw to 1st.'
        : 'Nobody on base — field it cleanly and throw the batter out at 1st.';
    }
    res.target = target;
    res.dp = dp;
    res.rules.push(outs === 2 ? 'G1' : fH ? 'G3' : f2 ? 'G2' : 'G4', 'G5');
    if (F === '1B' || F === '2B') res.rules.push('G6');
    if (F === '3B' && r[2]) res.rules.push('G7');
    if (!r[2] && !r[3]) res.rules.push('G8');
    res.rules.push('G9');
    if (anyRunners(r)) res.rules.push('G10');

    const tName = BASE_NAME[target];
    const cov = infieldCoverer(target, F);
    const selfPlay = cov === F;
    let fieldJob = selfPlay ? `Field it and step on ${tName} yourself` : `Field the grounder and throw ${toBase(target)}`;
    if (dp) fieldJob += ' — start the double play!';
    set(F, selfPlay ? G.coverPt(target) : ball, fieldJob, 'field');

    res.throwPath = [ball, BASES[target]];
    res.carry = selfPlay;
    if (!selfPlay) {
      set(cov, G.coverPt(target), dp ? `Cover ${tName}, get the force, then throw to 1st` : `Cover ${tName} and catch the throw`, 'cover');
    }
    if (dp) res.throwPath.push(BASES[1]);

    const c1 = F === '1B' ? 'P' : '1B';
    set(c1, G.coverPt('1'), F === '1B' ? 'Sprint over and cover 1st base!' : 'Cover 1st base', 'cover');
    set(infieldCoverer('2', F), G.coverPt('2'), 'Cover 2nd base', 'cover');
    if (F === '3B') {
      if (r[2] && !selfPlay) set('SS', G.coverPt('3'), 'Cover 3rd — the third baseman left the bag', 'cover');
      else set('SS', beyond(BASES.H, ball, 22 * K), 'Back up the third baseman', 'backup');
    } else {
      set('3B', G.coverPt('3'), 'Cover 3rd base', 'cover');
    }

    if (!r[2] && !r[3]) set('C', beyond(ball, BASES[1], 18 * K), 'Run down the line and back up the throw to 1st', 'backup');
    else set('C', G.coverPt('H'), 'Stay home — protect the plate', 'cover');

    if (F === '2B') set('P', along(HOME_POS.P, BASES[1], 40 * K), 'Break toward 1st on any ball hit to your left', 'other');
    set('P', along(HOME_POS.P, BASES[target], 12 * K), 'Get off the mound and be ready to help', 'other');

    if (F === '1B') set('2B', along(BASES[1], BASES[2], 0.35 * G.bases), 'Move toward 1st in case the pitcher is late', 'other');
    if (F === 'P') set('2B', beyond(ball, BASES[2], 18 * K), 'Back up the shortstop at 2nd', 'backup');

    const p = res.throwPath;
    const src1 = p[p.length - 1] === BASES[1] ? p[p.length - 2] : ball;
    set('RF', beyond(src1, BASES[1], 42 * K), 'Back up 1st base in case of an overthrow', 'backup');
    set('CF', along(BASES[2], HOME_POS.CF, 45 * K),
      ['P', 'SS', '2B'].includes(F) ? 'Charge in — back up the ball up the middle and 2nd base' : 'Back up 2nd base', 'backup');
    if (F === '3B' || F === 'SS') set('LF', beyond(BASES.H, ball, 55 * K), `Charge in and back up the ${POS_NAME[F].toLowerCase()}`, 'backup');
    else set('LF', beyond(ball, BASES[3], 40 * K), 'Back up 3rd base', 'backup');

    // Runners
    res.runners.push({ id: 'B', from: 'H', to: '1' });
    if (r[1]) res.runners.push({ id: 'R1', from: '1', to: '2' });
    if (r[2]) {
      const go = f3 || outs === 2 || F === '1B' || F === '2B';
      res.runners.push({ id: 'R2', from: '2', to: go ? '3' : '2', note: go ? '' : 'Holds — ball hit in front of them' });
    }
    if (r[3]) {
      const go = fH || outs === 2;
      res.runners.push({ id: 'R3', from: '3', to: go ? 'H' : '3', note: go ? '' : 'Holds — not forced' });
    }

    res.headline = selfPlay ? `Step on ${tName}!` : dp ? `Throw ${toBase(target)}, then 1st — double play!` : `Throw ${toBase(target)}!`;
    if (r[3] && !fH && outs < 2) res.tips.push('If the infield is playing in to stop the run, throw home to get the runner from 3rd instead.');
    if (F === '1B' && target === '1') res.tips.push('If you are close to the bag, just step on it yourself. If not, flip to the pitcher covering.');
    if (dp && G.key === 'll') res.tips.push('Little League double plays are hard — the must-have out is the lead runner. Get that one first, then try for two.');
    if (outs === 2) res.tips.push('With 2 outs, every runner takes off on contact.');
  }

  // ---------- Outfield throws ----------
  // Ball in front of the outfielder: one cutoff man lines up. Ball past them
  // (gap/wall): a relay man goes out, plus a trail man on big fields.
  function ofPlay(F, src, target, r, set, res, opts) {
    const { BASES: B, k: K } = G;
    const T = B[target];
    const d = dist(src, T);
    if (opts.relay) {
      const left = src.x <= 0;
      const lead = left ? 'SS' : '2B';
      const other = left ? '2B' : 'SS';
      const trail = G.doubleCut;
      const leadPt = along(src, T, 0.4 * d);
      set(lead, leadPt, 'Relay man — run out toward the ball, arms up, and yell!', 'cutoff');
      if (trail) set(other, along(leadPt, T, 32 * K), 'Trail the relay man by ~30 feet — catch a bad throw and yell where it goes', 'cutoff');
      set('C', G.coverPt('H'), 'Cover home', 'cover');
      if (target === 'H') {
        // 1B is the cutoff in front of home on every field size — it can cut the
        // relay throw and get the batter trying to take an extra base.
        const cut = along(B.H, leadPt, 48 * K);
        set('1B', cut, 'Watch the batter touch 1st, then hustle to the cutoff spot in front of home', 'cutoff');
        if (!trail) set(other, G.coverPt('2'), 'Cover 2nd base', 'cover');
        res.throwPath = [src, leadPt, cut, B.H];
        set('3B', G.coverPt('3'), 'Cover 3rd base', 'cover');
        const split = beyond(pt(0, G.bases / Math.SQRT2), mul(B[3], 0.5), 30 * K);
        set('P', split, 'Go halfway between 3rd and home in foul territory — read the throw, then back up that base', 'backup');
      } else {
        set('3B', G.coverPt('3'), 'Cover 3rd — keep the batter from a triple', 'cover');
        if (trail) {
          set('1B', G.coverPt('2'), 'Watch the batter touch 1st, then follow them to 2nd and cover it (both middle infielders are out on the relay)', 'cover');
        } else {
          set(other, G.coverPt('2'), 'Cover 2nd base', 'cover');
          set('1B', along(along(B[1], B[2], 0.5 * G.bases), G.MOUND, 14 * K),
            'Watch the batter touch 1st, then trail them toward 2nd — be ready to help in a rundown', 'other');
        }
        set('P', beyond(leadPt, T, 28 * K), `Back up ${BASE_NAME[target]} base`, 'backup');
        res.throwPath = [src, leadPt, T];
      }
      res.target = target;
      return;
    }

    let cut;
    if (target === 'H') {
      cut = along(B.H, src, 48 * K);
      if (F === 'LF') {
        set('3B', cut, 'Cutoff for the throw home — line up between the ball and home', 'cutoff');
        set('SS', G.coverPt('3'), 'Cover 3rd (the third baseman is the cutoff)', 'cover');
        set('2B', G.coverPt('2'), 'Cover 2nd base', 'cover');
        set('1B', G.coverPt('1'), 'Cover 1st — make sure the batter touches the bag', 'cover');
      } else {
        set('1B', cut, 'Cutoff for the throw home — line up between the ball and home', 'cutoff');
        set('2B', G.coverPt('1'), 'Cover 1st (the first baseman is the cutoff)', 'cover');
        set('SS', G.coverPt('2'), 'Cover 2nd base', 'cover');
        set('3B', G.coverPt('3'), 'Cover 3rd base', 'cover');
      }
      set('C', G.coverPt('H'), 'Cover home — yell "Cut!" or let it come through', 'cover');
      set('P', beyond(cut, B.H, 26 * K), 'Back up home plate', 'backup');
    } else if (target === '3') {
      cut = along(T, src, Math.min(60 * K, 0.45 * d));
      set('SS', cut, 'Cutoff for the throw to 3rd — line up and raise your arms', 'cutoff');
      set('3B', G.coverPt('3'), 'Cover 3rd and catch the throw', 'cover');
      set('2B', G.coverPt('2'), 'Cover 2nd base', 'cover');
      set('1B', G.coverPt('1'), 'Cover 1st — make sure the batter touches the bag', 'cover');
      set('P', beyond(cut, T, 28 * K), 'Back up 3rd base', 'backup');
      set('C', G.coverPt('H'), 'Cover home', 'cover');
    } else {
      const cutter = F === 'RF' ? '2B' : 'SS';
      const cov = cutter === '2B' ? 'SS' : '2B';
      cut = along(T, src, Math.min(50 * K, 0.4 * d));
      set(cutter, cut, opts.doThrow ? 'Go out toward the ball — be the cutoff for the throw to 2nd' : 'Go out toward the ball in case it gets dropped', 'cutoff');
      set(cov, G.coverPt('2'), 'Cover 2nd base', 'cover');
      set('1B', G.coverPt('1'), 'Cover 1st — make sure the batter touches the bag', 'cover');
      set('3B', G.coverPt('3'), 'Cover 3rd base', 'cover');
      set('P', beyond(cut, T, 24 * K), 'Back up the throw to 2nd', 'backup');
      if (opts.kind === 'single' && !anyRunners(r)) set('C', mul(pt(74, 50), K), 'Follow the batter down the line — back up 1st', 'backup');
      set('C', G.coverPt('H'), 'Cover home', 'cover');
    }
    if (opts.doThrow) {
      res.throwPath = [src, cut, T];
      res.target = target;
    }
    return cut;
  }

  function outfieldBackups(F, ball, set, res) {
    const { HOME_POS, BASES, k: K } = G;
    // The pitcher backs up 2nd/3rd close (24/28 ft); an outfielder on the same line stays deeper.
    const deep2 = 24 * K + 22 * G.dot;
    const deep3 = 28 * K + 22 * G.dot;
    const behind = (o) => {
      let p = add(ball, mul(unit(ball), 25 * K));
      p = add(p, mul(unit(sub(HOME_POS[o], ball)), 16 * K));
      return G.inFence(p, 8 * G.dot);
    };
    if (F === 'CF') {
      set('LF', behind('LF'), 'Back up the center fielder', 'backup');
      set('RF', behind('RF'), 'Back up the center fielder', 'backup');
    } else if (F === 'LF') {
      set('CF', behind('CF'), 'Back up the left fielder', 'backup');
      set('RF', beyond(ball, BASES[2], deep2), 'Back up 2nd — line up deep behind the bag on the throw from left', 'backup');
      if (res.target !== '2') res.altThrows.push([ball, BASES[2]]);
    } else if (F === 'RF') {
      set('CF', behind('CF'), 'Back up the right fielder', 'backup');
      if (res.target === '2') {
        set('LF', beyond(ball, BASES[2], deep2), 'Come in behind 2nd — back up the throw from right, deeper than the pitcher', 'backup');
      } else {
        set('LF', beyond(ball, BASES[3], deep3), 'Come in and back up 3rd base, deeper than the pitcher', 'backup');
        if (res.target !== '3') res.altThrows.push([ball, BASES[3]]);
      }
    }
  }

  // ---------- Fly balls (caught) ----------
  function fly(h, ball, r, outs, set, res) {
    const F = h.to;
    res.rules.push('S7', 'S8');
    const batterOut = { id: 'B', from: 'H', to: '1', out: true, endPt: along(G.BASES.H, G.BASES[1], 0.55 * G.bases) };
    if (outs === 2) {
      set(F, ball, "Catch it — that's the 3rd out!", 'field');
      res.headline = 'Catch it — inning over!';
      res.why = "Two outs: runners take off on contact, but a catch ends the inning. Everyone else still backs up and covers — just in case it's dropped.";
      ofPlay(F, ball, '2', r, set, res, { doThrow: false, kind: 'fly' });
      res.runners.push(batterOut);
      if (r[1]) res.runners.push({ id: 'R1', from: '1', to: '2' });
      if (r[2]) res.runners.push({ id: 'R2', from: '2', to: '3' });
      if (r[3]) res.runners.push({ id: 'R3', from: '3', to: 'H' });
    } else {
      const r2tags = r[2] && F !== 'LF';
      const target = r[3] ? 'H' : r2tags ? '3' : '2';
      res.rules.push('S6');
      if (target === 'H') res.rules.push('S4');
      set(F, ball, `Catch it, then throw ${toBase(target)} — hit the cutoff man`, 'field');
      res.headline = `Catch it, throw ${toBase(target)}!`;
      res.why = {
        H: 'Less than 2 outs with a runner on 3rd — they will TAG UP and try to score after the catch. Catch it moving toward home and throw through the cutoff.',
        3: 'The runner on 2nd can tag up and take 3rd on a fly to center or right. Throw to 3rd through the cutoff.',
        2: 'After the catch, get the ball back to the infield quickly — throw to 2nd so nobody sneaks an extra base.',
      }[target];
      ofPlay(F, ball, target, r, set, res, { doThrow: true, kind: 'fly' });
      res.runners.push(batterOut);
      if (r[1]) res.runners.push({ id: 'R1', from: '1', to: '1', note: 'Tags up and holds' });
      if (r[2]) res.runners.push({ id: 'R2', from: '2', to: r2tags ? '3' : '2', note: r2tags ? 'Tags up, goes to 3rd' : 'Tags up and holds' });
      if (r[3]) res.runners.push({ id: 'R3', from: '3', to: 'H', note: 'Tags up and tries to score' });
      res.tips.push('Runners: on a fly ball with less than 2 outs, go back and TAG your base. Leave when the ball is caught.');
    }
    outfieldBackups(F, ball, set, res);
  }

  // ---------- Singles ----------
  function single(h, ball, r, outs, set, res) {
    const F = h.to;
    const r1to = F === 'LF' ? '2' : '3';
    const target = r[2] ? 'H' : r[1] ? r1to : '2';
    res.rules.push(target === 'H' ? 'S4' : target === '3' ? 'S2' : r[1] ? 'S3' : 'S1');
    if (!anyRunners(r)) res.rules.push('S5');
    res.rules.push('S7', 'S8');
    const holdAt2 = F === 'LF' && r[1] && !r[2];
    if (holdAt2) {
      set(F, ball, 'Charge the ball — throw to 2nd, or to 3rd through the cutoff only if it’s a sure out', 'field');
      res.headline = 'Throw to 2nd — unless there’s a sure out at 3rd';
    } else {
      set(F, ball, `Charge the ball and throw ${toBase(target)} — hit the cutoff man`, 'field');
      res.headline = `Throw ${toBase(target)} through the cutoff!`;
    }
    if (target === 'H') {
      res.why = "The runner from 2nd will try to score. Throw home through the cutoff — if there's no play at home, the cutoff catches it and gets the batter trying for 2nd.";
    } else if (target === '3') {
      res.why = 'The runner from 1st will try to go first-to-third. Throw to 3rd through the shortstop (the cutoff) to stop them.';
    } else if (r[1]) {
      res.why = 'On a single to left, the runner from 1st usually stops at 2nd. The shortstop still lines up to 3rd in case they go — but unless you have a sure out at 3rd, throw to 2nd to keep the batter at 1st.';
    } else if (r[3]) {
      res.why = "The runner from 3rd scores easily — don't waste a throw home. Throw to 2nd to keep the batter at 1st.";
    } else {
      res.why = 'Nobody in scoring position. Throw to 2nd to keep the batter at 1st — no extra bases!';
    }
    if (holdAt2) {
      const cut = ofPlay(F, ball, '3', r, set, res, { doThrow: false, kind: 'single' });
      res.throwPath = [ball, G.BASES[2]];
      res.target = '2';
      res.altThrows.push([ball, cut, G.BASES[3]]);
    } else {
      ofPlay(F, ball, target, r, set, res, { doThrow: true, kind: 'single' });
    }
    outfieldBackups(F, ball, set, res);
    res.runners.push({ id: 'B', from: 'H', to: '1', note: 'Rounds 1st, looks to take 2nd on a throw home' });
    if (r[1]) res.runners.push({ id: 'R1', from: '1', to: r1to });
    if (r[2]) res.runners.push({ id: 'R2', from: '2', to: 'H' });
    if (r[3]) res.runners.push({ id: 'R3', from: '3', to: 'H' });
    res.tips.push('Outfielders: throw it low and hard to the cutoff man’s chest — never to the wrong base.');
  }

  // ---------- Gap doubles ----------
  function gap(h, ball, r, outs, set, res) {
    const { BASES, HOME_POS, k: K } = G;
    const left = h.side === 'L';
    const corner = left ? 'LF' : 'RF';
    const target = anyRunners(r) ? 'H' : '3';
    res.rules.push('R1', 'R2', target === 'H' ? 'R3' : 'R4', 'R5', 'S8');

    set('CF', ball, 'Chase it down and throw to the relay man', 'field');
    // Back up from the side (the ball is near the fence, so there's no room behind).
    const side = along(ball, HOME_POS[corner], 24 * G.dot);
    set(corner, G.inFence(add(side, mul(unit(ball), 6 * G.dot)), 8 * G.dot), 'Back up the center fielder', 'backup');
    ofPlay('CF', ball, target, r, set, res, { doThrow: true, kind: 'gap', relay: true });
    const leadPt = res.throwPath[1];
    if (left) {
      set('RF', beyond(leadPt, BASES[2], 24 * K + 22 * G.dot), 'Back up 2nd — line up behind the bag in case the relay man throws behind the batter (dotted line)', 'backup');
      res.altThrows.push([leadPt, BASES[2]]);
    } else {
      set('LF', beyond(leadPt, BASES[3], 28 * K + 22 * G.dot), 'Come in and back up 3rd base, deeper than the pitcher', 'backup');
      if (target !== '3') res.altThrows.push([leadPt, BASES[3]]);
    }

    if (target === 'H') {
      res.headline = 'Relay it home!';
      res.why = 'Runners will try to score on a ball in the gap. Use the relay: outfielder → relay man → home. Two short, strong throws beat one long, bouncing one.';
    } else {
      res.headline = 'Relay it to 3rd!';
      res.why = 'Nobody on, so the batter is thinking triple. Relay the ball to 3rd to hold them at 2nd.';
    }
    if (G.doubleCut) {
      res.tips.push('Big field = double cut. The relay man lines up with the outfielder, and the trail man ~30 feet behind shouts "Home! Home!" or "Three! Three!"');
    } else {
      res.tips.push('Small field = one relay man is enough — no trail man. The other middle infielder stays at 2nd so the batter can’t just walk into it.');
    }

    res.runners.push({ id: 'B', from: 'H', to: '2' });
    if (r[1]) res.runners.push({ id: 'R1', from: '1', to: 'H' });
    if (r[2]) res.runners.push({ id: 'R2', from: '2', to: 'H' });
    if (r[3]) res.runners.push({ id: 'R3', from: '3', to: 'H' });
  }

  // ---------- Bunts ----------
  function bunt(h, ball, r, outs, set, res) {
    const { BASES, HOME_POS, k: K } = G;
    // Runner on 2nd: 3B holds near the bag for a play at 3rd; pitcher takes the 3B-line bunt.
    const thirdStays = r[2];
    const F = thirdStays ? 'P' : '3B';
    res.rules.push('B1');
    if (thirdStays) res.rules.push(r[1] ? 'B2' : 'B3');
    res.rules.push('B4');
    set(F, ball, 'Field the bunt and throw to 1st for the sure out', 'field');
    set('1B', mul(pt(36, 40), K), 'Charge the bunt — then get out of the way', 'other');
    set('2B', G.coverPt('1'), 'Cover 1st base! (1B is charging)', 'cover');
    if (thirdStays) {
      set('3B', G.coverPt('3'), r[1] ? 'Read the bunt — if the pitcher can get it, stay at 3rd for the force' : 'Read the bunt — if the pitcher can get it, stay at 3rd for the tag play', 'cover');
      set('SS', G.coverPt('2'), 'Cover 2nd base', 'cover');
    } else {
      set('P', mul(pt(12, 34), K), 'Come off the mound — field it if it comes to you', 'other');
      set('SS', G.coverPt('2'), 'Cover 2nd base', 'cover');
    }
    set('C', G.coverPt('H'), 'Yell who should field it, then cover home', 'cover');
    set('RF', beyond(ball, BASES[1], 42 * K), 'Back up 1st base', 'backup');
    set('CF', along(BASES[2], HOME_POS.CF, 40 * K), 'Back up 2nd base', 'backup');
    set('LF', beyond(BASES.H, BASES[3], 35 * K), 'Back up 3rd base', 'backup');

    res.throwPath = [ball, BASES[1]];
    res.target = '1';
    res.headline = 'Get the sure out at 1st!';
    res.why = 'On a bunt, the corners crash in and someone MUST cover 1st (the second baseman). Unless you have an easy play on the lead runner, take the out at 1st.';
    if (r[3] && outs < 2) res.tips.push('Runner on 3rd — watch for the squeeze! If they break for home, flip it to the catcher.');

    res.runners.push({ id: 'B', from: 'H', to: '1' });
    if (r[1]) res.runners.push({ id: 'R1', from: '1', to: '2' });
    if (r[2]) res.runners.push({ id: 'R2', from: '2', to: '3' });
    if (r[3]) res.runners.push({ id: 'R3', from: '3', to: 'H' });
  }

  const KINDS = { ground, fly, single, gap, bunt };

  const api = { solve, field, LEVELS, HITS, POS, POS_NAME, BASE_NAME, pt, dist, along, polar };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Engine = api;
})(this);
