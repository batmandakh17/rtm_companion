* L2PHL_SYN: TESTS
* Runs the whole workflow, then checks its results against what the synthetic data were built with
* (tests/expected_counts.csv, written by tools/make_synthetic.py). Results in tests/results.txt.
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* Run from the package folder:  stata-mp -b do tests/run_tests.do   (or set glo wd first)

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear all
	if ("$wd" == "") glo wd "`c(pwd)'"
	do "$wd/L2PHL_SYN_master.do"

	tempname fh
	file open `fh' using "$tests/results.txt", write text replace
	file write `fh' "RTM companion tests, `c(current_date)' `c(current_time)'" _n
	loc fails 0
	cap program drop test_eq
	program define test_eq, rclass
		args fh what got want
		loc ok = abs(`got' - `want') < 1e-6
		file write `fh' (cond(`ok', "PASS", "FAIL")) "  `what': got `got', expected `want'" _n
		return scalar fail = !`ok'
	end
}

********************************************************************************
**# PLANTED PROBLEMS FOUND, COMPLETES, DIALS, PRELOADS, AUDIT, WEIGHTS: ROUND BY ROUND
********************************************************************************
{
	import delimited "$tests/expected_counts.csv", clear
	tempfile exp
	save `exp'
	import delimited "$afix/checks.csv", clear bindquote(strict)
	tempfile ck
	save `ck'
	loc all_completes 0
	foreach r of global ROUNDS {
		setround `r'											// the round's dated folders and $stub, as the do-files see them
		loc rr : di %02.0f `r'
		loc d`r' "$date"
		use `exp', clear
		keep if round == `r'
		foreach v in test_submissions duplicate_submissions negative_durations short_completes completes dials routing_broken required_missing out_of_range {
			loc e_`v' = `v'[1]
		}
		loc all_completes = `all_completes' + `e_completes'
		use `ck', clear
		foreach pair in "test_submissions|practice submissions dated before the first calling day" ///
						"duplicate_submissions|the same submission sent twice" ///
						"negative_durations|submissions saved before they were opened (device clock)" ///
						"short_completes|completes recorded in under 3 minutes" {
			gettoken key what : pair, parse("|")
			loc what = substr("`what'", 2, .)
			qui su n if round == `r' & check == "`what'"
			test_eq `fh' "R`r' `what'" `r(sum)' `e_`key''
			loc fails = `fails' + r(fail)
		}
		foreach what in "dials in only one of the two sources (call centre, form)" ///
						"dials where the two sources disagree on enumerator, start or outcome" ///
						"households complete in the calls but not in the passport, or the reverse" {
			qui su n if round == `r' & check == "`what'"
			test_eq `fh' "R`r' `what'" `r(sum)' 0
			loc fails = `fails' + r(fail)
		}
		qui count if round == `r' & strpos(check, "preload for round") & n == 0
		test_eq `fh' "R`r' preload for the next round identical to the generator's" `r(N)' 1
		loc fails = `fails' + r(fail)

		import delimited "$aud/${dta_file}_${date}_form_audit.csv", clear bindquote(strict)
		foreach v in routing_broken required_missing out_of_range {
			qui su `v'
			test_eq `fh' "R`r' skip-logic audit, `v'" `r(sum)' `e_`v''
			loc fails = `fails' + r(fail)
		}
		qui count if status == "not translated"
		test_eq `fh' "R`r' skip-logic audit, routing rules the audit could not read" `r(N)' 0
		loc fails = `fails' + r(fail)
		loc nfl 0
		cap confirm file "$fix/R`rr'_form_flags.csv"
		if _rc == 0 {
			import delimited "$fix/R`rr'_form_flags.csv", clear varnames(1)
			loc nfl = _N
		}
		loc e_flags = `e_routing_broken' + `e_required_missing' + `e_out_of_range'
		test_eq `fh' "R`r' skip-logic audit, flagged rows listed by household in Round`rr'/fix/<date>/R`rr'_form_flags.csv" `nfl' `e_flags'
		loc fails = `fails' + r(fail)

		use "${stub}_M00_passport.dta", clear
		test_eq `fh' "R`r' households interviewed" `=_N' `e_completes'
		loc fails = `fails' + r(fail)
		use "${stub}_HH_Level_Data.dta", clear
		test_eq `fh' "R`r' household-level data: one row per household interviewed" `=_N' `e_completes'
		loc fails = `fails' + r(fail)
		use "$call/${dta_file}_${date}_dials_kobo.dta", clear
		test_eq `fh' "R`r' dials after dropping practice and duplicate submissions" `=_N' `e_dials'
		loc fails = `fails' + r(fail)

		use "$wgt/${dta_file}_${date}_hhw.dta", clear
		qui count if missing(w_round) | w_round <= 0
		test_eq `fh' "R`r' every interviewed household has a positive weight" `r(N)' 0
		loc fails = `fails' + r(fail)
		import delimited "$wgt/${dta_file}_${date}_cells.csv", clear
		g double gap = abs(sum_indw / t_cell - 1)
		qui su gap
		test_eq `fh' "R`r' person weights sum to the baseline population in every cell (max gap x 1e6, rounded)" `=round(r(max) * 1e6)' 0
		loc fails = `fails' + r(fail)
	}
}

********************************************************************************
**# THE ALTERNATIVE WEIGHTING METHODS, ON THE FIRST ROUND
********************************************************************************
{
	* checks.csv is put back afterwards, so the extra runs leave no trace in the outputs
	loc r0 : word 1 of $ROUNDS
	loc rr0 : di %02.0f `r0'
	setround `r0'
	loc wfile "$wgt/${dta_file}_${date}_hhw.dta"
	tempfile checks_copy
	copy "$afix/checks.csv" `checks_copy', replace
	glo R `rr0'
	glo WEIGHTS rake
	qui do "$cati/do/L2PHL_SYN_CATI_wgt@R.do"
	use "`wfile'", clear
	qui su w_round
	loc wsum = r(sum)
	ren w_round w_rake
	keep hhid w_rake
	tempfile rake
	save `rake'
	use "$smpl/census_totals.dta", clear
	qui su households
	test_eq `fh' "R`r0' raking: household weights sum to the census households" `=round(`wsum')' `r(sum)'
	loc fails = `fails' + r(fail)
	cap which ebalance
	if _rc ~= 0 file write `fh' "SKIP  R`r0' entropy balancing: ebalance is not installed (ssc install ebalance)" _n
	else {
		glo WEIGHTS ebalance
		qui do "$cati/do/L2PHL_SYN_CATI_wgt@R.do"
		use "`wfile'", clear
		merge 1:1 hhid using `rake', assert(match) nogen
		g double gap = abs(w_round / w_rake - 1)
		qui su gap
		test_eq `fh' "R`r0' entropy balancing and raking give the same weights (max relative gap x 1e3, rounded)" `=round(r(max) * 1e3)' 0
		loc fails = `fails' + r(fail)
	}
	glo WEIGHTS cellpost
	qui do "$cati/do/L2PHL_SYN_CATI_wgt@R.do"
	copy `checks_copy' "$afix/checks.csv", replace
}

********************************************************************************
**# THE ANALYSIS FOLDER: HF POPULATED, THE FINAL FILES, THE DASHBOARD
********************************************************************************
{
	loc n_pop 0
	foreach r of global ROUNDS {
		loc rr : di %02.0f `r'
		cap confirm file "$hf/R`rr'/${dta_file}_`d`r''_M00_passport.dta"
		loc n_pop = `n_pop' + (_rc == 0)
	}
	test_eq `fh' "HF/R## populated with the module files of every round's latest export" `n_pop' `: word count $ROUNDS'
	loc fails = `fails' + r(fail)
	use "$hf/${dta_file}_cati_household.dta", clear
	test_eq `fh' "household file: one row per household and round, all rounds appended" `=_N' `all_completes'
	loc fails = `fails' + r(fail)
	qui count if missing(w_round) | missing(year)
	test_eq `fh' "household file: every row has its round weight and interview year" `r(N)' 0
	loc fails = `fails' + r(fail)
	use "$hf/${dta_file}_cati_individual.dta", clear
	qui count if present & missing(indw)
	test_eq `fh' "individual file: every member present has a person weight" `r(N)' 0
	loc fails = `fails' + r(fail)
	foreach f in cati_household cati_individual {
		cap confirm file "$share/${dta_file}_`f'.dta"
		test_eq `fh' "2share/${dta_file}_`f'.dta exists" `=_rc == 0' 1
		loc fails = `fails' + r(fail)
	}
	foreach f in index.html dashboard_data.js {
		cap confirm file "$tab/`f'"
		test_eq `fh' "dashboard file `f' exists" `=_rc == 0' 1
		loc fails = `fails' + r(fail)
	}
	file write `fh' _n (cond(`fails' == 0, "ALL PASS", "`fails' FAILED")) _n
	file close `fh'
	type "$tests/results.txt"
	if `fails' exit 9
}
