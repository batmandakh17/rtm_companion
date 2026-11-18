# Module files

The round do-file (`CATI/do/L2PHL_SYN_CATI@R.do`) writes one set of files per round to `CATI/Round##/dta/<date of the export>/`, named `l2phl_syn_<date>_<module>.dta` as in L2PHL. The analysis copies the latest set of every round into `CATI/Analysis/HF/R##` and appends them there. Every file carries `hhid` and `round`. Labels come from the round's form.

| File | One row per | Built from | Contents |
|---|---|---|---|
| M00_passport | household interviewed | main sheet (the kept complete submission) | interviewer, date, start, end, length, attempts, language, moved, closing questions, preload size |
| M01_roster | member listed so far | repeats `old_` and `newmembers` | member ID, status (still a member, left this round, left before, new), sex, age (corrected), relationship (from the roster master), why a member left or moved in |
| M03_shock_hh | household interviewed | main sheet | SH1, the shock types (codes and one 0/1 column per type), count of types |
| M03_shock | household and shock | repeat `sh2_` | the shock, and the ways of coping (codes and 0/1 columns) |
| M04_employment | member aged 15+ asked the module | repeats `employ_` and `employ_new` | A24/A27 (change since the last interview), A1, A26, A3, A5, A6, A10, A11, `employed`, sex, age |
| M06_finance | household interviewed (rounds 1, 3) | main sheet | F17, F1, F18, F2, F3, F6, F7, F10 |
| M07_health | household interviewed (round 2) | main sheet | H2, H2A, H3 |
| M08_food | household interviewed | main sheet | the eight food insecurity experiences (F08_A-H) and their count |

## Kept apart

These files hold identifying information. They exist so the team can call back or fix a record, and never leave the team:
- `CATI/Round##/pii/<date>/R##_contacts.dta`: respondent name and phone numbers.
- `CATI/Round##/pii/<date>/R##_names.dta`: member names.
- `CATI/Round##/pii/<date>/preload_R(next).csv`: the next round's preload.

## Rules step 3 applies

Practice submissions are those dated before the round's first calling day. The same interview sent twice keeps its first copy. A form saved before it was opened gets an empty duration.

A complete is result X15 = 1 or 2. A household with two different completes keeps the first.

Corrections of age and sex (D5a = 4, 5) replace the preloaded values. New members take the IDs after `fmid_max`.
