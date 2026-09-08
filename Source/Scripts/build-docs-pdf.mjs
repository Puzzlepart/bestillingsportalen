// Bygger PDF av markdown-dokumentasjonen for utsending til kunde.
//
// Standard er ÉN samlet PDF med tittelside, innholdsfortegnelse og
// kryssreferansene skrevet om til interne anker — konverterer man fil for fil,
// blir hver .md-lenke en død peker. --split gir likevel én PDF per fil.
//
// Bilder inlines som data-URI-er, så PDF-en er selvbærende. Mermaid-diagrammer
// rendres til SVG. Lenker til filer som ikke er med i PDF-en (skript, maler)
// peker til GitHub.
//
//   npm install --no-save markdown-it markdown-it-anchor playwright-core mermaid
//   node Source/Scripts/build-docs-pdf.mjs [repo-rot] [ut-mappe] [--split]
//
// Nettleser: bruker Edge eller Chrome hvis den finnes, ellers Chromium fra
// Playwright (npx playwright install chromium). Sett BP_CHROMIUM for å peke på
// en egen kjørbar fil.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'
import MarkdownIt from 'markdown-it'
import anchor from 'markdown-it-anchor'
import { chromium } from 'playwright-core'

const require = createRequire(import.meta.url)
const here = path.dirname(fileURLToPath(import.meta.url))
const repo = path.resolve(process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : path.join(here, '..', '..'))
const outDir = path.resolve(process.argv[3] && !process.argv[3].startsWith('--')
  ? process.argv[3]
  : path.join(repo, 'docs-pdf'))
const split = process.argv.includes('--split')

// Leserekkefølge: samme som navigasjonstabellen i README, med README først.
const ORDER = [
  'README.md',
  'Teknisk-losningsbeskrivelse.md',
  'Data-access-security.md',
  'Deployment-guide.md',
  'Configuration-guide.md',
  'Upgrade.md',
  'Upgrade-from-pre-1.0.md',
  'Data-stores.md',
  'Naming-conventions.md',
  'Business-units.md',
  'Provisioning-types.md',
  'Site-templates.md',
  'Sensitivity-labels.md',
  'Teams-templates.md',
  'PnP-templates.md',
  'Retention-labels.md',
  'Approval-flow.md',
  'Regional-settings.md',
  'Error-handling.md',
  'CHANGELOG.md',
  'CONTRIBUTING.md',
  'Images/error-handling-flow.md',
]

const files = ORDER.filter((f) => fs.existsSync(path.join(repo, f)))
const extra = fs
  .readdirSync(repo)
  .filter((f) => f.endsWith('.md') && !ORDER.includes(f))
if (extra.length) console.warn('Ikke i ORDER, hoppet over:', extra.join(', '))

const docId = (f) => 'doc-' + f.replace(/\.md$/, '').toLowerCase().replace(/[^a-z0-9]+/g, '-')

const mime = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp' }
const dataUri = (p) => {
  const ext = path.extname(p).toLowerCase()
  if (!mime[ext] || !fs.existsSync(p)) return null
  return `data:${mime[ext]};base64,${fs.readFileSync(p).toString('base64')}`
}

function makeMd(currentFile) {
  const md = new MarkdownIt({ html: true, linkify: false, breaks: false })
  md.use(anchor, {
    slugify: (s) =>
      docId(currentFile) + '--' + s.toLowerCase().trim()
        .replace(/[^\w\s\-æøå]/g, '').replace(/\s+/g, '-'),
  })

  // mermaid-fences (også med mellomrom: ``` mermaid) -> <pre class="mermaid">
  const fence = md.renderer.rules.fence
  md.renderer.rules.fence = (tokens, idx, opts, env, self) => {
    const info = (tokens[idx].info || '').trim().toLowerCase()
    if (info === 'mermaid')
      return `<pre class="mermaid">${md.utils.escapeHtml(tokens[idx].content)}</pre>`
    return fence(tokens, idx, opts, env, self)
  }

  // Bilder inlines som data-URI slik at PDF-en er selvbærende.
  const image = md.renderer.rules.image
  md.renderer.rules.image = (tokens, idx, opts, env, self) => {
    const t = tokens[idx]
    let src = decodeURIComponent(t.attrGet('src') || '')
    if (!/^https?:/.test(src)) {
      const abs = src.startsWith('/')
        ? path.join(repo, src.slice(1))
        : path.resolve(path.join(repo, path.dirname(currentFile)), src)
      const uri = dataUri(abs)
      if (uri) t.attrSet('src', uri)
      else console.warn(`  bilde mangler: ${currentFile} -> ${src}`)
    }
    return image(tokens, idx, opts, env, self)
  }

  // Kryssreferanser mellom .md-filene blir interne anker i den samlede PDF-en.
  md.renderer.rules.link_open = (tokens, idx, opts, env, self) => {
    const t = tokens[idx]
    let href = t.attrGet('href') || ''
    if (!/^(https?:|mailto:|tel:|#)/.test(href)) {
      const [rawPath, hash] = href.split('#')
      const target = decodeURIComponent(rawPath.replace(/^\//, ''))
      const base = target ? path.basename(target) : currentFile
      if (base.endsWith('.md') && files.includes(base) && !split) {
        t.attrSet('href', '#' + docId(base) + (hash ? '--' + hash.toLowerCase() : ''))
      } else if (!target) {
        t.attrSet('href', '#' + docId(currentFile) + '--' + (hash || '').toLowerCase())
      } else {
        // Filer som ikke er med i PDF-en (skript, maler): pek til GitHub.
        t.attrSet('href', `https://github.com/Puzzlepart/bestillingsportalen/blob/main/${target}`)
      }
    }
    return self.renderToken(tokens, idx, opts)
  }
  return md
}

const CSS = `
:root { --ink:#1a1a1a; --muted:#5b6472; --rule:#d8dde5; --accent:#0b4a8f; --code-bg:#f5f7fa; }
* { box-sizing:border-box; }
body { font-family:"Segoe UI",-apple-system,system-ui,sans-serif; font-size:10.2pt;
  line-height:1.55; color:var(--ink); margin:0; }
h1,h2,h3,h4 { line-height:1.25; margin:1.4em 0 .5em; break-after:avoid; page-break-after:avoid; color:#101418; }
h1 { font-size:20pt; border-bottom:2px solid var(--accent); padding-bottom:.25em; }
h2 { font-size:14pt; } h3 { font-size:11.5pt; } h4 { font-size:10.5pt; color:var(--muted); }
p,li { orphans:3; widows:3; }
a { color:var(--accent); text-decoration:none; }
code { font-family:"Cascadia Mono",Consolas,monospace; font-size:.88em;
  background:var(--code-bg); padding:.1em .3em; border-radius:3px; }
pre { background:var(--code-bg); border:1px solid var(--rule); border-radius:4px;
  padding:.7em .9em; overflow:hidden; break-inside:avoid; page-break-inside:avoid; }
pre code { background:none; padding:0; font-size:.82em; white-space:pre-wrap; word-break:break-word; }
table { border-collapse:collapse; width:100%; margin:1em 0; font-size:.85em; break-inside:auto; }
th,td { border:1px solid var(--rule); padding:.4em .55em; text-align:left; vertical-align:top; }
th { background:#eef2f7; font-weight:600; }
tr { break-inside:avoid; page-break-inside:avoid; }
blockquote { margin:1em 0; padding:.6em .9em; border-left:3px solid var(--accent);
  background:#f4f8fd; break-inside:avoid; }
blockquote p:first-child { margin-top:0; } blockquote p:last-child { margin-bottom:0; }
img { max-width:100%; height:auto; }
hr { border:0; border-top:1px solid var(--rule); margin:1.5em 0; }
.doc { page-break-before:always; break-before:page; }
.doc:first-of-type { page-break-before:avoid; break-before:auto; }
.doc > .srcname { font-size:7.5pt; color:var(--muted); text-transform:uppercase;
  letter-spacing:.08em; margin-bottom:-.6em; }
.mermaid { background:none; border:0; text-align:center; padding:0; }
.mermaid svg { max-width:100%; height:auto; }
/* Tittelside */
.title { height:24.5cm; display:flex; flex-direction:column; justify-content:center; }
.title h1 { font-size:30pt; border:0; margin:0 0 .2em; }
.title .sub { font-size:13pt; color:var(--muted); margin-bottom:2.5em; }
.title .meta { font-size:9.5pt; color:var(--muted); line-height:1.9; }
.title .meta b { color:var(--ink); font-weight:600; }
/* Innholdsfortegnelse */
.toc { page-break-before:always; break-before:page; }
.toc ol { list-style:none; padding-left:0; counter-reset:doc; }
.toc > ol > li { counter-increment:doc; margin:.45em 0; font-weight:600; }
.toc > ol > li::before { content:counter(doc) ". "; color:var(--muted); }
.toc ol ol { padding-left:1.6em; margin:.2em 0; }
.toc ol ol li { font-weight:400; font-size:.9em; color:#33404f; margin:.12em 0; }
.toc a { color:inherit; }
`

const MERMAID_INIT = `
window.__mermaidDone = (async () => {
  mermaid.initialize({ startOnLoad:false, theme:'neutral', securityLevel:'loose',
    fontFamily:'Segoe UI, system-ui, sans-serif',
    themeVariables:{ fontSize:'14px', primaryColor:'#eef2f7', primaryBorderColor:'#0b4a8f',
      lineColor:'#5b6472', primaryTextColor:'#101418' } })
  const nodes = [...document.querySelectorAll('pre.mermaid')]
  for (const [i, el] of nodes.entries()) {
    try {
      const { svg } = await mermaid.render('mmd-' + i, el.textContent)
      const d = document.createElement('div'); d.className = 'mermaid'; d.innerHTML = svg
      el.replaceWith(d)
    } catch (e) { el.classList.add('mermaid-failed'); console.log('MERMAID_FAIL ' + e.message) }
  }
  return nodes.length
})()
`

function buildHtml(docs, { withTitle }) {
  const toc = docs
    .map(
      (d) => `<li><a href="#${d.id}">${d.title}</a>${
        d.subs.length
          ? '<ol>' + d.subs.map((s) => `<li><a href="#${s.id}">${s.text}</a></li>`).join('') + '</ol>'
          : ''
      }</li>`
    )
    .join('\n')

  const today = new Date().toLocaleDateString('nb-NO', { year: 'numeric', month: 'long', day: 'numeric' })
  const version = (fs.readFileSync(path.join(repo, 'CHANGELOG.md'), 'utf8').match(/^##\s*([\d.]+)/m) || [, '?'])[1]

  const title = withTitle
    ? `<section class="title">
        <h1>Bestillingsportalen</h1>
        <div class="sub">Teknisk dokumentasjon</div>
        <div class="meta">
          <b>Versjon</b> ${version}<br>
          <b>Generert</b> ${today}<br>
          <b>Kilde</b> github.com/Puzzlepart/bestillingsportalen<br>
          <b>Dokumenter</b> ${docs.length}
        </div>
       </section>
       <section class="toc"><h1>Innhold</h1><ol>${toc}</ol></section>`
    : ''

  return `<!doctype html><html lang="no"><head><meta charset="utf-8">
<title>Bestillingsportalen – dokumentasjon</title><style>${CSS}</style></head><body>
${title}
${docs.map((d) => `<section class="doc" id="${d.id}"><div class="srcname">${d.file}</div>\n${d.html}</section>`).join('\n')}
</body></html>`
}

function renderDoc(file) {
  const md = makeMd(file)
  const src = fs.readFileSync(path.join(repo, file), 'utf8')
  const html = md.render(src)
  const id = docId(file)
  const titleMatch = src.match(/^#\s+(.+)$/m)
  const title = titleMatch ? titleMatch[1].replace(/`/g, '') : file
  const subs = [...src.matchAll(/^##\s+(.+)$/gm)].map((m) => {
    const text = m[1].replace(/`/g, '').replace(/\*\*/g, '')
    return {
      text,
      id: id + '--' + text.toLowerCase().trim().replace(/[^\w\s\-æøå]/g, '').replace(/\s+/g, '-'),
    }
  })
  return { file, id, title, subs, html }
}

// Prøv i rekkefølge: eksplisitt sti, installert Edge/Chrome, Playwrights Chromium.
async function launchBrowser() {
  const args = ['--no-sandbox', '--font-render-hinting=none']
  const attempts = [
    ...(process.env.BP_CHROMIUM ? [{ executablePath: process.env.BP_CHROMIUM, args }] : []),
    { channel: 'msedge', args },
    { channel: 'chrome', args },
    { args },
  ]
  const errors = []
  for (const opts of attempts) {
    try {
      return await chromium.launch(opts)
    } catch (e) {
      errors.push(`${opts.executablePath || opts.channel || 'chromium'}: ${e.message.split('\n')[0]}`)
    }
  }
  throw new Error('Fant ingen brukbar nettleser.\n  ' + errors.join('\n  ') +
    '\nKjør «npx playwright install chromium», eller sett BP_CHROMIUM til en kjørbar fil.')
}

const browser = await launchBrowser()

async function toPdf(html, outFile, { numbered }) {
  const page = await browser.newPage()
  page.on('console', (m) => { if (m.text().startsWith('MERMAID_FAIL')) console.warn('  ' + m.text()) })
  await page.setContent(html, { waitUntil: 'load' })
  await page.addScriptTag({ path: require.resolve('mermaid/dist/mermaid.min.js') })
  await page.addScriptTag({ content: MERMAID_INIT, type: 'module' })
  await page.waitForFunction(() => window.__mermaidDone !== undefined)
  const n = await page.evaluate(() => window.__mermaidDone)
  const failed = await page.evaluate(() => document.querySelectorAll('.mermaid-failed').length)
  if (failed) console.warn(`  ADVARSEL: ${failed} diagram rendret ikke`)
  if (failed) console.warn()
  await page.emulateMedia({ media: 'print' })
  await page.pdf({
    path: outFile,
    format: 'A4',
    printBackground: true,
    margin: { top: '18mm', bottom: '18mm', left: '18mm', right: '18mm' },
    displayHeaderFooter: numbered,
    headerTemplate: '<div></div>',
    footerTemplate: numbered
      ? `<div style="width:100%;font:8pt 'Segoe UI',sans-serif;color:#5b6472;
           padding:0 18mm;display:flex;justify-content:space-between;">
           <span>Bestillingsportalen – teknisk dokumentasjon</span>
           <span class="pageNumber"></span></div>`
      : '<div></div>',
  })
  await page.close()
  return n
}

fs.mkdirSync(outDir, { recursive: true })
if (split) {
  for (const f of files) {
    const d = renderDoc(f)
    const out = path.join(outDir, f.replace(/\.md$/, '.pdf'))
    const n = await toPdf(buildHtml([d], { withTitle: false }), out, { numbered: true })
    console.log(`${f} -> ${path.basename(out)}${n ? ` (${n} diagram)` : ''}`)
  }
} else {
  const docs = files.map(renderDoc)
  const out = path.join(outDir, 'Bestillingsportalen-dokumentasjon.pdf')
  const n = await toPdf(buildHtml(docs, { withTitle: true }), out, { numbered: true })
  console.log(`${docs.length} dokumenter, ${n} diagram -> ${out}`)
}
await browser.close()
