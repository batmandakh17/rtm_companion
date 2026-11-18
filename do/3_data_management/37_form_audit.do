* =============================================================================
* 37_form_audit.do (round): the skip-logic audit. The checks read their conditions from the form itself. For every
* question, the audit takes its routing (the relevant column, together with the conditions of the groups and repeats
* it sits in), whether it is required, and its constraint, and counts:
*   base              rows where the routing says the question should have been asked
*   answered          rows with an answer
*   routing_broken    an answer where the routing says the question was not asked
*   required_missing  a required question left empty where it should have been asked
*   out_of_range      an answer that fails the question's constraint
* Call-record questions (the local callrecord) are audited on every kept call attempt; the other questions on
* completed interviews only, because a partial interview stops early by design. A rule the translator cannot read
* (xls2stata in _programs.do) is reported as "not translated" and the question is skipped. The flags are also summed
* by enumerator for the monitoring view, and every flagged row is listed by household ID (with the submission, the
* repeat row, the question and the answer) in a review list for the team.
* In:  data/form/L2PHL_SYN_CATI_R##.xlsx, output/_raw/R##/submissions_flagged.dta and the repeat sheets
* Out: output/checks/form_audit_R##.csv, form_audit_enum_R##.csv, output/checks/review/R##_form_flags.csv
* =============================================================================
args r
local rr : display %02.0f `r'
local form "$DATA/form/L2PHL_SYN_CATI_R`rr'.xlsx"
local callrecord int_id hhid d3 z6 z7 z8 call_status1 z17 z9 z18 z18_oth x15 x16
tempfile rules parents res enum list pp
tempname ph pe pl

* ---------------------------------------------------------------- 1. the questions and their effective rules
import excel using "`form'", sheet("survey") firstrow allstring clear
rename label* label
gen vtype = word(type, 1)
gen vname = lower(name)
gen byte req = lower(required) == "yes"
foreach v in relevant constraint {
    gen `v'_st = subinstr(subinstr(lower(`v'), char(36) + "{", "", .), "}", "", .)
    gen `v'_tk = subinstr(subinstr(lower(`v'), char(36) + "{", " @", .), "}", " ", .)
    gen `v'_txt = subinstr(subinstr(`v', char(36) + "{", "[", .), "}", "]", .)
}
replace label = subinstr(subinstr(label, char(36) + "{", "[", .), "}", "]", .)
replace label = subinstr(label, `"""', "'", .)
replace label = usubstr(label, 1, 100)
gen str20 sheet = ""
gen str244 eff = ""
gen str244 eff_tk = ""
gen str244 rule = ""
local depth 0
local sh0 main
forvalues i = 1/`=_N' {
    local t = vtype[`i']
    if inlist("`t'", "begin_group", "begin_repeat") {
        local ++depth
        local rel`depth' = relevant_st[`i']
        local tk`depth' = relevant_tk[`i']
        local txt`depth' = relevant_txt[`i']
        local prev = `depth' - 1
        local sh`depth' = cond("`t'" == "begin_repeat", vname[`i'], "`sh`prev''")
        continue
    }
    if inlist("`t'", "end_group", "end_repeat") {
        local --depth
        continue
    }
    local e 1
    local k
    local x
    forvalues d = 1/`depth' {
        if `"`rel`d''"' != "" {
            local e `"`e' and (`rel`d'')"'
            local k `"`k' `tk`d''"'
            local x `"`x'; `txt`d''"'
        }
    }
    if relevant_st[`i'] != "" {
        local e `"`e' and (`=relevant_st[`i']')"'
        local k `"`k' `=relevant_tk[`i']'"'
        local x `"`x'; `=relevant_txt[`i']'"'
    }
    quietly replace sheet = "`sh`depth''" in `i'
    quietly replace eff = `"`e'"' in `i'
    quietly replace eff_tk = `"`k'"' in `i'
    quietly replace rule = substr(`"`x'"', 3, .) in `i'
}
keep if inlist(vtype, "select_one", "select_multiple", "integer", "decimal", "text", "date", "time", "select_one_from_file")
gen byte callrec = 0
foreach v of local callrecord {
    quietly replace callrec = 1 if vname == "`v'"
}
keep vname vtype label req callrec sheet eff eff_tk rule constraint_st constraint_tk constraint_txt
save `rules'

* ---------------------------------------------------------------- 2. the submissions the audit runs on
use "$OUT/_raw/R`rr'/submissions_flagged.dta", clear
drop if f_practice | f_duplicate
save `parents'

* ---------------------------------------------------------------- 3. sheet by sheet, question by question
postfile `ph' int round str20 sheet str32 variable str100 label str244 rule str100 constraint byte required ///
    long base answered routing_broken required_missing out_of_range str28 status using `res', replace
postfile `pe' int round long int_id str32 variable long flags using `enum', replace
postfile `pl' int round double hhid long submission long row long int_id str20 sheet str32 variable ///
    str20 flag str244 value using `list', replace
use `rules', clear
levelsof sheet, local(sheets)
foreach sh of local sheets {
    use `rules', clear
    keep if sheet == "`sh'"
    local need
    local nq = _N
    forvalues i = 1/`nq' {
        local tk = eff_tk[`i'] + " " + constraint_tk[`i']
        foreach w of local tk {
            if substr("`w'", 1, 1) == "@" local need `need' `=substr("`w'", 2, .)'
        }
        local v`i' = vname[`i']
        local lab`i' = label[`i']
        local eff`i' = eff[`i']
        local con`i' = constraint_st[`i']
        local ctx`i' = constraint_txt[`i']
        local rule`i' = rule[`i']
        local req`i' = req[`i']
        local cr`i' = callrec[`i']
    }
    local need : list uniq need
    if "`sh'" == "main" use `parents', clear
    else {
        use "$OUT/_raw/R`rr'/`sh'.dta", clear
        quietly ds
        local have `r(varlist)'
        local get : list need - have
        preserve
        use `parents', clear
        quietly ds
        local pv `r(varlist)'
        local get : list get & pv
        local keepv _parent_index complete int_id hhid _id
        local get : list get - keepv
        rename _index _parent_index
        keep `keepv' `get'
        save `pp', replace
        restore
        merge m:1 _parent_index using `pp', keep(match) nogenerate
    }
    if "`sh'" == "main" gen long __row = .
    else gen long __row = _index
    forvalues i = 1/`nq' {
        local v `v`i''
        capture confirm variable `v'
        if _rc {
            post `ph' (`r') ("`sh'") ("`v'") (`"`lab`i''"') (`"`rule`i''"') (`"`ctx`i''"') (`req`i'') (.) (.) (.) (.) (.) ("not in export")
            continue
        }
        capture drop __rel __ans __ok __base __run __flag __f1 __f2 __f3 __val
        local status ok
        xls2stata, expr(`"`eff`i''"') self(`v')
        if !r(ok) local status "not translated"
        else {
            capture gen byte __rel = (`r(expr)')
            if _rc local status "not translated"
        }
        if "`status'" != "ok" {
            post `ph' (`r') ("`sh'") ("`v'") (`"`lab`i''"') (`"`rule`i''"') (`"`ctx`i''"') (`req`i'') (.) (.) (.) (.) (.) ("`status'")
            continue
        }
        quietly replace __rel = 0 if missing(__rel)
        gen byte __run = `cr`i'' | complete
        gen byte __base = __rel & __run
        capture confirm string variable `v'
        if _rc gen byte __ans = !missing(`v')
        else gen byte __ans = `v' != ""
        gen byte __ok = 1
        local cstat ok
        if `"`con`i''"' != "" {
            capture confirm numeric variable `v'
            if _rc local cstat "constraint not translated"
            else {
                xls2stata, expr(`"`con`i''"') self(`v')
                if r(ok) {
                    capture replace __ok = (`r(expr)') if __ans
                    if _rc local cstat "constraint not translated"
                }
                else local cstat "constraint not translated"
            }
        }
        quietly count if __base
        local base = r(N)
        quietly count if __run & __ans
        local ans = r(N)
        quietly count if __run & __ans & !__base
        local rb = r(N)
        quietly count if __base & !__ans & `req`i''
        local rm = r(N)
        quietly count if __run & __ans & !__ok
        local oor = cond("`cstat'" == "ok", r(N), .)
        post `ph' (`r') ("`sh'") ("`v'") (`"`lab`i''"') (`"`rule`i''"') (`"`ctx`i''"') (`req`i'') (`base') (`ans') (`rb') (`rm') (`oor') ("`cstat'")
        gen byte __f1 = __run & __ans & !__base
        gen byte __f2 = __base & !__ans & `req`i''
        gen byte __f3 = __run & __ans & !__ok
        gen byte __flag = __f1 | __f2 | __f3
        capture confirm string variable `v'
        if _rc gen str244 __val = cond(__ans, string(`v', "%12.0g"), "")
        else gen str244 __val = `v'
        quietly count if __flag
        if r(N) > 0 {
            preserve
            keep if __flag
            forvalues j = 1/`=_N' {
                if __f1[`j'] post `pl' (`r') (hhid[`j']) (_id[`j']) (__row[`j']) (int_id[`j']) ("`sh'") ("`v'") ("routing_broken") (__val[`j'])
                if __f2[`j'] post `pl' (`r') (hhid[`j']) (_id[`j']) (__row[`j']) (int_id[`j']) ("`sh'") ("`v'") ("required_missing") (__val[`j'])
                if __f3[`j'] post `pl' (`r') (hhid[`j']) (_id[`j']) (__row[`j']) (int_id[`j']) ("`sh'") ("`v'") ("out_of_range") (__val[`j'])
            }
            collapse (count) flags = __flag, by(int_id)
            forvalues j = 1/`=_N' {
                post `pe' (`r') (int_id[`j']) ("`v'") (flags[`j'])
            }
            restore
        }
    }
}
postclose `ph'
postclose `pe'
postclose `pl'

use `res', clear
quietly summarize routing_broken
check_log `r' 3 "skip-logic audit: answers recorded where the routing says the question was not asked" `r(sum)' "listed by question and by household"
quietly summarize required_missing
check_log `r' 3 "skip-logic audit: required answers missing where the question was asked" `r(sum)' "listed by question and by household"
quietly summarize out_of_range
check_log `r' 3 "skip-logic audit: answers outside the form's constraints" `r(sum)' "listed by question and by household"
quietly count if status == "not translated"
check_log `r' 3 "skip-logic audit: questions whose routing rule the audit could not read" `r(N)' "listed"
export delimited using "$OUT/checks/form_audit_R`rr'.csv", replace

use `enum', clear
collapse (sum) flags, by(int_id)
merge 1:1 int_id using "$OUT/calls/enumerators.dta", keep(match using) nogenerate keepusing(enumerator)
replace flags = 0 if missing(flags)
gen int round = `r'
order round enumerator int_id flags
export delimited using "$OUT/checks/form_audit_enum_R`rr'.csv", replace

* the flagged rows by household: hhid, the submission (_id in the export), the row in the repeat sheet (row, empty
* for the main sheet), the enumerator, the question, the flag and the answer as recorded. For the team only.
use `list', clear
sort hhid submission sheet row variable flag
review_list `r' form_flags
di as result "37_form_audit R`rr': done"
