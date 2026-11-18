# The standard call file

Call records arrive in different layouts:
- the form's own call records (L2PHL), with one submission per attempt;
- call-centre system logs, which arrive as semicolon-separated files with each system's own codes;
- dialler recaps.

Step 4 brings every source to one layout. All the call analyses then use the same definitions whatever the source; they are the definitions of the handbook's Chapter 3.

## Dial file: `output/calls/dials_<source>_R##.dta`, one row per dial

| Variable | Type | Meaning |
|---|---|---|
| program | text | program code |
| round | integer | round |
| hhid | integer | household ID (the same in every round) |
| enumerator | text | the program's own enumerator code (E01...), from `data/lookups/enumerators.csv` |
| seq | integer | dial number for the household in the round, counted from the start times |
| dial_start, dial_end | Stata datetime (local time) | when the dial started and ended; for form records, the end is when the form was saved |
| dur_min | number | dial length in minutes (empty when the end is before the start) |
| outcome | integer | the result of the dial, in the codes below |
| contact | 0/1 | someone answered (every outcome except 6, 7, 8) |
| complete | 0/1 | the dial ended in an interview (outcome 1 or 2) |
| source | text | `kobo` or `callcentre` |
| dial_id | number | the record's ID in its source |

## Outcome codes (the L2PHL result codes, X15)

| Code | Meaning | Form (L2PHL) | Call centre (this example) |
|---|---|---|---|
| 1 | Complete | X15 = 1 | SCS |
| 2 | Partially complete, no more callback | X15 = 2 | PRC |
| 3 | Partially complete, callback scheduled | X15 = 3 | PRS |
| 4 | Not yet started, callback scheduled | X15 = 4 | CBK |
| 5 | Refused | X15 = 5 | RFS |
| 6 | Nobody answering | X15 = 6 | NOA |
| 7 | Number does not exist | X15 = 7 | NEX |
| 8 | Phone off or not in service | X15 = 8 | OFF |
| 9 | Does not know the household | X15 = 9 | DKH |
| 10 | Reference person cannot connect | X15 = 10 | REF |

To add a source, write one do-file that ends with `do "$DO/4_call_metadata/_standard_layout.do"`. Before that call, it must create every variable above except `dur_min` and `complete`, which the layout file makes. Keep the source's codes in a crosswalk at the top of that do-file, as `42_dials_from_callcentre.do` does.

## Cases: `output/calls/cases_R##.dta`, one row per household and round

`43_cases.do` applies the handbook's rules (Chapter 3):
- **complete:** the first dial coded complete that lasted at least 3 minutes. If there is none, it is the first dial coded complete of any length.
- **after the completing dial:** later dials are dropped.
- **clock errors:** dials dated more than 90 days from the round's median dial date are dropped.

The case file holds:
- the dials and calling days;
- the dials where someone answered;
- the date of the first dial;
- the completing dial (its number, date and length);
- the enumerator;
- `completed`.

When both sources exist, the call-centre log is used (`$CALLSOURCE`), because its durations measure the call itself.

## Fieldwork tables: `output/calls/calls_*.csv`

`44_call_indicators.do` writes the tables the dashboard draws:
- by round;
- by dial number;
- by outcome;
- by hour and weekday;
- by calling day;
- by enumerator.

Values from fewer than 10 cases or dials are left empty.
