* L2PHL_SYN: MASTER
* RTM companion package: the whole real-time monitoring workflow, from the sampling frame to the dashboard, on
* synthetic data laid out like the L2PHL phone rounds. Run this file; every output lands in dated subfolders of
* CAPI/, CATI/Round##/ and CATI/Analysis/.
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
*   L2PHL_SYN_preambles.do                      globals, folders, ado path (run by every file)
*   CAPI/do/1_L2PHL_SYN_CAPI_R00_psu2wgt.do     PSU selection and baseline weights
*   CAPI/do/2_L2PHL_SYN_CAPI_R00_dta2smp.do     phone subsample, round-1 preload, roster master
*   CATI/do/L2PHL_SYN_CATI@R.do                 each round: KoBo export to module files (M0-M8), household and roster
*                                               level files, checks, next preload, skip-logic audit, call logs
*   CATI/do/L2PHL_SYN_CATI_wgt@R.do             each round: round weights
*   CATI/Round##/do/L2PHL_SYN_CATI@R##.do       runs the two files above for one round
*   CATI/Analysis/do/hf_l2phl_syn_analysis.do   across rounds: HF populated with the latest files of every round,
*                                               appended, finalized (household and individual files) and harmonized;
*                                               form changes, call indicators, enumerator monitoring, weighted
*                                               indicators, dashboard
*   ado/                                        the package's own commands
* Stata 16 or later; no user-written commands (ebalance from SSC only for that weighting option). About 20 seconds.

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear all
	set more off

	if ("$wd" == "") glo wd "`c(pwd)'"
	cap confirm file "$wd/L2PHL_SYN_preambles.do"
	if _rc ~= 0 {
		di as error `"Cannot find L2PHL_SYN_preambles.do under "$wd". Set:  glo wd "<folder of this file>""'
		exit 601
	}
	do "$wd/L2PHL_SYN_preambles.do"

	cap erase "$afix/checks.csv"
	cap log close master
	log using "$wd/L2PHL_SYN_master.log", replace text name(master)
}

********************************************************************************
**# CAPI: SAMPLE AND BASELINE WEIGHTS
********************************************************************************
{
	do "$capi/do/1_L2PHL_SYN_CAPI_R00_psu2wgt.do"
	do "$capi/do/2_L2PHL_SYN_CAPI_R00_dta2smp.do"
}

********************************************************************************
**# CATI: ROUND BY ROUND
********************************************************************************
{
	foreach r of global ROUNDS {
		glo R : di %02.0f `r'
		do "$cati/do/L2PHL_SYN_CATI@R.do"
		do "$cati/do/L2PHL_SYN_CATI_wgt@R.do"
	}
}

********************************************************************************
**# ANALYSIS: ACROSS ROUNDS
********************************************************************************
{
	do "$anl/do/hf_l2phl_syn_analysis.do"

	log close master
	di in red _n "Done. Open CATI/Analysis/summary_dashboard/index.html; the data checks are in CATI/Analysis/fix/checks.csv."
}
