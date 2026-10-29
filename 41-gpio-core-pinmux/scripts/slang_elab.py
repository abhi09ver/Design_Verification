#!/usr/bin/env python3
"""Elaborate the UVM testbench with slang (pip install pyslang).

Uses slang's own diagnostic engine, so -W / -Wno- options on the command line
apply. Prints diagnostics that point at this project's files (not the UVM
library) and exits non-zero on any error anywhere.
Usage: see the 'elab' target in the Makefile.
"""
import os
import sys

import pyslang

D = pyslang.driver
here = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

drv = D.Driver()
drv.addStandardArgs()
if not drv.parseCommandLine(" ".join(["slang"] + sys.argv[1:]), D.CommandLineOptions()):
    sys.exit(2)
if not drv.processOptions():
    sys.exit(2)
drv.parseAllSources()
comp = drv.createCompilation()

engine = drv.diagEngine            # carries the -W / -Wno- settings
sm = comp.sourceManager
Sev = pyslang.DiagnosticSeverity
errors = 0
shown = 0
for diag in comp.getAllDiagnostics():
    sev = engine.getSeverity(diag.code, diag.location)
    if sev == Sev.Ignored:
        continue
    is_err = sev in (Sev.Error, Sev.Fatal)
    errors += int(is_err)
    path = str(sm.getFullPath(diag.location.buffer)) if diag.location else ""
    mine = bool(path) and here in os.path.abspath(path) and "uvm-core" not in path
    if is_err or mine:
        engine.issue(diag)
        shown += 1

print(drv.textDiagClient.getString())
print(f"slang: {errors} error(s), {shown} diagnostic(s) shown for this project")
sys.exit(1 if errors else 0)
