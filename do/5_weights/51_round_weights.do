* =============================================================================
* 51_round_weights.do (round): household weights for one phone round, in three steps.
*   1. Start: each household interviewed this round starts from its phone-sample weight (step 2: baseline weight x
*      households with a phone in the PSU / main households in the PSU).
*   2. Replacements: a replacement household takes the place of the main household it replaced. It comes from the
*      same PSU's list, so it starts from the same weight; nothing else changes.
*   3. Nonresponse, attrition and households without a phone: the starting weights are raked (iterative proportional
*      fitting, Deming and Stephan 1940) to two sets of totals: census households by stratum, and baseline
*      households by household size (1-2, 3-4, 5-6, 7+; all baseline households, with and without a phone,
*      weighted). Each round is raked afresh, so households lost since round 1 are made up by those still answering.
*      L2 programs do the same with entropy balancing (ebalance and svycal rake give the same weights). No trimming.
* Diagnostics: largest/smallest weight and the design effect from unequal weights, 1 + CV^2 (Kish 1965).
* In:  this round's M00, output/sample/phone_sample.dta, baseline_weights.dta, census_totals.dta
* Out: output/weights/weights_R##.dta, summary_R##.csv
* =============================================================================
args r
local rr : display %02.0f `r'
tempfile size

* margins
use "$OUT/sample/baseline_weights.dta", clear
gen byte sizecl = min(4, ceil(hhsize / 2))
collapse (sum) T_size = w_bl, by(sizecl)
save `size'

use hhid using "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_M00_passport.dta", clear
merge 1:1 hhid using "$OUT/sample/phone_sample.dta", keep(match) keepusing(stratum hhsize sample w_ph) nogenerate
gen byte sizecl = min(4, ceil(hhsize / 2))
merge m:1 stratum using "$OUT/sample/census_totals.dta", keep(match) keepusing(households) nogenerate
merge m:1 sizecl using `size', keep(match) nogenerate
rename households T_stratum

gen double w = w_ph
local it 0
local gap 1
while `gap' > 1e-10 & `it' < 200 {
    local ++it
    bysort stratum: egen double s = total(w)
    replace w = w * T_stratum / s
    drop s
    bysort sizecl: egen double s = total(w)
    replace w = w * T_size / s
    drop s
    bysort stratum: egen double s = total(w)
    gen double d = abs(s / T_stratum - 1)
    quietly summarize d
    local gap = r(max)
    drop s d
}
if `gap' > 1e-10 {
    di as error "51_round_weights R`rr': raking did not converge"
    exit 430
}
quietly summarize w
local ratio = round(r(max) / r(min), 0.1)
local tot = r(sum)
local deff = round(1 + (r(sd) * sqrt((r(N) - 1) / r(N)) / r(mean))^2, 0.01)
check_log `r' 5 "largest weight / smallest weight (raked in `it' passes)" `ratio' "no trimming"
check_log `r' 5 "design effect from unequal weights (1 + CV squared)" `deff' "reported"
preserve
gen byte repl = sample == 2
collapse (count) households = w (sum) weight_sum = w replacements = repl (min) w_min = w (max) w_max = w, fast
gen int round = `r'
gen double deff = `deff'
gen int passes = `it'
order round households replacements weight_sum w_min w_max deff passes
export delimited using "$OUT/weights/summary_R`rr'.csv", replace
restore
gen int round = `r'
rename w w_round
label variable w_round "Household weight, round `r'"
keep hhid round stratum w_round
sort hhid
save "$OUT/weights/weights_R`rr'.dta", replace
di as result "51_round_weights R`rr': " _N " households, weights sum to " %12.0fc `tot'
