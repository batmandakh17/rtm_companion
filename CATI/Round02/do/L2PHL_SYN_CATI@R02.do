* L2PHL_SYN CATI ROUND 02: THE ROUND'S DO-FILE
* RTM companion package, synthetic data laid out like the L2PHL phone rounds
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* L2PHL keeps the full do-file of each round here, in Round##/do. This package keeps one do-file for every round in
* CATI/do (the rounds differ only in their form, which the do-file reads) and runs it from here with the round set:
* the export to module files, the household and roster level files, checks, the next preload, the skip-logic audit
* and the call logs, then the round weights. Run it from the package folder, or set glo wd to the package folder first.

* PREAMBLES
*-------------------------------------------------------------------------------
{
	clear
	if ("$wd" == "") glo wd "`c(pwd)'"
	glo R 02
}

********************************************************************************
**# ROUND 02
********************************************************************************
{
	do "$wd/CATI/do/L2PHL_SYN_CATI@R.do"
	do "$wd/CATI/do/L2PHL_SYN_CATI_wgt@R.do"
}
