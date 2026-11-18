* L2PHL_SYN CAPI ROUND 00: PSU SELECTION AND BASELINE WEIGHTS (psu2wgt)
* RTM companion package, synthetic data laid out like the L2PHL phone rounds
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* Two-stage stratified design, as the L2 programs': census enumeration areas as PSUs, stratified by region and
* urban/rural; PSUs first, then households.
*   Stage 1: systematic PPS within each stratum, frame in PSU order, measure of size = census households, one
*            recorded random start per stratum (UN 2008, Designing Household Survey Samples: Practical Guidelines).
*            A PSU is selected when a selection point (start + k) * T / n falls in its stretch (prev, cum] of the
*            cumulative size; no PSU is larger than T / n, so none is selected twice.  pi1 = n * HH_psu / HH_stratum
*   Stage 2: households found by random walk, so there is no listing count:  pi2 = HH interviewed / HH census (PSU)
*   Base HH weight:  w_design = 1 / (pi1 * pi2)
*   Post-stratification (HH): w_bl = w_design scaled so that it sums to the census households of each stratum
* In:  data/frame/frame_psu.csv, data/frame/census_totals.csv, data/baseline/baseline_households.csv
* Out: $smpl/psu_selected.dta (with pi1), census_totals.dta, baseline_weights.dta

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear
	if ("$wd" == "") glo wd "`c(pwd)'"
	do "$wd/do/0_L2PHL_SYN_preambles.do"

	* Design parameters
	********************
	loc n_h 15												// PSUs per stratum
	loc starts 11 0.2718 12 0.5772 21 0.1414 22 0.8862 31 0.3183 32 0.6931 41 0.4142 42 0.7071
															// the random starts, one per stratum, drawn once with runiform()
}

********************************************************************************
**# STAGE 1: PSU SELECTION (SYSTEMATIC PPS)
********************************************************************************
{ // PSU:
	import delimited "$data/frame/frame_psu.csv", clear
	sort stratum psu
	by stratum: g double cum = sum(hh_census)
	g double prev = cum - hh_census
	by stratum: egen double tot = total(hh_census)

	g double start = .
	while "`starts'" ~= "" {
		gettoken s starts : starts
		gettoken u starts : starts
		replace start = `u' if stratum == `s'
	}
	as start < .

	g hits = floor(cum * `n_h' / tot - start) - floor(prev * `n_h' / tot - start)
		as hits <= 1
	g double pi1 = `n_h' * hh_census / tot
		la var pi1 "PSU selection probability (stage 1)"
	keep if hits == 1
	by stratum: as _N == `n_h'

	keep psu region locale stratum hh_census pop_census pi1
	save "$smpl/psu_selected.dta", replace

	// the baseline was fielded in exactly these PSUs
	preserve
		import delimited "$data/baseline/baseline_households.csv", clear
		keep psu
		duplicates drop
		merge 1:1 psu using "$smpl/psu_selected.dta", nogen assert(match)
	restore
	di in red "psu2wgt: " _N " PSUs selected, the same PSUs as the baseline"
}

********************************************************************************
**# BASELINE WEIGHTS
********************************************************************************
{ // WEIGHTS:
	import delimited "$data/frame/census_totals.csv", clear
	save "$smpl/census_totals.dta", replace

	import delimited "$data/baseline/baseline_households.csv", clear
	drop cp name											// contacts stay in the input file and in pii
	merge m:1 psu using "$smpl/psu_selected.dta", nogen assert(match) keepusing(pi1 hh_census)

	bys psu: g n_psu = _N
	g double pi2 = n_psu / hh_census
	g double w_design = 1 / (pi1 * pi2)
		la var w_design "Baseline design weight"

	// post-stratification to the census households of each stratum
	merge m:1 stratum using "$smpl/census_totals.dta", nogen assert(match) keepusing(households)
	bys stratum: egen double sum_w = total(w_design)
	g double w_bl = w_design * households / sum_w
		la var w_bl "Baseline household weight (scaled to census households by stratum)"

	keep hhid psu region locale stratum hhsize has_phone u w_design w_bl
	sort hhid
	save "$smpl/baseline_weights.dta", replace

	// QA: the weights add up to the census households of each stratum
	merge m:1 stratum using "$smpl/census_totals.dta", nogen keepusing(households)
	bys stratum: egen double chk = total(w_bl)
	as reldif(chk, households) < 1e-9
	di in red "psu2wgt: " _N " households weighted"
}
