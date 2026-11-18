# Synthetic data

Every file here was made by `tools/make_form.py` and `tools/make_synthetic.py` (seed 20261114). Nothing comes from a real survey. The layouts copy the L2PHL phone rounds, so the workflow meets the same files a real team would. The values are made up:
- Names are "Person <household>-<member>".
- Phone numbers are 12 digits starting with 000.
- Regions are numbered 1-4.

To change the example, edit the scripts and rerun `python3 tools/make_form.py` and then `python3 tools/make_synthetic.py`. These need Python 3 with openpyxl.

## The example

- **Country:** 4 regions, each split into urban and rural (8 strata). The frame has 1,779 PSUs with census household and person counts (`frame/frame_psu.csv`, `frame/census_totals.csv`).
- **Baseline (face to face):** 15 PSUs per stratum, drawn by systematic PPS with recorded random starts (`do/1_L2PHL_SYN_CAPI_R00_psu2wgt.do` repeats the draw exactly). There are 15 households per PSU, found by random walk, so there is no listing. That gives 1,800 households and 8,003 members (`baseline/`). Each household carries a random key `u`, drawn at baseline, which step 2 uses to pick the phone sample.
- **Phone panel:** in each PSU, the households with a phone are ranked by `u`. The first 6 (urban) or 7 (rural) form the main sample (780 households); the rest are replacements in rank order (880). Twelve enumerators, E01 to E12, call three monthly rounds, which start on 2 March, 6 April and 4 May 2026.
  - Round 1 calls the main sample. When a main household refuses, has a dead number, or is not reached, the next replacement in its PSU is called.
  - Rounds 2 and 3 call every household interviewed in round 1.

## Files for each round (`raw/R##`)

| File | What it is |
|---|---|
| `L2PHL_SYN_CATI_R##_-_all_versions_-_False_-_<date>.xlsx` | The KoBoToolbox export ("XML values and headers"). The main sheet has one row per call attempt; there is one sheet per repeat group (`old_`, `newmembers`, `sh2_`, `employ_`, `employ_new`). |
| `media/preload.csv`, `media/households.csv` | What the form reads: the preload (`pulldata`) and the list for the household question. `R04/media/preload.csv` is the preload a team would build for round 4. |
| `callcenter/calllog_R##.csv` | The same dials as a call-centre system's log (semicolon-separated). |

The forms are in `form/`. They are a shortened version of the L2PHL round-10 phone questionnaire, keeping its variable names, choice lists and codes. Finance is in rounds 1 and 3 and health in round 2, so the workflow has rotating modules to handle. The same forms with their media files, and the questionnaire as a Word document and a PDF, are in `questionnaire/` (see its README).

The sheets are colour-coded as the L2 forms are: groups, repeats and calculated fields in the L2PHL fills, then one colour per question type (single choice, multiple choice, number, text, date or time, note), a yellow name cell on every row the previous round's form did not have, and the choice lists banded grey and white. The `legend` sheet lists the colours; KoBoToolbox ignores it and the colours.

## Problems planted on purpose

The round do-file should find each of these (the last three through the skip-logic audit, which reads the rules from the form), and `tests/run_tests.do` checks that it does:

| Problem | Round 1 | Round 2 | Round 3 |
|---|---|---|---|
| Practice interviews dated the day before fieldwork | 3 | 0 | 0 |
| The same interview submitted twice | 4 | 4 | 4 |
| A form saved before it was opened (device clock) | 2 | 2 | 2 |
| A complete recorded in under 3 minutes | 3 | 3 | 3 |
| Call-centre operator code typed with a hyphen (CATI-07) | some | some | some |
| A new address typed although the household said it had not moved (routing broken) | 3 | 3 | 3 |
| A required food-insecurity answer left empty (required missing) | 4 | 4 | 4 |
| Hours or days of work outside the form's limits (out of range) | 3 | 3 | 3 |

## Call-centre status codes (this example's)

| Code | Meaning | Standard outcome (L2PHL X15) |
|---|---|---|
| SCS | Complete | 1 |
| PRC | Partial, no more callback | 2 |
| PRS | Partial, callback scheduled | 3 |
| CBK | Callback, not started | 4 |
| RFS | Refused | 5 |
| NOA | No answer | 6 |
| NEX | Number does not exist | 7 |
| OFF | Phone off or out of service | 8 |
| DKH | Does not know the household | 9 |
| REF | Reference person cannot connect | 10 |
