* =============================================================================
* 43_cases.do (round): cases (one household in one round) from the standard dial file, with the handbook's rules
* for its call-log analyses (Chapter 3):
*   complete = the first dial coded complete that lasted at least 3 minutes; if there is none, the first dial coded
*              complete of any length
*   dials after the completing dial are dropped
*   dials dated more than 90 days from the round's median dial date are dropped (device clock errors)
* The source is the call-centre log when there is one ($CALLSOURCE = callcentre), the form otherwise; durations from
* the call-centre log measure the call itself.
* Check: households complete in the calls should be the households in the passport (M00).
* In:  output/calls/dials_<source>_R##.dta, output/modules/R##/..._M00_passport.dta
* Out: output/calls/dials_R##.dta (the dials kept), output/calls/cases_R##.dta
* =============================================================================
args r
local rr : display %02.0f `r'
if "$CALLSOURCE" == "" global CALLSOURCE callcentre
capture confirm file "$OUT/calls/dials_${CALLSOURCE}_R`rr'.dta"
local src = cond(_rc, "kobo", "$CALLSOURCE")

use "$OUT/calls/dials_`src'_R`rr'.dta", clear
gen int date = dofc(dial_start)
format date %td
quietly summarize date, detail
local med = r(p50)
quietly count if abs(date - `med') > 90
check_log `r' 4 "dials more than 90 days from the round's median date" `r(N)' "dropped"
drop if abs(date - `med') > 90

bysort hhid: egen k_long = min(cond(complete & dur_min >= 3 & dur_min < ., seq, .))
bysort hhid: egen k_any = min(cond(complete, seq, .))
gen k_complete = cond(k_long < ., k_long, k_any)
quietly count if seq == k_any & k_long == . & k_any < .
check_log `r' 4 "cases whose only complete lasted under 3 minutes" `r(N)' "kept as complete"
drop if seq > k_complete
save "$OUT/calls/dials_R`rr'.dta", replace

egen byte tag_day = tag(hhid date)
gen byte is_k = seq == k_complete
gen int day_complete = date if is_k
gen double min_complete = dur_min if is_k
collapse (count) n_dials = seq (sum) n_days = tag_day contacts = contact (min) first_date = date ///
         (max) day_complete min_complete k_complete (firstnm) enumerator, by(program round hhid)
gen byte completed = k_complete < .
format first_date day_complete %td
label variable n_dials "Dials this round (up to the completing dial)"
label variable n_days "Days with a dial"
label variable contacts "Dials where someone answered"
label variable first_date "Date of the first dial"
label variable day_complete "Date of the completing dial"
label variable min_complete "Length of the completing dial (minutes)"
label variable k_complete "Dial number of the completing dial"
label variable completed "Household interviewed this round"
save "$OUT/calls/cases_R`rr'.dta", replace

merge 1:1 hhid using "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_M00_passport.dta", keepusing(hhid)
quietly count if (completed & _merge == 1) | (!completed & _merge == 3) | _merge == 2
check_log `r' 4 "households complete in the calls but not in the passport, or the reverse" `r(N)' "listed"
review_list `r' calls_vs_passport if (completed & _merge == 1) | (!completed & _merge == 3) | _merge == 2
di as result "43_cases R`rr': `=_N' cases from the `src' records"
