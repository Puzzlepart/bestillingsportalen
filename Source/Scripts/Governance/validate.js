// Static checks for Logic App ARM templates (no az/pwsh in this container).
'use strict';
const fs = require('fs');

const FUNCS = new Set(('and or not equals less lessOrEquals greater greaterOrEquals if empty coalesce contains concat substring length sub add mul div ' +
  'string int json createArray union intersection join first last take skip chunk utcNow addDays ticks formatDateTime toLower toUpper trim ' +
  'body outputs actions items variables parameters triggerBody listCallbackUrl encodeURIComponent dayOfWeek convertFromUtc item result replace split startsWith endsWith bool float array').split(/\s+/));

let errors = 0;
const err = (f, m) => { errors++; console.log(`  ERROR ${f}: ${m}`); };

// Extract expression fragments from a Logic App string value
function expressions(s) {
  if (typeof s !== 'string') return [];
  if (s.startsWith('@@')) return [];
  if (s.startsWith('@') && !s.startsWith('@{')) return [s.slice(1)];
  const out = [];
  let i = 0;
  while ((i = s.indexOf('@{', i)) !== -1) {
    let depth = 0, j = i + 1, inStr = false;
    for (; j < s.length; j++) {
      const c = s[j];
      if (inStr) { if (c === "'") { if (s[j + 1] === "'") j++; else inStr = false; } continue; }
      if (c === "'") inStr = true;
      else if (c === '{') depth++;
      else if (c === '}') { depth--; if (depth === 0) break; }
    }
    if (j >= s.length) { out.push({ unterminated: s.slice(i, i + 80) }); break; }
    out.push(s.slice(i + 2, j));
    i = j + 1;
  }
  return out;
}

function checkExpr(file, e, ctx) {
  if (typeof e === 'object') return err(file, `unterminated @{ in ${JSON.stringify(e.unterminated)}`);
  // balance
  let depth = 0, inStr = false;
  for (let i = 0; i < e.length; i++) {
    const c = e[i];
    if (inStr) { if (c === "'") { if (e[i + 1] === "'") i++; else inStr = false; } continue; }
    if (c === "'") inStr = true; else if (c === '(') depth++; else if (c === ')') { depth--; if (depth < 0) break; }
  }
  if (inStr || depth !== 0) return err(file, `unbalanced expression: ${e.slice(0, 160)}`);
  // strip string literals for token checks
  const code = e.replace(/'(?:[^']|'')*'/g, "''");
  for (const m of code.matchAll(/([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
    if (!FUNCS.has(m[1])) err(file, `unknown function ${m[1]} in ${e.slice(0, 120)}`);
  }
  for (const m of e.matchAll(/\b(body|outputs|actions)\('([^']+)'\)/g)) {
    if (!ctx.allActions.has(m[2])) err(file, `${m[1]}('${m[2]}') - no such action`);
  }
  for (const m of e.matchAll(/\bitems\('([^']+)'\)/g)) {
    if (!ctx.loops.includes(m[1])) err(file, `items('${m[1]}') outside that loop (in ${ctx.path})`);
  }
  for (const m of e.matchAll(/\bvariables\('([^']+)'\)/g)) {
    if (!ctx.vars.has(m[1])) err(file, `variables('${m[1]}') not initialised`);
  }
  for (const m of e.matchAll(/\bparameters\('([^']+)'\)/g)) {
    if (!ctx.params.has(m[1])) err(file, `parameters('${m[1]}') not defined`);
  }
  if (/\['fields'\]/.test(e)) err(file, `Graph list item 'fields' reference left: ${e.slice(0, 100)}`);
}

function walkValues(node, fn) {
  if (Array.isArray(node)) node.forEach((n) => walkValues(n, fn));
  else if (node && typeof node === 'object') Object.entries(node).forEach(([k, v]) => { fn(k); walkValues(v, fn); });
  else fn(node);
}

function collectActions(actions, set, vars) {
  for (const [name, a] of Object.entries(actions || {})) {
    if (set.has(name)) throw new Error(`duplicate action name ${name}`);
    set.add(name);
    if (a.type === 'InitializeVariable') a.inputs.variables.forEach((v) => vars.add(v.name));
    collectActions(a.actions, set, vars);
    if (a.else) collectActions(a.else.actions, set, vars);
    if (a.cases) Object.values(a.cases).forEach((c) => collectActions(c.actions, set, vars));
    if (a.default) collectActions(a.default.actions, set, vars);
  }
}

function checkScope(file, actions, ctx, path) {
  const names = Object.keys(actions || {});
  if (!names.length) return;
  const entries = names.filter((n) => Object.keys(actions[n].runAfter || {}).length === 0);
  if (!entries.length) err(file, `${path}: no entry action (all have runAfter)`);
  for (const n of names) {
    const a = actions[n];
    for (const dep of Object.keys(a.runAfter || {})) {
      if (!names.includes(dep)) err(file, `${path}/${n}: runAfter '${dep}' is not a sibling`);
    }
    // cycle check (simple DFS)
    const seen = new Set();
    const visit = (x) => { if (x === n && seen.size) return true; if (seen.has(x)) return false; seen.add(x); return Object.keys((actions[x] || {}).runAfter || {}).some(visit); };
    if (Object.keys(a.runAfter || {}).some((d) => { seen.clear(); return visit(d); })) err(file, `${path}/${n}: runAfter cycle`);

    const loops = a.type === 'Foreach' ? [...ctx.loops, n] : ctx.loops;
    const own = { ...a };
    delete own.actions; delete own.else; delete own.cases; delete own.default;
    const sub = { ...ctx, loops, path: `${path}/${n}` };
    walkValues(own, (v) => expressions(v).forEach((e) => checkExpr(file, e, a.type === 'Foreach' ? { ...ctx, path: sub.path } : sub)));
    checkScope(file, a.actions, sub, `${path}/${n}`);
    if (a.else) checkScope(file, a.else.actions, sub, `${path}/${n}/else`);
    if (a.cases) Object.entries(a.cases).forEach(([c, v]) => checkScope(file, v.actions, sub, `${path}/${n}/${c}`));
    if (a.default) checkScope(file, a.default.actions, sub, `${path}/${n}/default`);
  }
}

function checkArm(file, tpl) {
  const armParams = new Set(Object.keys(tpl.parameters));
  const armVars = new Set(Object.keys(tpl.variables || {}));
  walkValues(tpl, (v) => {
    if (typeof v !== 'string' || !v.startsWith('[') || v.startsWith('[[')) return;
    if (!v.endsWith(']')) return err(file, `ARM expression not closed: ${v.slice(0, 80)}`);
    for (const m of v.matchAll(/parameters\('([^']+)'\)/g)) if (!armParams.has(m[1])) err(file, `ARM parameters('${m[1]}') missing`);
    for (const m of v.matchAll(/variables\('([^']+)'\)/g)) if (!armVars.has(m[1])) err(file, `ARM variables('${m[1]}') missing`);
  });
}

for (const file of process.argv.slice(2)) {
  const raw = fs.readFileSync(file, 'utf8');
  let tpl;
  try { tpl = JSON.parse(raw); } catch (e) { err(file, e.message); continue; }
  checkArm(file, tpl);
  for (const r of tpl.resources.filter((x) => x.type === 'Microsoft.Logic/workflows')) {
    const d = r.properties.definition;
    const allActions = new Set();
    const vars = new Set();
    collectActions(d.actions, allActions, vars);
    const params = new Set(Object.keys(d.parameters));
    const ctx = { allActions, vars, params, loops: [], path: r.name };
    walkValues(d.triggers, (v) => expressions(v).forEach((e) => checkExpr(file, e, ctx)));
    checkScope(file, d.actions, ctx, r.name);
    for (const c of Object.keys(r.properties.parameters.$connections.value)) {
      if (!raw.includes(`['${c}']`)) err(file, `connection ${c} declared but unused`);
    }
    for (const m of raw.matchAll(/\$connections'\)\['([^']+)'\]/g)) {
      if (!r.properties.parameters.$connections.value[m[1]]) err(file, `connection ${m[1]} used but not declared`);
    }
    console.log(`${file}: ${allActions.size} actions checked`);
  }
}
console.log(errors ? `${errors} error(s)` : 'OK');
process.exit(errors ? 1 : 0);
