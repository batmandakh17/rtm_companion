# RTM companion: the monitoring workflow as code

This folder is the code companion to the Real-Time Monitoring Handbook. It runs a phone panel's monitoring work from start to finish in Stata:
- the sampling frame and baseline;
- the phone sample;
- each round's KoBoToolbox export, turned into module files;
- the call records, turned into one standard call file;
- weights;
- the analysis folder, where the latest files of every round are collected, appended, finalized and harmonized;
- a dashboard.

It runs on synthetic data that copy the layout of the L2PHL phone rounds, in the folders the L2PHL team works in. Anyone can download the folder, run one file, and see every step work. The handbook explains why each step is done the way it is; the code shows how.

Everything under `CAPI/raw`, `CAPI/ado`, `CATI/KOBO` and `CATI/Round##` is made up. Names, phone numbers (all start with 000), places and answers are synthetic, and none of the numbers are survey results.

## Run it

1. Open Stata (16 or later). No user-written commands are needed, except `ebalance` (SSC) if you choose the entropy-balancing weights.
2. Change to this folder (`cd`), or set `glo wd "<this folder>"`.
3. Run `do L2PHL_SYN_master.do`. It takes about 20 seconds.

Then open `CATI/Analysis/summary_dashboard/index.html` in a browser. Every data check is listed in `CATI/Analysis/fix/checks.csv`. To check the whole run against what the synthetic data were built with, run `do tests/run_tests.do` (64 checks; results in `tests/results.txt`).

## The folders, as in L2PHL

The package is laid out as the L2PHL survey folder is: the baseline in `CAPI`, one folder per phone round under `CATI`, and the work across rounds in `CATI/Analysis`.

```
CAPI/                      the baseline (round 00)
  ado/                     reference files: the frame and the census totals (as L2PHL keeps its census and design files)
  raw/                     the baseline interviews (households, members)
  do/                      1_..._psu2wgt.do (PSU selection, baseline weights), 2_..._dta2smp.do (phone sample, preload, roster master)
  dta/<date>/              what the run writes, dated by the last baseline interview: psu_selected, baseline_weights, phone_sample, ...
  pii/<date>/              the round-1 preload (names and numbers)
CATI/
  KOBO/                    the XLSForm of every round, as uploaded to KoBoToolbox
  ado/                     the enumerator lookup
  do/                      the round do-file (L2PHL_SYN_CATI@R.do) and the round weights (L2PHL_SYN_CATI_wgt@R.do)
  Round01/ ... Round03/    one folder per round
    do/                    L2PHL_SYN_CATI@R##.do: runs the two files above for this round
    xls/                   the KoBo export as downloaded, and the call-centre log received
    kobo/                  the media files the form read (households.csv, preload.csv)
    zzz/<date>/            the export in Stata, sheet by sheet          |
    dta/<date>/            the module files, l2phl_syn_<date>_M##_...   |
    call/<date>/           the standard dial and case files              |  written by the run, one subfolder
    fix/<date>/            review lists                                  |  per export date
    aud/<date>/            the skip-logic audit                          |
    wgt/<date>/            the round weights                             |
    pii/<date>/            names, numbers, the next round's preload      |
  Round04/kobo/            the preload a team would build for round 4 (the round-3 preload is checked against it)
  Questionnaire/           the questionnaire of every round as Word and PDF
  Analysis/
    do/                    hf_l2phl_syn_analysis.do and the dashboard page (dashboard_template.html)
    HF/                    R00, R01, ...: the latest files of every round, copied in; then the appended and final files
    2share/                the household and individual files to share
    call/, fix/            call indicators across rounds; checks.csv and the form changes
    summary_dashboard/     index.html and its data file
```

The dated subfolders are the L2PHL habit: each export is processed into its own set, and the analysis picks the latest. The date comes from the export's file name (`..._2026-03-22-18-00-00.xlsx` gives `20260322`), and for the baseline from its last interview day.

## What happens, step by step

| Step | Do-files | Reads | Writes | Handbook |
|---|---|---|---|---|
| 1 Frame and baseline | (provided) | | `CAPI/ado`, `CAPI/raw` | 2.3 Mode |
| 2 Sample | `CAPI/do/1_L2PHL_SYN_CAPI_R00_psu2wgt.do`, `CAPI/do/2_L2PHL_SYN_CAPI_R00_dta2smp.do` | frame, baseline | PSU selection, baseline weights, phone sample, round-1 preload, roster master | 2.3 Mode; sampling (planned section) |
| 3 Data management | `CATI/do/L2PHL_SYN_CATI@R.do`, each round: sections EXCEL TO STATA, (M0) to (M8), MERGING, CHECKS, PRELOAD, SKIP-LOGIC AUDIT | the round's KoBo export and form | module files M00-M08, the household and roster level files, checks, the audit, the next round's preload | 4.1, 4.2, 4.3.2 |
| 4 Call metadata | the CALL LOGS section of the round do-file; CALL INDICATORS and ENUMERATOR MONITORING in `CATI/Analysis/do/hf_l2phl_syn_analysis.do` | form call records or a call-centre log | standard dial and case files, fieldwork tables, panel balance, the enumerator monitoring view | 3.1-3.5 |
| 5 Weights | `CATI/do/L2PHL_SYN_CATI_wgt@R.do`, each round | module M00 and M01, phone sample, totals | round weights | Sampling (planned section) |
| 6 Analysis folder | POPULATE, APPEND, FINALIZE, HARMONIZE in `CATI/Analysis/do/hf_l2phl_syn_analysis.do` | the latest files of every round | `HF/R##`, the appended module files, the household and individual files, `2share` | 4.2 |
| 7 Dashboard | WEIGHTED INDICATORS and DASHBOARD in the same file | everything above | `CATI/Analysis/summary_dashboard/index.html` | 4.3 |
| Questionnaire | `tools/make_questionnaire.py` | the round's XLSForm | `CATI/Questionnaire`: the questionnaire as Word and PDF | Appendix C |
| Assignment | (the interview tool) | | | Appendix C |

### Step 3, data management

Step 3 reads each round's export as KoBoToolbox writes it: one sheet per form level, one submission per call attempt. It turns the export into module files named as in L2PHL, `l2phl_syn_<export date>_<module>.dta`:
- `M00_passport`: one row per interviewed household.
- `M01_roster`
- `M03_shock_hh` and `M03_shock`
- `M04_employment`
- `M06_finance` and `M07_health`: these modules rotate, so they appear only in rounds whose form has them.
- `M08_food`
- `HH_Level_Data` and `Roster_Level_Data`: the passport with the household modules side by side, and the roster with the member modules, as L2PHL's MERGING section builds them.

Labels come from the form itself (`form_labels`). Practice interviews, the same interview sent twice, and clock errors are found and handled by written rules.

Identifying fields go to the round's `pii` folder, not into the modules. The PRELOAD section builds the next round's preload, which is the file the form reads with `pulldata()`.

### Step 4, call metadata

Step 4 produces one standard dial file, laid out in `docs/call_log_standard.md`, from either of two sources:
- the form's own call records, as in L2PHL;
- a call-centre system's log, as programs dialling through a call centre receive it.

It then applies the handbook's Chapter 3 rules for cases. The first complete dial lasting 3 minutes or more counts; dials after it are dropped.

### Steps 2 and 5, sample and weights

The package draws its own sample and makes its own weights, in plain Stata.

**Step 2 (sample):**
- **Baseline PSUs:** systematic PPS within each stratum (region × urban/rural), with census households as the measure of size and one recorded random start per stratum, so the draw repeats exactly. The baseline found 15 households per PSU by random walk.
- **Baseline weights:** design weight 1 / (π1 π2), scaled in each stratum to the census number of households.
- **Phone panel (L2PHL's rule):** in each PSU, households with a phone are ranked by a random key drawn at baseline. The first 6 (urban) or 7 (rural) are the main sample; the rest are replacements in order. Each phone-sample weight = baseline weight × households with a phone in the PSU / main households in the PSU.

**Step 5 (round weights):** three methods, chosen with `glo WEIGHTS` in `L2PHL_SYN_preambles.do`.
- **cellpost, the default, L2PHL's procedure.** Every person present in an interviewed household starts from the household's phone-sample weight. The person weights are post-stratified in cells of stratum × age group (0-17, 18-45, 46 and over) × sex, so that each cell sums to its baseline-weighted population. The household weight is the mean of its members' person weights, the population weight their sum, and a PSU-smoothed household weight is kept alongside. Household data use the household weight, person data (the roster, employment) the person weight.
- **rake.** Household weights raked to census households by stratum and to baseline households by household size (1-2, 3-4, 5-6, 7+).
- **ebalance.** The same targets reached with entropy balancing, the `ebalance` command from SSC that the Tajikistan, Kyrgyzstan, Uzbekistan and Caucasus programs use. On categorical margins it gives the same weights as raking; the tests check this on round 1.
- In every method a replacement comes from the same PSU list as the household it replaced, so it starts from the same weight; each round is weighted afresh; no trimming.

L2PHL computes its round weights inside the analysis do-file, after appending the rounds. Here they are computed per round, in the round's `wgt` folder, so that each round folder is complete on its own; the analysis merges them when it appends.

Diagnostics (largest/smallest weight, the sum of household weights against the census, cells with few persons, design effect from unequal weights) are in `CATI/Analysis/fix/checks.csv`, in the round's `wgt` folder (`..._cells.csv`) and on the dashboard's Sample and weights tab.

Not built yet: blending the panel with a new survey, or adding a refreshment sample.

### Step 6, the analysis folder

As in L2PHL, the analysis do-file starts by filling `CATI/Analysis/HF`:
- **POPULATE.** `HF/R00` is emptied and refilled with the baseline's sample files, and `HF/R##` with the latest files of each round (module files, level files, weights, call files, the audit). What the analysis reads is always one dated set per round, named for its export.
- **APPEND.** Every module file is appended over rounds, with a `round` variable, and merged with the round weights: household files get `hhw`, `popw`, `ave_hhw` and `w_round`, person files `indw`. The result is one file per module in `HF`, `l2phl_syn_<module>.dta`.
- **FINALIZE.** The appended household-level data become `l2phl_syn_cati_household.dta` (with the interview date as year, quarter and month) and the roster-level data `l2phl_syn_cati_individual.dta`, the two files L2PHL shares; copies go to `2share`.
- **HARMONIZE.** The place for every rule that keeps a variable comparable across rounds. In this example the forms change only by rotating modules, so the section flags the rounds each rotating module was in (`mod_finance`, `mod_health`, so a missing answer reads as "not asked", not nonresponse) and refreshes every value label from the latest form. A change that needs a rule (a question that became multiple-choice, a question gated by a new filter, a scale with more codes) shows up in `form_changes.csv` and is counted in `checks.csv` until it is handled here.

### Quality checks

Three layers, described in `docs/quality_checks.md`:
- processing checks written into the do-files (a check that must never fail stops the run; what needs judgment goes to a review list);
- a skip-logic audit that reads every question's routing, required flag and constraint from the form itself, and counts answers where the question was not asked, required answers missing, and answers outside the constraint (the SKIP-LOGIC AUDIT section of the round do-file; results in the round's `aud` folder);
- an enumerator monitoring view with the indicators of handbook Section 3.2 side by side, plus panel balance and the changes in the form between rounds.

The dashboard's Quality checks tab shows every flag with the rule behind it. The households behind the flags are listed by ID in the round's `fix` folder (`R##_form_flags.csv`), which stays with the team.

### The five stages of handbook Section 4.2

| Section 4.2 stage | Here |
|---|---|
| 1 Raw | `CATI/Round##/xls`, never edited |
| 2 Cleaned | `CATI/Round##/zzz/<date>`: the export in Stata, plus the flagged submissions |
| 3 Harmonized | `CATI/Round##/dta/<date>` and `call/<date>`: module files, standard dial and case files; then `CATI/Analysis/HF`, appended and harmonized across rounds |
| 4 Weighted | `CATI/Round##/wgt/<date>`, merged into the `HF` files |
| 5 Published | `CATI/Analysis/summary_dashboard`: aggregates only, cells under 10 left empty |

As in Section 4.2, a check that must never fail stops the run (`check_log ... "stop"`). Rows that need a person's judgment go to review lists in the round's `fix` folder.

## Keep these files inside the team

Everything the run writes, the dated subfolders under `CAPI`, `CATI/Round##` and `CATI/Analysis` (`HF`, `2share`, `call`, `fix`, `summary_dashboard`), holds household IDs, names and phone numbers once real data go through the workflow. They are excluded from version control (`.gitignore`) and should never be shared. Only `CATI/Analysis/summary_dashboard` holds aggregates fit to publish.

## Adapting it to another program

- **Form:** put the program's XLSForm in `CATI/KOBO` and each export in `CATI/Round##/xls`; `python3 tools/make_questionnaire.py` then rebuilds the questionnaire documents from the forms.
- **Rounds:** set the round numbers and first calling days in `L2PHL_SYN_preambles.do`; add a `Round##` folder with its `do` stub, `xls` and `kobo` for each new round.
- **Enumerator codes:** list them in `CATI/ado/enumerators.csv`.
- **Text fields:** keep phone-number fields as text with `keepstring()` in the EXCEL TO STATA section of the round do-file.
- **Modules:** name your own modules in the (M1) to (M8) sections of the round do-file, and the household and member modules in its MERGING section.
- **Call-centre log:** for a different layout, change the import and the status crosswalk in the CALL LOGS section of the round do-file.
- **Harmonisation:** every row of `form_changes.csv` that is not a rotating module gets its rule in the HARMONIZE section of the analysis do-file.

## Files

```
L2PHL_SYN_master.do                 runs everything: CAPI, every round, the analysis
L2PHL_SYN_preambles.do              globals, folders, ado path (run by every file)
CLAUDE.md                           standing instructions for an AI agent working in the package
ado/                                the package's own commands (setround, rounddate, check_log, review_list, kobo_import, ...)
CAPI/                               the baseline: frame and census (ado), interviews (raw), do-files, dated outputs
CATI/KOBO/                          the forms
CATI/ado/                           the enumerator lookup
CATI/do/                            the round do-file and the round weights, run once per round
CATI/Round##/                       one folder per round: do stub, xls, kobo, and the dated outputs
CATI/Questionnaire/                 the questionnaire as Word and PDF, per round
CATI/Analysis/                      the analysis do-file and dashboard page (do), HF, 2share, call, fix, summary_dashboard
docs/                               module files, the standard call file, the quality checks, the synthetic data
prompts/                            how to set up an AI agent here, and the prompt that built the dashboard
tests/run_tests.do                  the whole run checked against the generator's counts
tools/                              Python scripts that made the data, the forms and the questionnaire (not needed to run the workflow)
```

### Layout and style

The do-files follow the L2 programs' conventions, so a team member can read them as their own:
- the same folders and the same chain of files as L2PHL: CAPI stage files (`psu2wgt`, `dta2smp`), a CATI do-file per round with a bookmarked section (`**#`) per module, a MERGING section and a CALL LOGS section, the round weights, and `hf_l2phl_syn_analysis.do` across rounds; the master only runs them in order;
- every file opens with a PREAMBLES block that sets the round and the folder globals; `setround` sets them as the L2PHL preamble does (`$xls` the export, `$zzz` the export in Stata, `$dta` the module files, `$call`, `$fix`, `$aud`, `$wgt`, `$pii`, `$date` the export date, `$stub` the prefix of the round's files), and `Round##/do/L2PHL_SYN_CATI@R##.do` reruns one round alone;
- sections sit in folding braces, commands use the short forms (`g`, `la var`, `ren`, `qui`, `cap`, `bys`), and the package's own commands live in `ado/`.

The workflow is in Stata, so the task team can read and run every step. Translating it to Python or R should be straightforward. `tools/` holds the only Python: it builds the form, the synthetic data and the questionnaire documents.

## An AI agent on this package

The dashboard page was written by an AI coding agent from a prompt; Stata writes the numbers, the agent wrote the page. `prompts/README.md` says how to set an agent up on the package (what it may read, what it must never see), `prompts/dashboard_prompt.md` is the prompt, and `CLAUDE.md` holds the standing rules an agent reads first.
