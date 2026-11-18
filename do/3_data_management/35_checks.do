* =============================================================================
* 35_checks.do (round): consistency checks on the module files. Nothing is changed here; every check writes its count
* to output/checks/checks.csv, where the team (and the dashboard's data-checks tab) reads what needs a look.
* Skip patterns are checked against the form's relevance rules; ranges against its constraints.
* =============================================================================
args r
local rr : display %02.0f `r'
local stub "$OUT/modules/R`rr'/${PROGRAM}_R`rr'"

* ---------------------------------------------------------------- M00 passport
use "`stub'_M00_passport.dta", clear
quietly count if intdate < date("${START_`r'}", "YMD") | intdate > date("${START_`r'}", "YMD") + 27
check_log `r' 3 "M00: interview dates outside the round's four weeks" `r(N)' "listed"
quietly count if missing(int_id)
check_log `r' 3 "M00: interviews without an interviewer code" `r(N)' "listed"

* ---------------------------------------------------------------- M01 roster
use "`stub'_M01_roster.dta", clear
quietly count if present & (age < 0 | age > 120)
check_log `r' 3 "M01: ages outside 0-120" `r(N)' "listed"
bysort hhid: egen n_present = total(present)
bysort hhid: egen n_left = total(status == 2)
bysort hhid: egen n_new = total(status == 4)
merge m:1 hhid using "`stub'_M00_passport.dta", keepusing(hhsize) keep(match) nogenerate
bysort hhid: gen byte first = _n == 1
quietly count if first & n_present != hhsize - n_left + n_new
check_log `r' 3 "M01: members present do not equal last size - leavers + joiners" `r(N)' "listed"

* ---------------------------------------------------------------- M03 shocks
use "`stub'_M03_shock_hh.dta", clear
quietly count if sh1 != 1 & n_shocks > 0
check_log `r' 3 "M03: shock types recorded without a shock (SH1 = no)" `r(N)' "listed"
quietly count if sh1 == 1 & n_shocks == 0
check_log `r' 3 "M03: a shock (SH1 = yes) without its type" `r(N)' "listed"

* ---------------------------------------------------------------- M04 employment
use "`stub'_M04_employment.dta", clear
quietly count if !missing(a24) & prev_work != 1
check_log `r' 3 "M04: A24 asked of a member not working at the last interview" `r(N)' "listed"
quietly count if !missing(a27) & prev_work != 2
check_log `r' 3 "M04: A27 asked of a member working at the last interview" `r(N)' "listed"
quietly count if employed & (missing(a5) | missing(a6) | missing(a10) | missing(a11))
check_log `r' 3 "M04: employed members without industry, class, days or hours" `r(N)' "listed"
quietly count if !employed & !missing(a5)
check_log `r' 3 "M04: industry recorded for a member not employed" `r(N)' "listed"
quietly count if (a10 > 7 & a10 < .) | (a11 > 168 & a11 < .)
check_log `r' 3 "M04: days or hours outside the form's limits" `r(N)' "listed"
quietly count if a11 > 16 * a10 & a11 < . & a10 > 0
check_log `r' 3 "M04: more than 16 hours a working day" `r(N)' "listed for a callback"
review_list `r' hours_per_day if a11 > 16 * a10 & a11 < . & a10 > 0
quietly count if age < 15
check_log `r' 3 "M04: members under 15 in the employment module" `r(N)' "listed"
review_list `r' employment_under15 if age < 15

* ---------------------------------------------------------------- M06 finance and M07 health (when in the round)
capture confirm file "`stub'_M06_finance.dta"
if !_rc {
    use "`stub'_M06_finance.dta", clear
    quietly count if (!missing(f1) & f17 != 1) | (missing(f1) & f17 == 1) | (!missing(f2) & f18 != 1) | (missing(f2) & f18 == 1)
    check_log `r' 3 "M06: account use (F1, F2) does not follow account ownership (F17, F18)" `r(N)' "listed"
    quietly count if (!missing(f10) & f7 != 1) | (missing(f10) & f7 == 1)
    check_log `r' 3 "M06: loan approval (F10) does not follow the loan question (F7)" `r(N)' "listed"
}
capture confirm file "`stub'_M07_health.dta"
if !_rc {
    use "`stub'_M07_health.dta", clear
    quietly count if (!missing(h2a) & !inlist(h2, 1, 2, 3)) | (missing(h2a) & inlist(h2, 1, 2, 3))
    check_log `r' 3 "M07: H2A does not follow the need for care (H2)" `r(N)' "listed"
    quietly count if (!missing(h3) & h2a != 2) | (missing(h3) & h2a == 2)
    check_log `r' 3 "M07: the reason for no care (H3) does not follow H2A" `r(N)' "listed"
}
di as result "35_checks R`rr': done"
