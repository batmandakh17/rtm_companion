* L2PHL_SYN: MASTER
* RTM companion package: the whole real-time monitoring workflow, from the sampling frame to the dashboard, on
* synthetic data laid out like the L2PHL phone rounds. Run this file; every output lands in output/.
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
*   do/0_L2PHL_SYN_preambles.do          globals, folders, ado path (run by every file)
*   do/1_L2PHL_SYN_CAPI_R00_psu2wgt.do   PSU selection and baseline weights
*   do/2_L2PHL_SYN_CAPI_R00_dta2smp.do   phone subsample and the round-1 preload
*   do/3_L2PHL_SYN_CATI@R.do             each round: KoBo export to module files (M0-M8), checks, next preload,
*                                        skip-logic audit, call logs
*   do/4_L2PHL_SYN_CATI_wgt@R.do         each round: round weights
*   do/5_hf_l2phl_syn_analysis.do        across rounds: form changes, call indicators, enumerator monitoring,
*                                        weighted indicators, dashboard
*   ado/                                 the package's own commands
* Stata 16 or later; no user-written commands (ebalance from SSC only for that weighting option). About 20 seconds.

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear all
	set more off

	if ("$wd" == "") glo wd "`c(pwd)'"
	cap confirm file "$wd/do/0_L2PHL_SYN_preambles.do"
	if _rc ~= 0 {
		di as error `"Cannot find do/0_L2PHL_SYN_preambles.do under "$wd". Set:  glo wd "<folder of this file>""'
		exit 601
	}
	do "$wd/do/0_L2PHL_SYN_preambles.do"

	cap erase "$afix/checks.csv"
	cap log close master
	log using "$logs/master.log", replace text name(master)
}

********************************************************************************
**# CAPI: SAMPLE AND BASELINE WEIGHTS
********************************************************************************
{
	do "$do/1_L2PHL_SYN_CAPI_R00_psu2wgt.do"
	do "$do/2_L2PHL_SYN_CAPI_R00_dta2smp.do"
}

********************************************************************************
**# CATI: ROUND BY ROUND
********************************************************************************
{
	foreach r of global ROUNDS {
		glo R : di %02.0f `r'
		do "$do/3_L2PHL_SYN_CATI@R.do"
		do "$do/4_L2PHL_SYN_CATI_wgt@R.do"
	}
}

********************************************************************************
**# ANALYSIS: ACROSS ROUNDS
********************************************************************************
{
	do "$do/5_hf_l2phl_syn_analysis.do"

	log close master
	di in red _n "Done. Open output/analysis/dashboard/index.html; the data checks are in output/analysis/fix/checks.csv."
}
