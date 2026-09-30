// Regenerates the iPad app's data from the web version:
//   - ios/SituationSimTests/fixtures.json: the web engine's answer for every
//     situation, which the Swift engine is tested against.
//   - ios/SituationSim/Resources/Sources.json: the rule notes from sources.js.
// Run from the repo root: node scripts/export-ios-data.js
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.join(__dirname, '..');
const E = require(path.join(root, 'engine.js'));

const r2 = (p) => (p ? [+p.x.toFixed(4), +p.y.toFixed(4)] : null);
const out = [];
for (const level of Object.keys(E.LEVELS)) {
  for (const hit of Object.keys(E.HITS)) {
    for (let m = 0; m < 8; m++) {
      for (let o = 0; o < 3; o++) {
        const runners = { 1: !!(m & 1), 2: !!(m & 2), 3: !!(m & 4) };
        const r = E.solve({ level, hit, outs: o, runners });
        out.push({
          level, hit, outs: o, runners: [runners[1], runners[2], runners[3]],
          ball: r2(r.ball),
          assignments: Object.fromEntries(E.POS.map((p) => [p, { to: r2(r.A[p].to), job: r.A[p].job, type: r.A[p].type }])),
          throwPath: r.throwPath.map(r2),
          altThrows: r.altThrows.map((a) => a.map(r2)),
          carry: r.carry,
          runnerMoves: r.runners.map((mv) => ({ id: mv.id, from: mv.from, to: mv.to, out: !!mv.out, note: mv.note || '', endPt: r2(mv.endPt) })),
          target: r.target, played: r.played, headline: r.headline, why: r.why, tips: r.tips, rules: r.rules,
        });
      }
    }
  }
}
fs.writeFileSync(path.join(root, 'ios/SituationSimTests/fixtures.json'), JSON.stringify(out));

const ctx = {};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(root, 'sources.js'), 'utf8'), ctx);
fs.writeFileSync(path.join(root, 'ios/SituationSim/Resources/Sources.json'), JSON.stringify(ctx.SOURCES, null, 1));

console.log(`Wrote ${out.length} situations and ${Object.keys(ctx.SOURCES).length} rule notes.`);
