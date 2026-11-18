# Setting up an AI agent on this package

The dashboard in this package (`CATI/Analysis/do/dashboard_template.html`) was written by an AI coding agent from a prompt; Stata writes the numbers, the agent wrote the page that draws them. This folder holds that prompt and the way to set an agent up, so a team can build its own dashboard, or change this one, the same way.

- `dashboard_prompt.md`: the prompt. It describes the data file the page reads, the seven tabs, the rules the page must keep, and how to check the result.
- `../CLAUDE.md` (at the package root): the standing instructions the agent reads on its own when it is Claude Code. Other agents can be given the same text as their first message.

## What the agent gets, and what it never gets

The agent only needs the aggregates: `CATI/Analysis/summary_dashboard/dashboard_data.js`, the current page, and the docs. It does not need, and must not be given, the export (`CATI/Round##/xls`), the files in `zzz`, `dta`, `pii` or `fix`, or the `HF` and `2share` folders: once real data run through the workflow those hold household IDs, names and phone numbers. The synthetic data of this package carry no real person, but the habit should be the one real data need.

The data file itself holds only tables that the do-files already suppressed: every cell from fewer than 10 households (or members, or dials) is empty before it reaches the page. The agent's page must keep it that way: it draws what Stata wrote and computes nothing new from it.

## Setting up Claude Code

1. Install Claude Code (https://docs.claude.com/en/docs/claude-code) and sign in with the account the team uses.
2. Open a terminal in the package folder (the folder of `L2PHL_SYN_master.do`) and start it with `claude`. It reads `CLAUDE.md` at the root, so the standing rules are in place before the first message.
3. Run the workflow once (`do L2PHL_SYN_master.do` in Stata), so `CATI/Analysis/summary_dashboard/dashboard_data.js` exists for the agent to read.
4. Paste the contents of `dashboard_prompt.md` as the first message. To change the existing page rather than build a new one, say so in one line before the prompt ("change the page in CATI/Analysis/do/dashboard_template.html; keep everything it does and add ...").
5. Ask it to open the result in a browser and look at every tab, then run `tests/run_tests.do`; the last two checks confirm the page and the data file are in place.

The same prompt works with any coding agent that can read and write files in the folder (Codex, Copilot, Cursor and the like); only step 2 differs, and `CLAUDE.md` is then pasted as the first message.

## Working habits that kept this package safe

- The agent works in the package folder only, and never in a folder that holds real exports.
- It never pastes a row of data into the chat, a commit message or an issue; it reports counts.
- Its page is reviewed in the browser before it is shared, tab by tab, with the questions in `dashboard_prompt.md` under "How to check the result".
- What it changes in the do-files is run through `tests/run_tests.do` before it is kept.
- The page stays a single file next to the data file, without external libraries, so it opens offline and can be sent as two files.
