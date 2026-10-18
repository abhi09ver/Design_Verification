#!/usr/bin/env python3
"""Builds the RISC-V CPU verification atlas: one infographic plate per concept."""
import html, importlib.util, pathlib, sys

HERE = pathlib.Path(__file__).parent
PLATES = []
for part in sorted(HERE.glob("plates_*.py")):
    spec = importlib.util.spec_from_file_location(part.stem, part)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    PLATES.extend(mod.PLATES)

PARTS = {
    "I":   ("Architecture", "What the ISA promises"),
    "II":  ("Design", "How one core keeps the promise"),
    "III": ("Performance", "Pipelines, out-of-order, memory"),
    "IV":  ("Verification", "Proving it, and proving the proof"),
    "V":   ("Interview", "Bugs, debug, and the answers"),
}

CSS = r"""
/* Layout: an atlas of uniform plates. Each plate = header strip, diagram + deep dive, then a
   three-cell footer (spec rules / bugs that live here / interview line). Same order on every plate. */
:root{
  --paper:#eef1f4; --card:#ffffff; --ink:#132030; --muted:#566476; --rule:#cfd7e0; --wash:#e3e9ef;
  --accent:#1f5fae;           /* signal blue: design, wires */
  --dv:#0d7a6c;               /* verification teal */
  --bug:#b8322a; --bugwash:#fbeceb;
  --rule-c:#8a5a00; --rulewash:#fbf3e2;
  --askwash:#e8f1fb;
  --f-display:"Barlow Condensed","Arial Narrow",system-ui,sans-serif;
  --f-body:"IBM Plex Sans",system-ui,-apple-system,"Segoe UI",sans-serif;
  --f-mono:"JetBrains Mono",ui-monospace,"SFMono-Regular",Menlo,Consolas,monospace;
}
@media (prefers-color-scheme: dark){ :root:not([data-theme="light"]){
  --paper:#0e141b; --card:#151e28; --ink:#dde5ee; --muted:#93a2b3; --rule:#2a3746; --wash:#1b2632;
  --accent:#6aa5ec; --dv:#3cc2ae; --bug:#ff7b6e; --bugwash:#2e1a1a; --rule-c:#e2b65a; --rulewash:#2a2414;
  --askwash:#16263a; color-scheme:dark; } }
:root[data-theme="dark"]{
  --paper:#0e141b; --card:#151e28; --ink:#dde5ee; --muted:#93a2b3; --rule:#2a3746; --wash:#1b2632;
  --accent:#6aa5ec; --dv:#3cc2ae; --bug:#ff7b6e; --bugwash:#2e1a1a; --rule-c:#e2b65a; --rulewash:#2a2414;
  --askwash:#16263a; color-scheme:dark; }

*{box-sizing:border-box}
body{background:var(--paper);color:var(--ink);font:15px/1.5 var(--f-body);}
body::before{content:"";position:fixed;inset:0 0 auto;height:env(safe-area-inset-top,0px);z-index:10;background:var(--card)}
.wrap{max-width:1180px;margin:0 auto;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));padding-block:0 48px}
code,.mono{font-family:var(--f-mono);font-size:.86em}
h1,h2,h3{font-family:var(--f-display);text-wrap:balance;margin:0;letter-spacing:.01em}

/* masthead */
.mast{padding-block:28px 18px;display:grid;gap:10px;border-bottom:2px solid var(--ink)}
.mast .kicker{font:600 12px/1 var(--f-mono);letter-spacing:.14em;text-transform:uppercase;color:var(--accent)}
.mast h1{font-size:clamp(34px,6vw,58px);font-weight:700;line-height:.95}
.mast p{margin:0;max-width:72ch;color:var(--muted)}
.legend{display:flex;flex-wrap:wrap;gap:8px 18px;font-size:13px;color:var(--muted)}
.legend span{display:inline-flex;align-items:center;gap:6px}
.sw{width:12px;height:12px;border-radius:2px;display:inline-block}

/* sticky index */
.nav{position:sticky;top:env(safe-area-inset-top,0px);z-index:9;background:var(--card);border-bottom:1px solid var(--rule);margin-inline:calc(-1*max(16px,env(safe-area-inset-left,0px)));padding:8px max(16px,env(safe-area-inset-left,0px))}
.nav-row{display:flex;gap:6px;overflow-x:auto;scrollbar-width:thin;padding-bottom:2px}
.nav a{flex:0 0 auto;text-decoration:none;color:var(--ink);font:500 12.5px/1 var(--f-mono);padding:7px 9px;border:1px solid var(--rule);border-radius:4px;background:var(--paper);white-space:nowrap}
.nav a:hover,.nav a:focus-visible{border-color:var(--accent);color:var(--accent);outline:none}
.nav a b{font-family:var(--f-display);font-size:14px;letter-spacing:.03em}

/* part dividers */
.part{margin-top:42px;display:grid;grid-template-columns:auto 1fr;gap:4px 16px;align-items:end;border-bottom:1px solid var(--rule);padding-bottom:8px}
.part .num{font:700 64px/0.8 var(--f-display);color:var(--accent);grid-row:span 2}
.part h2{font-size:30px}
.part p{margin:0;color:var(--muted)}

/* plate */
.plate{margin-top:22px;background:var(--card);border:1px solid var(--rule);border-radius:6px;overflow:hidden;scroll-margin-top:64px}
.ph{display:grid;grid-template-columns:auto 1fr;gap:2px 14px;padding:14px 18px 12px;border-bottom:1px solid var(--rule);background:var(--wash)}
.ph .code{grid-row:span 2;font:700 15px/1 var(--f-mono);color:var(--card);background:var(--ink);padding:8px 8px;border-radius:3px;align-self:start;text-align:center;min-width:52px}
.ph h3{font-size:clamp(22px,3vw,30px);font-weight:700;line-height:1.05}
.ph .thesis{margin:2px 0 0;color:var(--muted);max-width:90ch}
.pb{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(0,1fr);gap:18px;padding:16px 18px}
.fig{min-width:0}
.fig .scroll{overflow-x:auto}
.deep{min-width:0}
.deep h4,.pf h4{font:600 11.5px/1 var(--f-mono);letter-spacing:.12em;text-transform:uppercase;margin:0 0 8px;color:var(--muted)}
.deep ul{margin:0;padding-left:18px;display:grid;gap:6px}
.deep li::marker{color:var(--accent)}
.pf{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));border-top:1px solid var(--rule)}
.pf > div{padding:12px 16px;min-width:0}
.pf ul{margin:0;padding-left:16px;display:grid;gap:5px;font-size:14px}
.pf .rules{background:var(--rulewash)} .pf .rules h4{color:var(--rule-c)}
.pf .bugs{background:var(--bugwash)} .pf .bugs h4{color:var(--bug)}
.pf .ask{background:var(--askwash)} .pf .ask h4{color:var(--accent)}
.pf .ask p{margin:0 0 6px;font-size:14px}
.pf .ask .q{font-weight:600}
.tag{display:inline-block;font:600 10.5px/1 var(--f-mono);padding:3px 5px;border-radius:3px;border:1px solid currentColor;margin-right:4px;vertical-align:1px}
.t-bug{color:var(--bug)} .t-dv{color:var(--dv)} .t-rule{color:var(--rule-c)} .t-d{color:var(--accent)}

/* figure parts */
table.bits{border-collapse:collapse;font:12px/1.2 var(--f-mono);width:100%;min-width:560px}
table.bits td,table.bits th{border:1px solid var(--rule);padding:5px 4px;text-align:center}
table.bits th{font-weight:500;color:var(--muted);background:var(--paper);font-size:10.5px}
table.bits td.f{background:var(--wash)}
table.bits td.imm{background:var(--rulewash);color:var(--rule-c);font-weight:600}
table.bits td.op{background:var(--askwash);color:var(--accent)}
table.bits td.lbl{text-align:left;font-weight:700;background:var(--card);font-family:var(--f-display);font-size:15px}
table.grid{border-collapse:collapse;font-size:13px;width:100%}
table.grid th,table.grid td{border-bottom:1px solid var(--rule);padding:5px 8px;text-align:left;vertical-align:top}
table.grid th{font:600 11px/1.2 var(--f-mono);letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}
table.grid td.n{font-variant-numeric:tabular-nums;text-align:right;font-family:var(--f-mono)}
.bad{color:var(--bug);font-weight:600} .good{color:var(--dv);font-weight:600}
svg{max-width:100%;height:auto;display:block}
svg .ink{fill:var(--ink)} svg .mut{fill:var(--muted)} svg .acc{fill:var(--accent)} svg .dvf{fill:var(--dv)} svg .bugf{fill:var(--bug)}
svg .box{fill:var(--card);stroke:var(--ink);stroke-width:1.4}
svg .boxw{fill:var(--wash);stroke:var(--rule);stroke-width:1.2}
svg .boxa{fill:var(--askwash);stroke:var(--accent);stroke-width:1.4}
svg .boxd{fill:var(--card);stroke:var(--dv);stroke-width:1.6}
svg .boxb{fill:var(--bugwash);stroke:var(--bug);stroke-width:1.4}
svg .boxr{fill:var(--rulewash);stroke:var(--rule-c);stroke-width:1.2}
svg .w{stroke:var(--ink);stroke-width:1.4;fill:none}
svg .wa{stroke:var(--accent);stroke-width:1.8;fill:none}
svg .wd{stroke:var(--dv);stroke-width:1.8;fill:none}
svg .wb{stroke:var(--bug);stroke-width:1.8;fill:none;stroke-dasharray:5 3}
svg .wm{stroke:var(--muted);stroke-width:1;fill:none;stroke-dasharray:3 3}
svg text{font-family:var(--f-body);font-size:12px}
svg .t{fill:var(--ink)} svg .tm{fill:var(--muted);font-size:11px} svg .tb{font-weight:700}
svg .tmono{font-family:var(--f-mono);font-size:11px}
svg .th{font-family:var(--f-display);font-size:15px;font-weight:700;fill:var(--ink)}
.callout{margin-top:10px;padding:8px 12px;border-left:3px solid var(--accent);background:var(--wash);font-size:13.5px}
.callout.b{border-color:var(--bug)} .callout.d{border-color:var(--dv)}
.kv{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;font-size:13.5px}
.kv dt{font-family:var(--f-mono);font-size:12.5px;color:var(--accent)}
.kv dd{margin:0}
.chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
.chip{font:500 12px/1 var(--f-mono);border:1px solid var(--rule);border-radius:999px;padding:5px 9px;background:var(--paper)}
.foot{margin-top:40px;color:var(--muted);font-size:13px;border-top:1px solid var(--rule);padding-top:12px}

@media (max-width:860px){ .pb{grid-template-columns:1fr} .pf{grid-template-columns:1fr} }
@media (max-width:480px){ .part .num{font-size:46px} .ph{padding:12px} .pb{padding:12px} }
@media (prefers-reduced-motion: no-preference){ .nav a{transition:border-color .15s,color .15s} }
"""

def li(items): return "".join(f"<li>{x}</li>" for x in items)

def plate(p):
    ask = "".join(f'<p class="q">{q}</p><p>{a}</p>' for q, a in p["ask"])
    return f"""
<article class="plate" id="{p['id']}">
  <header class="ph"><span class="code">{p['id'].upper().replace('P','PL·')}</span>
    <h3>{p['title']}</h3><p class="thesis">{p['thesis']}</p></header>
  <div class="pb"><div class="fig">{p['fig']}</div>
    <div class="deep"><h4>Deep dive</h4><ul>{li(p['deep'])}</ul></div></div>
  <div class="pf">
    <div class="rules"><h4>Spec rules &amp; constraints</h4><ul>{li(p['rules'])}</ul></div>
    <div class="bugs"><h4>Bugs that live here</h4><ul>{li(p['bugs'])}</ul></div>
    <div class="ask"><h4>Interview</h4>{ask}</div>
  </div>
</article>"""

def build():
    nav = "".join(f'<a href="#{p["id"]}"><b>{p["id"][1:]}</b> {p["short"]}</a>' for p in PLATES)
    body, cur = [], None
    for p in PLATES:
        if p["part"] != cur:
            cur = p["part"]; name, sub = PARTS[cur]
            body.append(f'<section class="part" id="part-{cur}"><span class="num">{cur}</span><h2>{name}</h2><p>{sub}</p></section>')
        body.append(plate(p))
    out = f"""<title>RISC-V Core &amp; DV Atlas</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;700&family=IBM+Plex+Sans:wght@400;500;600&family=JetBrains+Mono:wght@400;500;600;700&display=swap">
<style>{CSS}</style>
<div class="wrap">
<header class="mast">
  <span class="kicker">RV32I · single-cycle · 5-stage · Tomasulo · class-based DV</span>
  <h1>RISC-V Core &amp; Verification Atlas</h1>
  <p>One plate per concept, built up from the ISA contract to out-of-order execution to how a senior CPU
  verification engineer proves it all works. Every plate reads the same way. Bugs marked with an ID were found
  and fixed in the YARP, pq5 and Tomasulo labs.</p>
  <div class="legend">
    <span><i class="sw" style="background:var(--accent)"></i>design / datapath</span>
    <span><i class="sw" style="background:var(--dv)"></i>verification</span>
    <span><i class="sw" style="background:var(--rule-c)"></i>spec rule / constraint</span>
    <span><i class="sw" style="background:var(--bug)"></i>bug</span>
  </div>
</header>
<nav class="nav" aria-label="Plates"><div class="nav-row">{nav}</div></nav>
{''.join(body)}
<p class="foot">Lab IDs: Y1–Y4 = YARP RTL bugs · B01–B15 = Tomasulo core bugs · T/D/M/A/S = YARP class-testbench bugs · P1–P6 = injected mutants.
Measured numbers come from the labs in the Design_Verification repo, branch cpu-ooo-interview-lab.</p>
</div>"""
    (HERE / "riscv_dv_atlas.html").write_text(out)
    print(f"{len(PLATES)} plates, {len(out)//1024} KB")

if __name__ == "__main__":
    build()
