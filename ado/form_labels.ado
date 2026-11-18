*! form_labels: variable and value labels from the XLSForm (survey and choices sheets)
*! form_labels using xlsform.xlsx
*! Labels every variable in memory that the form names: question text as the variable label, choice lists as value
*! labels (list names with "-" become "_"), and "question: choice" on each 0/1 column of a select_multiple.
program define form_labels
	syntax using/
	tempfile cmds data
	tempname fh
	qui save `data'
	import excel using `"`using'"', sheet("choices") firstrow allstring clear
	ren (list_name name) (list code)
	ren label* label
	file open `fh' using `cmds', write text replace
	forvalues i = 1/`=_N' {
		loc l = subinstr(list[`i'], "-", "_", .)
		loc c = code[`i']
		loc t = subinstr(label[`i'], `"""', "'", .)
		if (real("`c'") < .) {
			file write `fh' `"cap la def `l' `c' `"`t'"', modify"' _n
			loc codes_`l' `codes_`l'' `c'
			loc lab_`l'_`c' `"`t'"'
		}
	}
	import excel using `"`using'"', sheet("survey") firstrow allstring clear
	ren label* label
	replace label = subinstr(subinstr(label, char(36) + "{", "[", .), "}", "]", .)
	replace label = subinstr(label, `"""', "'", .)
	forvalues i = 1/`=_N' {
		loc v = lower(name[`i'])
		loc ty = word(type[`i'], 1)
		loc li = subinstr(word(type[`i'], 2), "-", "_", .)
		loc t = usubstr(label[`i'], 1, 80)
		if ("`v'" == "" | inlist("`ty'", "begin_group", "end_group", "begin_repeat", "end_repeat", "note")) continue
		if `"`t'"' ~= "" file write `fh' `"cap la var `v' `"`t'"'"' _n
		if ("`ty'" == "select_one") file write `fh' `"cap la val `v' `li'"' _n
		if ("`ty'" == "select_multiple") {
			loc short = usubstr(word(label[`i'], 1), 1, 12)
			foreach c of local codes_`li' {
				loc cl = usubstr(`"`lab_`li'_`c''"', 1, 60)
				file write `fh' `"cap la var `v'`c' `"`short' `cl'"'"' _n
			}
		}
	}
	file close `fh'
	use `data', clear
	qui do `cmds'
end
