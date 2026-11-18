# RTM companion: the monitoring workflow as code

This folder is the code companion to the Real-Time Monitoring Handbook. It runs a phone panel's monitoring work from start to finish in Stata:
- the sampling frame and baseline;
- the phone sample;
- each round's KoBoToolbox export, turned into module files;
- the call records, turned into one standard call file;
- weights;
- a dashboard.

It runs on synthetic data that copy the layout of the L2PHL phone rounds. Anyone can download the folder, run one file, and see every step work. The handbook explains why each step is done the way it is; the code shows how.

Everything in `data/` is made up. Names, phone numbers (all start with 000), places and answers are synthetic, and none of the numbers are survey results.

## Run it

1. Open Stata (16 or later). No user-written commands are needed, except `ebalance` (SSC) if you choose the entropy-balancing weights.
2. Change to this folder (`cd`), or set `glo wd "<this folder>"`.
3. Run `do L2PHL_SYN_master.do`. It takes about 20 seconds.

Then open `output/analysis/dashboard/index.html` in a browser. Every data check is listed in `output/analysis/fix/checks.csv`. To check the whole run against what the synthetic data were built with, run `do tests/run_tests.do` (56 checks; results in `tests/results.txt`).

## What happens, step by step

| Step | Do-files | Reads | Writes | Handbook |
|---|---|---|---|---|
| 1 Frame and baseline | (provided) | | `data/frame`, `data/baseline` | 2.3 Mode |
| 2 Sample | `do/1_L2PHL_SYN_CAPI_R00_psu2wgt.do`, `do/2_L2PHL_SYN_CAPI_R00_dta2smp.do` | frame, baseline | PSU selection, baseline weights, phone sample, round-1 preload | 2.3 Mode; sampling (planned section) |
| 3 Data management | `do/3_L2PHL_SYN_CATI@R.do`, each round: sections EXCEL TO STATA, (M0) to (M8), CHECKS, PRELOAD, SKIP-LOGIC AUDIT | the round's KoBo export and form | module files M00-M08, checks, the skip-logic audit, the next round's preload | 4.1, 4.2, 4.3.2 |
| 4 Call metadata | the CALL LOGS section of `do/3_L2PHL_SYN_CATI@R.do`; CALL INDICATORS and ENUMERATOR MONITORING in `do/5_hf_l2phl_syn_analysis.do` | form call records or a call-centre log | standard dial and case files, fieldwork tables, panel balance, the enumerator monitoring view | 3.1-3.5 |
| 5 Weights | `do/4_L2PHL_SYN_CATI_wgt@R.do`, each round | module M00, phone sample, totals | round weights | Sampling (planned section) |
| 6 Dashboard | WEIGHTED INDICATORS and DASHBOARD in `do/5_hf_l2phl_syn_analysis.do` | everything above | `output/analysis/dashboard/index.html` | 4.3 |
| Questionnaire | `tools/make_questionnaire.py` | the round's XLSForm | `questionnaire/`: the KoBo form as uploaded, the questionnaire as Word and PDF | Appendix C |
| Assignment | (the interview tool) | | | Appendix C |

### Step 3, data management

Step 3 reads each round's export as KoBoToolbox writes it: one sheet per form level, one submission per call attempt. It turns the export into module files named as in L2PHL:
- `M00_passport`: one row per interviewed household.
- `M01_roster`
- `M03_shock_hh` and `M03_shock`
- `M04_employment`
- `M06_finance` and `M07_health`: these modules rotate, so they appear only in rounds whose form has them.
- `M08_food`

Labels come from the form itself (`form_labels`). Practice interviews, the same interview sent twice, and clock errors are found and handled by written rules.

Identifying fields go to `output/R##/pii`, not into the modules. The PRELOAD section builds the next round's preload, which is the file the form reads with `pulldata()`.

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

**Step 5 (round weights):** three methods, chosen with `glo WEIGHTS` in `do/0_L2PHL_SYN_preambles.do`.
- **cellpost, the default, L2PHL's procedure.** Every person present in an interviewed household starts from the household's phone-sample weight. The person weights are post-stratified in cells of stratum × age group (0-17, 18-45, 46 and over) × sex, so that each cell sums to its baseline-weighted population. The household weight is the mean of its members' person weights, the population weight their sum, and a PSU-smoothed household weight is kept alongside. Household data use the household weight, person data (the roster, employment) the person weight.
- **rake.** Household weights raked to census households by stratum and to baseline households by household size (1-2, 3-4, 5-6, 7+).
- **ebalance.** The same targets reached with entropy balancing, the `ebalance` command from SSC that the Tajikistan, Kyrgyzstan, Uzbekistan and Caucasus programs use. On categorical margins it gives the same weights as raking; the tests check this on round 1.
- In every method a replacement comes from the same PSU list as the household it replaced, so it starts from the same weight; each round is weighted afresh; no trimming.

Diagnostics (largest/smallest weight, the sum of household weights against the census, cells with few persons, design effect from unequal weights) are in `output/analysis/fix/checks.csv`, in `output/R##/wgt/cells_R##.csv` and on the dashboard's Sample and weights tab.

Not built yet: blending the panel with a new survey, or adding a refreshment sample.

### Quality checks

Three layers, described in `docs/quality_checks.md`:
- processing checks written into the do-files (a check that must never fail stops the run; what needs judgment goes to a review list);
- a skip-logic audit that reads every question's routing, required flag and constraint from the form itself, and counts answers where the question was not asked, required answers missing, and answers outside the constraint (the SKIP-LOGIC AUDIT section of the round do-file);
- an enumerator monitoring view with the indicators of handbook Section 3.2 side by side, plus panel balance and the changes in the form between rounds.

The dashboard's Quality checks tab shows every flag with the rule behind it. The households behind the flags are listed by ID in `output/R##/fix/R##_form_flags.csv`, which stays with the team.

### The five stages of handbook Section 4.2

| Section 4.2 stage | Here |
|---|---|
| 1 Raw | `data/raw/R##`, never edited |
| 2 Cleaned | `output/R##/zzz`: the export in Stata, plus the flagged submissions |
| 3 Harmonized | `output/R##/dta` and `output/R##/call`: module files, standard dial and case files |
| 4 Weighted | `output/R##/wgt` |
| 5 Published | `output/analysis/dashboard`: aggregates only, cells under 10 left empty |

As in Section 4.2, a check that must never fail stops the run (`check_log ... "stop"`). Rows that need a person's judgment go to review lists in the round's `fix` folder.

## Keep these files inside the team

`output/R##/zzz`, `output/R##/pii` and the review lists in `output/R##/fix` hold household IDs, names and phone numbers once real data go through the workflow. They are excluded from version control (`.gitignore`) and should never be shared. Only `output/analysis/dashboard` holds aggregates fit to publish.

## Adapting it to another program

- **Form:** put the program's XLSForm in `data/form` and its exports in `data/raw/R##`; `python3 tools/make_questionnaire.py` then rebuilds the questionnaire documents from it.
- **Rounds:** set the round numbers and first calling days in `do/0_L2PHL_SYN_preambles.do`.
- **Enumerator codes:** list them in `data/lookups/enumerators.csv`.
- **Text fields:** keep phone-number fields as text with `keepstring()` in the EXCEL TO STATA section of `do/3_L2PHL_SYN_CATI@R.do`.
- **Modules:** name your own modules in the (M1) to (M8) sections of the round do-file.
- **Call-centre log:** for a different layout, change the import and the status crosswalk in the CALL LOGS section of the round do-file.

## Files

```
L2PHL_SYN_master.do                 runs everything
do/0_L2PHL_SYN_preambles.do         globals, folders, ado path (run by every file)
do/1_L2PHL_SYN_CAPI_R00_psu2wgt.do  PSU selection and baseline weights
do/2_L2PHL_SYN_CAPI_R00_dta2smp.do  phone subsample and the round-1 preload
do/3_L2PHL_SYN_CATI@R.do            each round: export to module files, checks, preload, audit, call logs
do/4_L2PHL_SYN_CATI_wgt@R.do        each round: round weights
do/5_hf_l2phl_syn_analysis.do       across rounds: form changes, call indicators, monitoring, indicators, dashboard
do/dashboard_template.html          the dashboard page
ado/                                the package's own commands (check_log, review_list, kobo_import, ...)
data/                               synthetic inputs (see data/README.md)
questionnaire/                      the KoBo form as uploaded and the questionnaire as Word and PDF, per round
docs/                               module files, the standard call file, the quality checks
tests/run_tests.do                  the whole run checked against the generator's counts
tools/                              Python scripts that made data/ and the questionnaire (not needed to run the workflow)
output/                             everything the run writes (not kept in version control)
```

### Layout and style

The do-files follow the L2 programs' conventions, so a team member can read them as their own:
- the same chain of files as L2PHL: CAPI stage files (`psu2wgt`, `dta2smp`), one CATI do-file per round with a bookmarked section (`**#`) per module and a CALL LOGS section, a weights file and an analysis file; the master only runs them in order;
- every file opens with a PREAMBLES block that sets the round and the folder globals; the round file is run with `glo R` set (`glo R 02` then `do do/3_L2PHL_SYN_CATI@R.do` reruns round 2 alone);
- the folder globals and names are L2PHL's: `$xls` the export, `$zzz` the export in Stata, `$dta` the module files, `$call`, `$fix` (checks and review lists), `$wgt`, `$pii`, one folder per round under `output/`, the baseline and sample under `output/R00`, everything across rounds under `output/analysis`;
- sections sit in folding braces, commands use the short forms (`g`, `la var`, `ren`, `qui`, `cap`, `bys`), and the package's own commands live in `ado/` as in the L2PHL round folders.

The workflow is in Stata, so the task team can read and run every step. Translating it to Python or R should be straightforward. `tools/` holds the only Python: it builds the form and the synthetic data.
