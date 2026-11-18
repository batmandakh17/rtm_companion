*! kobo_import: one sheet of a KoBoToolbox export, names in lower case, numbers made numeric
*! kobo_import using export.xlsx, sheet(name) [form(xlsform) keepstring(varlist)]
*! KoBo writes codes as text. Columns that read as numbers become numeric, except the form's text, date and time
*! questions (read from form()) and the variables in keepstring() (phone numbers keep their leading zeros), which
*! stay text even when empty. Variable labels keep the export's column names (e.g. "SH1b_/1").
program define kobo_import
	syntax using/, sheet(string) [form(string) keepstring(string)]
	loc keep = lower(`"`keepstring'"')
	if `"`form'"' ~= "" {
		import excel using `"`form'"', sheet("survey") firstrow allstring clear
		qui keep if inlist(word(type, 1), "text", "date", "time", "start", "end", "deviceid", "select_multiple")
		forvalues i = 1/`=_N' {
			loc keep `keep' `=lower(name[`i'])'
		}
	}
	import excel using `"`using'"', sheet(`"`sheet'"') firstrow allstring clear
	ren *, lower
	qui ds
	loc all `r(varlist)'
	loc keep : list keep & all
	loc num : list all - keep
	if ("`num'" ~= "" & _N > 0) qui destring `num', replace
end
