*! check_log: one line in CATI/Analysis/fix/checks.csv for every data check
*! check_log round step "what was checked" n_flagged "what was done"   (action "stop" with n > 0 ends the run)
*! round is a number, or "all" for a check across rounds (written as missing)
program define check_log
	args round step what n action
	tempname fh
	cap confirm file "$afix/checks.csv"
	if _rc ~= 0 {
		file open `fh' using "$afix/checks.csv", write text replace
		file write `fh' "round,step,check,n,action" _n
	}
	else file open `fh' using "$afix/checks.csv", write text append
	file write `fh' `"`=real("`round'")',`step',"`what'",`n',"`action'""' _n
	file close `fh'
	if ("`action'" == "stop" & `n' > 0) {
		di as error "CHECK FAILED (round `round', step `step'): `what' (`n'). The run stops here."
		exit 9
	}
end
