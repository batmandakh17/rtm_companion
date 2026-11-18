* =============================================================================
* 36_preload.do (round): the next round's preload, the file the form reads with pulldata() (members, ages, sex,
* who still lives there, who worked). It starts from this round's preload and updates every household interviewed
* this round from the module files; households not reached keep what was known. The panel is the households
* interviewed in round 1. The file holds names and numbers, so it is written to output/pii.
* Check: when data/raw/R(next)/media/preload.csv exists (the file the synthetic data were built with), the two must
* agree cell by cell; the count of differing cells goes to checks.csv.
* In:  output/pii/preload_R##.csv, this round's M00, M01, M04 and names; round 1's M00
* Out: output/pii/preload_R(next).csv
* =============================================================================
args r
local rr : display %02.0f `r'
local nn : display %02.0f `=`r' + 1'
local stub "$OUT/modules/R`rr'/${PROGRAM}_R`rr'"
tempfile cur prev panel

* this round's members, with their names and whether they worked
use hhid fmid status age sex using "`stub'_M01_roster.dta", clear
merge 1:1 hhid fmid using "$OUT/pii/R`rr'_names.dta", keepusing(name) nogenerate assert(match)
merge 1:1 hhid fmid using "`stub'_M04_employment.dta", keepusing(employed) keep(master match) nogenerate
gen byte perm_n = inlist(status, 1, 4)
gen byte emp_n = cond(employed == 1, 1, cond(employed == 0, 2, .))
rename (age sex name) (age_n sex_n name_n)
keep hhid fmid age_n sex_n name_n perm_n emp_n
save `cur'

* this round's preload, one row per member
import delimited "$OUT/pii/preload_R`rr'.csv", clear stringcols(_all)
rename name respname
quietly ds respname cp name*, not
destring `r(varlist)', replace
reshape long name age sex perm emp, i(hhid) j(fmid)
drop if name == "" & missing(age)
merge 1:1 hhid fmid using `cur'
gen byte interviewed = _merge >= 2
bysort hhid: egen byte hh_int = max(interviewed)
foreach v in age sex perm {
    replace `v' = `v'_n if interviewed
}
replace emp = emp_n if interviewed & emp_n < .
replace name = name_n if interviewed
replace emp = . if perm == 0
foreach v in respname cp {
    bysort hhid (fmid): replace `v' = `v'[1]
}
foreach v in psu stratum round_lastint {
    bysort hhid (fmid): replace `v' = `v'[1]
}
replace round_lastint = `r' if hh_int
bysort hhid: egen n_perm = total(perm)
bysort hhid: egen n_max = max(fmid)
replace hhsize = n_perm
replace fmid_max = n_max
replace sample = 1
keep hhid fmid hhsize fmid_max sample round_lastint respname cp psu stratum name age sex perm emp
bysort hhid (fmid): replace hhsize = hhsize[1]
reshape wide name age sex perm emp, i(hhid) j(fmid)
rename respname name

* the panel: households interviewed in round 1
preserve
use hhid using "$OUT/modules/R01/${PROGRAM}_R01_M00_passport.dta", clear
save `panel'
restore
merge 1:1 hhid using `panel', keep(match) nogenerate
do "$DO/3_data_management/_preload_order.do"
export delimited using "$OUT/pii/preload_R`nn'.csv", replace nolabel

* the check against the preload the synthetic data were built with
capture confirm file "$DATA/raw/R`nn'/media/preload.csv"
if !_rc {
    import delimited "$OUT/pii/preload_R`nn'.csv", clear stringcols(_all)
    save `prev'
    import delimited "$DATA/raw/R`nn'/media/preload.csv", clear stringcols(_all)
    quietly ds hhid, not
    local vars `r(varlist)'
    rename (`vars') (=_x)
    merge 1:1 hhid using `prev'
    quietly count if _merge != 3
    local bad = r(N)
    foreach v of local vars {
        quietly count if `v' != `v'_x & _merge == 3
        local bad = `bad' + r(N)
    }
    check_log `r' 3 "preload for round `=`r' + 1': cells that differ from the file the synthetic data used" `bad' "stop"
}
di as result "36_preload R`rr': preload for round `=`r' + 1' written"
