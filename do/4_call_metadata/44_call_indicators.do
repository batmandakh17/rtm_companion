* =============================================================================
* 44_call_indicators.do: fieldwork indicators from the call records of all rounds, as tables for the dashboard.
* Definitions follow the handbook's call-log sections (Chapter 3): a case is a household in a round; completion rate
* = cases completed / cases; dials per complete = dials / completes; contact rate = dials where someone answered /
* dials; an operator-day is an enumerator with at least one dial on a date. Values from fewer than 10 cases (or 10
* dials) are left empty.
* In:  output/calls/dials_R##.dta, cases_R##.dta; output/sample/phone_sample.dta
* Out: output/calls/calls_by_round.csv, calls_panel.csv, calls_by_dialno.csv, calls_outcomes.csv, calls_by_hour.csv,
*      calls_by_weekday.csv, calls_by_day.csv, calls_enumerators.csv
* =============================================================================
tempfile dials cases
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    append using "$OUT/calls/dials_R`rr'.dta"
}
capture drop date
gen int date = dofc(dial_start)
save `dials'
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    append using "$OUT/calls/cases_R`rr'.dta"
}
merge m:1 hhid using "$OUT/sample/phone_sample.dta", keepusing(sample) keep(master match) nogenerate
save `cases'

* ---------------------------------------------------------------- by round
use `dials', clear
bysort round hhid: egen byte any_refusal = max(outcome == 5)
bysort round hhid: egen byte all_dead = min(inlist(outcome, 7, 8))
egen byte tag_case = tag(round hhid)
egen byte tag_date = tag(round date)
gen byte ref_case = any_refusal * tag_case
gen byte dead_case = all_dead * tag_case
collapse (sum) contact_n = contact refusals = ref_case dead = dead_case days = tag_date (count) dials = seq, by(round) fast
gen double contact_rate = contact_n / dials
tempfile byr
save `byr'
use `cases', clear
gen byte sample_rep = sample == 2
collapse (count) cases = hhid (sum) completes = completed replacements = sample_rep (median) median_minutes = min_complete, ///
    by(round) fast
merge 1:1 round using `byr', nogenerate
gen double completion_rate = completes / cases
gen double dials_per_complete = dials / completes
gen double refusal_rate = refusals / cases
gen double dead_number_rate = dead / cases
rename days fieldwork_days
keep round cases completes completion_rate dials dials_per_complete contact_rate refusal_rate dead_number_rate ///
    median_minutes fieldwork_days replacements
foreach v of varlist completion_rate dials_per_complete contact_rate refusal_rate dead_number_rate median_minutes {
    replace `v' = . if cases < 10
}
export delimited using "$OUT/calls/calls_by_round.csv", replace nolabel

* ---------------------------------------------------------------- panel balance: what became of each household called
use `dials', clear
bysort round hhid: egen byte c_ref = max(outcome == 5)
bysort round hhid: egen byte c_contact = max(contact)
bysort round hhid: egen byte c_dead = min(inlist(outcome, 7, 8))
collapse (first) c_ref c_contact c_dead, by(round hhid) fast
merge 1:1 round hhid using `cases', keepusing(completed) keep(match) nogenerate
gen byte st_interviewed = completed
gen byte st_refused = !completed & c_ref
gen byte st_dead = !completed & !c_ref & c_dead
gen byte st_never_answered = !completed & !c_ref & !c_dead & !c_contact
gen byte st_other = !completed & !c_ref & !c_dead & c_contact
bysort hhid (round): gen byte all_so_far = sum(completed) == _n & completed
collapse (count) called = hhid (sum) st_* all_so_far, by(round) fast
export delimited using "$OUT/calls/calls_panel.csv", replace

* ---------------------------------------------------------------- completion by dial number (cumulative)
use `cases', clear
forvalues k = 1/6 {
    gen byte done`k' = completed & k_complete <= `k'
}
collapse (count) cases = hhid (mean) done1-done6, by(round) fast
reshape long done, i(round cases) j(dial)
rename done share_completed
replace share_completed = . if cases < 10
export delimited using "$OUT/calls/calls_by_dialno.csv", replace nolabel

* ---------------------------------------------------------------- outcomes of dials
use `dials', clear
contract round outcome, freq(dials)
bysort round: egen double share = total(dials)
replace share = dials / share
decode outcome, gen(outcome_label)
replace share = . if dials < 10
export delimited using "$OUT/calls/calls_outcomes.csv", replace nolabel

* ---------------------------------------------------------------- hour of day and day of week (all rounds)
use `dials', clear
gen byte hour = hh(dial_start)
gen byte weekday = dow(date)
foreach by in hour weekday {
    preserve
    collapse (count) dials = seq (mean) contact_rate = contact complete_rate = complete, by(`by') fast
    foreach v of varlist contact_rate complete_rate {
        replace `v' = . if dials < 10
    }
    if "`by'" == "weekday" {
        label define weekday 0 "Sun" 1 "Mon" 2 "Tue" 3 "Wed" 4 "Thu" 5 "Fri" 6 "Sat", replace
        label values weekday weekday
        decode weekday, gen(day_label)
    }
    export delimited using "$OUT/calls/calls_by_`by'.csv", replace nolabel
    restore
}

* ---------------------------------------------------------------- completes by fieldwork day
use `dials', clear
egen fieldday = group(round date)
bysort round (fieldday): gen first_day = fieldday[1]
replace fieldday = fieldday - first_day + 1
drop first_day
collapse (sum) completes = complete, by(round fieldday) fast
bysort round (fieldday): gen cum_completes = sum(completes)
bysort round (fieldday): gen double cum_share = cum_completes / cum_completes[_N]
export delimited using "$OUT/calls/calls_by_day.csv", replace nolabel

* ---------------------------------------------------------------- enumerators
use `dials', clear
egen byte tag_od = tag(round enumerator date)
gen double min_c = dur_min if complete
collapse (count) dials = seq (sum) completes = complete operator_days = tag_od (median) median_minutes = min_c, ///
    by(round enumerator) fast
gen double completes_per_day = completes / operator_days
foreach v of varlist completes_per_day median_minutes {
    replace `v' = . if completes < 10
}
export delimited using "$OUT/calls/calls_enumerators.csv", replace nolabel
di as result "44_call_indicators: tables written to output/calls"
