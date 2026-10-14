# Design_Verification

Interview preparation notes for Senior Design Verification (DV) Engineer roles.
Each file takes one real-world DV challenge, explains it from first principles, corrects common misconceptions, and ends with likely interviewer follow-ups and a 60-second answer pitch.

## Challenges

| # | Topic | Key concepts |
|---|---|---|
| 01 | [The `uvm_config_db` "Phasing Trap"](01-uvm-config-db-phasing-trap.md) | `create()` vs `build_phase`, config_db lookup (scope/name/type), factory overrides, `super.build_phase`, objections, debug flow |
| 02 | [Constrained-Random Verification Storytelling](02-constrained-random-verification-storytelling.md) | Constraint layering, `dist`/`soft`/`solve-before`, seeds vs. constraints, regression budgeting, coverage ranking, STAR bug story |

## How each file is structured

1. Problem statement
2. Background concepts (fresher level)
3. Root-cause analysis
4. Debug steps used in real projects
5. Minimal fix vs. robust senior-level fix
6. Likely interviewer follow-ups with model answers
7. Common mistakes
8. 60-second interview pitch
9. Self-check list
