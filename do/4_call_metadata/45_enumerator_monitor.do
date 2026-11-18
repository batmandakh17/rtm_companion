* =============================================================================
* 45_enumerator_monitor.do: the enumerator monitoring view (handbook 3.2): the indicators side by side for each
* enumerator and round, with the round's pooled value ("All") to compare against.
*   from the calls: dials, interviews, operator-days, interviews per operator-day, dials per interview, share of
*     cases with a refusal, median length of the completing dial, share of interviews shorter than 60% of the round's
*     median length
*   from the answers: share of "don't know" and "refused" codes (98, 99) among select-one answers; share of
*     interviews reporting a shock; share reporting four or more food insecurity experiences (two answer
*     distributions an enumerator can shift, 3.2.1)
*   from the skip-logic audit: flags per 100 interviews
* Values from fewer than 10 interviews are left empty.
* In:  output/calls/dials_R##.dta, cases_R##.dta, output/_raw/R##/completes.dta, output/checks/form_audit_enum_R##.csv
* Out: output/calls/enumerator_monitor.csv
* =============================================================================
tempfile dials cases ans flags out
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    append using "$OUT/calls/dials_R`rr'.dta"
}
capture drop date
gen int date = dofc(dial_start)
egen byte tag_od = tag(round enumerator date)
bysort round hhid: egen byte c_ref = max(outcome == 5)
egen byte tag_case = tag(round hhid)
gen byte case_ref = c_ref * tag_case
save `dials'
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    append using "$OUT/calls/cases_R`rr'.dta"
}
bysort round: egen double med_round = median(min_complete)
gen byte short = completed & min_complete < 0.6 * med_round
save `cases'

* answers: don't know / refused codes among the select-one questions, and two answer distributions
import excel using "$DATA/form/L2PHL_SYN_CATI_R01.xlsx", sheet("survey") firstrow allstring clear
keep if word(type, 1) == "select_one"
local sel
forvalues i = 1/`=_N' {
    local sel `sel' `=lower(name[`i'])'
}
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    preserve
    use "$OUT/_raw/R`rr'/completes.dta", clear
    quietly ds
    local have `r(varlist)'
    local use : list sel & have
    local num
    foreach v of local use {
        capture confirm numeric variable `v'
        if !_rc local num `num' `v'
    }
    egen long n_sel = rownonmiss(`num')
    egen long n_dk = anycount(`num'), values(98 99)
    gen byte shock = sh1 == 1
    egen byte fies = anycount(f08_?), values(1)
    gen byte fies4 = fies >= 4
    keep round int_id n_sel n_dk shock fies4
    tempfile one
    save `one'
    restore
    append using `one'
}
merge m:1 int_id using "$OUT/calls/enumerators.dta", keep(match) keepusing(enumerator) nogenerate
save `ans'

clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    preserve
    import delimited "$OUT/checks/form_audit_enum_R`rr'.csv", clear varnames(1)
    tempfile one
    save `one'
    restore
    append using `one'
}
keep round enumerator flags
save `flags'

* by enumerator, then pooled
foreach level in enumerator all {
    local by = cond("`level'" == "enumerator", "round enumerator", "round")
    use `dials', clear
    collapse (count) dials = seq (sum) operator_days = tag_od refusals = case_ref cases = tag_case, by(`by') fast
    tempfile d
    save `d'
    use `cases', clear
    collapse (sum) completes = completed shorts = short (median) median_minutes = min_complete, by(`by') fast
    merge 1:1 `by' using `d', nogenerate
    tempfile c
    save `c'
    use `ans', clear
    collapse (sum) n_sel n_dk (mean) shock_share = shock fies4_share = fies4, by(`by') fast
    merge 1:1 `by' using `c', nogenerate
    if "`level'" == "enumerator" merge 1:1 `by' using `flags', nogenerate
    else {
        preserve
        use `flags', clear
        collapse (sum) flags, by(round)
        tempfile f
        save `f'
        restore
        merge 1:1 round using `f', nogenerate
        gen str12 enumerator = "All"
    }
    replace flags = 0 if missing(flags)
    gen double completes_per_day = completes / operator_days
    gen double dials_per_complete = dials / completes
    gen double refusal_rate = refusals / cases
    gen double short_share = shorts / completes
    gen double dk_share = n_dk / n_sel
    gen double flags_per_100 = 100 * flags / completes
    foreach v in completes_per_day dials_per_complete refusal_rate median_minutes short_share dk_share flags_per_100 shock_share fies4_share {
        replace `v' = . if completes < 10
    }
    keep round enumerator dials completes operator_days cases completes_per_day dials_per_complete refusal_rate ///
        median_minutes short_share dk_share flags_per_100 shock_share fies4_share
    if "`level'" == "enumerator" save `out'
    else append using `out'
}
sort round enumerator
order round enumerator
export delimited using "$OUT/calls/enumerator_monitor.csv", replace
di as result "45_enumerator_monitor: written"
