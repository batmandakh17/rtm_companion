* L2PHL_SYN CATI ROUND $R: ROUND WEIGHTS (wgt)
* RTM companion package, synthetic data laid out like the L2PHL phone rounds
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* Household and person weights for one phone round. Three methods, chosen with $WEIGHTS in the preambles; the default
* is the procedure L2PHL runs.
*   cellpost (default, L2PHL): every person present in an interviewed household starts from the household's
*       phone-sample weight. The person weights are then post-stratified in cells of stratum x age group (0-17, 18-45,
*       46 and over) x sex: each cell is scaled so that it sums to the cell's baseline-weighted number of persons.
*       hhw = mean of the members' person weights, popw = their sum, ave_hhw = hhw averaged within the PSU (the
*       smoothed household weight L2PHL carries alongside).
*   rake: household weights raked (iterative proportional fitting, Deming and Stephan 1940) to census households by
*       stratum and to baseline households by household size (1-2, 3-4, 5-6, 7+). Person weight = household weight.
*   ebalance: the same two sets of targets reached with entropy balancing (Hainmueller 2012), the ebalance command
*       from SSC as the Tajikistan, Kyrgyzstan, Uzbekistan and Caucasus programs use it. On categorical margins
*       entropy balancing solves the same problem as raking, so the two give the same weights (tests/run_tests.do
*       checks this).
* In every method a replacement household comes from the same PSU's list as the household it replaced, so it starts
* from the same phone-sample weight. Each round is weighted afresh, so households lost since round 1 are made up by
* those still answering. No trimming. Diagnostics: largest/smallest household weight and the design effect from
* unequal weights, 1 + CV^2 (Kish 1965).
* In:  this round's M00 and M01; $smpl/phone_sample.dta, baseline_weights.dta, census_totals.dta;
*      data/baseline/baseline_members.csv
* Out: $wgt/weights_R##.dta (hhid round stratum hhw popw ave_hhw w_round = hhw, the weight the analysis uses for
*      household data), weights_persons_R##.dta (hhid round fmid indw, for person data), cells_R##.csv (cellpost:
*      targets and sums by cell), summary_R##.csv (for the dashboard)

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear
	set more off
	if ("$wd" == "") glo wd "`c(pwd)'"
	do "$wd/do/0_L2PHL_SYN_preambles.do"

	* Set round and method
	********************
	if ("$R" == "") glo R 01
	setround $R
	loc r = real("$R")
	glo stub "$dta/${dta_file}_R${R}"
	loc method = cond("$WEIGHTS" == "", "cellpost", lower("$WEIGHTS"))
	if (!inlist("`method'", "cellpost", "rake", "ebalance")) {
		di as error "wgt: global WEIGHTS must be cellpost, rake or ebalance (is `method')"
		exit 198
	}
	tempfile hh persons cells size
}

********************************************************************************
**# START WEIGHTS AND TARGETS
********************************************************************************
{ // TARGETS:
	// the interviewed households and their phone-sample weights
	use hhid using "${stub}_M00_passport.dta", clear
	merge 1:1 hhid using "$smpl/phone_sample.dta", keep(match) keepusing(psu stratum hhsize sample w_ph) nogen
	save `hh'

	// the persons present this round, with their cell
	use hhid fmid present sex age using "${stub}_M01_roster.dta", clear
	keep if present
	merge m:1 hhid using `hh', keep(match using) keepusing(psu stratum sample w_ph) nogen
		qui count if missing(fmid)
		check_log `r' 5 "interviewed households with no member present in the roster" `r(N)' "stop"
	g byte agegrp = cond(age <= 17, 1, cond(age <= 45, 2, 3)) if age < .
		la def agegrp 1 "0-17" 2 "18-45" 3 "46+"
		la val agegrp agegrp
		qui count if missing(agegrp) | !inlist(sex, 1, 2)
		check_log `r' 5 "persons without age or sex (cannot be placed in a cell)" `r(N)' "stop"
	save `persons'

	// cell targets from the baseline: persons, each carrying the household's baseline weight
	import delimited "$data/baseline/baseline_members.csv", clear
	keep hhid sex age
	merge m:1 hhid using "$smpl/baseline_weights.dta", keep(match) keepusing(stratum w_bl) nogen
	g byte agegrp = cond(age <= 17, 1, cond(age <= 45, 2, 3))
	collapse (sum) t_cell = w_bl (count) n_baseline = w_bl, by(stratum agegrp sex)
	save `cells'

	// size-class targets from the baseline (rake and ebalance)
	use "$smpl/baseline_weights.dta", clear
	g byte sizecl = min(4, ceil(hhsize / 2))
	collapse (sum) t_size = w_bl, by(sizecl)
	save `size'
}

********************************************************************************
**# WEIGHTING: CELL POST-STRATIFICATION (L2PHL), OR RAKING / ENTROPY BALANCING
********************************************************************************
if ("`method'" == "cellpost") {
	* Cell post-stratification of person weights (L2PHL)
	********************************************************************************
	use `persons', clear
	g double indw_base = w_ph
	bys stratum agegrp sex: egen double s_cell = total(indw_base)
	bys stratum agegrp sex: g long n_cell = _N
	merge m:1 stratum agegrp sex using `cells', keep(match using) nogen
		qui count if missing(hhid)
		check_log `r' 5 "cells of stratum x age group x sex with no interviewed person" `r(N)' "stop"
	g double indw = indw_base * t_cell / s_cell

	preserve
		collapse (first) n_baseline t_cell n_cell (sum) sum_indw = indw, by(stratum agegrp sex)
		g int round = `r'
		order round stratum agegrp sex n_baseline t_cell n_cell sum_indw
			qui count if n_cell < 10
			check_log `r' 5 "cells with fewer than 10 interviewed persons" `r(N)' "listed in R$R/wgt/cells_R${R}.csv"
		export delimited using "$wgt/cells_R${R}.csv", replace
	restore

	bys hhid: egen double hhw = mean(indw)
	bys hhid: egen double popw = total(indw)
	g int round = `r'
	preserve
		keep hhid round fmid indw
			la var indw "Person weight, round `r' (post-stratified by stratum x age group x sex)"
		sort hhid fmid
		save "$wgt/weights_persons_R${R}.dta", replace
	restore
	collapse (first) round psu stratum sample hhw popw, by(hhid)
}
else {
	* Raking and entropy balancing of household weights (the alternatives)
	********************************************************************************
	use `hh', clear
	g byte sizecl = min(4, ceil(hhsize / 2))
	merge m:1 stratum using "$smpl/census_totals.dta", keep(match) keepusing(households) nogen
	ren households t_stratum
	merge m:1 sizecl using `size', keep(match) nogen

	* Raking (iterative proportional fitting)
	********************
	if ("`method'" == "rake") {
		g double w = w_ph
		loc it 0
		loc gap 1
		while (`gap' > 1e-10 & `it' < 200) {
			loc ++it
			bys stratum: egen double s = total(w)
			replace w = w * t_stratum / s
			drop s
			bys sizecl: egen double s = total(w)
			replace w = w * t_size / s
			drop s
			bys stratum: egen double s = total(w)
			g double d = abs(s / t_stratum - 1)
			qui su d
			loc gap = r(max)
			drop s d
		}
		if (`gap' > 1e-10) {
			di as error "wgt R$R: raking did not converge"
			exit 430
		}
		check_log `r' 5 "raking passes to convergence" `it' "reported"
	}

	* Entropy balancing
	********************
	else {
		cap which ebalance
		if _rc ~= 0 {
			check_log `r' 5 "ebalance is not installed (ssc install ebalance)" 1 "stop"
		}
		* two groups: the respondents (treat 0) with their phone-sample weights as base weights, and every baseline
		* household (treat 1) with its baseline weight, so the targets are the baseline-weighted shares of each
		* stratum (the census shares) and of each size class, the same margins as raking. One dummy of each set is
		* left out: its share is implied by the others. (ebalance's manual-targets mode is not used because it
		* resets the base weights to 1.)
		use "$smpl/census_totals.dta", clear
		qui su households
		loc t_total = r(sum)
		levelsof stratum, local(sts)
		use `size', clear
		levelsof sizecl, local(szs)

		use `hh', clear
		g byte sizecl = min(4, ceil(hhsize / 2))
		g byte treat = 0
		g double bw = w_ph
		append using "$smpl/baseline_weights.dta", keep(hhid stratum hhsize w_bl)
		replace treat = 1 if missing(treat)
		replace sizecl = min(4, ceil(hhsize / 2)) if missing(sizecl)
		replace bw = w_bl if treat == 1
		loc covs
		loc k 0
		foreach c of local sts {
			loc ++k
			if (`k' > 1) {
				g byte st_`c' = stratum == `c'
				loc covs `covs' st_`c'
			}
		}
		loc k 0
		foreach c of local szs {
			loc ++k
			if (`k' > 1) {
				g byte sz_`c' = sizecl == `c'
				loc covs `covs' sz_`c'
			}
		}
		qui ebalance treat `covs', basewt(bw) wttreat generate(w_eb) tolerance(1e-9) maxiter(1000)
		keep if treat == 0
		qui su w_eb
		g double w = w_eb * `t_total' / r(sum)
		drop w_eb bw treat w_bl st_* sz_*
		merge m:1 stratum using "$smpl/census_totals.dta", keep(match) keepusing(households) nogen
		ren households t_stratum
		merge m:1 sizecl using `size', keep(match) nogen
		bys stratum: egen double s = total(w)
		g double d = abs(s / t_stratum - 1)
		qui su d
		loc gap6 = round(r(max) * 1e6)
		drop s d
		check_log `r' 5 "entropy balancing: largest gap to the stratum targets, x 1e6" `gap6' "reported"
	}
	ren w hhw
	g int round = `r'

	* Person weight = household weight; population weight = household weight x persons present
	********************
	preserve
		keep hhid hhw
		tempfile hw
		save `hw'
		use `persons', clear
		merge m:1 hhid using `hw', keep(match) nogen
		g double indw = hhw
		g int round = `r'
		keep hhid round fmid indw
			la var indw "Person weight, round `r' (= household weight)"
		sort hhid fmid
		save "$wgt/weights_persons_R${R}.dta", replace
		collapse (count) n_present = indw, by(hhid)
		save `hw', replace
	restore
	merge 1:1 hhid using `hw', keep(match) nogen
	g double popw = hhw * n_present
	keep hhid round psu stratum sample hhw popw
}

********************************************************************************
**# HOUSEHOLD FILE, DIAGNOSTICS AND SUMMARY
********************************************************************************
{ // SUMMARY:
	bys psu: egen double ave_hhw = mean(hhw)
	qui su hhw
	loc ratio = round(r(max) / r(min), 0.1)
	loc tot = r(sum)
	loc deff = round(1 + (r(sd) * sqrt((r(N) - 1) / r(N)) / r(mean))^2, 0.01)
	loc n_hh = r(N)
	preserve
		use "$smpl/census_totals.dta", clear
		qui su households
		loc census = r(sum)
	restore
	check_log `r' 5 "household weights (`method'): largest / smallest" `ratio' "no trimming"
	check_log `r' 5 "household weights (`method'): sum as a share of census households, %" `=round(100 * `tot' / `census', 0.1)' "reported"
	check_log `r' 5 "design effect from unequal household weights (1 + CV squared)" `deff' "reported"

	// the summary for the dashboard
	preserve
		use "$wgt/weights_persons_R${R}.dta", clear
		loc np = _N
		loc nc .
		loc ns .
		if ("`method'" == "cellpost") {
			import delimited "$wgt/cells_R${R}.csv", clear
			loc nc = _N
			qui count if n_cell < 10
			loc ns = r(N)
		}
	restore
	preserve
		g byte repl = sample == 2
		collapse (count) households = hhw (sum) replacements = repl hhw_sum = hhw (min) hhw_min = hhw (max) hhw_max = hhw, fast
		g int round = `r'
		g str8 method = "`method'"
		g double deff = `deff'
		g long persons = `np'
		g int cells = `nc'
		g int cells_small = `ns'
		order round method households persons replacements hhw_sum hhw_min hhw_max deff cells cells_small
		export delimited using "$wgt/summary_R${R}.csv", replace
	restore

	g double w_round = hhw
		la var hhw 		"Household weight, round `r' (`method')"
		la var popw 	"Population weight, round `r': sum of the members' person weights"
		la var ave_hhw 	"Smoothed household weight: hhw averaged within the PSU"
		la var w_round 	"Household weight used by the analysis (= hhw)"
	keep hhid round stratum hhw popw ave_hhw w_round
	sort hhid
	save "$wgt/weights_R${R}.dta", replace
	di in red "wgt R$R (`method'): `n_hh' households, household weights sum to " %12.0fc `tot'
}
