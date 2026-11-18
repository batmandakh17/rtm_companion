* =============================================================================
* run_tests.do: runs the whole workflow, then checks its results against what the synthetic data were built with
* (tests/expected_counts.csv, written by tools/make_synthetic.py). Results in tests/results.txt.
* Run from the package folder:  stata-mp -b do tests/run_tests.do   (or set global RTM first)
* =============================================================================
clear all
if `"$RTM"' == "" global RTM `"`c(pwd)'"'
do `"$RTM/00_master.do"'

tempname fh
file open `fh' using "$RTM/tests/results.txt", write text replace
file write `fh' "RTM companion tests, `c(current_date)' `c(current_time)'" _n
local fails 0
capture program drop test_eq
program define test_eq, rclass
    args fh what got want
    local ok = abs(`got' - `want') < 1e-6
    file write `fh' (cond(`ok', "PASS", "FAIL")) "  `what': got `got', expected `want'" _n
    return scalar fail = !`ok'
end

* ---------------------------------------------------------------- planted problems found, completes and dials
import delimited "$RTM/tests/expected_counts.csv", clear
tempfile exp
save `exp'
import delimited "$OUT/checks/checks.csv", clear bindquote(strict)
tempfile ck
save `ck'
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    use `exp', clear
    keep if round == `r'
    foreach v in test_submissions duplicate_submissions negative_durations short_completes completes dials routing_broken required_missing out_of_range {
        local e_`v' = `v'[1]
    }
    use `ck', clear
    foreach pair in "test_submissions|practice submissions dated before the first calling day" ///
                    "duplicate_submissions|the same submission sent twice" ///
                    "negative_durations|submissions saved before they were opened (device clock)" ///
                    "short_completes|completes recorded in under 3 minutes" {
        gettoken key what : pair, parse("|")
        local what = substr("`what'", 2, .)
        quietly summarize n if round == `r' & check == "`what'"
        test_eq `fh' "R`r' `what'" `r(sum)' `e_`key''
        local fails = `fails' + r(fail)
    }
    foreach what in "dials in only one of the two sources (call centre, form)" ///
                    "dials where the two sources disagree on enumerator, start or outcome" ///
                    "households complete in the calls but not in the passport, or the reverse" {
        quietly summarize n if round == `r' & check == "`what'"
        test_eq `fh' "R`r' `what'" `r(sum)' 0
        local fails = `fails' + r(fail)
    }
    quietly count if round == `r' & strpos(check, "preload for round") & n == 0
    test_eq `fh' "R`r' preload for the next round identical to the generator's" `r(N)' 1
    local fails = `fails' + r(fail)
    import delimited "$OUT/checks/form_audit_R`rr'.csv", clear bindquote(strict)
    foreach v in routing_broken required_missing out_of_range {
        quietly summarize `v'
        test_eq `fh' "R`r' skip-logic audit, `v'" `r(sum)' `e_`v''
        local fails = `fails' + r(fail)
    }
    quietly count if status == "not translated"
    test_eq `fh' "R`r' skip-logic audit, routing rules the audit could not read" `r(N)' 0
    local fails = `fails' + r(fail)
    local nfl 0
    capture confirm file "$OUT/checks/review/R`rr'_form_flags.csv"
    if !_rc {
        import delimited "$OUT/checks/review/R`rr'_form_flags.csv", clear varnames(1)
        local nfl = _N
    }
    local e_flags = `e_routing_broken' + `e_required_missing' + `e_out_of_range'
    test_eq `fh' "R`r' skip-logic audit, flagged rows listed by household in review/R`rr'_form_flags.csv" `nfl' `e_flags'
    local fails = `fails' + r(fail)
    use "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_M00_passport.dta", clear
    test_eq `fh' "R`r' households interviewed" `=_N' `e_completes'
    local fails = `fails' + r(fail)
    use "$OUT/calls/dials_kobo_R`rr'.dta", clear
    test_eq `fh' "R`r' dials after dropping practice and duplicate submissions" `=_N' `e_dials'
    local fails = `fails' + r(fail)
    use "$OUT/weights/weights_R`rr'.dta", clear
    quietly summarize w_round
    local wsum = r(sum)
    use "$OUT/sample/census_totals.dta", clear
    quietly summarize households
    test_eq `fh' "R`r' weights sum to the census households" `=round(`wsum')' `r(sum)'
    local fails = `fails' + r(fail)
}

* ---------------------------------------------------------------- dashboard files
foreach f in index.html dashboard_data.js {
    capture confirm file "$OUT/dashboard/`f'"
    test_eq `fh' "dashboard file `f' exists" `=_rc == 0' 1
    local fails = `fails' + r(fail)
}
file write `fh' _n (cond(`fails' == 0, "ALL PASS", "`fails' FAILED")) _n
file close `fh'
type "$RTM/tests/results.txt"
if `fails' exit 9
