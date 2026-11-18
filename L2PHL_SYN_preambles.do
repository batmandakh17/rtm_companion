* L2PHL_SYN: PREAMBLES (globals, folders, ado path) shared by every do-file of the package
* RTM companion package, synthetic data laid out like the L2PHL phone rounds
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* Every stage file runs this once. $wd is the package folder; the master sets it, or set it yourself:
*     glo wd "<folder of L2PHL_SYN_master.do>"
* The folders are L2PHL's: CAPI/ is the baseline (round 00), CATI/Round##/ one folder per phone round, CATI/Analysis/
* the work across rounds (HF/ is filled with the latest files of every round, then appended, finalized and harmonized
* there; 2share/ holds the files to share). Inside a stage folder, xls and kobo hold what was received, ado reference
* files, and the run writes dated subfolders, one per export date: zzz (the export in Stata), dta (module files), call,
* fix (checks and review lists), aud (the skip-logic audit), wgt (weights), pii (names and numbers).

* PREAMBLES
*-------------------------------------------------------------------------------
{
	version 16
	set more off
	set varabbrev off

	if ("$wd" == "") {
		di as error `"Set the package folder first:  glo wd "<folder of L2PHL_SYN_master.do>""'
		exit 198
	}
	cap confirm file "$wd/L2PHL_SYN_preambles.do"
	if _rc ~= 0 {
		di as error `"$wd is not the package folder (L2PHL_SYN_preambles.do not found)"'
		exit 601
	}

	* Program and rounds
	********************
	glo dta_file l2phl_syn			// prefix of every module file: l2phl_syn_<export date>_M00_passport.dta
	glo ROUNDS 1 2 3
	glo START_1 "2026-03-02"		// first calling day of each round: earlier submissions are practice
	glo START_2 "2026-04-06"
	glo START_3 "2026-05-04"

	* Choices
	********************
	if ("$WEIGHTS" == "")    glo WEIGHTS cellpost		// round weights: cellpost (L2PHL's cell post-stratification),
														// rake or ebalance; set before the run to change it
	if ("$CALLSOURCE" == "") glo CALLSOURCE callcentre	// cases from the call-centre log when there is one, else the form

	* Folders
	********************
	glo capi  "$wd/CAPI"						// the baseline: ado (frame, census), raw (the interviews), do, dta, pii
	glo cati  "$wd/CATI"						// the phone rounds: KOBO (the forms), ado, do, Round##, Analysis
	glo anl   "$cati/Analysis"
	glo kobo  "$cati/KOBO"
	glo ado   "$wd/ado"
	glo tests "$wd/tests"

	foreach dir in HF 2share call fix summary_dashboard {
		cap mkdir "$anl/`dir'"
	}
	glo hf    "$anl/HF"					// R00, R##: the latest files of every round; then the appended and final files
	glo share "$anl/2share"				// the household and individual files to share
	glo acall "$anl/call"				// call indicators across rounds
	glo afix  "$anl/fix"				// checks.csv, form changes
	glo tab   "$anl/summary_dashboard"	// the dashboard and its tables

	* Ado folder: the package's own commands (check_log, review_list, kobo_import, form_labels, js_table,
	* xls2stata, preload_order, call_layout, setround, rounddate)
	****************************************************
	cap adopath - "$ado"
	adopath + "$ado"							// after editing an ado file in a running session: discard

	* The baseline's date (its last interview day) names its dated folders; $smpl holds its sample files
	********************
	rounddate 0
	glo capi_date "`r(date)'"
	cap mkdir "$capi/dta"
	cap mkdir "$capi/dta/$capi_date"
	glo smpl "$capi/dta/$capi_date"		// PSU selection, baseline weights, phone sample, roster master
}
