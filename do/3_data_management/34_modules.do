* =============================================================================
* 34_modules.do (round): the other module files, named as in L2PHL.
*   M03 shocks       household level (SH1, SH1b) and one row per household and shock with its coping (repeat sh2_)
*   M04 employment   one row per member aged 15+ asked the module: members from the last interview (repeat employ_)
*                    and new members (repeat employ_new, renamed without _new)
*   M06 finance      household level, rounds whose form has the module (rotating)
*   M07 health       household level, rounds whose form has the module (rotating)
*   M08 food         household level, the eight food insecurity experiences and their count
* In:  output/_raw/R##/completes.dta, sh2_.dta, employ_.dta, employ_new.dta; the round's M01
* Out: output/modules/R##/l2phl_syn_R##_M03_shock_hh.dta, _M03_shock.dta, _M04_employment.dta, _M06_finance.dta,
*      _M07_health.dta, _M08_food.dta
* =============================================================================
args r
local rr : display %02.0f `r'
local form "$DATA/form/L2PHL_SYN_CATI_R`rr'.xlsx"
local stub "$OUT/modules/R`rr'/${PROGRAM}_R`rr'"

use hhid _index fmid_max using "$OUT/_raw/R`rr'/completes.dta", clear
rename _index _parent_index
tempfile parents oldemp
save `parents'

* ---------------------------------------------------------------- M03 shocks, household level
use "$OUT/_raw/R`rr'/completes.dta", clear
keep hhid round sh1 sh1b_*
rename sh1b_ sh1b_codes
gen n_shocks = wordcount(sh1b_codes)
label variable n_shocks "Number of shock types reported"
form_labels using "`form'"
label variable sh1b_codes "SH1b. Shock types (codes, space-separated)"
compress
save "`stub'_M03_shock_hh.dta", replace

* M03 shocks, one row per household and shock
use "$OUT/_raw/R`rr'/sh2_.dta", clear
merge m:1 _parent_index using `parents', keep(match) nogenerate
rename (sh1b_ans sh2_) (shock sh2_codes)
drop sh1b_ansname
keep hhid round shock sh2_*
form_labels using "`form'"
label values shock shocks
label variable shock "Shock"
label variable sh2_codes "SH2. Coping (codes, space-separated)"
bysort hhid: gen n_rows = _N
merge m:1 hhid using "`stub'_M03_shock_hh.dta", keep(master match) keepusing(n_shocks) nogenerate
quietly count if n_rows != n_shocks
check_log `r' 3 "M03: households whose coping rows differ from the shocks reported" `r(N)' "listed"
drop n_rows n_shocks
compress
save "`stub'_M03_shock.dta", replace

* ---------------------------------------------------------------- M04 employment
use "$OUT/_raw/R`rr'/employ_.dta", clear
merge m:1 _parent_index using `parents', keep(match) nogenerate
rename employ_fmid fmid
keep if fmid_employment < . & employ_left == 0
gen byte prev_work = fmid_employment
keep hhid round fmid prev_work a24 a27 a1 a26 a3 a3_oth a5 a5_oth a6 a10 a11
save `oldemp'
use "$OUT/_raw/R`rr'/employ_new.dta", clear
merge m:1 _parent_index using `parents', keep(match) nogenerate
if _N > 0 {
    gen fmid = fmid_max + employ_fmid_new
    keep if employ_age_new >= 15
    rename (*_new) (*)
    keep hhid round fmid a1 a26 a3 a3_oth a5 a5_oth a6 a10 a11
    append using `oldemp'
}
else use `oldemp', clear
gen byte employed = a24 == 4 | a1 == 1 | a26 == 1
label variable employed "Worked last week or has a job or business"
label variable prev_work "Working at the last interview (1 yes, 2 no; empty for new members)"
merge 1:1 hhid fmid using "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_M01_roster.dta", keep(master match) keepusing(sex age)
quietly count if _merge == 1
check_log `r' 3 "M04: members not found in the roster" `r(N)' "stop"
drop _merge
form_labels using "`form'"
label values sex gender
order hhid round fmid sex age employed prev_work
sort hhid fmid
compress
save "`stub'_M04_employment.dta", replace

* ---------------------------------------------------------------- M06 finance and M07 health (rotating modules)
foreach m in M06_finance M07_health {
    use "$OUT/_raw/R`rr'/completes.dta", clear
    local first = cond("`m'" == "M06_finance", "f17", "h2")
    capture confirm variable `first'
    if _rc {
        di as text "34_modules R`rr': `m' is not in this round's form"
        continue
    }
    if "`m'" == "M06_finance" keep hhid round f17 f1 f18 f2 f3 f6 f7 f10
    else keep hhid round h2 h2a h3 h3_oth
    form_labels using "`form'"
    compress
    save "`stub'_`m'.dta", replace
}

* ---------------------------------------------------------------- M08 food insecurity
use "$OUT/_raw/R`rr'/completes.dta", clear
keep hhid round f08_?
egen fies_raw = anycount(f08_?), values(1)
egen n_answered = rownonmiss(f08_?)
quietly count if n_answered != 8
check_log `r' 3 "M08: households without all eight food insecurity answers" `r(N)' "listed"
drop n_answered
label variable fies_raw "Food insecurity experiences reported (0-8)"
form_labels using "`form'"
compress
save "`stub'_M08_food.dta", replace

di as result "34_modules R`rr': done"
