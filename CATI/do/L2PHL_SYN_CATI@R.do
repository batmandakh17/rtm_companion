* L2PHL_SYN CATI ROUND $R: KOBO EXPORT TO MODULE FILES, CHECKS, PRELOAD, SKIP-LOGIC AUDIT AND CALL LOGS
* RTM companion package, synthetic data laid out like the L2PHL phone rounds
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* One do-file for every round, with one bookmarked section per module as in L2PHL. The master runs it for every round
* and Round##/do/L2PHL_SYN_CATI@R##.do for one round ($R set before the call); on its own, set the round in PREAMBLES.
* Every output goes to the round's dated folders (CATI/Round##/<folder>/<date of the export>), and the module files
* are named l2phl_syn_<date>_<module>.dta, so the analysis can pick the latest files of each round.
*   EXCEL TO STATA      the export, sheet by sheet, as it is                      -> $zzz
*   (M0) PASSPORT       one row per household interviewed                        -> $dta/..._M00_passport.dta
*   (M1) ROSTER         members listed so far, with status                       -> $dta/..._M01_roster.dta
*   (M3) SHOCKS         household level and one row per household and shock
*   (M4) EMPLOYMENT     members aged 15+ asked the module
*   (M6) (M7)           finance and health, the rotating modules
*   (M8) FOOD           the eight food insecurity experiences
*   MERGING             the household-level and roster-level data                -> $dta/..._HH_Level_Data.dta,
*                                                                                   ..._Roster_Level_Data.dta
*   CHECKS              consistency checks on the module files                   -> checks.csv, review lists in $fix
*   PRELOAD             the next round's pulldata file                           -> $pii/preload_R(next).csv
*   SKIP-LOGIC AUDIT    routing, required and constraints read from the form     -> $aud/..._form_audit.csv
*   CALL LOGS           the standard dial file from the form and from the call centre, then the cases -> $call
* Identifying fields (names, numbers, addresses) go to $pii, never into the module files.

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear
	set more off
	if ("$wd" == "") glo wd "`c(pwd)'"
	do "$wd/L2PHL_SYN_preambles.do"

	* Set round (the master and Round##/do set $R; set it here when running this file on its own)
	********************
	if ("$R" == "") glo R 01
	setround $R										// $date, $excel_file, $stub and the round's folders
	loc r = real("$R")
	loc nn : di %02.0f `r' + 1

	* Enumerator lookup (program code, call-centre operator code)
	********************
	import delimited "$cati/ado/enumerators.csv", clear stringcols(2 3)
	save "$call/enumerators.dta", replace
}

********************************************************************************
**# EXCEL TO STATA: THE KOBO EXPORT, SHEET BY SHEET
********************************************************************************
{ // EXPORT:
	* The export is the .xlsx KoBo writes with "XML values and headers": one sheet for the form's main level (one row
	* per submission, here one per call attempt) and one sheet per repeat group (rows linked to their submission by
	* _parent_index = the main sheet's _index). If $xls holds several exports, the latest (by file name) is read, and
	* its date names this round's dated folders (rounddate, called by setround).
	qui import excel using "$xls/$excel_file", describe
	loc ns = r(N_worksheet)
	forvalues i = 1/`ns' {
		loc sh`i' = r(worksheet_`i')
	}
	forvalues i = 1/`ns' {
		kobo_import using "$xls/$excel_file", sheet("`sh`i''") form("$form") keepstring(oldcp oldrespo replacement_hhid)
		loc name = cond(`i' == 1, "main", "`sh`i''")
		g int round = `r'
		save "$zzz/`name'.dta", replace
		check_log `r' 3 "rows read from sheet `sh`i''" `=_N' "imported"
	}
	di in red "R$R: `ns' sheets read from $excel_file"
}

********************************************************************************
**# (M0) PASSPORT OF QUESTIONNAIRE
********************************************************************************
{ // PASSPORT:
	* Rules, in order:
	*   1. times: start and end are the device's local time; _submission_time is UTC (+8 hours here)
	*   2. practice submissions, dated before the round's first calling day ($START_#), are dropped
	*   3. a negative duration (device clock) is set to missing
	*   4. the same interview sent twice (same household, start, end and result) keeps its first copy
	*   5. complete = result X15 coded 1 (complete) or 2 (partially complete, no more callback), as in L2PHL
	*   6. a household with two different completes keeps the first (none in the synthetic data; the rule is there)
	use "$zzz/main.dta", clear

	// 1. Submission time & durations
	{
		foreach v in start end {
			g double `v'_t = clock(subinstr(substr(`v', 1, 19), "T", " ", 1), "YMDhms")
				format `v'_t %tcCCYY-NN-DD_HH:MM:SS
		}
		g double sub_t = clock(subinstr(_submission_time, "T", " ", 1), "YMDhms") + msofhours(8)
			format sub_t %tcCCYY-NN-DD_HH:MM:SS
		g double dur_min = (end_t - start_t) / 60000
		g int day = dofc(start_t)
			format day %td
		la var start_t 	"Form opened (local time)"
		la var end_t 	"Form saved (local time)"
		la var sub_t 	"Submitted to the server (local time)"
		la var dur_min 	"Minutes from form opened to form saved"
	}

	// 2. Practice submissions
	g byte f_practice = day < date("${START_`r'}", "YMD")
		qui count if f_practice
		check_log `r' 3 "practice submissions dated before the first calling day" `r(N)' "dropped"

	// 3. Negative durations
	g byte f_negdur = dur_min < 0
		qui count if f_negdur
		check_log `r' 3 "submissions saved before they were opened (device clock)" `r(N)' "duration set to missing"
	replace dur_min = . if f_negdur

	// 4. The same interview sent twice
	sort hhid start end x15 sub_t _id
	by hhid start end x15: g byte f_duplicate = _n > 1 & !f_practice
		qui count if f_duplicate
		check_log `r' 3 "the same submission sent twice" `r(N)' "later copy dropped"

	// 5. Completes
	g byte complete = inlist(x15, 1, 2)
		la var complete "Interview complete (X15 = 1 or 2)"
	g byte f_short = complete & dur_min < 3
		qui count if f_short & !f_practice & !f_duplicate
		check_log `r' 3 "completes recorded in under 3 minutes" `r(N)' "flagged (the call logs apply the 3-minute rule)"
		review_list `r' short_completes if f_short & !f_practice & !f_duplicate
	save "$zzz/submissions_flagged.dta", replace

	// The passport
	drop if f_practice | f_duplicate
	bys hhid (start_t _id): g n_subs = _N
		la var n_subs "Call attempts recorded this round"
	keep if complete

	// 6. Two different completes for one household
	bys hhid (start_t _id): g byte f_second = _n > 1
		qui count if f_second
		check_log `r' 3 "households with a second, different complete" `r(N)' "first kept"
	drop if f_second
	save "$zzz/completes.dta", replace

	// Identifying fields: respondent name, phone numbers, new address
	preserve
		keep hhid round oldrespo oldcp x14 z21
		save "$pii/R${R}_contacts.dta", replace
	restore

	g int intdate = date(z6, "YMD")
		format intdate %td
		la var intdate "Z6. Date of interview"
	keep hhid round int_id sample replacement_hhid hhsize fmid_max round_lastint d3 intdate start_t end_t sub_t dur_min ///
		 n_subs z8 call_status1 z17 z9 z20 z1 z5 x11 x20 x15 f_short
	order hhid round int_id intdate start_t end_t dur_min n_subs
	form_labels using "$form"
		la var hhid 			"Household ID"
		la var round 			"Round"
		la var hhsize 			"Household size at the last interview (preload)"
		la var fmid_max 		"Members listed so far (preload)"
		la var round_lastint 	"Round of the last interview (0 = baseline)"
		la var f_short 			"Complete recorded in under 3 minutes"
	compress
	save "${stub}_M00_passport.dta", replace
	di in red "R$R (M0): " _N " households interviewed"
}

********************************************************************************
**# (M1) ROSTER (OLD AND NEW MEMBERS)
********************************************************************************
{ // ROSTER:
	* Members listed at the last interview come from the repeat old_ (member ID fmid = position in the preload); new
	* members from the repeat newmembers get the next IDs (fmid_max + 1, ...). Corrections of name, age and sex
	* (D5a = 3, 4, 5) replace the preloaded values. Relationship to the head is not asked again: it comes from the
	* roster master, which starts from the baseline and gains each round's new members.
	* Member status: 1 still a member, 2 left this round, 3 left before this round, 4 new this round.
	copy "$pdta/roster_master.dta" "$dta/roster_master.dta", replace		// the previous round's, carried on

	use hhid _index fmid_max using "$zzz/completes.dta", clear
	ren _index _parent_index
	tempfile parents old
	save `parents'

	// ROSTER OLD: members listed at the last interview (rows of practice or duplicate submissions drop out in the merge)
	use "$zzz/old_.dta", clear
	merge m:1 _parent_index using `parents', keep(match) nogen
	bys hhid: g n_rows = _N
	g byte bad = n_rows ~= fmid_max
		qui count if bad
		check_log `r' 3 "M01: households whose old-member rows differ from fmid_max" `r(N)' "stop"

	g byte status = cond(fmidpermanent == 0, 3, cond(d5a_ == 2, 2, 1))
	g age = fmidage
		replace age = d28 if d5a_ == 4					// D28: corrected age
	g sex = fmidsex
		replace sex = d33 if d5a_ == 5					// D33: corrected sex
	g name = fmidname
		replace name = d27 if d5a_ == 3					// D27: corrected name
	ren (d25 d25_oth) (leave_reason leave_reason_oth)
	keep hhid round fmid name sex age status d5a_ leave_reason leave_reason_oth
	save `old'

	// ROSTER NEW: D30 - M13 (new household members)
	use "$zzz/newmembers.dta", clear
	merge m:1 _parent_index using `parents', keep(match) nogen
	if (_N > 0) {
		bys _parent_index (_index): g fmid = fmid_max + _n
		ren (d30 d31 d32 d6 m13_ m13_oth) (name sex age relationship movein movein_oth)
		g byte status = 4
		keep hhid round fmid name sex age relationship movein movein_oth status
		append using `old'
	}
	else {
		use `old', clear
		g relationship = .
		g movein = .
		g movein_oth = ""
	}

	// MERGING: relationship to the head from the roster master; this round's new members join it
	merge m:1 hhid fmid using "$dta/roster_master.dta", keep(master match match_update) keepusing(relationship) update nogen
	preserve
		keep if status == 4
		keep hhid fmid relationship
		append using "$dta/roster_master.dta"
		duplicates drop hhid fmid, force
		sort hhid fmid
		save "$dta/roster_master.dta", replace
	restore

	preserve
		keep hhid round fmid name
		save "$pii/R${R}_names.dta", replace
	restore
	drop name

	g byte present = inlist(status, 1, 4)
	la def status 1 "Still a member" 2 "Left this round" 3 "Left before this round" 4 "New this round"
	la val status status
	form_labels using "$form"
		la val sex gender
		la val relationship relationship
		la val leave_reason leave_reason
		la val movein movein
		la var fmid 		"Member ID"
		la var sex 			"Sex"
		la var age 			"Age (years)"
		la var relationship "Relationship to the household head"
		la var status 		"Member status this round"
		la var present 		"Member of the household this round"
		la var leave_reason "D25. Why the member left"
		la var movein 		"M13. Why the new member moved in"
	order hhid round fmid status present sex age relationship
	sort hhid fmid
	compress
	save "${stub}_M01_roster.dta", replace
	di in red "R$R (M1): " _N " members"
}

********************************************************************************
**# (M3) SHOCKS (HH) AND (M3) SHOCKS (REPEAT SHOCK)
********************************************************************************
{ // SHOCKS:
	use hhid _index fmid_max using "$zzz/completes.dta", clear
	ren _index _parent_index
	tempfile parents
	save `parents'

	// SHOCKS (HH): SH1, SH1b
	use "$zzz/completes.dta", clear
	keep hhid round sh1 sh1b_*
	ren sh1b_ sh1b_codes
	g n_shocks = wordcount(sh1b_codes)
		la var n_shocks "Number of shock types reported"
	form_labels using "$form"
		la var sh1b_codes "SH1b. Shock types (codes, space-separated)"
	compress
	save "${stub}_M03_shock_hh.dta", replace

	// SHOCKS (REPEAT): one row per household and shock, with its coping
	use "$zzz/sh2_.dta", clear
	merge m:1 _parent_index using `parents', keep(match) nogen
	ren (sh1b_ans sh2_) (shock sh2_codes)
	drop sh1b_ansname
	keep hhid round shock sh2_*
	form_labels using "$form"
		la val shock shocks
		la var shock 	 "Shock"
		la var sh2_codes "SH2. Coping (codes, space-separated)"
	bys hhid: g n_rows = _N
	merge m:1 hhid using "${stub}_M03_shock_hh.dta", keep(master match) keepusing(n_shocks) nogen
		qui count if n_rows ~= n_shocks
		check_log `r' 3 "M03: households whose coping rows differ from the shocks reported" `r(N)' "listed"
	drop n_rows n_shocks
	compress
	save "${stub}_M03_shock.dta", replace
}

********************************************************************************
**# (M4) EMPLOYMENT (OLD ROSTER AND NEW ROSTER)
********************************************************************************
{ // EMPLOYMENT:
	* One row per member aged 15+ asked the module: members from the last interview (repeat employ_) and new members
	* (repeat employ_new, renamed without _new).
	use hhid _index fmid_max using "$zzz/completes.dta", clear
	ren _index _parent_index
	tempfile parents oldemp
	save `parents'

	// OLD ROSTER
	use "$zzz/employ_.dta", clear
	merge m:1 _parent_index using `parents', keep(match) nogen
	ren employ_fmid fmid
	keep if fmid_employment < . & employ_left == 0
	g byte prev_work = fmid_employment
	keep hhid round fmid prev_work a24 a27 a1 a26 a3 a3_oth a5 a5_oth a6 a10 a11
	save `oldemp'

	// NEW ROSTER
	use "$zzz/employ_new.dta", clear
	merge m:1 _parent_index using `parents', keep(match) nogen
	if (_N > 0) {
		g fmid = fmid_max + employ_fmid_new
		keep if employ_age_new >= 15
		ren (*_new) (*)
		keep hhid round fmid a1 a26 a3 a3_oth a5 a5_oth a6 a10 a11
		append using `oldemp'
	}
	else use `oldemp', clear

	// MERGING
	g byte employed = a24 == 4 | a1 == 1 | a26 == 1
		la var employed  "Worked last week or has a job or business"
		la var prev_work "Working at the last interview (1 yes, 2 no; empty for new members)"
	merge 1:1 hhid fmid using "${stub}_M01_roster.dta", keep(master match) keepusing(sex age)
		qui count if _merge == 1
		check_log `r' 3 "M04: members not found in the roster" `r(N)' "stop"
	drop _merge
	form_labels using "$form"
		la val sex gender
	order hhid round fmid sex age employed prev_work
	sort hhid fmid
	compress
	save "${stub}_M04_employment.dta", replace
}

********************************************************************************
**# (M6) FINANCE AND (M7) HEALTH: THE ROTATING MODULES
********************************************************************************
{ // ROTATING:
	foreach m in M06_finance M07_health {
		use "$zzz/completes.dta", clear
		loc first = cond("`m'" == "M06_finance", "f17", "h2")
		cap confirm variable `first'
		if _rc ~= 0 {
			di in red "R$R: `m' is not in this round's form"
			continue
		}
		if ("`m'" == "M06_finance") keep hhid round f17 f1 f18 f2 f3 f6 f7 f10
		else keep hhid round h2 h2a h3 h3_oth
		form_labels using "$form"
		compress
		save "${stub}_`m'.dta", replace
	}
}

********************************************************************************
**# (M8) FOOD INSECURITY (HH)
********************************************************************************
{ // FOOD:
	use "$zzz/completes.dta", clear
	keep hhid round f08_?
	egen fies_raw = anycount(f08_?), values(1)
	egen n_answered = rownonmiss(f08_?)
		qui count if n_answered ~= 8
		check_log `r' 3 "M08: households without all eight food insecurity answers" `r(N)' "listed"
	drop n_answered
		la var fies_raw "Food insecurity experiences reported (0-8)"
	form_labels using "$form"
	compress
	save "${stub}_M08_food.dta", replace
	di in red "R$R (M3-M8): module files written to $dta"
}

********************************************************************************
**# MERGING: HOUSEHOLD LEVEL AND ROSTER LEVEL DATA
********************************************************************************
{ // MERGING:
	* As in L2PHL, the round ends with two wide files the analysis appends across rounds: the household-level data
	* (the passport with the household modules side by side) and the roster-level data (the roster with the member
	* modules). The repeat-level shocks file (one row per household and shock) stays on its own.
	use "${stub}_M00_passport.dta", clear
	foreach m in M03_shock_hh M08_food M06_finance M07_health {
		cap confirm file "${stub}_`m'.dta"
		if _rc == 0 merge 1:1 hhid using "${stub}_`m'.dta", assert(match) nogen
	}
	save "${stub}_HH_Level_Data.dta", replace

	use "${stub}_M01_roster.dta", clear
	merge 1:1 hhid fmid using "${stub}_M04_employment.dta", keep(master match) nogen
	save "${stub}_Roster_Level_Data.dta", replace
	di in red "R$R (MERGING): household and roster level files written"
}

********************************************************************************
**# CHECKS: CONSISTENCY OF THE MODULE FILES
********************************************************************************
{ // CHECKS:
	* Nothing is changed here; every check writes its count to checks.csv, where the team (and the dashboard's
	* Quality checks tab) reads what needs a look. Rows that need a person's judgment go to review lists in $fix.

	// M00 passport
	use "${stub}_M00_passport.dta", clear
	qui count if intdate < date("${START_`r'}", "YMD") | intdate > date("${START_`r'}", "YMD") + 27
	check_log `r' 3 "M00: interview dates outside the round's four weeks" `r(N)' "listed"
	qui count if missing(int_id)
	check_log `r' 3 "M00: interviews without an interviewer code" `r(N)' "listed"

	// M01 roster
	use "${stub}_M01_roster.dta", clear
	qui count if present & (age < 0 | age > 120)
	check_log `r' 3 "M01: ages outside 0-120" `r(N)' "listed"
	bys hhid: egen n_present = total(present)
	bys hhid: egen n_left = total(status == 2)
	bys hhid: egen n_new = total(status == 4)
	merge m:1 hhid using "${stub}_M00_passport.dta", keepusing(hhsize) keep(match) nogen
	bys hhid: g byte first = _n == 1
	qui count if first & n_present ~= hhsize - n_left + n_new
	check_log `r' 3 "M01: members present do not equal last size - leavers + joiners" `r(N)' "listed"

	// M03 shocks
	use "${stub}_M03_shock_hh.dta", clear
	qui count if sh1 ~= 1 & n_shocks > 0
	check_log `r' 3 "M03: shock types recorded without a shock (SH1 = no)" `r(N)' "listed"
	qui count if sh1 == 1 & n_shocks == 0
	check_log `r' 3 "M03: a shock (SH1 = yes) without its type" `r(N)' "listed"

	// M04 employment
	use "${stub}_M04_employment.dta", clear
	qui count if !missing(a24) & prev_work ~= 1
	check_log `r' 3 "M04: A24 asked of a member not working at the last interview" `r(N)' "listed"
	qui count if !missing(a27) & prev_work ~= 2
	check_log `r' 3 "M04: A27 asked of a member working at the last interview" `r(N)' "listed"
	qui count if employed & (missing(a5) | missing(a6) | missing(a10) | missing(a11))
	check_log `r' 3 "M04: employed members without industry, class, days or hours" `r(N)' "listed"
	qui count if !employed & !missing(a5)
	check_log `r' 3 "M04: industry recorded for a member not employed" `r(N)' "listed"
	qui count if (a10 > 7 & a10 < .) | (a11 > 168 & a11 < .)
	check_log `r' 3 "M04: days or hours outside the form's limits" `r(N)' "listed"
	qui count if a11 > 16 * a10 & a11 < . & a10 > 0
	check_log `r' 3 "M04: more than 16 hours a working day" `r(N)' "listed for a callback"
	review_list `r' hours_per_day if a11 > 16 * a10 & a11 < . & a10 > 0
	qui count if age < 15
	check_log `r' 3 "M04: members under 15 in the employment module" `r(N)' "listed"
	review_list `r' employment_under15 if age < 15

	// M06 finance and M07 health (when in the round)
	cap confirm file "${stub}_M06_finance.dta"
	if _rc == 0 {
		use "${stub}_M06_finance.dta", clear
		qui count if (!missing(f1) & f17 ~= 1) | (missing(f1) & f17 == 1) | (!missing(f2) & f18 ~= 1) | (missing(f2) & f18 == 1)
		check_log `r' 3 "M06: account use (F1, F2) does not follow account ownership (F17, F18)" `r(N)' "listed"
		qui count if (!missing(f10) & f7 ~= 1) | (missing(f10) & f7 == 1)
		check_log `r' 3 "M06: loan approval (F10) does not follow the loan question (F7)" `r(N)' "listed"
	}
	cap confirm file "${stub}_M07_health.dta"
	if _rc == 0 {
		use "${stub}_M07_health.dta", clear
		qui count if (!missing(h2a) & !inlist(h2, 1, 2, 3)) | (missing(h2a) & inlist(h2, 1, 2, 3))
		check_log `r' 3 "M07: H2A does not follow the need for care (H2)" `r(N)' "listed"
		qui count if (!missing(h3) & h2a ~= 2) | (missing(h3) & h2a == 2)
		check_log `r' 3 "M07: the reason for no care (H3) does not follow H2A" `r(N)' "listed"
	}
	di in red "R$R (CHECKS): done"
}

********************************************************************************
**# PRELOAD FOR THE NEXT ROUND
********************************************************************************
{ // PRELOAD:
	* The file the next round's form reads with pulldata() (members, ages, sex, who still lives there, who worked).
	* It starts from this round's preload and updates every household interviewed this round from the module files;
	* households not reached keep what was known. The panel is the households interviewed in round 1. The file holds
	* names and numbers, so it is written to $pii.
	* Check: when CATI/Round(next)/kobo/preload.csv exists (the file the synthetic data were built with), the two
	* must agree cell by cell; the count of differing cells goes to checks.csv.
	tempfile cur prev panel

	// this round's members, with their names and whether they worked
	use hhid fmid status age sex using "${stub}_M01_roster.dta", clear
	merge 1:1 hhid fmid using "$pii/R${R}_names.dta", keepusing(name) nogen assert(match)
	merge 1:1 hhid fmid using "${stub}_M04_employment.dta", keepusing(employed) keep(master match) nogen
	g byte perm_n = inlist(status, 1, 4)
	g byte emp_n = cond(employed == 1, 1, cond(employed == 0, 2, .))
	ren (age sex name) (age_n sex_n name_n)
	keep hhid fmid age_n sex_n name_n perm_n emp_n
	save `cur'

	// this round's preload, one row per member, updated
	import delimited "$ppii/preload_R${R}.csv", clear stringcols(_all)
	ren name respname
	qui ds respname cp name*, not
	destring `r(varlist)', replace
	reshape long name age sex perm emp, i(hhid) j(fmid)
	drop if name == "" & missing(age)
	merge 1:1 hhid fmid using `cur'
	g byte interviewed = _merge >= 2
	bys hhid: egen byte hh_int = max(interviewed)
	foreach v in age sex perm {
		replace `v' = `v'_n if interviewed
	}
	replace emp = emp_n if interviewed & emp_n < .
	replace name = name_n if interviewed
	replace emp = . if perm == 0
	foreach v in respname cp psu stratum round_lastint {
		bys hhid (fmid): replace `v' = `v'[1]
	}
	replace round_lastint = `r' if hh_int
	bys hhid: egen n_perm = total(perm)
	bys hhid: egen n_max = max(fmid)
	replace hhsize = n_perm
	replace fmid_max = n_max
	replace sample = 1
	keep hhid fmid hhsize fmid_max sample round_lastint respname cp psu stratum name age sex perm emp
	bys hhid (fmid): replace hhsize = hhsize[1]
	reshape wide name age sex perm emp, i(hhid) j(fmid)
	ren respname name

	// the panel: households interviewed in round 1 (the latest files of round 1)
	rounddate 1
	loc d1 `r(date)'
	preserve
		use hhid using "$cati/Round01/dta/`d1'/${dta_file}_`d1'_M00_passport.dta", clear
		save `panel'
	restore
	merge 1:1 hhid using `panel', keep(match) nogen
	preload_order
	export delimited using "$pii/preload_R`nn'.csv", replace nolabel

	// the check against the preload the synthetic data were built with
	cap confirm file "$cati/Round`nn'/kobo/preload.csv"
	if _rc == 0 {
		import delimited "$pii/preload_R`nn'.csv", clear stringcols(_all)
		save `prev'
		import delimited "$cati/Round`nn'/kobo/preload.csv", clear stringcols(_all)
		qui ds hhid, not
		loc vars `r(varlist)'
		ren (`vars') (=_x)
		merge 1:1 hhid using `prev'
		qui count if _merge ~= 3
		loc bad = r(N)
		foreach v of local vars {
			qui count if `v' ~= `v'_x & _merge == 3
			loc bad = `bad' + r(N)
		}
		check_log `r' 3 "preload for round `=`r' + 1': cells that differ from the file the synthetic data used" `bad' "stop"
	}
	di in red "R$R (PRELOAD): preload for round `=`r' + 1' written"
}

********************************************************************************
**# SKIP-LOGIC AUDIT: ROUTING, REQUIRED AND CONSTRAINTS READ FROM THE FORM
********************************************************************************
{ // AUDIT:
	* For every question the audit takes its routing (the relevant column, together with the conditions of the groups
	* and repeats it sits in), whether it is required, and its constraint, and counts:
	*   base              rows where the routing says the question should have been asked
	*   answered          rows with an answer
	*   routing_broken    an answer where the routing says the question was not asked
	*   required_missing  a required question left empty where it should have been asked
	*   out_of_range      an answer that fails the question's constraint
	* Call-record questions (the local callrecord) are audited on every kept call attempt; the other questions on
	* completed interviews only, because a partial interview stops early by design. A rule the translator cannot read
	* (xls2stata) is reported as "not translated" and the question is skipped. The flags are also summed by enumerator
	* for the monitoring view, and every flagged row is listed by household ID (with the submission, the repeat row,
	* the question and the answer) in a review list for the team.
	loc callrecord int_id hhid d3 z6 z7 z8 call_status1 z17 z9 z18 z18_oth x15 x16
	tempfile rules parents res enum list pp
	tempname ph pe pl

	// 1. The questions and their effective rules
	{
		import excel using "$form", sheet("survey") firstrow allstring clear
		ren label* label
		g vtype = word(type, 1)
		g vname = lower(name)
		g byte req = lower(required) == "yes"
		foreach v in relevant constraint {
			g `v'_st  = subinstr(subinstr(lower(`v'), char(36) + "{", "", .), "}", "", .)
			g `v'_tk  = subinstr(subinstr(lower(`v'), char(36) + "{", " @", .), "}", " ", .)
			g `v'_txt = subinstr(subinstr(`v', char(36) + "{", "[", .), "}", "]", .)
		}
		replace label = subinstr(subinstr(label, char(36) + "{", "[", .), "}", "]", .)
		replace label = subinstr(label, `"""', "'", .)
		replace label = usubstr(label, 1, 100)
		g str20 sheet = ""
		g str244 eff = ""
		g str244 eff_tk = ""
		g str244 rule = ""
		loc depth 0
		loc sh0 main
		forvalues i = 1/`=_N' {
			loc t = vtype[`i']
			if inlist("`t'", "begin_group", "begin_repeat") {
				loc ++depth
				loc rel`depth' = relevant_st[`i']
				loc tk`depth'  = relevant_tk[`i']
				loc txt`depth' = relevant_txt[`i']
				loc prev = `depth' - 1
				loc sh`depth' = cond("`t'" == "begin_repeat", vname[`i'], "`sh`prev''")
				continue
			}
			if inlist("`t'", "end_group", "end_repeat") {
				loc --depth
				continue
			}
			loc e 1
			loc k
			loc x
			forvalues d = 1/`depth' {
				if `"`rel`d''"' ~= "" {
					loc e `"`e' and (`rel`d'')"'
					loc k `"`k' `tk`d''"'
					loc x `"`x'; `txt`d''"'
				}
			}
			if relevant_st[`i'] ~= "" {
				loc e `"`e' and (`=relevant_st[`i']')"'
				loc k `"`k' `=relevant_tk[`i']'"'
				loc x `"`x'; `=relevant_txt[`i']'"'
			}
			qui replace sheet = "`sh`depth''" in `i'
			qui replace eff = `"`e'"' in `i'
			qui replace eff_tk = `"`k'"' in `i'
			qui replace rule = substr(`"`x'"', 3, .) in `i'
		}
		keep if inlist(vtype, "select_one", "select_multiple", "integer", "decimal", "text", "date", "time", "select_one_from_file")
		g byte callrec = 0
		foreach v of local callrecord {
			qui replace callrec = 1 if vname == "`v'"
		}
		keep vname vtype label req callrec sheet eff eff_tk rule constraint_st constraint_tk constraint_txt
		save `rules'
	}

	// 2. The submissions the audit runs on
	use "$zzz/submissions_flagged.dta", clear
	drop if f_practice | f_duplicate
	save `parents'

	// 3. Sheet by sheet, question by question
	{
		postfile `ph' int round str20 sheet str32 variable str100 label str244 rule str100 constraint byte required ///
			long base answered routing_broken required_missing out_of_range str28 status using `res', replace
		postfile `pe' int round long int_id str32 variable long flags using `enum', replace
		postfile `pl' int round double hhid long submission long row long int_id str20 sheet str32 variable ///
			str20 flag str244 value using `list', replace
		use `rules', clear
		levelsof sheet, local(sheets)
		foreach sh of local sheets {
			use `rules', clear
			keep if sheet == "`sh'"
			loc need
			loc nq = _N
			forvalues i = 1/`nq' {
				loc tk = eff_tk[`i'] + " " + constraint_tk[`i']
				foreach w of local tk {
					if (substr("`w'", 1, 1) == "@") loc need `need' `=substr("`w'", 2, .)'
				}
				loc v`i'    = vname[`i']
				loc lab`i'  = label[`i']
				loc eff`i'  = eff[`i']
				loc con`i'  = constraint_st[`i']
				loc ctx`i'  = constraint_txt[`i']
				loc rule`i' = rule[`i']
				loc req`i'  = req[`i']
				loc cr`i'   = callrec[`i']
			}
			loc need : list uniq need
			if ("`sh'" == "main") use `parents', clear
			else {
				use "$zzz/`sh'.dta", clear
				qui ds
				loc have `r(varlist)'
				loc get : list need - have
				preserve
					use `parents', clear
					qui ds
					loc pv `r(varlist)'
					loc get : list get & pv
					loc keepv _parent_index complete int_id hhid _id
					loc get : list get - keepv
					ren _index _parent_index
					keep `keepv' `get'
					save `pp', replace
				restore
				merge m:1 _parent_index using `pp', keep(match) nogen
			}
			if ("`sh'" == "main") g long __row = .
			else g long __row = _index
			forvalues i = 1/`nq' {
				loc v `v`i''
				cap confirm variable `v'
				if _rc ~= 0 {
					post `ph' (`r') ("`sh'") ("`v'") (`"`lab`i''"') (`"`rule`i''"') (`"`ctx`i''"') (`req`i'') (.) (.) (.) (.) (.) ("not in export")
					continue
				}
				cap drop __rel __ans __ok __base __run __flag __f1 __f2 __f3 __val
				loc status ok
				xls2stata, expr(`"`eff`i''"') self(`v')
				if (!r(ok)) loc status "not translated"
				else {
					cap g byte __rel = (`r(expr)')
					if _rc ~= 0 loc status "not translated"
				}
				if ("`status'" ~= "ok") {
					post `ph' (`r') ("`sh'") ("`v'") (`"`lab`i''"') (`"`rule`i''"') (`"`ctx`i''"') (`req`i'') (.) (.) (.) (.) (.) ("`status'")
					continue
				}
				qui replace __rel = 0 if missing(__rel)
				g byte __run = `cr`i'' | complete
				g byte __base = __rel & __run
				cap confirm string variable `v'
				if _rc ~= 0 g byte __ans = !missing(`v')
				else g byte __ans = `v' ~= ""
				g byte __ok = 1
				loc cstat ok
				if `"`con`i''"' ~= "" {
					cap confirm numeric variable `v'
					if _rc ~= 0 loc cstat "constraint not translated"
					else {
						xls2stata, expr(`"`con`i''"') self(`v')
						if r(ok) {
							cap replace __ok = (`r(expr)') if __ans
							if _rc ~= 0 loc cstat "constraint not translated"
						}
						else loc cstat "constraint not translated"
					}
				}
				qui count if __base
				loc base = r(N)
				qui count if __run & __ans
				loc ans = r(N)
				qui count if __run & __ans & !__base
				loc rb = r(N)
				qui count if __base & !__ans & `req`i''
				loc rm = r(N)
				qui count if __run & __ans & !__ok
				loc oor = cond("`cstat'" == "ok", r(N), .)
				post `ph' (`r') ("`sh'") ("`v'") (`"`lab`i''"') (`"`rule`i''"') (`"`ctx`i''"') (`req`i'') (`base') (`ans') (`rb') (`rm') (`oor') ("`cstat'")

				g byte __f1 = __run & __ans & !__base
				g byte __f2 = __base & !__ans & `req`i''
				g byte __f3 = __run & __ans & !__ok
				g byte __flag = __f1 | __f2 | __f3
				cap confirm string variable `v'
				if _rc ~= 0 g str244 __val = cond(__ans, string(`v', "%12.0g"), "")
				else g str244 __val = `v'
				qui count if __flag
				if (r(N) > 0) {
					preserve
						keep if __flag
						forvalues j = 1/`=_N' {
							if __f1[`j'] post `pl' (`r') (hhid[`j']) (_id[`j']) (__row[`j']) (int_id[`j']) ("`sh'") ("`v'") ("routing_broken") (__val[`j'])
							if __f2[`j'] post `pl' (`r') (hhid[`j']) (_id[`j']) (__row[`j']) (int_id[`j']) ("`sh'") ("`v'") ("required_missing") (__val[`j'])
							if __f3[`j'] post `pl' (`r') (hhid[`j']) (_id[`j']) (__row[`j']) (int_id[`j']) ("`sh'") ("`v'") ("out_of_range") (__val[`j'])
						}
						collapse (count) flags = __flag, by(int_id)
						forvalues j = 1/`=_N' {
							post `pe' (`r') (int_id[`j']) ("`v'") (flags[`j'])
						}
					restore
				}
			}
		}
		postclose `ph'
		postclose `pe'
		postclose `pl'
	}

	// 4. By question, by enumerator, by household
	use `res', clear
	qui su routing_broken
	check_log `r' 3 "skip-logic audit: answers recorded where the routing says the question was not asked" `r(sum)' "listed by question and by household"
	qui su required_missing
	check_log `r' 3 "skip-logic audit: required answers missing where the question was asked" `r(sum)' "listed by question and by household"
	qui su out_of_range
	check_log `r' 3 "skip-logic audit: answers outside the form's constraints" `r(sum)' "listed by question and by household"
	qui count if status == "not translated"
	check_log `r' 3 "skip-logic audit: questions whose routing rule the audit could not read" `r(N)' "listed"
	export delimited using "$aud/${dta_file}_${date}_form_audit.csv", replace

	use `enum', clear
	collapse (sum) flags, by(int_id)
	merge 1:1 int_id using "$call/enumerators.dta", keep(match using) nogen keepusing(enumerator)
	replace flags = 0 if missing(flags)
	g int round = `r'
	order round enumerator int_id flags
	export delimited using "$aud/${dta_file}_${date}_form_audit_enum.csv", replace

	// the flagged rows by household: hhid, the submission (_id in the export), the row in the repeat sheet (row, empty
	// for the main sheet), the enumerator, the question, the flag and the answer as recorded. For the team only.
	use `list', clear
	sort hhid submission sheet row variable flag
	review_list `r' form_flags
	di in red "R$R (AUDIT): done"
}

********************************************************************************
**# CALL LOGS
********************************************************************************
{ // CALL LOGS:
	* The standard dial file (docs/call_log_standard.md): one row per dial, enumerator in the program's own code
	* (E01...), local times, the outcome in the standard codes (here the L2PHL X15 codes) and the dial number seq
	* counted from the times. Two sources: the form's own call records, as in L2PHL, and a call-centre system's log.
	* Then the cases, with the handbook's Chapter 3 rules.
	loc cstub "$call/${dta_file}_${date}"					// prefix of this round's call files

	* CALL LOG FROM KOBO (PASSPORT + CLOSING)
	********************************************************************************
	{
		* In L2PHL every call attempt is a submission of the form (Z8 attempt, call_status1 spoke with someone, Z17
		* correct respondent, Z9 consent, X15 result), so the form is the call log. Practice and duplicate submissions
		* are left out with the passport's flags. Z8, typed by the enumerator, stops at 3; seq is counted by time.
		* Note: the form's end is when the form was saved, so dur_min runs a little longer than the call itself.
		use "$zzz/submissions_flagged.dta", clear
		drop if f_practice | f_duplicate
		merge m:1 int_id using "$call/enumerators.dta", keep(master match) keepusing(enumerator)
			qui count if _merge == 1
			check_log `r' 4 "dials whose interviewer code is not in the lookup" `r(N)' "listed"
		drop _merge

		g str12 program = "$dta_file"
		g double dial_start = start_t
		g double dial_end = end_t if !f_negdur
			format dial_start dial_end %tcCCYY-NN-DD_HH:MM:SS
		g byte outcome = x15
		g byte contact = call_status1 == 1
			qui count if contact ~= !inlist(outcome, 6, 7, 8)
			check_log `r' 4 "dials where 'spoke with someone' disagrees with the result code" `r(N)' "listed"
		g str10 source = "kobo"
		g double dial_id = _id
		bys hhid (dial_start dial_id): g byte seq = _n
			qui count if z8 ~= min(seq, 3)
			check_log `r' 4 "dials whose typed attempt number (Z8) differs from the count by time" `r(N)' "seq used"

		call_layout
		save "`cstub'_dials_kobo.dta", replace
		di in red "R$R (CALL LOGS): " _N " dials from the form"
	}

	* CALL LOG FROM THE CALL-CENTRE SYSTEM
	********************************************************************************
	{
		* Programs that dial through a call-centre system get its log as a semicolon-separated file, one row per dial,
		* with the operator's code in the system, the household, the number dialled, start and end times and a status
		* code. Operator codes are typed differently across files (CATI07, CATI-07, CATI_07), so they are normalized
		* and matched to the program's enumerator codes; status codes are mapped onto the standard outcomes. The number
		* dialled is identifying and is not kept.
		* Check: the dials from this log and from the form should agree dial by dial on household, start and outcome;
		* their ends differ by the time the enumerator took to save the form.
		import delimited "$xls/callcenter/calllog_R${R}.csv", delimiter(";") clear stringcols(_all)
		destring id hh_id round, replace
		ren (hh_id id) (hhid dial_id)
		drop dialing_phone

		// operators: upper case, no punctuation, then the lookup
		g str20 callcenter_operator = ustrupper(ustrregexra(operator_id, "[^A-Za-z0-9]", ""))
			qui count if callcenter_operator ~= operator_id
			check_log `r' 4 "call-centre rows whose operator code needed normalizing" `r(N)' "normalized"
		merge m:1 callcenter_operator using "$call/enumerators.dta", keep(master match) keepusing(enumerator)
			qui count if _merge == 1
			check_log `r' 4 "call-centre rows whose operator is not in the lookup" `r(N)' "listed"
		drop _merge

		// status codes onto the standard outcomes
		g byte outcome = .
		loc map SCS 1 PRC 2 PRS 3 CBK 4 RFS 5 NOA 6 NEX 7 OFF 8 DKH 9 REF 10
		while "`map'" ~= "" {
			gettoken code map : map
			gettoken o map : map
			replace outcome = `o' if status == "`code'"
		}
			qui count if missing(outcome)
			check_log `r' 4 "call-centre rows with a status code not in the crosswalk" `r(N)' "listed"

		g str12 program = "$dta_file"
		g double dial_start = clock(start_time, "YMDhms")
		g double dial_end = clock(end_time, "YMDhms")
		g byte contact = !inlist(outcome, 6, 7, 8)
		g str10 source = "callcentre"
		bys hhid (dial_start dial_id): g byte seq = _n
		call_layout
		save "`cstub'_dials_callcentre.dta", replace

		// agreement with the form's records
		ren (enumerator dial_start dial_end outcome) (enumerator_cc start_cc end_cc outcome_cc)
		keep hhid seq enumerator_cc start_cc end_cc outcome_cc
		merge 1:1 hhid seq using "`cstub'_dials_kobo.dta", keepusing(enumerator dial_start dial_end outcome)
		qui count if _merge ~= 3
		check_log `r' 4 "dials in only one of the two sources (call centre, form)" `r(N)' "listed"
		qui count if _merge == 3 & (enumerator ~= enumerator_cc | abs(dial_start - start_cc) > 1000 | outcome ~= outcome_cc)
		check_log `r' 4 "dials where the two sources disagree on enumerator, start or outcome" `r(N)' "listed"
		qui count if _merge == 3 & (missing(dial_end) | dial_end < end_cc | (dial_end - end_cc) > msofminutes(3))
		check_log `r' 4 "dials whose form was saved before the call ended, or over 3 minutes after" `r(N)' "listed"
	}

	* CASES (ONE HOUSEHOLD IN ONE ROUND)
	********************************************************************************
	{
		* The handbook's rules for its call-log analyses (Chapter 3):
		*   complete = the first dial coded complete that lasted at least 3 minutes; if there is none, the first dial
		*              coded complete of any length
		*   dials after the completing dial are dropped
		*   dials dated more than 90 days from the round's median dial date are dropped (device clock errors)
		* The source is the call-centre log when there is one ($CALLSOURCE = callcentre), the form otherwise;
		* durations from the call-centre log measure the call itself.
		* Check: households complete in the calls should be the households in the passport (M00).
		if ("$CALLSOURCE" == "") glo CALLSOURCE callcentre
		cap confirm file "`cstub'_dials_${CALLSOURCE}.dta"
		loc src = cond(_rc, "kobo", "$CALLSOURCE")

		use "`cstub'_dials_`src'.dta", clear
		g int date = dofc(dial_start)
			format date %td
		qui su date, detail
		loc med = r(p50)
			qui count if abs(date - `med') > 90
			check_log `r' 4 "dials more than 90 days from the round's median date" `r(N)' "dropped"
		drop if abs(date - `med') > 90

		bys hhid: egen k_long = min(cond(complete & dur_min >= 3 & dur_min < ., seq, .))
		bys hhid: egen k_any = min(cond(complete, seq, .))
		g k_complete = cond(k_long < ., k_long, k_any)
			qui count if seq == k_any & k_long == . & k_any < .
			check_log `r' 4 "cases whose only complete lasted under 3 minutes" `r(N)' "kept as complete"
		drop if seq > k_complete
		save "`cstub'_dials.dta", replace

		egen byte tag_day = tag(hhid date)
		g byte is_k = seq == k_complete
		g int day_complete = date if is_k
		g double min_complete = dur_min if is_k
		collapse (count) n_dials = seq (sum) n_days = tag_day contacts = contact (min) first_date = date ///
				 (max) day_complete min_complete k_complete (firstnm) enumerator, by(program round hhid)
		g byte completed = k_complete < .
			format first_date day_complete %td
			la var n_dials 		"Dials this round (up to the completing dial)"
			la var n_days 		"Days with a dial"
			la var contacts 	"Dials where someone answered"
			la var first_date 	"Date of the first dial"
			la var day_complete "Date of the completing dial"
			la var min_complete "Length of the completing dial (minutes)"
			la var k_complete 	"Dial number of the completing dial"
			la var completed 	"Household interviewed this round"
		save "`cstub'_cases.dta", replace

		merge 1:1 hhid using "${stub}_M00_passport.dta", keepusing(hhid)
		qui count if (completed & _merge == 1) | (!completed & _merge == 3) | _merge == 2
		check_log `r' 4 "households complete in the calls but not in the passport, or the reverse" `r(N)' "listed"
		review_list `r' calls_vs_passport if (completed & _merge == 1) | (!completed & _merge == 3) | _merge == 2
		di in red "R$R (CASES): `=_N' cases from the `src' records"
	}
}
