// Generates the Teams governance Logic App ARM templates in Source/ARMTemplates/LogicApps.
// Usage (from the repo root or anywhere): node Source/Scripts/Governance/build.js
// The generated JSON files are committed - deploy.ps1 deploys them like any other template.
'use strict';
const fs = require('fs');
const path = require('path');

const out = process.argv[2] || path.join(__dirname, '..', '..', 'ARMTemplates', 'LogicApps');
const files = {
  'governancenotify.json': require('./notify'),
  'governancesync.json': require('./sync').sync(),
  'governanceenddate.json': require('./parents').endDate(),
  'governanceannualreview.json': require('./parents').annualReview(),
};
for (const [file, tpl] of Object.entries(files)) {
  const target = path.join(out, file);
  fs.writeFileSync(target, JSON.stringify(tpl, null, 4) + '\n');
  console.log(`${path.relative(process.cwd(), target)} (${fs.statSync(target).size} bytes)`);
}
