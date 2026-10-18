#!/usr/bin/env node
// Regenerates hpca/sheets/*.md from the flash-sheet data files (html/flash-sheets/b0*.js).
// Usage: node hpca/tools/export_markdown.js   (run from the repo root)
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const dataDir = path.join(root, "html", "flash-sheets");
const outDir = path.join(root, "sheets");

// Load the data files exactly as the page does.
global.window = {};
fs.readdirSync(dataDir).filter(f => /^b\d+\.js$/.test(f)).sort()
  .forEach(f => eval(fs.readFileSync(path.join(dataDir, f), "utf8")));
const SHEETS = window.SHEETS.slice().sort((a, b) => (a.id < b.id ? -1 : 1));

// Lesson names: read from the page so there is one source of truth.
const page = fs.readFileSync(path.join(dataDir, "index.html"), "utf8");
const LESSONS = eval(page.match(/window\.LESSONS=(\[[\s\S]*?\]\]);/)[1]);

const md = s => String(s)
  .replace(/<b>(.*?)<\/b>/g, "**$1**")
  .replace(/<i>(.*?)<\/i>/g, "*$1*")
  .replace(/<em>(.*?)<\/em>/g, "*$1*")
  .replace(/<code>(.*?)<\/code>/g, "`$1`")
  .replace(/<sup>(.*?)<\/sup>/g, "^$1")
  .replace(/<sub>(.*?)<\/sub>/g, "_$1")
  .replace(/<[^>]+>/g, "")
  .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
const cell = s => md(s).replace(/\|/g, "\\|");
const list = a => a.map(x => `- ${md(x)}`).join("\n");
const table = t => [
  `| ${t[0].map(cell).join(" | ")} |`,
  `| ${t[0].map(() => "---").join(" | ")} |`,
  ...t.slice(1).map(r => `| ${r.map(cell).join(" | ")} |`)
].join("\n");

const pad = n => String(n).padStart(2, "0");
const slug = s => s.toLowerCase().replace(/&/g, "and").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
// GitHub heading anchors: lowercase, drop punctuation (keep letters, digits, space, _ and -), spaces → "-".
const anchor = s => s.toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu, "").replace(/ /g, "-");
const files = [];

LESSONS.forEach(([n, name]) => {
  const sheets = SHEETS.filter(s => s.L === n);
  if (!sheets.length) return;
  const file = `${pad(n)}-${slug(name)}.md`;
  files.push([n, name, file, sheets.length]);
  const out = [`# Lesson ${pad(n)} · ${name}`, "",
    `${sheets.length} sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run \`node hpca/tools/export_markdown.js\`.`, "",
    sheets.map((s, i) => `${i + 1}. [${md(s.t)}](#${anchor(s.id + " " + md(s.t))})`).join("\n"), ""];
  sheets.forEach(s => {
    out.push("---", "", `## ${s.id} ${md(s.t)}`, "", `*${md(s.vids)}*`, "", `> ${md(s.gist)}`, "");
    if (s.pts) out.push("**Concepts**", "", list(s.pts), "");
    if (s.tbl) out.push(table(s.tbl), "");
    if (s.nums) out.push("**Numbers & formulas:** " + s.nums.map(x => "`" + md(x) + "`").join(" · "), "");
    if (s.wk) out.push("**Worked**", "", table([["Problem", "Answer"], ...s.wk]), "");
    if (s.fix) out.push("**Check your notes**", "", list(s.fix), "");
    if (s.dv) out.push("**Verification lens**", "", list(s.dv), "");
    if (s.bugs) out.push("**Bugs that ship**", "", list(s.bugs), "");
    if (s.qa) {
      out.push("**Interview**", "");
      s.qa.forEach(([q, a]) => out.push(`<details><summary>${md(q)}</summary>`, "", md(a), "", "</details>", ""));
    }
  });
  fs.writeFileSync(path.join(outDir, file), out.join("\n"));
});

fs.writeFileSync(path.join(outDir, "INDEX.md"), [
  "# HPCA flash sheets: lesson index", "",
  "| # | Lesson | Sheets |", "|---|---|---|",
  ...files.map(([n, name, f, c]) => `| ${pad(n)} | [${name}](${f}) | ${c} |`),
  "", `**Total: ${SHEETS.length} sheets**`, ""].join("\n"));
console.log(`${SHEETS.length} sheets → ${files.length} lesson files`);
