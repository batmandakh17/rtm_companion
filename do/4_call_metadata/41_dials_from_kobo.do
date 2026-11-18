* =============================================================================
* 41_dials_from_kobo.do (round): the standard dial file from the form's call records.
* In L2PHL every call attempt is a submission of the form (Z8 attempt, call_status1 spoke with someone, Z17 correct
* respondent, Z9 consent, X15 result), so the form is the call log. Practice and duplicate submissions are left out
* with step 3's flags. The standard layout is in docs/call_log_standard.md: one row per dial, enumerator in the
* program's own code (E01...), local times, the outcome in the standard codes (here the L2PHL X15 codes) and the
* dial number seq counted from the times (Z8, typed by the enumerator, stops at 3).
* Note: the form's end is when the form was saved, so dur_min runs a little longer than the call itself.
* In:  output/_raw/R##/submissions_flagged.dta, data/lookups/enumerators.csv
* Out: output/calls/dials_kobo_R##.dta
* =============================================================================
args r
local rr : display %02.0f `r'

import delimited "$DATA/lookups/enumerators.csv", clear stringcols(2 3)
save "$OUT/calls/enumerators.dta", replace

use "$OUT/_raw/R`rr'/submissions_flagged.dta", clear
drop if f_practice | f_duplicate
merge m:1 int_id using "$OUT/calls/enumerators.dta", keep(master match) keepusing(enumerator)
quietly count if _merge == 1
check_log `r' 4 "dials whose interviewer code is not in the lookup" `r(N)' "listed"
drop _merge

gen str12 program = "$PROGRAM"
gen double dial_start = start_t
gen double dial_end = end_t if !f_negdur
format dial_start dial_end %tcCCYY-NN-DD_HH:MM:SS
gen byte outcome = x15
gen byte contact = call_status1 == 1
quietly count if contact != !inlist(outcome, 6, 7, 8)
check_log `r' 4 "dials where 'spoke with someone' disagrees with the result code" `r(N)' "listed"
gen str10 source = "kobo"
gen double dial_id = _id
bysort hhid (dial_start dial_id): gen byte seq = _n
quietly count if z8 != min(seq, 3)
check_log `r' 4 "dials whose typed attempt number (Z8) differs from the count by time" `r(N)' "seq used"

do "$DO/4_call_metadata/_standard_layout.do"
save "$OUT/calls/dials_kobo_R`rr'.dta", replace
di as result "41_dials_from_kobo R`rr': " _N " dials"
