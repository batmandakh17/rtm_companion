* =============================================================================
* 38_form_changes.do: what changed in the form from one round to the next: questions added or dropped, a question's
* type or wording changed, a choice list with a different number of options. A question that leaves and comes back
* is a rotating module. Read from the forms themselves, so the list is complete whatever the round notes say.
* In:  data/form/L2PHL_SYN_CATI_R##.xlsx
* Out: output/checks/form_changes.csv
* =============================================================================
tempfile all cur
tempname ph
postfile `ph' int from_round to_round str12 change str32 variable str100 label using `cur', replace
local prev
clear
save `all', emptyok
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    import excel using "$DATA/form/L2PHL_SYN_CATI_R`rr'.xlsx", sheet("choices") firstrow allstring clear
    rename list_name list
    contract list, freq(n_options)
    tempfile ch
    save `ch'
    import excel using "$DATA/form/L2PHL_SYN_CATI_R`rr'.xlsx", sheet("survey") firstrow allstring clear
    rename label* label
    gen vtype = word(type, 1)
    keep if inlist(vtype, "select_one", "select_multiple", "integer", "decimal", "text", "date", "time", "select_one_from_file")
    gen vname = lower(name)
    gen list = word(type, 2)
    merge m:1 list using `ch', keep(master match) nogenerate
    replace label = usubstr(subinstr(subinstr(label, char(36) + "{", "[", .), "}", "]", .), 1, 100)
    gen int round = `r'
    keep round vname vtype label n_options
    append using `all'
    save `all', replace
}
use `all', clear
sort vname round
levelsof round, local(rs)
local last
foreach r of local rs {
    if "`last'" != "" {
        preserve
        keep if inlist(round, `last', `r')
        gen byte new = round == `r'
        bysort vname: egen byte in_prev = max(!new)
        bysort vname: egen byte in_new = max(new)
        bysort vname (round): gen str40 t0 = vtype[1]
        bysort vname (round): gen str100 l0 = label[1]
        bysort vname (round): gen n0 = n_options[1]
        forvalues i = 1/`=_N' {
            if new[`i'] & !in_prev[`i'] post `ph' (`last') (`r') ("added") (vname[`i']) (label[`i'])
            if !new[`i'] & !in_new[`i'] post `ph' (`last') (`r') ("dropped") (vname[`i']) (label[`i'])
            if new[`i'] & in_prev[`i'] {
                if vtype[`i'] != t0[`i'] post `ph' (`last') (`r') ("type") (vname[`i']) (label[`i'])
                else if label[`i'] != l0[`i'] post `ph' (`last') (`r') ("wording") (vname[`i']) (label[`i'])
                else if n_options[`i'] != n0[`i'] post `ph' (`last') (`r') ("options") (vname[`i']) (label[`i'])
            }
        }
        restore
    }
    local last `r'
}
postclose `ph'
use `all', clear
bysort vname: egen byte n_rounds = count(round)
bysort vname (round): gen byte gap = round - round[_n-1] > 1 if _n > 1
bysort vname: egen byte has_gap = max(gap)
local nr : word count `rs'
keep if has_gap == 1 | (n_rounds < `nr' & round != `: word 1 of `rs'' & round != `: word `nr' of `rs'')
keep vname has_gap
duplicates drop
rename vname variable
gen byte rotating = 1
tempfile rot
save `rot'
use `cur', clear
merge m:1 variable using `rot', keep(master match) keepusing(rotating) nogenerate
replace rotating = 0 if missing(rotating)
sort from_round to_round change variable
export delimited using "$OUT/checks/form_changes.csv", replace
di as result "38_form_changes: " _N " changes between rounds"
