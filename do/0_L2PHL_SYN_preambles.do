* L2PHL_SYN: PREAMBLES (globals, folders, ado path) shared by every do-file of the package
* RTM companion package, synthetic data laid out like the L2PHL phone rounds
* last modified: 18 Nov 2026
*-------------------------------------------------------------------------------
* Every stage file runs this once. $wd is the package folder; the master sets it, or set it yourself:
*     glo wd "<folder of L2PHL_SYN_master.do>"
* Folders follow the L2 programs' names: raw/xls = the KoBo export, zzz = the export in Stata, dta = module files,
* call = call files, fix = checks and review lists, wgt = weights, pii = names and numbers. One folder per round
* (output/R01, R02, ...), the baseline and sample under R00, everything across rounds under analysis/.

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
	cap confirm file "$wd/do/0_L2PHL_SYN_preambles.do"
	if _rc ~= 0 {
		di as error `"$wd is not the package folder (do/0_L2PHL_SYN_preambles.do not found)"'
		exit 601
	}

	* Program and rounds
	********************
	glo dta_file l2phl_syn			// prefix of every module file: l2phl_syn_R01_M00_passport.dta
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
	glo data "$wd/data"
	glo out  "$wd/output"
	glo do   "$wd/do"
	glo ado  "$wd/ado"
	glo tests "$wd/tests"

	cap mkdir "$out"
	foreach dir in R00 R00/sample R00/pii analysis analysis/call analysis/fix analysis/dashboard analysis/dta logs {
		cap mkdir "$out/`dir'"
	}
	glo smpl  "$out/R00/sample"			// PSU selection, baseline weights, phone sample
	glo acall "$out/analysis/call"		// call indicators across rounds, enumerator lookup
	glo afix  "$out/analysis/fix"		// checks.csv, form changes
	glo tab   "$out/analysis/dashboard"	// the dashboard and its tables
	glo adta  "$out/analysis/dta"		// files kept across rounds (roster master)
	glo logs  "$out/logs"

	* Ado folder: the package's own commands (check_log, review_list, kobo_import, form_labels, js_table,
	* xls2stata, preload_order, call_layout, setround)
	****************************************************
	cap adopath - "$ado"
	adopath + "$ado"							// after editing an ado file in a running session: discard
}
