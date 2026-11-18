# Prompt: build the monitoring dashboard page

Build a single-file HTML dashboard for a monthly phone-survey panel. Stata has already computed every number and written them into one JavaScript data file; the page only draws them. Read the data file first, then write the page.

## Inputs

- `CATI/Analysis/summary_dashboard/dashboard_data.js`: sets `window.DATA`, with `DATA.meta` and one array of row objects per table. Open it and read the column names before writing anything; do not guess them.
- `README.md` and `docs/quality_checks.md`: what the workflow does and what each check means, so the page can explain its own numbers in one line each.
- The handbook sections the page refers to: Chapter 3 (call logs: completion rate, dials per interview, contact rate, operator-days, enumerator monitoring in Section 3.2) and Section 4.3.2 (quality checks).

The tables in the data file, and what they hold:

| Table | One row per | Use |
|---|---|---|
| `meta` | run | program, title, date made, the rounds with their first calling day and export date |
| `by_round` | round | cases, completes, completion rate, dials, dials per interview, contact rate, refusal rate, dead-number rate, median interview minutes, fieldwork days, replacements |
| `panel` | round | households called and what became of them: interviewed, reached but not finished, refused, never answered, number not working; and how many were interviewed in every round so far |
| `by_dialno` | round and dial number | cumulative share of cases completed by that dial |
| `outcomes` | round and result code | dials and share, with the code's label |
| `by_hour`, `by_weekday` | hour, weekday | dials, share answered, share ending in an interview |
| `by_day` | round and calling day | completes, cumulative completes, cumulative share |
| `enumerators` | round and enumerator | dials, completes, operator-days, completes per operator-day, median minutes |
| `monitor` | round and enumerator, plus an "All" row per round | the monitoring view of handbook Section 3.2: pace, refusals, short interviews, don't-know and refused answers, form flags per 100 interviews, two answer shares |
| `indicators` | indicator, round and group (all, urban, rural) | weighted estimate with its 95% confidence bounds and the number of respondents |
| `shock_types` | round and shock code | weighted share of households reporting that shock, with its label |
| `explorer` | module file, variable, round and answer code | weighted percent in each answer, the number of respondents, variable and answer labels |
| `audit` | round, sheet and question | the skip-logic audit: how many should have been asked, answered, answered where not asked, required but missing, outside the constraint; the routing rule as written in the form; a status when a rule could not be read |
| `form_changes` | change between two rounds | added, dropped, type, wording or options, with a rotating flag |
| `checks` | processing check | round, step, the check's text, the count, and what the do-files did |
| `reviews` | review list | file name and row count |
| `sample` | stratum | PSUs in the frame, census households, PSUs drawn, baseline households, with a phone, phone main sample, replacements, mean baseline weight |
| `weights` | round | method, households and persons weighted, replacements, sum, smallest and largest household weight, design effect, cells and cells under 10 persons |

An empty value in any table means the cell had fewer than 10 households, members or dials and was suppressed by Stata. Show it as "<10", never as zero and never recomputed.

## The page

One HTML file, `dashboard_template.html`, that loads `dashboard_data.js` from the same folder with one script tag and nothing else: no external libraries, fonts or network requests, so it opens offline from a double-click and can be sent as two files. Charts are inline SVG drawn with plain JavaScript. If the data file is missing, say so on the page.

A header with the title from `meta`, the rounds, the date made, and a banner saying that the data are synthetic. Then seven tabs, the chosen tab remembered in the browser when storage is allowed:

1. **Overview.** Six headline figures for the latest round (households interviewed with the change on the previous round, completion rate, dials per interview, dials answered, median interview length, form-logic flags). A fieldwork table by round from `by_round`. A panel-balance chart (100% stacked bars by round from `panel`) with a small table of how many of the round-1 panel were interviewed in every round so far. A "quality at a glance" list for the latest round: the three audit totals, rules the audit could not read, processing checks that found something, review lists to read.
2. **Fieldwork.** Cumulative interviews by calling day (line, one series per round); share of cases interviewed by dial number (line per round); what happened on each dial (100% stacked bars by round, the ten result codes grouped into interview, callback, refused, no answer or off, number or household wrong, with the full table behind a disclosure); best hours to call and days of the week (answered and interview rates).
3. **Enumerators.** The monitoring view: a table of every indicator in `monitor` for one round (a round selector), the "All" row first, and a cell marked when it is more than 50% above or a third below the pooled value in the direction that matters for that indicator (pace, refusals, short interviews and don't-know shares are marked when high, interviews per operator-day when low, lengths and answer shares either way; tiny differences in shares are not marked). Add a short "how to read it" list: a marked cell is a prompt to look, not a verdict.
4. **Results.** One small chart per indicator (estimate by round with its confidence interval as a vertical bar at each point), a segmented control for all, urban and rural households, a note under each chart with the latest value, its number of respondents, and the rounds in which the question was not asked. A horizontal bar chart of the eight most reported shock types by round.
5. **Module explorer.** A module selector; for every labelled variable of the module, a table of answers by round with the weighted percent, shaded as a one-hue sequential heat map (white text on the dark steps). Respondents under 10 show "<10".
6. **Quality checks.** Six headline figures for the latest round (routing broken, required missing, out of range, rules not read, processing checks that found something, review lists). The skip-logic audit table: one row per question, the routing rule as written in the form, and per round "asked · flags" with a four-step flag shading and a hover tooltip giving the five counts; a sheet selector and a box to show only questions with a flag or an unread rule. The form changes between rounds with pills for added and dropped and a rotating mark. The processing checks, those that found something first, with a box to show the ones that found nothing; checks that only report a value (rows read, largest and smallest weight, design effect, share of census, raking passes, largest gap) are information, not problems, and must not count as flags. The review lists with their row counts, and a four-point list on what to do with a flag.
7. **Sample and weights.** The sample table by stratum from `sample` with a two-sentence note on the design (PPS PSUs, 15 households each, phone sample of 6 urban or 7 rural per PSU with replacements in order). The round weights table from `weights` with a note on the method (person weights post-stratified by stratum, age group and sex to the baseline population; household weight the mean of the members' person weights; raking and entropy balancing as alternatives; design effect 1 + CV²).

Put a count on the Quality checks tab: the latest round's audit flags plus the processing checks that found something.

## Rules the page must keep

- **Nothing is computed from microdata.** The page draws what Stata wrote. It may add, divide and sort the aggregates it is given (a total from the parts of a stacked bar, a cumulative share), nothing else, and it never fills a suppressed cell.
- **Suppression is kept.** Any empty value reads "<10" and is left out of charts.
- **No personal data.** Enumerators appear by their program code (E01, E02, ...); no names, phone numbers or household IDs anywhere on the page, including tooltips. The review lists are shown as file names and row counts only.
- **One file, offline.** No external scripts, stylesheets, fonts or images; no network request at all.
- **Charts.** Thin marks, one y-axis per chart (never two scales), a legend whenever a chart has two or more series, direct labels at the line ends when there are at most four series, recessive grid lines, a hover tooltip on every chart. Series colours assigned to rounds in a fixed order so a round keeps its colour across every chart. Status colours (the warning yellow, the flag orange) are reserved for flags and never used as a series colour. A single sequential hue for the heat map; a two-hue scale only if something is a signed difference.
- **Light and dark.** Colours are tokens on `:root`, redefined for dark mode under a `prefers-color-scheme` media query and under `[data-theme="dark"]`; the body has an explicit background. Both modes are checked.
- **Phone width.** The layout works at 360px with a 16px side gutter and no horizontal page scroll; wide tables scroll inside their card.
- **Explain in one line.** Every card has a one-line note saying where its numbers come from and what counts, in the words of the handbook section it illustrates. No jargon the field team does not use.
- **Numbers.** Percentages with one decimal where a difference of a point matters (completion, refusals), none where it does not (shares of a stacked bar); integers with thousands separators; "–" for a value that does not apply.

## How to check the result

Open the page in a browser and go through every tab with these questions:

- Does every number on the Overview match the same number in `by_round` and `audit` in the data file?
- Is there any "0" on the page that should be "<10"? (Search the data file for empty values and find where each lands.)
- Do the rounds keep the same colour on every chart?
- Does the Enumerators table mark cells only in the direction that matters, and never the "All" row?
- Does the Quality checks count on the tab equal the audit flags plus the processing checks that found something, and exclude the information-only checks?
- Switch the system to dark mode: is every chart, table, pill and shaded cell still readable?
- Narrow the window to a phone width: does anything overflow?
- Is there any name, number or ID on the page, in any tooltip?

Then run `tests/run_tests.do` from the package folder; its last checks confirm the page and its data file are where the workflow expects them.
