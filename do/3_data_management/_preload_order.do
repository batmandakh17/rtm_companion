* _preload_order.do: the preload's fixed layout (the form's pulldata() calls read these column names).
* Members 1-15 side by side; columns for members a household does not have stay empty.
forvalues k = 1/15 {
    foreach v in age sex perm emp {
        capture confirm variable `v'`k'
        if _rc gen `v'`k' = .
    }
    capture confirm variable name`k'
    if _rc gen name`k' = ""
}
local mem
forvalues k = 1/15 {
    local mem `mem' name`k' age`k' sex`k' perm`k' emp`k'
}
keep hhid hhsize fmid_max sample round_lastint name cp psu stratum `mem'
order hhid hhsize fmid_max sample round_lastint name cp psu stratum `mem'
sort hhid
