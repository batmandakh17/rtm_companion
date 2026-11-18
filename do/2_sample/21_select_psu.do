* =============================================================================
* 21_select_psu.do: baseline stage 1, PSUs drawn with probability proportional to size.
* The baseline design is the L2 programs': census enumeration areas as PSUs, stratified by region and urban/rural,
* two stages (PSUs, then households). Selection with PPS at stage 1 follows UN (2008), Designing Household Survey
* Samples: Practical Guidelines.
* Method: systematic PPS within each stratum, frame in PSU order, measure of size = census households, one random
* start per stratum. The starts were drawn once with runiform() and are recorded here, so the draw can be repeated
* exactly. A PSU is selected when a selection point (start + k) * T / n falls in its stretch (prev, cum] of the
* cumulative size; no PSU here is larger than the interval T / n, so none is selected twice.
* In:  data/frame/frame_psu.csv
* Out: output/sample/psu_selected.dta (with pi1, the PSU's selection probability)
* =============================================================================

* ---------------------------------------------------------------- parameters
local n_h 15                                       // PSUs per stratum
local starts 11 0.2718 12 0.5772 21 0.1414 22 0.8862 31 0.3183 32 0.6931 41 0.4142 42 0.7071

import delimited "$DATA/frame/frame_psu.csv", clear
sort stratum psu
by stratum: gen double cum = sum(hh_census)
gen double prev = cum - hh_census
by stratum: egen double tot = total(hh_census)
gen double start = .
while "`starts'" != "" {
    gettoken s starts : starts
    gettoken u starts : starts
    replace start = `u' if stratum == `s'
}
assert start < .
gen hits = floor(cum * `n_h' / tot - start) - floor(prev * `n_h' / tot - start)
assert hits <= 1
gen double pi1 = `n_h' * hh_census / tot
label variable pi1 "PSU selection probability (stage 1)"
keep if hits == 1
by stratum: assert _N == `n_h'
keep psu region locale stratum hh_census pop_census pi1
save "$OUT/sample/psu_selected.dta", replace

* the baseline was fielded in exactly these PSUs
preserve
import delimited "$DATA/baseline/baseline_households.csv", clear
keep psu
duplicates drop
merge 1:1 psu using "$OUT/sample/psu_selected.dta", nogenerate assert(match)
restore
di as result "21_select_psu: " _N " PSUs selected, the same PSUs as the baseline"
