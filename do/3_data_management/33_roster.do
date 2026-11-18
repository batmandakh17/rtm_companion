* =============================================================================
* 33_roster.do (round): module M01, the roster: one row per member listed so far in each interviewed household.
* Members listed at the last interview come from the repeat old_ (member ID fmid = position in the preload); new members
* from the repeat newmembers get the next IDs (fmid_max + 1, ...). Corrections of name, age and sex (D5a = 3, 4, 5)
* replace the preloaded values. Relationship to the head is not asked again: it comes from the roster master, which
* starts from the baseline and gains each round's new members.
* Member status: 1 still a member, 2 left this round, 3 left before this round, 4 new this round.
* In:  output/_raw/R##/completes.dta, old_.dta, newmembers.dta; data/baseline/baseline_members.csv (first round)
* Out: output/modules/R##/l2phl_syn_R##_M01_roster.dta, output/modules/roster_master.dta, output/pii/R##_names.dta
* =============================================================================
args r
local rr : display %02.0f `r'
local form "$DATA/form/L2PHL_SYN_CATI_R`rr'.xlsx"

capture confirm file "$OUT/modules/roster_master.dta"
if _rc | `r' == 1 {
    import delimited "$DATA/baseline/baseline_members.csv", clear
    keep hhid fmid relationship
    save "$OUT/modules/roster_master.dta", replace
}

use hhid _index fmid_max using "$OUT/_raw/R`rr'/completes.dta", clear
rename _index _parent_index
tempfile parents old
save `parents'

* members listed at the last interview (rows of practice or duplicate submissions drop out in the merge)
use "$OUT/_raw/R`rr'/old_.dta", clear
merge m:1 _parent_index using `parents', keep(match) nogenerate
bysort hhid: gen n_rows = _N
gen byte bad = n_rows != fmid_max
quietly count if bad
check_log `r' 3 "M01: households whose old-member rows differ from fmid_max" `r(N)' "stop"
gen byte status = cond(fmidpermanent == 0, 3, cond(d5a_ == 2, 2, 1))
gen age = fmidage
replace age = d28 if d5a_ == 4
gen sex = fmidsex
replace sex = d33 if d5a_ == 5
gen name = fmidname
replace name = d27 if d5a_ == 3
rename (d25 d25_oth) (leave_reason leave_reason_oth)
keep hhid round fmid name sex age status d5a_ leave_reason leave_reason_oth
save `old'

* new members
use "$OUT/_raw/R`rr'/newmembers.dta", clear
merge m:1 _parent_index using `parents', keep(match) nogenerate
if _N > 0 {
    bysort _parent_index (_index): gen fmid = fmid_max + _n
    rename (d30 d31 d32 d6 m13_ m13_oth) (name sex age relationship movein movein_oth)
    gen byte status = 4
    keep hhid round fmid name sex age relationship movein movein_oth status
    append using `old'
}
else {
    use `old', clear
    gen relationship = .
    gen movein = .
    gen movein_oth = ""
}

* relationship to the head: the roster master, then this round's new members join it
merge m:1 hhid fmid using "$OUT/modules/roster_master.dta", keep(master match match_update) keepusing(relationship) update nogenerate
preserve
keep if status == 4
keep hhid fmid relationship
append using "$OUT/modules/roster_master.dta"
duplicates drop hhid fmid, force
sort hhid fmid
save "$OUT/modules/roster_master.dta", replace
restore

preserve
keep hhid round fmid name
save "$OUT/pii/R`rr'_names.dta", replace
restore
drop name

gen byte present = inlist(status, 1, 4)
label define status 1 "Still a member" 2 "Left this round" 3 "Left before this round" 4 "New this round"
label values status status
form_labels using "`form'"
label values sex gender
label values relationship relationship
label values leave_reason leave_reason
label values movein movein
label variable fmid "Member ID"
label variable sex "Sex"
label variable age "Age (years)"
label variable relationship "Relationship to the household head"
label variable status "Member status this round"
label variable present "Member of the household this round"
label variable leave_reason "D25. Why the member left"
label variable movein "M13. Why the new member moved in"
order hhid round fmid status present sex age relationship
sort hhid fmid
compress
save "$OUT/modules/R`rr'/${PROGRAM}_R`rr'_M01_roster.dta", replace
di as result "33_roster R`rr': " _N " members"
