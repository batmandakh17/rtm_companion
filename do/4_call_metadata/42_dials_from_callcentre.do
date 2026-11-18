* =============================================================================
* 42_dials_from_callcentre.do (round): the same standard dial file from a call-centre system's log.
* Programs that dial through a call-centre system get its log as a semicolon-separated file, one row per dial, with
* the operator's code in the system, the household, the number dialled, start and end times and a status code. Two
* things need care: operator codes are typed differently across files (CATI07, CATI-07, CATI_07), so they are
* normalized and matched to the program's enumerator codes; status codes are mapped onto the standard outcomes.
* The number dialled is identifying and is not kept.
* Check: the dials from this log and from the form (41) should agree dial by dial on household, start and outcome;
* their ends differ by the time the enumerator took to save the form.
* In:  data/raw/R##/callcenter/calllog_R##.csv, output/calls/enumerators.dta, output/calls/dials_kobo_R##.dta
* Out: output/calls/dials_callcentre_R##.dta
* =============================================================================
args r
local rr : display %02.0f `r'

import delimited "$DATA/raw/R`rr'/callcenter/calllog_R`rr'.csv", delimiter(";") clear stringcols(_all)
destring id hh_id round, replace
rename (hh_id id) (hhid dial_id)
drop dialing_phone

* operators: upper case, no punctuation, then the lookup
gen str20 callcenter_operator = ustrupper(ustrregexra(operator_id, "[^A-Za-z0-9]", ""))
quietly count if callcenter_operator != operator_id
check_log `r' 4 "call-centre rows whose operator code needed normalizing" `r(N)' "normalized"
merge m:1 callcenter_operator using "$OUT/calls/enumerators.dta", keep(master match) keepusing(enumerator)
quietly count if _merge == 1
check_log `r' 4 "call-centre rows whose operator is not in the lookup" `r(N)' "listed"
drop _merge

* status codes onto the standard outcomes
gen byte outcome = .
local map SCS 1 PRC 2 PRS 3 CBK 4 RFS 5 NOA 6 NEX 7 OFF 8 DKH 9 REF 10
while "`map'" != "" {
    gettoken code map : map
    gettoken o map : map
    replace outcome = `o' if status == "`code'"
}
quietly count if missing(outcome)
check_log `r' 4 "call-centre rows with a status code not in the crosswalk" `r(N)' "listed"

gen str12 program = "$PROGRAM"
gen double dial_start = clock(start_time, "YMDhms")
gen double dial_end = clock(end_time, "YMDhms")
gen byte contact = !inlist(outcome, 6, 7, 8)
gen str10 source = "callcentre"
bysort hhid (dial_start dial_id): gen byte seq = _n
do "$DO/4_call_metadata/_standard_layout.do"
save "$OUT/calls/dials_callcentre_R`rr'.dta", replace

* agreement with the form's records
rename (enumerator dial_start dial_end outcome) (enumerator_cc start_cc end_cc outcome_cc)
keep hhid seq enumerator_cc start_cc end_cc outcome_cc
merge 1:1 hhid seq using "$OUT/calls/dials_kobo_R`rr'.dta", keepusing(enumerator dial_start dial_end outcome)
quietly count if _merge != 3
check_log `r' 4 "dials in only one of the two sources (call centre, form)" `r(N)' "listed"
quietly count if _merge == 3 & (enumerator != enumerator_cc | abs(dial_start - start_cc) > 1000 | outcome != outcome_cc)
check_log `r' 4 "dials where the two sources disagree on enumerator, start or outcome" `r(N)' "listed"
quietly count if _merge == 3 & (missing(dial_end) | dial_end < end_cc | (dial_end - end_cc) > msofminutes(3))
check_log `r' 4 "dials whose form was saved before the call ended, or over 3 minutes after" `r(N)' "listed"
di as result "42_dials_from_callcentre R`rr': done"
