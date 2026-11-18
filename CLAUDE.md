# Standing instructions for an AI agent working in this package

This is the RTM companion package: a phone-panel monitoring workflow in Stata, on synthetic data laid out like the L2PHL phone rounds. Read `README.md` first. `prompts/README.md` says how an agent is set up here and `prompts/dashboard_prompt.md` is the prompt that built the dashboard page.

## Privacy

- Treat `CATI/Round##/xls`, `zzz`, `dta`, `pii`, `fix` and `CATI/Analysis/HF` and `2share` as if they held real households: never print a row from them, never paste one into a reply, a commit message or an issue, never copy them anywhere. Report counts.
- Anything meant for people outside the team (the dashboard, a table, a note) carries aggregates only, with cells under 10 households, members or dials left empty. Never fill a suppressed cell.
- Enumerators are referred to by their program code (E01, ...), never by a name.

## Working in the code

- Everything runs from `L2PHL_SYN_master.do` in the package folder; `tests/run_tests.do` runs it and checks the results against `tests/expected_counts.csv`. Run the tests after any change to a do-file or an ado-file and do not keep a change that fails them.
- Keep the layout: CAPI for the baseline, CATI/Round## for a phone round, CATI/Analysis for the work across rounds, dated subfolders for everything the run writes. Inputs are the files under version control; outputs are in `.gitignore` and are never committed.
- Keep the do-file conventions (PREAMBLES block, `**#` bookmarked sections, folding braces, the short command forms). No user-written Stata commands other than the optional `ebalance`.
- The dashboard page computes nothing from data: Stata writes `dashboard_data.js`, the page draws it. A new number means a new column in a do-file, not a calculation in the page.
- No slash-star sequences inside Stata comments (they open a block comment).
- Never hard-code a survey number into text or code: numbers come from the data through the do-files.
- Do not add names of people, local paths or credentials to any file.
