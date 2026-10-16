# -*- coding: utf-8 -*-
import html, json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import content as C
import diagrams as D

E = html.escape
TRACE = json.load(open(sys.argv[1]))
OUT = sys.argv[2]

SEV = {"deadlock": "Deadlock", "data": "Wrong data", "race": "Race / sim-only", "spec": "Spec violation", "perf": "Performance"}

def code(txt):
    return f'<pre class="code"><code>{E(txt)}</code></pre>'

def bug_card(bid):
    b = C.BUGS[bid]
    return f'''<article class="bug" id="{bid}" data-sev="{b['sev']}">
  <header><span class="bid">{bid}</span><h4>{b['title']}</h4><span class="sev {b['sev']}">{SEV[b['sev']]}</span></header>
  <p class="loc"><span>Where</span><code>{E(b['loc'])}</code></p>
  <p><span class="k">Symptom</span>{b['symptom']}</p>
  <p class="hint"><span class="k">Hint</span>{b['hint']}</p>
  <details><summary>Reveal root cause and fix</summary>
    <div class="reveal">
      <p><span class="k">Root cause</span>{b['cause']}</p>
      <div class="twocode"><div><div class="cl bad">original</div>{code(b['orig'])}</div><div><div class="cl ok">fix</div>{code(b['fix'])}</div></div>
      <p><span class="k">Caught by</span>{b['caught']}</p>
      <p class="lesson"><span class="k">Lesson</span>{b['lesson']}</p>
    </div>
  </details>
</article>'''

def qa_block(qa):
    out = ['<div class="qa">']
    for q, a in qa:
        out.append(f'<details class="q"><summary>{q}</summary><p>{a}</p></details>')
    out.append('</div>')
    return ''.join(out)

DIAG = {"fetch": D.fetch, "formats": D.formats, "rob": D.rob, "wakeup": D.wakeup, "lsq": D.lsq}

def module(m):
    parts = [f'<section class="mod" id="{m["id"]}" data-track="{m["id"]}">',
             f'<div class="modhead"><span class="modn">Module {m["n"]}</span><h2>{m["name"]}</h2>'
             f'<p class="files">{m["files"]}</p>'
             f'<label class="done"><input type="checkbox" id="done-{m["id"]}" data-done="{m["id"]}"> Mark module done</label></div>',
             f'<h3>What it does</h3>{m["what"]}']
    if m["diagram"]:
        parts.append(DIAG[m["diagram"]]())
    if m["id"] == "issue":
        pass
    parts.append('<h3>Hidden concepts</h3><div class="concepts">')
    for t, d in m["concepts"]:
        parts.append(f'<div class="concept"><h4>{t}</h4><p>{d}</p></div>')
    parts.append('</div>')
    parts.append('<h3>Code walk</h3><ul class="walk">')
    for r, d in m["code"]:
        parts.append(f'<li><code class="ref">{E(r)}</code><span>{d}</span></li>')
    parts.append('</ul>')
    if m["bugs"]:
        parts.append(f'<h3>Bugs found here <span class="count">{len(m["bugs"])}</span></h3><p class="muted">Try the hint first. Run the matching test on <code>rtl/</code> and find it yourself before you reveal.</p>')
        parts.extend(bug_card(b) for b in m["bugs"])
    parts.append('<h3>Build it</h3><ol class="build">')
    for b in m["build"]:
        parts.append(f'<li>{b}</li>')
    parts.append('</ol>')
    parts.append('<h3>Interview questions</h3>' + qa_block(m["qa"]))
    parts.append('</section>')
    return ''.join(parts)

NAV = [("start", "Start here"), ("machine", "The machine"), ("run", "Watch it run")] + \
      [(m["id"], f'{m["n"]} · {m["name"]}') for m in C.MODULES] + \
      [("verify", "9 · Verification"), ("capstone", "10 · Capstone: branches"), ("drill", "Interview drill"),
       ("catalog", "Bug catalog"), ("kit", "Lab kit")]
TRACKED = [m["id"] for m in C.MODULES] + ["verify", "capstone", "drill"]

CSS = r'''
/* Layout: technical-reference-manual feel — left rail index, one reading column, wide figures. */
:root{
  --paper:#F1F3F2; --panel:#FFFFFF; --ink:#16201E; --ink2:#33403D; --muted:#5E6B68; --rule:#D2D9D6;
  --accent:#B0561E; --accent-soft:#F4E3D7; --signal:#1D5FA8; --signal-soft:#DCE8F5;
  --ok:#2C7A4B; --ok-soft:#DDEFE3; --bad:#B02A20; --bad-soft:#F6DEDB; --warn:#9A6200; --warn-soft:#F5EAD2;
  --code-bg:#E8ECEA;
  --f-display:"IBM Plex Sans Condensed", "Arial Narrow", system-ui, sans-serif;
  --f-body:"IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
  --f-mono:"IBM Plex Mono", ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace;
}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){
  --paper:#101615; --panel:#172120; --ink:#E3EAE7; --ink2:#C3CECA; --muted:#93A29E; --rule:#2B3735;
  --accent:#E58C52; --accent-soft:#3A271B; --signal:#76AEF0; --signal-soft:#1A2A3D;
  --ok:#5EC489; --ok-soft:#173326; --bad:#F2766C; --bad-soft:#3B1D1A; --warn:#E3AE48; --warn-soft:#3A2D12;
  --code-bg:#1D2928; color-scheme:dark;}}
:root[data-theme="dark"]{
  --paper:#101615; --panel:#172120; --ink:#E3EAE7; --ink2:#C3CECA; --muted:#93A29E; --rule:#2B3735;
  --accent:#E58C52; --accent-soft:#3A271B; --signal:#76AEF0; --signal-soft:#1A2A3D;
  --ok:#5EC489; --ok-soft:#173326; --bad:#F2766C; --bad-soft:#3B1D1A; --warn:#E3AE48; --warn-soft:#3A2D12;
  --code-bg:#1D2928; color-scheme:dark;}
*{box-sizing:border-box}
body{background:var(--paper);color:var(--ink);font-family:var(--f-body);font-size:16px;line-height:1.6;
  padding-left:max(16px, env(safe-area-inset-left, 0px));padding-right:max(16px, env(safe-area-inset-right, 0px))}
a{color:var(--signal)}
code{font-family:var(--f-mono);font-size:.86em;background:var(--code-bg);padding:.08em .32em;border-radius:3px}
.shell{max-width:1240px;margin:0 auto;display:grid;grid-template-columns:232px minmax(0,1fr);gap:48px;padding-block:28px 80px}
nav.rail{position:sticky;top:calc(env(safe-area-inset-top, 0px) + 16px);align-self:start;max-height:calc(100vh - 32px);overflow:auto;font-size:14px}
.rail .prog{font-family:var(--f-mono);font-size:12px;color:var(--muted);margin:0 0 6px}
.rail .bar{height:4px;background:var(--rule);border-radius:2px;margin-bottom:14px;overflow:hidden}
.rail .bar i{display:block;height:100%;width:0;background:var(--accent);transition:width .3s}
.rail ol{list-style:none;margin:0;padding:0;display:grid;gap:1px}
.rail a{display:flex;justify-content:space-between;gap:8px;text-decoration:none;color:var(--ink2);padding:5px 10px;border-left:2px solid transparent}
.rail a:hover{background:var(--panel)}
.rail a.cur{border-left-color:var(--accent);color:var(--ink);font-weight:600;background:var(--panel)}
.rail a .tick{color:var(--ok);font-size:12px;visibility:hidden}
.rail a.ok .tick{visibility:visible}
main{min-width:0}
.hero{border-bottom:1px solid var(--rule);padding-bottom:28px;margin-bottom:8px}
.eyebrow{font-family:var(--f-mono);font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--accent);margin:0}
h1{font-family:var(--f-display);font-weight:600;font-size:clamp(40px,6vw,64px);line-height:1.02;margin:.15em 0 .25em;letter-spacing:-.01em;text-wrap:balance}
.lede{font-size:19px;max-width:62ch;color:var(--ink2);margin:0 0 22px}
.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:1px;background:var(--rule);border:1px solid var(--rule);border-radius:4px;overflow:hidden}
.stat{background:var(--panel);padding:14px 16px;min-width:0}
.stat b{display:block;font-family:var(--f-display);font-size:30px;font-weight:600;line-height:1.1;font-variant-numeric:tabular-nums}
.stat span{display:block;font-size:13px;color:var(--ink2)}
.stat small{display:block;font-size:12px;color:var(--muted);font-family:var(--f-mono)}
section{padding-top:44px;scroll-margin-top:12px}
h2{font-family:var(--f-display);font-weight:600;font-size:36px;line-height:1.1;margin:.1em 0 .2em;text-wrap:balance}
h3{font-family:var(--f-display);font-weight:600;font-size:22px;margin:32px 0 10px;text-wrap:balance}
h4{margin:0}
p,li{max-width:70ch}
.modhead{border-top:3px solid var(--ink);padding-top:12px;display:grid;grid-template-columns:1fr auto;gap:4px 16px;align-items:start}
.modhead h2,.modhead .files{grid-column:1}
.modn{grid-column:1;font-family:var(--f-mono);font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--accent)}
.files{font-family:var(--f-mono);font-size:13px;color:var(--muted);margin:0}
label.done{grid-column:2;grid-row:1 / span 2;font-size:13px;display:flex;gap:6px;align-items:center;white-space:nowrap;cursor:pointer;color:var(--ink2);border:1px solid var(--rule);padding:6px 10px;border-radius:3px;background:var(--panel)}
label.done:has(input:checked){border-color:var(--ok);color:var(--ok)}
.muted{color:var(--muted)}
.fig{margin:22px 0;border:1px solid var(--rule);background:var(--panel);border-radius:4px}
.figscroll{overflow-x:auto;padding:14px}
.fig figcaption{border-top:1px solid var(--rule);padding:10px 14px;font-size:14px;color:var(--ink2)}
.fignum{font-family:var(--f-mono);font-size:12px;color:var(--accent);margin-right:10px}
svg.dg{width:100%;height:auto;display:block;font-family:var(--f-body)}
.dg .bx{fill:var(--panel);stroke:var(--ink2);stroke-width:1.2}
.dg .bx.acc{stroke:var(--accent);stroke-width:2}
.dg .bx.dim{fill:var(--paper);stroke:var(--rule)}
.dg .bx.ghost{fill:none;stroke:var(--rule);stroke-dasharray:4 3}
.dg .bx.key{fill:var(--accent-soft);stroke:var(--accent)}
.dg .bx.imm{fill:var(--bad-soft);stroke:var(--bad)}
.dg .bx.ok{fill:var(--ok-soft);stroke:var(--ok)}
.dg .bx.warn{fill:var(--warn-soft);stroke:var(--warn)}
.dg .hl{fill:none;stroke:var(--bad);stroke-width:2;stroke-dasharray:6 4}
.dg .callout{fill:var(--bad-soft);stroke:var(--bad)}
.dg .cell{fill:var(--paper);stroke:var(--rule)} .dg .cell.on{fill:var(--accent-soft);stroke:var(--accent)}
.dg .seg{fill:var(--paper);stroke:var(--rule)} .dg .seg.on{fill:var(--accent-soft);stroke:var(--accent)}
.dg .bus{fill:var(--signal-soft);stroke:var(--signal)}
.dg .bar{fill:var(--accent)} .dg .bar.full{fill:var(--ok)}
.dg .grid{stroke:var(--rule);stroke-width:1}
.dg .wv{fill:none;stroke:var(--ink);stroke-width:1.6}
.dg .wvbus{fill:var(--signal-soft);stroke:var(--signal);stroke-width:1.2}
.dg .ln{fill:none;stroke:var(--muted);stroke-width:1.4} .dg .ln.dash{stroke-dasharray:5 4}
.dg .ln.sig{stroke:var(--signal);stroke-width:1.8} .dg .ln.bad{stroke:var(--bad)} .dg .ln.acc{stroke:var(--accent);stroke-width:2.4}
.dg .ahd{fill:var(--muted)}
.dg text{fill:var(--ink)} .dg .t{font-size:14px;font-weight:600} .dg .ts{font-size:12px;fill:var(--muted)}
.dg .tm{font-size:14px;fill:var(--muted)} .dg .tm2{font-size:12px;font-family:var(--f-mono)} .dg .lab{font-family:var(--f-mono);font-size:12px;letter-spacing:.08em;fill:var(--accent)}
.dg .tb{font-size:13px;font-weight:600;fill:var(--signal)} .dg .tsig{font-size:12px;fill:var(--signal)}
.dg .tbad{font-size:13px;fill:var(--bad)} .dg .tok{font-size:14px;fill:var(--ok);font-family:var(--f-mono)}
.concepts{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}
.concept{border-top:2px solid var(--signal);padding-top:8px;min-width:0}
.concept h4{font-family:var(--f-display);font-size:17px;font-weight:600;margin-bottom:4px}
.concept p{margin:0;font-size:15px;color:var(--ink2)}
ul.walk{list-style:none;padding:0;margin:0;border:1px solid var(--rule);border-radius:4px;background:var(--panel)}
ul.walk li{display:grid;grid-template-columns:minmax(0,300px) minmax(0,1fr);gap:16px;padding:10px 14px;border-top:1px solid var(--rule);max-width:none;font-size:15px}
ul.walk li:first-child{border-top:0}
code.ref{background:none;padding:0;color:var(--accent);font-size:13px;overflow-wrap:anywhere}
.count{font-family:var(--f-mono);font-size:14px;color:var(--bad);border:1px solid var(--bad);border-radius:10px;padding:0 8px;vertical-align:middle}
.bug{border:1px solid var(--rule);border-left:4px solid var(--bad);background:var(--panel);border-radius:4px;padding:14px 18px;margin:14px 0}
.bug[data-sev="perf"]{border-left-color:var(--warn)} .bug[data-sev="spec"]{border-left-color:var(--signal)}
.bug header{display:flex;flex-wrap:wrap;gap:6px 12px;align-items:baseline}
.bug h4{font-family:var(--f-display);font-size:19px;font-weight:600;flex:1 1 300px}
.bid{font-family:var(--f-mono);font-size:13px;color:var(--bad);font-weight:600}
.sev{font-size:12px;font-family:var(--f-mono);padding:1px 8px;border-radius:10px;white-space:nowrap}
.sev.deadlock{background:var(--bad-soft);color:var(--bad)} .sev.data{background:var(--bad-soft);color:var(--bad)}
.sev.race{background:var(--accent-soft);color:var(--accent)} .sev.spec{background:var(--signal-soft);color:var(--signal)} .sev.perf{background:var(--warn-soft);color:var(--warn)}
.bug p{margin:.5em 0;font-size:15px;max-width:none}
.k{display:inline-block;font-family:var(--f-mono);font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);min-width:92px}
.loc{display:flex;gap:0;align-items:baseline;flex-wrap:wrap} .loc span{font-family:var(--f-mono);font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);min-width:92px}
.hint{color:var(--ink2)}
details>summary{cursor:pointer;color:var(--signal);font-weight:600;font-size:15px;padding:4px 0}
details>summary:focus-visible, a:focus-visible, button:focus-visible, input:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.reveal{border-top:1px dashed var(--rule);margin-top:8px;padding-top:6px}
.twocode{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:10px;margin:10px 0}
.cl{font-family:var(--f-mono);font-size:11px;text-transform:uppercase;letter-spacing:.06em;margin-bottom:2px}
.cl.bad{color:var(--bad)} .cl.ok{color:var(--ok)}
pre.code{margin:0;background:var(--code-bg);border-radius:3px;padding:10px 12px;overflow-x:auto;font-size:12.5px;line-height:1.5}
pre.code code{background:none;padding:0;font-size:inherit}
.lesson{background:var(--ok-soft);padding:8px 10px;border-radius:3px}
ol.build{padding-left:22px} ol.build li{margin:6px 0}
.qa{display:grid;gap:6px}
details.q{border:1px solid var(--rule);border-radius:4px;background:var(--panel);padding:8px 14px}
details.q summary{color:var(--ink);font-weight:600}
details.q p{margin:8px 0 4px;color:var(--ink2);max-width:none}
.loop{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:1px;background:var(--rule);border:1px solid var(--rule);border-radius:4px;overflow:hidden;margin:16px 0}
.loop div{background:var(--panel);padding:12px;min-width:0}
.loop b{display:block;font-family:var(--f-display);font-size:16px}
.loop span{font-size:13px;color:var(--ink2)}
.loop i{font-style:normal;font-family:var(--f-mono);font-size:11px;color:var(--accent)}
/* stepper */
.stepper{border:1px solid var(--rule);border-radius:4px;background:var(--panel);margin:18px 0}
.st-ctrl{display:flex;flex-wrap:wrap;gap:10px;align-items:center;padding:12px 14px;border-bottom:1px solid var(--rule)}
.st-ctrl button{font:600 14px var(--f-body);background:var(--paper);color:var(--ink);border:1px solid var(--rule);border-radius:3px;padding:6px 12px;cursor:pointer}
.st-ctrl button:hover{border-color:var(--ink2)}
.st-ctrl input[type=range]{flex:1 1 200px;accent-color:var(--accent)}
.st-cyc{font-family:var(--f-mono);font-size:14px;min-width:90px;font-variant-numeric:tabular-nums}
.st-note{padding:12px 14px;border-bottom:1px solid var(--rule);background:var(--accent-soft);font-size:15px;min-height:3.6em}
.st-grid{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(0,1fr);gap:0}
.st-col{padding:12px 14px;min-width:0}
.st-col+.st-col{border-left:1px solid var(--rule)}
.st-col h4{font-family:var(--f-mono);font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin:10px 0 6px}
.st-col h4:first-child{margin-top:0}
table.tt{border-collapse:collapse;width:100%;font-size:13px;font-variant-numeric:tabular-nums}
table.tt td,table.tt th{padding:3px 6px;border-bottom:1px solid var(--rule);text-align:left;white-space:nowrap}
table.tt th{font-weight:600;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.05em}
table.tt td.asm{font-family:var(--f-mono);font-size:12.5px}
.pill{display:inline-block;font-family:var(--f-mono);font-size:11px;padding:0 7px;border-radius:9px;border:1px solid var(--rule);color:var(--muted)}
.pill.dec{border-color:var(--signal);color:var(--signal)}
.pill.wait{border-color:var(--warn);color:var(--warn);background:var(--warn-soft)}
.pill.done{border-color:var(--ok);color:var(--ok);background:var(--ok-soft)}
.pill.ret{background:var(--ink);color:var(--paper);border-color:var(--ink)}
.flash{background:var(--signal-soft)}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chip{font-family:var(--f-mono);font-size:12px;border:1px solid var(--rule);border-radius:3px;padding:2px 7px;background:var(--paper)}
.chip.sig{border-color:var(--signal);color:var(--signal);background:var(--signal-soft)}
.chip.ok{border-color:var(--ok);color:var(--ok);background:var(--ok-soft)}
.empty{color:var(--muted);font-size:13px}
/* verification + catalog */
.layers{display:grid;gap:0;border:1px solid var(--rule);border-radius:4px;background:var(--panel)}
.layer{display:grid;grid-template-columns:minmax(0,190px) minmax(0,1fr) minmax(0,1fr);gap:14px;padding:12px 14px;border-top:1px solid var(--rule);font-size:14.5px}
.layer:first-child{border-top:0}
.layer b{font-family:var(--f-display);font-size:16px}
.layer p{margin:0;max-width:none}
.layer .found{color:var(--ink2);border-left:2px solid var(--accent);padding-left:10px}
.filters{display:flex;flex-wrap:wrap;gap:6px;margin:10px 0}
.filters button{font:13px var(--f-body);border:1px solid var(--rule);background:var(--panel);color:var(--ink2);border-radius:14px;padding:3px 12px;cursor:pointer}
.filters button[aria-pressed="true"]{background:var(--ink);color:var(--paper);border-color:var(--ink)}
.tablewrap{overflow-x:auto;border:1px solid var(--rule);border-radius:4px;background:var(--panel)}
table.cat{border-collapse:collapse;width:100%;font-size:14px;min-width:760px}
table.cat th,table.cat td{padding:8px 10px;border-bottom:1px solid var(--rule);text-align:left;vertical-align:top}
table.cat th{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);font-weight:600}
table.cat td code{font-size:12px}
.steps{counter-reset:s;list-style:none;padding:0;display:grid;gap:10px}
.steps li{counter-increment:s;border:1px solid var(--rule);background:var(--panel);border-radius:4px;padding:12px 14px 12px 52px;position:relative;max-width:none}
.steps li::before{content:counter(s);position:absolute;left:14px;top:10px;font-family:var(--f-display);font-size:24px;font-weight:600;color:var(--accent)}
.steps b{font-family:var(--f-display);font-size:17px}
pre.term{background:var(--ink);color:var(--paper);border-radius:4px;padding:14px 16px;overflow-x:auto;font-family:var(--f-mono);font-size:13px;line-height:1.55}
.note{border-left:3px solid var(--signal);padding:6px 12px;background:var(--signal-soft);border-radius:0 3px 3px 0;max-width:70ch}
@media (max-width: 980px){
  .shell{grid-template-columns:minmax(0,1fr);gap:0}
  nav.rail{position:static;max-height:none;border-bottom:1px solid var(--rule);padding-bottom:10px}
  .rail ol{display:flex;flex-wrap:nowrap;overflow-x:auto;gap:4px;padding-bottom:6px}
  .rail a{white-space:nowrap;border-left:0;border-bottom:2px solid transparent;padding:4px 8px}
  .rail a.cur{border-bottom-color:var(--accent)}
  .stats{grid-template-columns:repeat(2,minmax(0,1fr))}
  .loop{grid-template-columns:repeat(2,minmax(0,1fr))}
}
@media (max-width: 680px){
  .concepts,.twocode,.st-grid{grid-template-columns:minmax(0,1fr)}
  .st-col+.st-col{border-left:0;border-top:1px solid var(--rule)}
  ul.walk li,.layer{grid-template-columns:minmax(0,1fr);gap:4px}
  .modhead{grid-template-columns:minmax(0,1fr)} label.done{grid-column:1;grid-row:auto;justify-self:start}
  h2{font-size:30px}
}
@media (prefers-reduced-motion: reduce){*{transition:none!important;scroll-behavior:auto!important}}
'''

NOTES = {
 5: "Cycle 5. The first bundle (addi, addi, mul) sits in decode. Nothing is in the back end yet.",
 6: "Bundle 0 is renamed: the RAT now maps x1→ROB0, x2→ROB1, x3→ROB2. Bundle 1 (add, addi, sub) is in decode. The RAT shown is the registered state at the start of the cycle.",
 7: "ROB 0–2 are allocated. The MUL waits in MD_RS[0] for tags 0 and 1. Tag 0 is exactly the case the original wakeup logic could never wake (bug B04). The addis broadcast 6 and 7 on the CDB this cycle. x3 now maps to ROB5 (the sub): renaming has already removed the WAW hazard on x3.",
 8: "ROB 0 and 1 commit (x1=6, x2=7). The independent addi (ROB4) broadcasts 100. The MUL now has both operands.",
 9: "Bundle 2 arrives. The store waits in the LSB for x4 (tag 3). The load's address is ready, but it must not pass the older store to the same address.",
 10: "Out-of-order completion: the SUB (ROB5, the younger write to x3) finishes before the MUL (ROB2) that comes before it in program order.",
 11: "The MUL is in the Booth pipeline. ROB4 and ROB5 are done, but they cannot commit: ROB2 is the oldest and not ready. In-order commit.",
 14: "The MUL broadcasts 42. The add (ROB3) captures it this cycle…",
 15: "…the MUL commits (x3 = 42 for now). The add needs one more cycle before it is selected: that is the 2-cycle wakeup loop (Fig 4.1).",
 17: "The add broadcasts 48, three cycles after its operand appeared on the CDB.",
 18: "3-wide commit: ROB 3, 4 and 5 retire together. x3 becomes 94 (the SUB), overwriting the MUL's 42 in program order. That is how renaming plus in-order commit resolves WAW.",
 19: "The store got its data, entered the store queue, and became ready.",
 20: "The store commits and becomes a senior store. The load gets 48, forwarded from the store queue, not stale memory.",
 22: "The final add broadcasts 48 + 94 = 142.",
 23: "Done: 9 instructions, every value matches the ISS.",
}

JS = r'''
(function(){
  const T = TRACE_DATA;
  const NOTES = NOTE_DATA;
  const $ = s => document.querySelector(s);
  const asm = T.asm;
  const pcName = pc => asm[pc/4] || ('pc '+pc);
  const hex = v => '0x' + (v>>>0).toString(16);
  let i = 0, timer = null;
  const committedBy = []; // per index: set of pcs committed up to and including that cycle
  let acc = new Set();
  T.cycles.forEach((c,k)=>{ c.commit.forEach(x=>acc.add(x.pc)); committedBy[k]=new Set(acc); });
  const doneBy = []; let dacc = new Set();
  T.cycles.forEach((c,k)=>{ c.rob.forEach(r=>{ if(r.rdy) dacc.add(r.pc); }); c.cdb.forEach(x=>{ const r=(c.rob.find(e=>e.i===x.rob)); if(r) dacc.add(r.pc); }); doneBy[k]=new Set(dacc); });
  function status(pc, k){
    const c = T.cycles[k];
    if (c.commit.some(x=>x.pc===pc)) return ['ret','retiring'];
    if (k>0 && committedBy[k-1].has(pc)) return ['ret','retired'];
    if (c.dec.includes(pc)) return ['dec','decode'];
    const r = c.rob.find(e=>e.pc===pc);
    if (r) return r.rdy || c.cdb.some(x=>x.rob===r.i) ? ['done','done, waits to commit'] : ['wait','in flight'];
    return ['', 'not fetched'];
  }
  function render(){
    const c = T.cycles[i];
    $('#st-cyc').textContent = 'cycle ' + c.c;
    $('#st-range').value = i;
    let note = NOTES[c.c];
    if (!note) note = 'Cycle ' + c.c + '. ' + (c.commit.length ? 'Retiring ROB ' + c.commit.map(x=>x.rob).join(', ') + '. ' : '') + (c.cdb.length ? 'CDB: ' + c.cdb.map(x=>'ROB'+x.rob+'='+x.v).join(', ') + '.' : 'No broadcast this cycle.');
    $('#st-note').textContent = note;
    // program
    let h = '<table class="tt"><tr><th>pc</th><th>instruction</th><th>state</th></tr>';
    asm.forEach((a,k)=>{ const [cls,txt]=status(k*4,i); h += `<tr><td>${(k*4).toString(16).padStart(2,'0')}</td><td class="asm">${a}</td><td><span class="pill ${cls}">${txt}</span></td></tr>`; });
    $('#st-prog').innerHTML = h + '</table>';
    // ROB
    if (c.rob.length){
      h = '<table class="tt"><tr><th>ROB</th><th>instruction</th><th>rd</th><th>ready</th><th>value</th></tr>';
      c.rob.forEach(r=>{ const hot = c.cdb.some(x=>x.rob===r.i); h += `<tr class="${hot?'flash':''}"><td>${r.i}${r.i===c.tail?' ◂commit':''}</td><td class="asm">${pcName(r.pc)}</td><td>${r.rd?'x'+r.rd:'–'}</td><td>${r.rdy?'yes':(hot?'CDB':'no')}</td><td>${r.rdy?r.v:''}</td></tr>`; });
      $('#st-rob').innerHTML = h + '</table>';
    } else $('#st-rob').innerHTML = '<p class="empty">empty</p>';
    // RS
    if (c.rs.length){
      h = '<table class="tt"><tr><th>RS</th><th>ROB</th><th>src1</th><th>src2</th><th>ready</th></tr>';
      const src = (v,t)=> v ? '<span class="pill done">value</span>' : `<span class="pill wait">wait ROB${t}</span>`;
      c.rs.forEach(r=>{ const s2 = r.t==='LSB' ? (r.s2v||r.s2t ? src(r.s2v,r.s2t) : '–') : src(r.s2v,r.s2t); h += `<tr><td>${r.t}[${r.k}]</td><td>${r.rob}</td><td>${src(r.s1v,r.s1t)}</td><td>${s2}</td><td>${r.rdy?'yes':'no'}</td></tr>`; });
      $('#st-rs').innerHTML = h + '</table>';
    } else $('#st-rs').innerHTML = '<p class="empty">no busy entries</p>';
    const rat = Object.entries(c.rat);
    $('#st-rat').innerHTML = rat.length ? '<div class="chips">' + rat.map(([r,t])=>`<span class="chip">x${r} → ROB${t}</span>`).join('') + '</div>' : '<p class="empty">all registers in the ARF</p>';
    $('#st-cdb').innerHTML = c.cdb.length ? '<div class="chips">' + c.cdb.map(x=>`<span class="chip sig">ROB${x.rob} = ${x.v}</span>`).join('') + '</div>' : '<p class="empty">idle</p>';
    $('#st-com').innerHTML = c.commit.length ? '<div class="chips">' + c.commit.map(x=>`<span class="chip ok">ROB${x.rob} ${x.rd?'x'+x.rd+' = '+x.v:'(store)'}</span>`).join('') + '</div>' : '<p class="empty">none</p>';
  }
  function go(k){ i = Math.max(0, Math.min(T.cycles.length-1, k)); render(); }
  function stop(){ if(timer){clearInterval(timer); timer=null; $('#st-play').textContent='Play';} }
  $('#st-range').max = T.cycles.length-1;
  $('#st-prev').onclick = ()=>{stop(); go(i-1);};
  $('#st-next').onclick = ()=>{stop(); go(i+1);};
  $('#st-range').oninput = e=>{stop(); go(+e.target.value);};
  $('#st-play').onclick = ()=>{ if(timer){stop();return;} if(i>=T.cycles.length-1) go(0); $('#st-play').textContent='Pause'; timer=setInterval(()=>{ if(i>=T.cycles.length-1){stop();return;} go(i+1); }, 1400); };
  document.addEventListener('keydown', e=>{ if(e.target.closest('input,textarea')) return; const r=$('#run').getBoundingClientRect(); if(r.top<innerHeight && r.bottom>0){ if(e.key==='ArrowRight'){stop();go(i+1);} if(e.key==='ArrowLeft'){stop();go(i-1);} }});
  go(0);

  // progress (per-viewer convenience only)
  const TR = TRACKED_IDS;
  const store = { get(k){ try{return localStorage.getItem(k);}catch(e){return null;} }, set(k,v){ try{localStorage.setItem(k,v);}catch(e){} } };
  function prog(){
    let n=0; TR.forEach(id=>{ const cb=document.getElementById('done-'+id); const on = cb && cb.checked; if(on) n++; const a=document.querySelector('.rail a[href="#'+id+'"]'); if(a) a.classList.toggle('ok', !!on); });
    $('#prog-txt').textContent = n + ' of ' + TR.length + ' sections done';
    $('#prog-bar').style.width = (100*n/TR.length) + '%';
  }
  TR.forEach(id=>{ const cb=document.getElementById('done-'+id); if(!cb) return; cb.checked = store.get('done-'+id)==='1'; cb.addEventListener('change', ()=>{ store.set('done-'+id, cb.checked?'1':'0'); prog(); }); });
  prog();
  // current section in rail
  const links=[...document.querySelectorAll('.rail a')];
  const obs = new IntersectionObserver(es=>{ es.forEach(en=>{ if(en.isIntersecting){ links.forEach(a=>a.classList.toggle('cur', a.getAttribute('href')==='#'+en.target.id)); } }); }, {rootMargin:'-20% 0px -70% 0px'});
  document.querySelectorAll('main section[id]').forEach(s=>obs.observe(s));
  // catalog filters
  document.querySelectorAll('.filters button').forEach(b=>b.addEventListener('click', ()=>{
    document.querySelectorAll('.filters button').forEach(x=>x.setAttribute('aria-pressed', x===b?'true':'false'));
    const f=b.dataset.f; document.querySelectorAll('table.cat tbody tr').forEach(tr=>{ tr.hidden = !(f==='all' || tr.dataset.sev===f); });
  }));
})();
'''

def page():
    P = []
    P.append('<title>Tomasulo Core Lab</title><meta name="claude:viewport-fit-sides" content="cover">')
    P.append('<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>')
    P.append('<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans+Condensed:wght@500;600&family=IBM+Plex+Sans:ital,wght@0,400;0,600;1,400&display=swap">')
    P.append(f'<style>{CSS}</style>')
    P.append('<div class="shell"><nav class="rail" aria-label="Course sections"><p class="prog" id="prog-txt">0 sections done</p><div class="bar"><i id="prog-bar"></i></div><ol>')
    for i, n in NAV:
        P.append(f'<li><a href="#{i}"><span>{n}</span><span class="tick">✓</span></a></li>')
    P.append('</ol></nav><main>')
    # hero
    P.append('<header class="hero" id="start"><p class="eyebrow">RV32IM · 3-wide · Tomasulo + ROB · result_3.zip</p>'
             '<h1>Tomasulo Core Lab</h1>'
             '<p class="lede">Your out-of-order core, taken apart one module at a time. Every concept is tied to a line of your RTL, and every bug below was reproduced in simulation, fixed, and re-verified against a golden model.</p><div class="stats">')
    for big, s, sm in C.STATS:
        P.append(f'<div class="stat"><b>{big}</b><span>{s}</span><small>{sm}</small></div>')
    P.append('</div></header>')
    # start here
    P.append('<section id="how"><h2>How to use this</h2><p>Work through the modules in order. Each one follows the same loop, which is also the loop a DV engineer runs on a real block:</p><div class="loop">'
             '<div><i>1</i><b>Read</b><span>What it does, the hidden concepts, the code walk with line numbers.</span></div>'
             '<div><i>2</i><b>Reproduce</b><span>Run the bug-hunt test on <code>rtl/</code>. Watch it fail.</span></div>'
             '<div><i>3</i><b>Fix it yourself</b><span>Use the hint. Re-run until the ISS agrees.</span></div>'
             '<div><i>4</i><b>Compare</b><span>Reveal the root cause, diff against <code>solutions/</code>.</span></div>'
             '<div><i>5</i><b>Explain</b><span>Answer the interview questions out loud, in 60 seconds each.</span></div></div>'
             '<p class="note">The lab kit (sent alongside this page) has everything: your RTL with only the 4 compile fixes, the full solutions, the testbench, the ISS, 20 directed tests, the random generator, SVA and a unit test. It runs on Verilator 5.026 or newer. The same files also run on Xcelium.</p></section>')
    # machine
    P.append('<section id="machine"><div class="modhead"><span class="modn">Module 0</span><h2>The machine at a glance</h2><p class="files">design.sv · tomasulo_pkg.sv</p></div>')
    P.append(D.machine())
    P.append('''<h3>The life of one instruction</h3>
<p>Follow <code>mul x3, x1, x2</code> from the demo program (measured cycle numbers in the stepper below):</p>
<ol class="build">
<li><b>Fetch</b>: read with its bundle into the fetch register, then the instruction queue, then the fetch→decode latch.</li>
<li><b>Decode</b> (cycle 5): operation key, type 10 (MUL/DIV), sources x1 and x2, destination x3.</li>
<li><b>Rename / dispatch</b> (cycle 6): gets ROB 2. Its sources are produced by ROB 0 and 1 in the same bundle, so it records <i>tags</i>, not values. The RAT now says x3 → ROB 2.</li>
<li><b>Reservation station</b> (cycle 7): written into MD_RS[0], waiting for tags 0 and 1. Both broadcast this cycle.</li>
<li><b>Issue and execute</b> (cycle 9 onward): selected, then 3 Booth stages and the completion buffer.</li>
<li><b>Writeback</b> (cycle 14): 42 on the CDB with tag 2. The ROB entry becomes ready, and the waiting add captures the value.</li>
<li><b>Commit</b> (cycle 15): oldest in the ROB, so it retires and writes x3 = 42 into the architectural register file.</li></ol>
<div class="concepts"><div class="concept"><h4>Three orders</h4><p>Instructions <b>enter</b> in program order (fetch, decode, rename), <b>execute</b> in dataflow order (whenever operands are ready), and <b>leave</b> in program order (commit). Everything in an OOO core exists to connect those three orders safely.</p></div>
<div class="concept"><h4>Three hazards, three answers</h4><p>WAR and WAW (false dependencies): renaming. RAW through registers: tags and wakeup on the CDB. RAW through memory: the load/store queues, because addresses are only known late.</p></div></div>
</section>''')
    # stepper
    P.append('''<section id="run"><div class="modhead"><span class="modn">Interactive</span><h2>Watch it run</h2><p class="files">real trace · fixed RTL · tests/demo_stepper.s</p></div>
<p>A real cycle-by-cycle trace from Verilator of the <b>fixed</b> core running a 9-instruction program built to show renaming, out-of-order completion, in-order commit and a store→load dependence. Padding NOPs are hidden. Use the arrow keys or the slider.</p>
<div class="stepper" aria-label="Cycle stepper">
 <div class="st-ctrl"><button id="st-prev" type="button">◂ Prev</button><button id="st-play" type="button">Play</button><button id="st-next" type="button">Next ▸</button>
 <input id="st-range" type="range" min="0" max="1" value="0" aria-label="cycle"><span class="st-cyc" id="st-cyc">cycle</span></div>
 <div class="st-note" id="st-note" aria-live="polite"></div>
 <div class="st-grid"><div class="st-col"><h4>Program</h4><div id="st-prog"></div><h4>RAT (register → in-flight producer)</h4><div id="st-rat"></div></div>
 <div class="st-col"><h4>Reorder buffer</h4><div id="st-rob"></div><h4>Reservation stations</h4><div id="st-rs"></div><h4>CDB this cycle</h4><div id="st-cdb"></div><h4>Commit this cycle</h4><div id="st-com"></div></div></div>
</div>
<p class="muted">Try this: step to cycle 10 and find two instructions that are done but cannot commit. Then explain to yourself why x3 ends up 94 and not 42.</p></section>''')
    for m in C.MODULES:
        P.append(module(m))
    # verification
    V = C.VERIFY
    P.append('<section id="verify" data-track="verify"><div class="modhead"><span class="modn">Module 9</span><h2>Verification: how these bugs were found</h2><p class="files">tb/ · tools/ · tests/ · unit/</p>'
             '<label class="done"><input type="checkbox" id="done-verify"> Mark module done</label></div>' + V["intro"])
    P.append(D.vflow())
    P.append('<h3>Six layers, and what each one caught</h3><div class="layers">')
    for t, d, f in V["layers"]:
        P.append(f'<div class="layer"><b>{t}</b><p>{d}</p><p class="found">{f}</p></div>')
    P.append('</div>')
    P.append(D.bars(V["stages"]))
    P.append('''<h3>Principles to say out loud in an interview</h3><div class="concepts">
<div class="concept"><h4>Check the contract, not the implementation</h4><p>The hard-coded checker encoded what the author expected the RTL to do, including a wrong comment (instruction 16 is <code>xor</code>). An independent reference model encodes what the <i>ISA</i> says.</p></div>
<div class="concept"><h4>Liveness is a check</h4><p>Half of these bugs were deadlocks. Without a watchdog that reports which ROB entry is stuck, a deadlock looks like a slow test.</p></div>
<div class="concept"><h4>Masking and layering</h4><p>Fix, re-run, repeat. The failure profile changed completely after each layer of fixes.</p></div>
<div class="concept"><h4>Random needs constraints</h4><p>8 memory words instead of 1024 is what made aliasing common enough to hit the LSQ bugs in 120 seeds.</p></div></div>
<h3>Build it</h3><ol class="build">
<li>Add <b>functional coverage</b> to <code>tb_lab.sv</code> (covergroups or counters): forward vs. wait vs. memory read per load size, ROB occupancy buckets, CDB lanes used per cycle, RS full events. Which of these did the 720 random seeds never hit?</li>
<li>Close the A5 blind spot: <code>b11_branch</code> deadlocks without any assertion firing, because the ROB head is <i>invalid</i>, not stuck. Write a property that catches a hole between commit and alloc pointers.</li>
<li>Add an IPC check per directed test, so a performance regression (like the 2-cycle wakeup loop) fails CI.</li></ol>
<h3>Interview questions</h3>''' + qa_block([
 ("Your test passes. Why might you still not trust it?", "Because the checker might be wrong or blind. Here the original checker was keyed by ROB id with hand-written expectations (one comment was wrong), it ignored liveness (an instruction-count cap ended the test), and it could not see internal invariants (the LQ duplicate). Ask: what is the oracle, what does it compare, at what granularity, and what can fail without the oracle noticing?"),
 ("Scoreboard at commit vs. at writeback: trade-offs?", "Commit-level comparison is architecturally clean (it matches the ISS exactly) but reports late and cannot see transient corruption that gets overwritten. Writeback- or unit-level scoreboards localise failures but need a microarchitectural model (expected latency, ordering). Real projects do both: architectural at the top, transaction-level at each unit boundary."),
 ("How do you know you're done verifying?", "Coverage closure against a verification plan (features × corner cases), assertion coverage (every property exercised, not just never failed), a bug-rate trend that has flattened across random seeds, a code-coverage review of holes, and sign-off reviews. Never 'all tests pass'."),
]) + '</section>')
    # capstone
    K = C.CAPSTONE
    P.append('<section id="capstone" data-track="capstone"><div class="modhead"><span class="modn">Module 10</span><h2>Capstone: build branch support</h2><p class="files">every module</p>'
             '<label class="done"><input type="checkbox" id="done-capstone"> Mark module done</label></div>' + K["intro"] + '<ol class="steps">')
    for t, d in K["steps"]:
        P.append(f'<li><b>{t}</b><p>{d}</p></li>')
    P.append('</ol><p class="note">Done means: <code>b11_branch</code> passes, plus your own loop, call/return and data-dependent-branch tests pass against <code>tools/rv.py</code>, with 0 SVA firings over 500 random seeds after you add branches to <code>gen_random.py</code>.</p></section>')
    # drill
    P.append('<section id="drill" data-track="drill"><div class="modhead"><span class="modn">Practice</span><h2>Interview drill</h2><p class="files">senior design verification · CPU / GPU</p>'
             '<label class="done"><input type="checkbox" id="done-drill"> Mark done</label></div>'
             '<p>Answer each out loud before you open it. A good answer names a mechanism, a failure mode, and how you would check it.</p>' + qa_block(C.INTERVIEW) + '</section>')
    # catalog
    P.append('<section id="catalog"><div class="modhead"><span class="modn">Reference</span><h2>Bug catalog</h2><p class="files">15 functional bugs · 4 compile errors · 10 review findings</p></div>'
             '<div class="filters" role="group" aria-label="Filter by severity"><button type="button" data-f="all" aria-pressed="true">All</button>')
    for k, v in SEV.items():
        P.append(f'<button type="button" data-f="{k}" aria-pressed="false">{v}</button>')
    P.append('</div><div class="tablewrap"><table class="cat"><thead><tr><th>ID</th><th>Bug</th><th>Type</th><th>Where</th><th>Found by</th><th>Status</th></tr></thead><tbody>')
    for bid, b in C.BUGS.items():
        caught = b['caught'].split('.')[0]
        P.append(f'<tr data-sev="{b["sev"]}"><td><a href="#{bid}">{bid}</a></td><td>{b["title"]}</td><td><span class="sev {b["sev"]}">{SEV[b["sev"]]}</span></td><td><code>{E(b["loc"])}</code></td><td>{caught}</td><td>fixed</td></tr>')
    for sev, t, loc, d in C.NOTFIXED:
        P.append(f'<tr data-sev="{sev}"><td>R</td><td><b>{t}</b><br><span class="muted">{d}</span></td><td><span class="sev {sev}">{SEV[sev]}</span></td><td><code>{E(loc)}</code></td><td>code review</td><td>open (exercise)</td></tr>')
    for loc, d in C.COMPILE:
        P.append(f'<tr data-sev="race"><td>C</td><td>{d}</td><td><span class="sev race">Compile / elab</span></td><td><code>{E(loc)}</code></td><td>Xcelium / Verilator</td><td>fixed in rtl/</td></tr>')
    P.append('</tbody></table></div></section>')
    # kit
    P.append('''<section id="kit"><div class="modhead"><span class="modn">Reference</span><h2>Lab kit</h2><p class="files">tomasulo_core_lab.zip</p></div>
<pre class="term">rtl/          your design + only the 4 compile fixes (start here)
solutions/    reference fixes, each marked FIX-n in a comment
patches/      one diff per file: rtl/ vs solutions/
tb/           tb_lab.sv (commit monitor, watchdog, +TRACE) · core_sva.sv (bind)
tools/        rv.py (assembler + ISS) · run_test.py · gen_random.py · trace2json.py
tests/        t00_original + b01..b19 bug hunts
unit/         tb_btb_plru.sv
examples/     demo_stepper.s (the program in "Watch it run")</pre>
<pre class="term"># build both designs (Verilator >= 5.026)
make sim RTL=rtl          # your design
make sim RTL=solutions    # reference

# one test, then the whole directed suite
make test T=tests/b03_rob_tag0.s RTL=rtl
make regress RTL=solutions

# constrained random
python3 tools/gen_random.py 42 build/r42.s
SIM_BIN=obj_solutions/sim python3 tools/run_test.py build/r42.s

# debug views
obj_rtl/sim +PROG=$PWD/build/b03_rob_tag0.hex +DEBUG     # the design's own per-cycle dump
obj_rtl/sim +PROG=$PWD/build/b07_three_loads_same_addr.hex +MMUDBG</pre>
<p class="note">On Xcelium: <code>xrun -sv -timescale 1ns/1ns -incdir rtl rtl/design.sv tb/core_sva.sv tb/tb_lab.sv</code> and pass the same <code>+PROG=</code>. <code>run_test.py</code> only needs the simulator command in <code>SIM_BIN</code> to print the <code>COMMIT</code>/<code>STATUS</code> lines.</p>
<p class="note">Assertions are on by default. A firing assertion stops the run and <code>run_test.py</code> prints it as <code>ASSERTION: [SVA A7] …</code>. That is why your original <code>t00</code> fails with SVA on and passes with <code>make sim SVA=0</code>.</p>
</section>''')
    P.append('</main></div>')
    js = JS.replace('TRACE_DATA', json.dumps(TRACE, separators=(',', ':'))).replace('NOTE_DATA', json.dumps(NOTES)).replace('TRACKED_IDS', json.dumps(TRACKED))
    P.append(f'<script>{js}</script>')
    return '\n'.join(P)

open(OUT, 'w').write(page())
print('wrote', OUT, os.path.getsize(OUT))
