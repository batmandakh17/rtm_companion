*! preload_order: the preload's fixed layout (the form's pulldata() calls read these column names)
*! Members 1-15 side by side; columns for members a household does not have stay empty.
program define preload_order
	forvalues k = 1/15 {
		foreach v in age sex perm emp {
			cap confirm variable `v'`k'
			if _rc ~= 0 g `v'`k' = .
		}
		cap confirm variable name`k'
		if _rc ~= 0 g name`k' = ""
	}
	loc mem
	forvalues k = 1/15 {
		loc mem `mem' name`k' age`k' sex`k' perm`k' emp`k'
	}
	keep  hhid hhsize fmid_max sample round_lastint name cp psu stratum `mem'
	order hhid hhsize fmid_max sample round_lastint name cp psu stratum `mem'
	sort hhid
end
