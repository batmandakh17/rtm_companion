*! js_table: the data in memory as a JavaScript array, for the dashboard
*! js_table using file.js, name(DATA.key) [append]   ->   DATA.key = [{...}, ...];
program define js_table
	syntax using/, name(string) [append]
	tempname fh
	if ("`append'" ~= "") file open `fh' using `"`using'"', write text append
	else file open `fh' using `"`using'"', write text replace
	qui ds
	loc vars `r(varlist)'
	file write `fh' "`name' = ["
	forvalues i = 1/`=_N' {
		if (`i' > 1) file write `fh' ","
		file write `fh' _n "{"
		loc first 1
		foreach v of local vars {
			if (!`first') file write `fh' ","
			loc first 0
			cap confirm string variable `v'
			if _rc ~= 0 {
				loc x = `v'[`i']
				if missing(`x') loc x null
				else {
					loc x = strtrim(string(`x', "%20.10g"))
					if (substr("`x'", 1, 1) == ".") loc x 0`x'
					if (substr("`x'", 1, 2) == "-.") loc x = "-0" + substr("`x'", 2, .)
				}
				file write `fh' `""`v'":`x'"'
			}
			else {
				loc x = subinstr(subinstr(`v'[`i'], "\", "\\", .), `"""', `"\""', .)
				file write `fh' `""`v'":"`x'""'
			}
		}
		file write `fh' "}"
	}
	file write `fh' "];" _n
	file close `fh'
end
