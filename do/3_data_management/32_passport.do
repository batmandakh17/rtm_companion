* =============================================================================
* 32_passport.do (round): module M00, the passport: one row per household interviewed in the round.
* Rules, in order:
*   1. times: start and end are the device's local time; _submission_time is UTC (+8 hours here)
*   2. practice submissions, dated before the round's first calling day ($START_#), are dropped
*   3. a negative duration (device clock) is set to missing
*   4. the same interview sent twice (same household, start, end and result) keeps its first copy
*   5. complete = result X15 coded 1 (complete) or 2 (partially complete, no more callback), as in L2PHL
*   6. a household with two different completes keeps the first (none in the synthetic data; the rule is there)
* Identifying fields (respondent name, phone numbers, new address) go to output/pii, not into the module.
* In:  output/_raw/R##/main.dta
* Out: output/_raw/R##/submissions_flagged.dta (every submission with its flags; step 4 reads it)
*      output/_raw/R##/completes.dta (the kept complete submissions with every answer; 33 and 34 read it)
*      output/modules/R##/l2phl_syn_R##_M00_passport.dta, output/pii/R##_contacts.dta
* =============================================================================
args r
local rr : display %02.0f `r'
local form "$DATA/form/L2PHL_SYN_CATI_R`rr'.xlsx"
use "$OUT/_raw/R`rr'/main.dta", clear

* 1. times
foreach v in start end {
    gen double `v'_t = clock(subinstr(substr(`v', 1, 19), "T", " ", 1), "YMDhms")
    format `v'_t %tcCCYY-NN-DD_HH:MM:SS
}
gen double sub_t = clock(subinstr(_submission_time, "T", " ", 1), "YMDhms") + msofhours(8)
format sub_t %tcCCYY-NN-DD_HH:MM:SS
gen double dur_min = (end_t - start_t) / 60000
gen int day = dofc(start_t)
format day %td
label variable start_t "Form opened (local time)"
label variable end_t "Form saved (local time)"
label variable sub_t "Submitted to the server (local time)"
label variable dur_min "Minutes from form opened to form saved"

* 2. practice submissions
gen byte f_practice = day < date("${START_`r'}", "YMD")
quietly count if f_practice
check_log `r' 3 "practice submissions dated before the first calling day" `r(N)' "dropped"

* 3. negative durations
gen byte f_negdur = dur_min < 0
quietly count if f_negdur
check_log `r' 3 "submissions saved before they were opened (device clock)" `r(N)' "duration set to missing"
replace dur_min = . if f_negdur

* 4. the same interview sent twice
sort hhid start end x15 sub_t _id
by hhid start end x15: gen byte f_duplicate = _n > 1 & !f_practice
quietly count if f_duplicate
check_log `r' 3 "the same submission sent twice" `r(N)' "later copy dropped"

* 5. completes
gen byte complete = inlist(x15, 1, 2)
label variable complete "Interview complete (X15 = 1 or 2)"
gen byte f_short = complete & dur_min < 3
quietly count if f_short & !f_practice & !f_duplicate
check_log `r' 3 "completes recorded in under 3 minutes" `r(N)' "flagged (step 4 applies the 3-minute rule)"
review_list `r' short_completes if f_short & !f_practice & !f_duplicate
save "$OUT/_raw/R`rr'/submissions_flagged.dta", replace

* the passport
drop if f_practice | f_duplicate
bysort hhid (start_t _id): gen n_subs = _N
label variable n_subs "Call attempts recorded this round"
keep if complete
* 6. two different completes for one household
bysort hhid (start_t _id): gen byte f_second = _n > 1
quietly count if f_second
check_log `r' 3 "households with a second, different complete" `r(N)' "first kept"
drop if f_second
save "$OUT/_raw/R`rr'/completes.dta", replace

preserve
keep hhid round oldrespo oldcp x14 z21
save "$OUT/pii/R`rr'_contacts.dta", replace
restore

gen int intdate = date(z6, "YMD")
format intdate %td
label variable intdate "Z6. Date of interview"
keep hhid round int_id sample replacement_hhid hhsize fmid_max round_lastint d3 intdate start_t end_t sub_t dur_min ///
     n_subs z8 call_status1 z17 z9 z20 z1 z5 x11 x20 x15 f_short
order hhid round int_id intdate start_t end_t dur_min n_subs
form_labels using "`form'"
label variable hhid "Household ID"
label variable round "Round"
label variable hhsize "Household size at the last interview (preload)"
label variable fmid_max "Members listed so far (preload)"
label variable round_lastint "Round of the last interview (0 = baseline)"
label variable f_short "Complete recorded in under 3 minutes"
compress
save "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_M00_passport.dta", replace
di as result "32_passport R`rr': " _N " households interviewed"
