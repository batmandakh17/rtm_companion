* =============================================================================
* 61_indicators.do: the dashboard's survey results, weighted, by round.
*   indicators.csv   key indicators with 95% confidence intervals, for all households and for urban and rural ones
*                    (design: strata and PSUs of the baseline, round weights from step 5)
*   shock_types.csv  share of households reporting each type of shock
*   explorer.csv     every labelled question of every module file: weighted percent in each answer, by round (the
*                    "module explorer", as in the L2PHL summary dashboard)
* Cells from fewer than 10 households (or members) are left empty.
* In:  output/modules/R## (module files), output/weights/weights_R##.dta, output/sample/phone_sample.dta
* Out: output/dashboard/indicators.csv, shock_types.csv, explorer.csv
* =============================================================================
tempfile hh pp res

* ---------------------------------------------------------------- analysis files: households and adults, all rounds
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    local stub "$OUT/modules/R`rr'/${PROGRAM}_R`rr'"
    preserve
    use hhid round using "`stub'_M00_passport.dta", clear
    merge 1:1 hhid using "$OUT/weights/weights_R`rr'.dta", keepusing(w_round) nogenerate assert(match)
    merge 1:1 hhid using "`stub'_M03_shock_hh.dta", keepusing(sh1 sh1b_1 sh1b_11 sh1b_13 sh1b_20) nogenerate
    merge 1:1 hhid using "`stub'_M08_food.dta", keepusing(fies_raw f08_h) nogenerate
    foreach m in M06_finance M07_health {
        capture confirm file "`stub'_`m'.dta"
        if !_rc merge 1:1 hhid using "`stub'_`m'.dta", nogenerate
    }
    * coping: reduced food consumption for any shock
    tempfile cope
    save `cope'
    use hhid sh2_13 using "`stub'_M03_shock.dta", clear
    collapse (max) cope_food = sh2_13, by(hhid)
    merge 1:1 hhid using `cope', nogenerate
    tempfile one
    save `one'
    restore
    append using `one'
}
merge m:1 hhid using "$OUT/sample/phone_sample.dta", keepusing(psu stratum locale) keep(match) nogenerate
foreach v in f17 f18 f6 h2 h2a {
    capture gen `v' = .
}
gen byte shock_any = sh1 == 1
gen byte shock_prices = sh1b_11 == 1
gen byte shock_typhoon = sh1b_1 == 1
gen byte shock_illness = sh1b_20 == 1
replace cope_food = . if sh1 != 1
gen byte fies4 = fies_raw >= 4 if fies_raw < .
gen byte skip_meal = f08_h == 1 if f08_h < .
gen byte bank = f17 == 1 if f17 < .
gen byte mobile_money = f18 == 1 if f18 < .
gen byte emergency = f6 == 1 if inlist(f6, 1, 2)
gen byte care_unmet = h2a == 2 if inlist(h2, 1, 2, 3) & inlist(h2a, 1, 2)
save `hh'

use `hh', clear
keep hhid round w_round psu stratum locale
tempfile wts
save `wts'
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    append using "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_M04_employment.dta", keep(hhid round fmid employed)
}
merge m:1 hhid round using `wts', keep(match) nogenerate
save `pp'

* ---------------------------------------------------------------- key indicators
local K_shock_any     "Households hit by a shock in the past 30 days"
local K_shock_prices  "Households hit by higher prices of food, fuel or other goods"
local K_shock_typhoon "Households hit by a typhoon"
local K_shock_illness "Households hit by a major illness"
local K_cope_food     "Households hit by a shock that cut food consumption to cope"
local K_fies4         "Households reporting 4 or more of 8 food insecurity experiences"
local K_skip_meal     "Households where someone skipped a meal for lack of money"
local K_bank          "Households with a bank account"
local K_mobile_money  "Households with a mobile money account"
local K_emergency     "Households able to pay an emergency expense of one month's income"
local K_care_unmet    "Households that needed health care and did not get it"
local K_employed      "Adults (15+) who worked or had a job last week"

tempname ph
postfile `ph' str16 indicator str90 label int round str6 group double(est lb ub) long n using `res', replace
foreach k in shock_any shock_prices shock_typhoon shock_illness cope_food fies4 skip_meal bank mobile_money emergency care_unmet employed {
    if "`k'" == "employed" use `pp', clear
    else use `hh', clear
    quietly svyset psu [pw = w_round], strata(stratum) singleunit(centered)
    foreach r of global ROUNDS {
        foreach g in all urban rural {
            local cond = cond("`g'" == "all", "1", cond("`g'" == "urban", "locale == 1", "locale == 2"))
            quietly count if round == `r' & `cond' & `k' < .
            if r(N) == 0 continue
            capture quietly svy, subpop(if round == `r' & `cond' & `k' < .): mean `k'
            if _rc continue
            local n = e(N_sub)
            local b = el(e(b), 1, 1)
            local se = sqrt(el(e(V), 1, 1))
            local t = invttail(e(df_r), 0.025)
            if `n' < 10 post `ph' ("`k'") ("`K_`k''") (`r') ("`g'") (.) (.) (.) (`n')
            else post `ph' ("`k'") ("`K_`k''") (`r') ("`g'") (`b') (max(0, `b' - `t' * `se')) (min(1, `b' + `t' * `se')) (`n')
        }
    }
}
postclose `ph'
use `res', clear
export delimited using "$OUT/dashboard/indicators.csv", replace

* ---------------------------------------------------------------- shock types
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    append using "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_M03_shock_hh.dta"
}
merge 1:1 hhid round using `wts', keep(match) nogenerate
quietly ds sh1b_*
local types
foreach v in `r(varlist)' {
    capture confirm numeric variable `v'
    if !_rc local types `types' `v'
}
foreach v of local types {
    replace `v' = 0 if sh1 != 1
    local lab`v' : variable label `v'
}
collapse (mean) `types' [aw = w_round], by(round)
reshape long sh1b_, i(round) j(code)
rename sh1b_ share
gen str60 label = ""
foreach v of local types {
    local c = substr("`v'", 6, .)
    replace label = substr("`lab`v''", strpos("`lab`v''", " ") + 1, .) if code == `c'
}
export delimited using "$OUT/dashboard/shock_types.csv", replace

* ---------------------------------------------------------------- module explorer
tempname pe
tempfile ex
postfile `pe' str20 module str32 var str80 varlabel int round long code str80 catlabel double pct long n using `ex', replace
local skip hhid round fmid int_id sample z8 call_status1 z17 z9 x15 status present prev_work d5a_
foreach m in M00_passport M01_roster M03_shock_hh M04_employment M06_finance M07_health M08_food {
    foreach r of global ROUNDS {
        local rr : display %02.0f `r'
        capture confirm file "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_`m'.dta"
        if _rc continue
        use "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_`m'.dta", clear
        merge m:1 hhid using "$OUT/weights/weights_R`rr'.dta", keepusing(w_round) keep(match) nogenerate
        if "`m'" == "M01_roster" keep if present
        quietly ds, has(vallabel)
        local vars `r(varlist)'
        local vars : list vars - skip
        foreach v of local vars {
            quietly levelsof `v', local(codes)
            if `: word count `codes'' > 25 continue
            local vl : variable label `v'
            quietly summarize w_round if `v' < .
            local tot = r(sum)
            foreach c of local codes {
                quietly summarize w_round if `v' == `c'
                local wc = r(sum)
                local nc = r(N)
                local cl : label (`v') `c'
                local pct = cond(`nc' < 10, ., 100 * `wc' / `tot')
                post `pe' ("`m'") ("`v'") (`"`vl'"') (`r') (`c') (`"`cl'"') (`pct') (`nc')
            }
        }
    }
}
postclose `pe'
use `ex', clear
export delimited using "$OUT/dashboard/explorer.csv", replace
di as result "61_indicators: indicators, shock types and explorer written"
