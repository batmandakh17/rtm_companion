* L2PHL_SYN: ANALYSIS ACROSS ROUNDS (hf_l2phl_syn_analysis)
* RTM companion package, synthetic data laid out like the L2PHL phone rounds
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* The work across rounds, in CATI/Analysis as L2PHL does it:
*   POPULATE            HF/R00 and HF/R## get the latest files of the baseline and of every round  -> $hf/R##
*   APPEND              every module file appended over rounds, with the round weights            -> $hf/l2phl_syn_<module>.dta
*   FINALIZE            the household and individual files, with dates                           -> $hf, $share
*   FORM CHANGES        what changed in the form from one round to the next                      -> $afix/form_changes.csv
*   HARMONIZE           variables made comparable across rounds                                  -> $hf, $share
*   CALL INDICATORS     fieldwork indicators from the call records                                -> $acall/calls_*.csv
*   ENUMERATOR MONITOR  the monitoring view of handbook 3.2                                       -> $acall/enumerator_monitor.csv
*   WEIGHTED INDICATORS survey results with confidence intervals, module explorer                -> $tab
*   DASHBOARD           one data file next to a fixed page                                       -> $tab/index.html
* (no slash-star sequences in comments: Stata would read them as a block comment)

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear
	set more off
	if ("$wd" == "") glo wd "`c(pwd)'"
	do "$wd/L2PHL_SYN_preambles.do"

	* The rounds and the dates of their latest exports, as L2PHL's $RDATES (to analyse other exports, set the dates here)
	********************
	glo RDATES
	foreach r of global ROUNDS {
		rounddate `r'
		glo RDATES "$RDATES `r(date)'"
	}
	glo RDATES = strtrim("$RDATES")
	loc k 0
	foreach r of global ROUNDS {
		loc ++k
		loc rr : di %02.0f `r'
		loc d`r'    : word `k' of $RDATES
		loc hf`r'   "$hf/R`rr'"
		loc stub`r' "$hf/R`rr'/${dta_file}_`d`r''"			// prefix of round `r''s files once in HF
	}
	loc rlast : word `k' of $ROUNDS
	loc rrlast : di %02.0f `rlast'
	di in red "ANALYSIS: rounds $ROUNDS, exports of $RDATES"
}

********************************************************************************
**# POPULATE: THE LATEST FILES OF EVERY ROUND INTO HF
********************************************************************************
{ // POPULATE:
	* As in L2PHL, HF/R## is emptied and refilled with the latest files of each round, so that the analysis always
	* reads one dated set per round: the module files, the household and roster level data, the roster master, the
	* weights, the call files and the skip-logic audit. HF/R00 gets the baseline's sample files.
	cap mkdir "$hf/R00"
	loc old : dir "$hf/R00" files "*.*"
	foreach f of local old {
		erase "$hf/R00/`f'"
	}
	foreach f in psu_selected.dta census_totals.dta baseline_weights.dta phone_sample.dta roster_master.dta sample_summary.csv {
		copy "$smpl/`f'" "$hf/R00/`f'", replace
	}
	foreach r of global ROUNDS {
		loc rr : di %02.0f `r'
		cap mkdir "`hf`r''"
		loc old : dir "`hf`r''" files "*.*"
		foreach f of local old {
			erase "`hf`r''/`f'"
		}
		loc n 0
		foreach dir in dta wgt call aud {
			loc files : dir "$cati/Round`rr'/`dir'/`d`r''" files "*.*"
			foreach f of local files {
				copy "$cati/Round`rr'/`dir'/`d`r''/`f'" "`hf`r''/`f'", replace
				loc ++n
			}
		}
		di in red "POPULATE: R`rr' <- `n' files of `d`r''"
	}
}

********************************************************************************
**# APPEND: EVERY MODULE OVER ROUNDS, WITH THE ROUND WEIGHTS
********************************************************************************
{ // APPEND:
	* The round weights first (one file of household weights, one of person weights, all rounds), then every module
	* file appended over rounds and merged with its weights: household files get stratum, hhw, popw, ave_hhw and
	* w_round (= hhw), person files indw. A rotating module is absent in some rounds; the rounds it was in are kept in
	* $MOD_<module> for HARMONIZE. Value labels come from the first round appended; HARMONIZE refreshes them.
	foreach w in hhw indw {
		clear
		foreach r of global ROUNDS {
			append using "`stub`r''_`w'.dta"
		}
		sort round hhid
		save "$hf/${dta_file}_cati_`w'.dta", replace
	}

	foreach m in M00_passport M03_shock_hh M03_shock M06_finance M07_health M08_food HH_Level_Data {
		clear
		glo MOD_`m'
		foreach r of global ROUNDS {
			cap confirm file "`stub`r''_`m'.dta"
			if _rc ~= 0 continue
			append using "`stub`r''_`m'.dta"
			glo MOD_`m' "${MOD_`m'} `r'"
		}
		if (_N == 0) continue
		merge m:1 round hhid using "$hf/${dta_file}_cati_hhw.dta", keepusing(stratum hhw popw ave_hhw w_round)
			qui count if _merge == 1
			check_log all 6 "`m': households without a round weight" `r(N)' "stop"
		keep if _merge == 3
		drop _merge
		sort round hhid
		save "$hf/${dta_file}_`m'.dta", replace
	}
	foreach m in M01_roster M04_employment Roster_Level_Data {
		clear
		foreach r of global ROUNDS {
			append using "`stub`r''_`m'.dta"
		}
		merge 1:1 round hhid fmid using "$hf/${dta_file}_cati_indw.dta", keep(master match) keepusing(indw)
		if ("`m'" == "M04_employment") qui count if _merge == 1
		else qui count if _merge == 1 & present
			check_log all 6 "`m': members present without a person weight" `r(N)' "stop"
		drop _merge
		sort round hhid fmid
		save "$hf/${dta_file}_`m'.dta", replace
	}
	di in red "APPEND: module files appended over rounds $ROUNDS"
}

********************************************************************************
**# FINALIZE: THE HOUSEHOLD AND INDIVIDUAL FILES
********************************************************************************
{ // FINALIZE:
	* The two files the team shares, as L2PHL's l2phl_cati_household.dta and l2phl_cati_individual.dta: the appended
	* household-level data with the round weights and the interview date (year, quarter, month), and the appended
	* roster-level data with the person weights and the same dates. Copies go to 2share.
	use "$hf/${dta_file}_HH_Level_Data.dta", clear
	isid round hhid
	g int year = year(intdate)
	g byte quarter = quarter(intdate)
	g int qofd = qofd(intdate)
		format qofd %tq
	g byte month = month(intdate)
	g int mofd = mofd(intdate)
		format mofd %tm
		la var year 	"Year of the interview"
		la var quarter 	"Quarter of the interview"
		la var qofd 	"Quarter of the interview (quarterly date)"
		la var month 	"Month of the interview"
		la var mofd 	"Month of the interview (monthly date)"
	order hhid round intdate year quarter qofd month mofd stratum hhw popw ave_hhw w_round
	compress
	save "$hf/${dta_file}_cati_household.dta", replace

	use "$hf/${dta_file}_Roster_Level_Data.dta", clear
	isid round hhid fmid
	merge m:1 round hhid using "$hf/${dta_file}_cati_household.dta", assert(match) nogen ///
		keepusing(intdate year quarter qofd month mofd stratum hhw popw)
	order hhid round fmid intdate year quarter qofd month mofd stratum indw hhw popw
	compress
	save "$hf/${dta_file}_cati_individual.dta", replace

	// the intermediate files, as in L2PHL: the level files are now the household and individual files
	foreach f in HH_Level_Data Roster_Level_Data cati_hhw cati_indw {
		erase "$hf/${dta_file}_`f'.dta"
	}
	di in red "FINALIZE: household and individual files written"
}

********************************************************************************
**# FORM CHANGES BETWEEN ROUNDS
********************************************************************************
{ // FORM CHANGES:
	* Questions added or dropped, a question's type or wording changed, a choice list with a different number of
	* options. A question that leaves and comes back is a rotating module. Read from the forms themselves, so the
	* list is complete whatever the round notes say.
	tempfile all cur
	tempname ph
	postfile `ph' int from_round to_round str12 change str32 variable str100 label using `cur', replace
	clear
	save `all', emptyok
	foreach r of global ROUNDS {
		loc rr : di %02.0f `r'
		import excel using "$kobo/L2PHL_SYN_CATI_R`rr'.xlsx", sheet("choices") firstrow allstring clear
		ren list_name list
		contract list, freq(n_options)
		tempfile ch
		save `ch'
		import excel using "$kobo/L2PHL_SYN_CATI_R`rr'.xlsx", sheet("survey") firstrow allstring clear
		ren label* label
		g vtype = word(type, 1)
		keep if inlist(vtype, "select_one", "select_multiple", "integer", "decimal", "text", "date", "time", "select_one_from_file")
		g vname = lower(name)
		g list = word(type, 2)
		merge m:1 list using `ch', keep(master match) nogen
		replace label = usubstr(subinstr(subinstr(label, char(36) + "{", "[", .), "}", "]", .), 1, 100)
		g int round = `r'
		keep round vname vtype label n_options
		append using `all'
		save `all', replace
	}
	use `all', clear
	sort vname round
	levelsof round, local(rs)
	loc last
	foreach r of local rs {
		if ("`last'" ~= "") {
			preserve
				keep if inlist(round, `last', `r')
				g byte new = round == `r'
				bys vname: egen byte in_prev = max(!new)
				bys vname: egen byte in_new = max(new)
				bys vname (round): g str40 t0 = vtype[1]
				bys vname (round): g str100 l0 = label[1]
				bys vname (round): g n0 = n_options[1]
				forvalues i = 1/`=_N' {
					if (new[`i'] & !in_prev[`i']) post `ph' (`last') (`r') ("added") (vname[`i']) (label[`i'])
					if (!new[`i'] & !in_new[`i']) post `ph' (`last') (`r') ("dropped") (vname[`i']) (label[`i'])
					if (new[`i'] & in_prev[`i']) {
						if (vtype[`i'] ~= t0[`i']) post `ph' (`last') (`r') ("type") (vname[`i']) (label[`i'])
						else if (label[`i'] ~= l0[`i']) post `ph' (`last') (`r') ("wording") (vname[`i']) (label[`i'])
						else if (n_options[`i'] ~= n0[`i']) post `ph' (`last') (`r') ("options") (vname[`i']) (label[`i'])
					}
				}
			restore
		}
		loc last `r'
	}
	postclose `ph'

	// rotating modules: a question with a gap in its rounds, or absent at one end only
	use `all', clear
	bys vname: egen byte n_rounds = count(round)
	bys vname (round): g byte gap = round - round[_n-1] > 1 if _n > 1
	bys vname: egen byte has_gap = max(gap)
	loc nr : word count `rs'
	keep if has_gap == 1 | (n_rounds < `nr' & round ~= `: word 1 of `rs'' & round ~= `: word `nr' of `rs'')
	keep vname has_gap
	duplicates drop
	ren vname variable
	g byte rotating = 1
	tempfile rot
	save `rot'
	use `cur', clear
	merge m:1 variable using `rot', keep(master match) keepusing(rotating) nogen
	replace rotating = 0 if missing(rotating)
	sort from_round to_round change variable
	export delimited using "$afix/form_changes.csv", replace
	di in red "FORM CHANGES: " _N " changes between rounds"
}

********************************************************************************
**# HARMONIZE: VARIABLES COMPARABLE ACROSS ROUNDS
********************************************************************************
{ // HARMONIZE:
	* Appended rounds are not yet a panel a user can read straight: what one round did not ask looks like nonresponse,
	* and the value labels are the first round's. This section makes the files comparable round after round, and it
	* is where a program adds a rule for every change in form_changes.csv that touches a variable's meaning (a question
	* that became multiple-choice, a question gated by a new filter question, a scale with more codes): the comparable
	* variable is built here, once, with its rule written next to it, and the raw variable is left as it is.
	* In this example the only changes are the rotating modules, so two things are done:
	*   1. a flag per rotating module, 1 in the rounds the module was in and 0 in the others, so that a missing finance
	*      or health answer reads as "not asked this round" and not as nonresponse;
	*   2. every value label refreshed from the latest round's form, so the codes read as the last form labels them.
	* Check: the changes in form_changes.csv that are not a rotating module, and so need a rule here, are counted.
	foreach f in cati_household cati_individual M00_passport M01_roster M03_shock_hh M03_shock M04_employment M06_finance M07_health M08_food {
		cap confirm file "$hf/${dta_file}_`f'.dta"
		if _rc ~= 0 continue
		use "$hf/${dta_file}_`f'.dta", clear
		if inlist("`f'", "cati_household", "M00_passport") {
			foreach m in M06_finance M07_health {
				loc mm = lower(substr("`m'", 5, .))
				g byte mod_`mm' = 0
				foreach r of global MOD_`m' {
					replace mod_`mm' = 1 if round == `r'
				}
				la var mod_`mm' "`m' asked this round (rotating module)"
			}
		}
		form_labels using "$kobo/L2PHL_SYN_CATI_R`rrlast'.xlsx"
		save "$hf/${dta_file}_`f'.dta", replace
		if inlist("`f'", "cati_household", "cati_individual") copy "$hf/${dta_file}_`f'.dta" "$share/${dta_file}_`f'.dta", replace
	}
	import delimited "$afix/form_changes.csv", clear varnames(1) bindquote(strict)
	qui count if rotating == 0
	check_log all 6 "form changes between rounds that need a harmonisation rule (not a rotating module)" `r(N)' "listed in form_changes.csv"
	di in red "HARMONIZE: rotating-module flags and the latest form's labels applied; files copied to $share"
}

********************************************************************************
**# CALL LOGS: FIELDWORK INDICATORS
********************************************************************************
{ // CALL INDICATORS:
	* Definitions follow the handbook's call-log sections (Chapter 3): a case is a household in a round; completion
	* rate = cases completed / cases; dials per complete = dials / completes; contact rate = dials where someone
	* answered / dials; an operator-day is an enumerator with at least one dial on a date. Values from fewer than 10
	* cases (or 10 dials) are left empty.
	tempfile dials cases byr
	clear
	foreach r of global ROUNDS {
		append using "`stub`r''_dials.dta"
	}
	cap drop date
	g int date = dofc(dial_start)
	save `dials'
	clear
	foreach r of global ROUNDS {
		append using "`stub`r''_cases.dta"
	}
	merge m:1 hhid using "$hf/R00/phone_sample.dta", keepusing(sample) keep(master match) nogen
	save `cases'

	// by round
	use `dials', clear
	bys round hhid: egen byte any_refusal = max(outcome == 5)
	bys round hhid: egen byte all_dead = min(inlist(outcome, 7, 8))
	egen byte tag_case = tag(round hhid)
	egen byte tag_date = tag(round date)
	g byte ref_case = any_refusal * tag_case
	g byte dead_case = all_dead * tag_case
	collapse (sum) contact_n = contact refusals = ref_case dead = dead_case days = tag_date (count) dials = seq, by(round) fast
	g double contact_rate = contact_n / dials
	save `byr'
	use `cases', clear
	g byte sample_rep = sample == 2
	collapse (count) cases = hhid (sum) completes = completed replacements = sample_rep (median) median_minutes = min_complete, ///
		by(round) fast
	merge 1:1 round using `byr', nogen
	g double completion_rate = completes / cases
	g double dials_per_complete = dials / completes
	g double refusal_rate = refusals / cases
	g double dead_number_rate = dead / cases
	ren days fieldwork_days
	keep round cases completes completion_rate dials dials_per_complete contact_rate refusal_rate dead_number_rate ///
		median_minutes fieldwork_days replacements
	foreach v of varlist completion_rate dials_per_complete contact_rate refusal_rate dead_number_rate median_minutes {
		replace `v' = . if cases < 10
	}
	export delimited using "$acall/calls_by_round.csv", replace nolabel

	// panel balance: what became of each household called
	use `dials', clear
	bys round hhid: egen byte c_ref = max(outcome == 5)
	bys round hhid: egen byte c_contact = max(contact)
	bys round hhid: egen byte c_dead = min(inlist(outcome, 7, 8))
	collapse (first) c_ref c_contact c_dead, by(round hhid) fast
	merge 1:1 round hhid using `cases', keepusing(completed) keep(match) nogen
	g byte st_interviewed = completed
	g byte st_refused = !completed & c_ref
	g byte st_dead = !completed & !c_ref & c_dead
	g byte st_never_answered = !completed & !c_ref & !c_dead & !c_contact
	g byte st_other = !completed & !c_ref & !c_dead & c_contact
	bys hhid (round): g byte all_so_far = sum(completed) == _n & completed
	collapse (count) called = hhid (sum) st_* all_so_far, by(round) fast
	export delimited using "$acall/calls_panel.csv", replace

	// completion by dial number (cumulative)
	use `cases', clear
	forvalues k = 1/6 {
		g byte done`k' = completed & k_complete <= `k'
	}
	collapse (count) cases = hhid (mean) done1-done6, by(round) fast
	reshape long done, i(round cases) j(dial)
	ren done share_completed
	replace share_completed = . if cases < 10
	export delimited using "$acall/calls_by_dialno.csv", replace nolabel

	// outcomes of dials
	use `dials', clear
	contract round outcome, freq(dials)
	bys round: egen double share = total(dials)
	replace share = dials / share
	decode outcome, gen(outcome_label)
	replace share = . if dials < 10
	export delimited using "$acall/calls_outcomes.csv", replace nolabel

	// hour of day and day of week (all rounds)
	use `dials', clear
	g byte hour = hh(dial_start)
	g byte weekday = dow(date)
	foreach by in hour weekday {
		preserve
			collapse (count) dials = seq (mean) contact_rate = contact complete_rate = complete, by(`by') fast
			foreach v of varlist contact_rate complete_rate {
				replace `v' = . if dials < 10
			}
			if ("`by'" == "weekday") {
				la def weekday 0 "Sun" 1 "Mon" 2 "Tue" 3 "Wed" 4 "Thu" 5 "Fri" 6 "Sat", replace
				la val weekday weekday
				decode weekday, gen(day_label)
			}
			export delimited using "$acall/calls_by_`by'.csv", replace nolabel
		restore
	}

	// completes by fieldwork day
	use `dials', clear
	egen fieldday = group(round date)
	bys round (fieldday): g first_day = fieldday[1]
	replace fieldday = fieldday - first_day + 1
	drop first_day
	collapse (sum) completes = complete, by(round fieldday) fast
	bys round (fieldday): g cum_completes = sum(completes)
	bys round (fieldday): g double cum_share = cum_completes / cum_completes[_N]
	export delimited using "$acall/calls_by_day.csv", replace nolabel

	// enumerators
	use `dials', clear
	egen byte tag_od = tag(round enumerator date)
	g double min_c = dur_min if complete
	collapse (count) dials = seq (sum) completes = complete operator_days = tag_od (median) median_minutes = min_c, ///
		by(round enumerator) fast
	g double completes_per_day = completes / operator_days
	foreach v of varlist completes_per_day median_minutes {
		replace `v' = . if completes < 10
	}
	export delimited using "$acall/calls_enumerators.csv", replace nolabel
	di in red "CALL INDICATORS: tables written to $acall"
}

********************************************************************************
**# CALL LOGS: ENUMERATOR MONITORING (HANDBOOK 3.2)
********************************************************************************
{ // ENUMERATOR MONITOR:
	* The indicators side by side for each enumerator and round, with the round's pooled value ("All"):
	*   from the calls: dials, interviews, operator-days, interviews per operator-day, dials per interview, share of
	*     cases with a refusal, median length of the completing dial, share of interviews shorter than 60% of the
	*     round's median length
	*   from the answers: share of "don't know" and "refused" codes (98, 99) among select-one answers; share of
	*     interviews reporting a shock; share reporting four or more food insecurity experiences
	*   from the skip-logic audit: flags per 100 interviews
	* Values from fewer than 10 interviews are left empty.
	tempfile dials cases ans flags out enums
	clear
	foreach r of global ROUNDS {
		append using "`stub`r''_dials.dta"
	}
	cap drop date
	g int date = dofc(dial_start)
	egen byte tag_od = tag(round enumerator date)
	bys round hhid: egen byte c_ref = max(outcome == 5)
	egen byte tag_case = tag(round hhid)
	g byte case_ref = c_ref * tag_case
	save `dials'
	clear
	foreach r of global ROUNDS {
		append using "`stub`r''_cases.dta"
	}
	bys round: egen double med_round = median(min_complete)
	g byte short = completed & min_complete < 0.6 * med_round
	save `cases'

	// answers: don't know / refused codes among the select-one questions, and two answer distributions
	import delimited "$cati/ado/enumerators.csv", clear stringcols(2 3)
	save `enums'
	import excel using "$kobo/L2PHL_SYN_CATI_R01.xlsx", sheet("survey") firstrow allstring clear
	keep if word(type, 1) == "select_one"
	loc sel
	forvalues i = 1/`=_N' {
		loc sel `sel' `=lower(name[`i'])'
	}
	clear
	foreach r of global ROUNDS {
		loc rr : di %02.0f `r'
		preserve
			use "$cati/Round`rr'/zzz/`d`r''/completes.dta", clear
			qui ds
			loc have `r(varlist)'
			loc use : list sel & have
			loc num
			foreach v of local use {
				cap confirm numeric variable `v'
				if _rc == 0 loc num `num' `v'
			}
			egen long n_sel = rownonmiss(`num')
			egen long n_dk = anycount(`num'), values(98 99)
			g byte shock = sh1 == 1
			egen byte fies = anycount(f08_?), values(1)
			g byte fies4 = fies >= 4
			keep round int_id n_sel n_dk shock fies4
			tempfile one
			save `one'
		restore
		append using `one'
	}
	merge m:1 int_id using `enums', keep(match) keepusing(enumerator) nogen
	save `ans'

	// flags from the skip-logic audit
	clear
	foreach r of global ROUNDS {
		preserve
			import delimited "`stub`r''_form_audit_enum.csv", clear varnames(1)
			tempfile one
			save `one'
		restore
		append using `one'
	}
	keep round enumerator flags
	save `flags'

	// by enumerator, then pooled
	foreach level in enumerator all {
		loc by = cond("`level'" == "enumerator", "round enumerator", "round")
		use `dials', clear
		collapse (count) dials = seq (sum) operator_days = tag_od refusals = case_ref cases = tag_case, by(`by') fast
		tempfile d
		save `d'
		use `cases', clear
		collapse (sum) completes = completed shorts = short (median) median_minutes = min_complete, by(`by') fast
		merge 1:1 `by' using `d', nogen
		tempfile c
		save `c'
		use `ans', clear
		collapse (sum) n_sel n_dk (mean) shock_share = shock fies4_share = fies4, by(`by') fast
		merge 1:1 `by' using `c', nogen
		if ("`level'" == "enumerator") merge 1:1 `by' using `flags', nogen
		else {
			preserve
				use `flags', clear
				collapse (sum) flags, by(round)
				tempfile f
				save `f'
			restore
			merge 1:1 round using `f', nogen
			g str12 enumerator = "All"
		}
		replace flags = 0 if missing(flags)
		g double completes_per_day = completes / operator_days
		g double dials_per_complete = dials / completes
		g double refusal_rate = refusals / cases
		g double short_share = shorts / completes
		g double dk_share = n_dk / n_sel
		g double flags_per_100 = 100 * flags / completes
		foreach v in completes_per_day dials_per_complete refusal_rate median_minutes short_share dk_share flags_per_100 shock_share fies4_share {
			replace `v' = . if completes < 10
		}
		keep round enumerator dials completes operator_days cases completes_per_day dials_per_complete refusal_rate ///
			median_minutes short_share dk_share flags_per_100 shock_share fies4_share
		if ("`level'" == "enumerator") save `out'
		else append using `out'
	}
	sort round enumerator
	order round enumerator
	export delimited using "$acall/enumerator_monitor.csv", replace
	di in red "ENUMERATOR MONITOR: written"
}

********************************************************************************
**# WEIGHTED INDICATORS
********************************************************************************
{ // INDICATORS:
	*   indicators.csv   key indicators with 95% confidence intervals, for all households and for urban and rural
	*                    ones (design: strata and PSUs of the baseline, the round weights carried by the HF files)
	*   shock_types.csv  share of households reporting each type of shock
	*   explorer.csv     every labelled question of every module file: weighted percent in each answer, by round
	*                    (the "module explorer", as in the L2PHL summary dashboard)
	* Household data use the household weight, person data the person weight. Cells from fewer than 10 households (or
	* members) are left empty.
	tempfile hh pp res cope

	// households: the household file (passport and household modules, all rounds), with coping from the shocks file
	use round hhid sh2_13 using "$hf/${dta_file}_M03_shock.dta", clear
	collapse (max) cope_food = sh2_13, by(round hhid)
	save `cope'
	use "$hf/${dta_file}_cati_household.dta", clear
	merge 1:1 round hhid using `cope', keep(master match) nogen
	merge m:1 hhid using "$hf/R00/phone_sample.dta", keepusing(psu locale) keep(match) nogen
	foreach v in f17 f18 f6 h2 h2a {
		cap g `v' = .
	}
	g byte shock_any = sh1 == 1
	g byte shock_prices = sh1b_11 == 1
	g byte shock_typhoon = sh1b_1 == 1
	g byte shock_illness = sh1b_20 == 1
	replace cope_food = . if sh1 ~= 1
	g byte fies4 = fies_raw >= 4 if fies_raw < .
	g byte skip_meal = f08_h == 1 if f08_h < .
	g byte bank = f17 == 1 if f17 < .
	g byte mobile_money = f18 == 1 if f18 < .
	g byte emergency = f6 == 1 if inlist(f6, 1, 2)
	g byte care_unmet = h2a == 2 if inlist(h2, 1, 2, 3) & inlist(h2a, 1, 2)
	save `hh'

	// persons: the employment module with the person weight
	use "$hf/${dta_file}_M04_employment.dta", clear
	merge m:1 round hhid using `hh', keep(match) nogen keepusing(psu stratum locale)
	g double w_round = indw
	save `pp'

	// key indicators
	loc K_shock_any     "Households hit by a shock in the past 30 days"
	loc K_shock_prices  "Households hit by higher prices of food, fuel or other goods"
	loc K_shock_typhoon "Households hit by a typhoon"
	loc K_shock_illness "Households hit by a major illness"
	loc K_cope_food     "Households hit by a shock that cut food consumption to cope"
	loc K_fies4         "Households reporting 4 or more of 8 food insecurity experiences"
	loc K_skip_meal     "Households where someone skipped a meal for lack of money"
	loc K_bank          "Households with a bank account"
	loc K_mobile_money  "Households with a mobile money account"
	loc K_emergency     "Households able to pay an emergency expense of one month's income"
	loc K_care_unmet    "Households that needed health care and did not get it"
	loc K_employed      "Adults (15+) who worked or had a job last week"

	tempname ph
	postfile `ph' str16 indicator str90 label int round str6 group double(est lb ub) long n using `res', replace
	foreach k in shock_any shock_prices shock_typhoon shock_illness cope_food fies4 skip_meal bank mobile_money emergency care_unmet employed {
		if ("`k'" == "employed") use `pp', clear
		else use `hh', clear
		qui svyset psu [pw = w_round], strata(stratum) singleunit(centered)
		foreach r of global ROUNDS {
			foreach g in all urban rural {
				loc cond = cond("`g'" == "all", "1", cond("`g'" == "urban", "locale == 1", "locale == 2"))
				qui count if round == `r' & `cond' & `k' < .
				if (r(N) == 0) continue
				cap qui svy, subpop(if round == `r' & `cond' & `k' < .): mean `k'
				if _rc ~= 0 continue
				loc n = e(N_sub)
				loc b = el(e(b), 1, 1)
				loc se = sqrt(el(e(V), 1, 1))
				loc t = invttail(e(df_r), 0.025)
				if (`n' < 10) post `ph' ("`k'") ("`K_`k''") (`r') ("`g'") (.) (.) (.) (`n')
				else post `ph' ("`k'") ("`K_`k''") (`r') ("`g'") (`b') (max(0, `b' - `t' * `se')) (min(1, `b' + `t' * `se')) (`n')
			}
		}
	}
	postclose `ph'
	use `res', clear
	export delimited using "$tab/indicators.csv", replace

	// shock types
	use "$hf/${dta_file}_M03_shock_hh.dta", clear
	qui ds sh1b_*
	loc types
	foreach v in `r(varlist)' {
		cap confirm numeric variable `v'
		if _rc == 0 loc types `types' `v'
	}
	foreach v of local types {
		replace `v' = 0 if sh1 ~= 1
		loc lab`v' : variable label `v'
	}
	collapse (mean) `types' [aw = w_round], by(round)
	reshape long sh1b_, i(round) j(code)
	ren sh1b_ share
	g str60 label = ""
	foreach v of local types {
		loc c = substr("`v'", 6, .)
		replace label = substr("`lab`v''", strpos("`lab`v''", " ") + 1, .) if code == `c'
	}
	export delimited using "$tab/shock_types.csv", replace

	// module explorer
	tempname pe
	tempfile ex
	postfile `pe' str20 module str32 var str80 varlabel int round long code str80 catlabel double pct long n using `ex', replace
	loc skip hhid round fmid int_id sample z8 call_status1 z17 z9 x15 status present prev_work d5a_
	foreach m in M00_passport M01_roster M03_shock_hh M04_employment M06_finance M07_health M08_food {
		cap confirm file "$hf/${dta_file}_`m'.dta"
		if _rc ~= 0 continue
		use "$hf/${dta_file}_`m'.dta", clear
		cap confirm variable fmid
		if _rc == 0 g double w_round = indw							// person data: the person weight
		if ("`m'" == "M01_roster") keep if present
		qui ds, has(vallabel)
		loc vars `r(varlist)'
		loc vars : list vars - skip
		foreach r of global ROUNDS {
			qui count if round == `r'
			if (r(N) == 0) continue
			foreach v of local vars {
				qui levelsof `v' if round == `r', local(codes)
				if (`: word count `codes'' > 25) continue
				loc vl : variable label `v'
				qui su w_round if `v' < . & round == `r'
				loc tot = r(sum)
				foreach c of local codes {
					qui su w_round if `v' == `c' & round == `r'
					loc wc = r(sum)
					loc nc = r(N)
					loc cl : label (`v') `c'
					loc pct = cond(`nc' < 10, ., 100 * `wc' / `tot')
					post `pe' ("`m'") ("`v'") (`"`vl'"') (`r') (`c') (`"`cl'"') (`pct') (`nc')
				}
			}
		}
	}
	postclose `pe'
	use `ex', clear
	export delimited using "$tab/explorer.csv", replace
	di in red "INDICATORS: indicators, shock types and explorer written"
}

********************************************************************************
**# DASHBOARD
********************************************************************************
{ // DASHBOARD:
	* Every table above goes into one JavaScript data file next to a fixed page (Analysis/do/dashboard_template.html),
	* so the dashboard opens from the folder with a double-click, offline, and a new round only needs the do-files
	* rerun. Nothing is computed in the page; it only draws what Stata wrote.
	loc js "$tab/dashboard_data.js"
	tempname fh
	file open `fh' using "`js'", write text replace
	file write `fh' "window.DATA = {};" _n
	file write `fh' `"DATA.meta = {"program":"$dta_file","title":"L2PHL synthetic example","made":"`c(current_date)'","rounds":["'
	loc first 1
	foreach r of global ROUNDS {
		if (!`first') file write `fh' ","
		loc first 0
		file write `fh' `"{"round":`r',"start":"${START_`r'}","export":"`d`r''"}"'
	}
	file write `fh' "]};" _n
	file close `fh'

	foreach t in by_round by_dialno outcomes by_hour by_weekday by_day enumerators {
		import delimited "$acall/calls_`t'.csv", clear varnames(1) asdouble
		js_table using "`js'", name(DATA.`t') append
	}
	foreach t in indicators shock_types explorer {
		import delimited "$tab/`t'.csv", clear varnames(1) bindquote(strict) asdouble
		js_table using "`js'", name(DATA.`t') append
	}
	import delimited "$hf/R00/sample_summary.csv", clear varnames(1) asdouble
	js_table using "`js'", name(DATA.sample) append

	// per-round files stacked: weights summaries, skip-logic audits
	foreach t in weights audit {
		clear
		foreach r of global ROUNDS {
			preserve
				if ("`t'" == "weights") import delimited "`stub`r''_wgt_summary.csv", clear varnames(1) asdouble
				else import delimited "`stub`r''_form_audit.csv", clear varnames(1) bindquote(strict) asdouble
				tempfile one
				save `one'
			restore
			append using `one'
		}
		js_table using "`js'", name(DATA.`t') append
	}
	import delimited "$afix/form_changes.csv", clear varnames(1) bindquote(strict) asdouble
	js_table using "`js'", name(DATA.form_changes) append
	import delimited "$acall/calls_panel.csv", clear varnames(1) asdouble
	js_table using "`js'", name(DATA.panel) append
	import delimited "$acall/enumerator_monitor.csv", clear varnames(1) asdouble
	js_table using "`js'", name(DATA.monitor) append

	// the review lists a person should read, with their row counts (the round's fix folder)
	clear
	g str60 file = ""
	g long rows = .
	foreach r of global ROUNDS {
		loc rr : di %02.0f `r'
		loc files : dir "$cati/Round`rr'/fix/`d`r''" files "R`rr'_*.csv"
		loc files : list sort files
		foreach f of local files {
			preserve
				import delimited "$cati/Round`rr'/fix/`d`r''/`f'", clear varnames(1)
				loc n = _N
			restore
			loc new = _N + 1
			set obs `new'
			qui replace file = "`f'" in `new'
			qui replace rows = `n' in `new'
		}
	}
	js_table using "`js'", name(DATA.reviews) append
	import delimited "$afix/checks.csv", clear varnames(1) bindquote(strict) asdouble
	js_table using "`js'", name(DATA.checks) append

	copy "$anl/do/dashboard_template.html" "$tab/index.html", replace
	di in red "DASHBOARD: open CATI/Analysis/summary_dashboard/index.html"
}
