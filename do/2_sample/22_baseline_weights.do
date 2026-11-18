* =============================================================================
* 22_baseline_weights.do: baseline household weights.
* Design weight = 1 / (pi1 * pi2), with pi2 = households interviewed in the PSU / census households in the PSU (the
* baseline used a random walk, so there is no listing count). The design weights are then scaled so that they sum,
* in each stratum, to the census number of households.
* In:  output/sample/psu_selected.dta, data/baseline/baseline_households.csv, data/frame/census_totals.csv
* Out: output/sample/baseline_weights.dta, output/sample/census_totals.dta
* =============================================================================

import delimited "$DATA/frame/census_totals.csv", clear
save "$OUT/sample/census_totals.dta", replace

import delimited "$DATA/baseline/baseline_households.csv", clear
drop cp name                                        // contacts stay in the input file and in output/pii
merge m:1 psu using "$OUT/sample/psu_selected.dta", nogenerate assert(match) keepusing(pi1 hh_census)
bysort psu: gen n_psu = _N
gen double pi2 = n_psu / hh_census
gen double w_design = 1 / (pi1 * pi2)
merge m:1 stratum using "$OUT/sample/census_totals.dta", nogenerate assert(match) keepusing(households)
bysort stratum: egen double sum_w = total(w_design)
gen double w_bl = w_design * households / sum_w
label variable w_design "Baseline design weight"
label variable w_bl "Baseline household weight (scaled to census households by stratum)"
keep hhid psu region locale stratum hhsize has_phone u w_design w_bl
sort hhid
save "$OUT/sample/baseline_weights.dta", replace

* check: weights add up to the census households of each stratum
use "$OUT/sample/baseline_weights.dta", clear
merge m:1 stratum using "$OUT/sample/census_totals.dta", nogenerate keepusing(households)
bysort stratum: egen double chk = total(w_bl)
assert reldif(chk, households) < 1e-9
di as result "22_baseline_weights: " _N " households weighted"
