* L2PHL_SYN CAPI ROUND 00: PHONE SUBSAMPLE AND ROUND-1 PRELOAD (dta2smp)
* RTM companion package, synthetic data laid out like the L2PHL phone rounds
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* The rule is L2PHL's: in each PSU, baseline households with a phone are ranked by the random key u drawn at
* baseline; the first 6 (urban PSUs) or 7 (rural PSUs) are the main sample, the others are replacements in rank
* order, used in round 1 when a main household of the same PSU refuses, has a dead number or cannot be reached.
* Phone-sample weight = baseline weight x (households with a phone in the PSU / main households in the PSU); the
* round weights (4_L2PHL_SYN_CATI_wgt@R.do) then adjust for households without a phone and for nonresponse.
* In:  $smpl/baseline_weights.dta, psu_selected.dta; CAPI/raw/baseline_*.csv; CAPI/ado/frame_psu.csv
* Out: $smpl/phone_sample.dta, sample_summary.csv (by stratum, for the dashboard), roster_master.dta (every baseline
*      member's relationship to the head, which each round carries on); CAPI/pii/<date>/preload_R01.csv (what the
*      round-1 form reads; names and numbers)

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear
	if ("$wd" == "") glo wd "`c(pwd)'"
	do "$wd/L2PHL_SYN_preambles.do"
	setround 0

	* Design parameters
	********************
	loc main_urban 6
	loc main_rural 7
}

********************************************************************************
**# PHONE SUBSAMPLE: MAIN SAMPLE AND REPLACEMENTS
********************************************************************************
{ // SAMPLE:
	use "$smpl/baseline_weights.dta", clear
	keep if has_phone == 1

	sort psu u hhid
	by psu: g rank_psu = _n
	g byte sample = 1 + (rank_psu > cond(locale == 1, `main_urban', `main_rural'))
	g rank = cond(sample == 1, 0, rank_psu - cond(locale == 1, `main_urban', `main_rural'))
	bys psu: g n_phone = _N
	bys psu: egen n_main = total(sample == 1)
	g double w_ph = w_bl * n_phone / n_main

	la def sample 1 "Main" 2 "Replacement"
	la val sample sample
		la var rank "Replacement order within the PSU (0 = main)"
		la var w_ph "Phone-sample weight"
	keep hhid psu region locale stratum hhsize sample rank w_bl w_ph
	sort hhid
	save "$smpl/phone_sample.dta", replace
	tab sample
}

********************************************************************************
**# SAMPLE SUMMARY: THE SAMPLE AT EACH STAGE, BY STRATUM
********************************************************************************
{ // SUMMARY:
	tempfile ph ps bl
	g byte main = sample == 1
	g byte repl = sample == 2
	collapse (sum) main repl, by(stratum) fast
	save `ph'

	use "$smpl/psu_selected.dta", clear
	contract stratum, freq(psus)
	save `ps'

	use "$smpl/baseline_weights.dta", clear
	collapse (count) baseline = hhid (sum) phone = has_phone (mean) w_bl, by(stratum region locale) fast
	merge 1:1 stratum using `ph', nogen assert(match)
	merge 1:1 stratum using `ps', nogen assert(match)
	save `bl'

	import delimited "$capi/ado/frame_psu.csv", clear
	collapse (count) frame_psus = psu (sum) census_households = hh_census, by(stratum) fast
	merge 1:1 stratum using `bl', nogen assert(match)
	order stratum region locale frame_psus census_households psus baseline phone main repl w_bl
	export delimited using "$smpl/sample_summary.csv", replace nolabel
}

********************************************************************************
**# ROUND-1 PRELOAD (THE FORM'S PULLDATA FILE)
********************************************************************************
{ // PRELOAD:
	// one row per household, members side by side: name#, age#, sex#, perm# (1 = member) and emp# (1 worked, 2 did
	// not, empty under 15), from the baseline
	import delimited "$capi/raw/baseline_members.csv", clear stringcols(3)
	ren (worked_last_week) (emp)
	g perm = 1
	keep hhid fmid name age sex perm emp
	reshape wide name age sex perm emp, i(hhid) j(fmid)
	tempfile wide
	save `wide'

	import delimited "$capi/raw/baseline_households.csv", clear stringcols(9 11)
	keep hhid hhsize name cp psu stratum
	merge 1:1 hhid using "$smpl/phone_sample.dta", keep(match) nogen keepusing(sample)
	merge 1:1 hhid using `wide', keep(match) nogen
	g fmid_max = hhsize
	g round_lastint = 0
	preload_order
	export delimited using "$pii/preload_R01.csv", replace nolabel
	di in red "dta2smp: preload_R01.csv written for " _N " households"
}

********************************************************************************
**# ROSTER MASTER
********************************************************************************
{ // ROSTER MASTER:
	// relationship to the head is asked once, at baseline; every round reads the previous round's roster master and
	// adds its new members, so the module files carry it without asking again
	import delimited "$capi/raw/baseline_members.csv", clear
	keep hhid fmid relationship
	sort hhid fmid
	save "$smpl/roster_master.dta", replace
}
