*! review_list: the rows a person should look at before the round is closed (the run goes on)
*! review_list round name [if]  ->  $fix/R##_name.csv. These lists hold household IDs: keep them with the team.
program define review_list
	syntax anything(name=args) [if]
	gettoken round name : args
	loc name = strtrim("`name'")
	loc rr : di %02.0f real("`round'")
	preserve
		if `"`if'"' ~= "" qui keep `if'
		if (_N > 0) export delimited using "$fix/R`rr'_`name'.csv", replace
		else cap erase "$fix/R`rr'_`name'.csv"
	restore
end
