* =============================================================================
* 23_phone_subsample.do: the phone panel's main sample and its replacements, and the round-1 preload.
* The rule is L2PHL's.
* Rule: in each PSU, baseline households with a phone are ranked by the random key u drawn at baseline; the first 6
* (urban PSUs) or 7 (rural PSUs) are the main sample, the others are replacements in rank order, used in round 1 when
* a main household of the same PSU refuses, has a dead number or cannot be reached.
* Phone-sample weight = baseline weight x (households with a phone in the PSU / main households in the PSU); the
* round weights (step 5) then adjust for households without a phone and for nonresponse.
* In:  output/sample/baseline_weights.dta, data/baseline/baseline_*.csv
* Out: output/sample/phone_sample.dta, sample_summary.csv (by stratum, for the dashboard);
*      output/pii/preload_R01.csv (what the form reads; names and numbers)
* =============================================================================

local main_urban 6
local main_rural 7

use "$OUT/sample/baseline_weights.dta", clear
keep if has_phone == 1
sort psu u hhid
by psu: gen rank_psu = _n
gen byte sample = 1 + (rank_psu > cond(locale == 1, `main_urban', `main_rural'))
gen rank = cond(sample == 1, 0, rank_psu - cond(locale == 1, `main_urban', `main_rural'))
bysort psu: gen n_phone = _N
bysort psu: egen n_main = total(sample == 1)
gen double w_ph = w_bl * n_phone / n_main
label define sample 1 "Main" 2 "Replacement"
label values sample sample
label variable rank "Replacement order within the PSU (0 = main)"
label variable w_ph "Phone-sample weight"
keep hhid psu region locale stratum hhsize sample rank w_bl w_ph
sort hhid
save "$OUT/sample/phone_sample.dta", replace
tab sample

* ---------------------------------------------------------------- the sample at each stage, by stratum
tempfile ph ps bl
gen byte main = sample == 1
gen byte repl = sample == 2
collapse (sum) main repl, by(stratum) fast
save `ph'
use "$OUT/sample/psu_selected.dta", clear
contract stratum, freq(psus)
save `ps'
use "$OUT/sample/baseline_weights.dta", clear
collapse (count) baseline = hhid (sum) phone = has_phone (mean) w_bl, by(stratum region locale) fast
merge 1:1 stratum using `ph', nogenerate assert(match)
merge 1:1 stratum using `ps', nogenerate assert(match)
save `bl'
import delimited "$DATA/frame/frame_psu.csv", clear
collapse (count) frame_psus = psu (sum) census_households = hh_census, by(stratum) fast
merge 1:1 stratum using `bl', nogenerate assert(match)
order stratum region locale frame_psus census_households psus baseline phone main repl w_bl
export delimited using "$OUT/sample/sample_summary.csv", replace nolabel

* ---------------------------------------------------------------- the round-1 preload (pulldata file of the form)
* one row per household, members side by side: name#, age#, sex#, perm# (1 = member) and emp# (1 worked, 2 did not,
* empty under 15), from the baseline
import delimited "$DATA/baseline/baseline_members.csv", clear stringcols(3)
rename (worked_last_week) (emp)
gen perm = 1
keep hhid fmid name age sex perm emp
reshape wide name age sex perm emp, i(hhid) j(fmid)
tempfile wide
save `wide'
import delimited "$DATA/baseline/baseline_households.csv", clear stringcols(9 11)
keep hhid hhsize name cp psu stratum
merge 1:1 hhid using "$OUT/sample/phone_sample.dta", keep(match) nogenerate keepusing(sample)
merge 1:1 hhid using `wide', keep(match) nogenerate
gen fmid_max = hhsize
gen round_lastint = 0
do "$DO/3_data_management/_preload_order.do"
export delimited using "$OUT/pii/preload_R01.csv", replace nolabel
di as result "23_phone_subsample: preload_R01.csv written for " _N " households"
