* =============================================================================
* _programs.do: small programs the steps share.
*   kobo_import   one sheet of a KoBoToolbox export, names in lower case, numbers made numeric
*   form_labels   variable and value labels from the XLSForm (survey and choices sheets)
*   check_log     one line in output/checks/checks.csv for every data check; action "stop" ends the run
*   review_list   rows for a person to look at, in output/checks/review
*   js_table      the data in memory as a JavaScript array (for the dashboard)
* =============================================================================

capture program drop kobo_import
program define kobo_import
    * KoBo writes codes as text. Columns that read as numbers become numeric, except the form's text, date and time
    * questions (read from form()) and the variables in keepstring() (phone numbers keep their leading zeros), which
    * stay text even when empty. Variable labels keep the export's column names (e.g. "SH1b_/1").
    syntax using/, sheet(string) [form(string) keepstring(string)]
    local keep = lower(`"`keepstring'"')
    if `"`form'"' != "" {
        import excel using `"`form'"', sheet("survey") firstrow allstring clear
        quietly keep if inlist(word(type, 1), "text", "date", "time", "start", "end", "deviceid", "select_multiple")
        forvalues i = 1/`=_N' {
            local keep `keep' `=lower(name[`i'])'
        }
    }
    import excel using `"`using'"', sheet(`"`sheet'"') firstrow allstring clear
    rename *, lower
    quietly ds
    local all `r(varlist)'
    local keep : list keep & all
    local num : list all - keep
    if "`num'" != "" & _N > 0 quietly destring `num', replace
end

capture program drop form_labels
program define form_labels
    * Labels every variable in memory that the form names: question text as the variable label, choice lists as value
    * labels (list names with "-" become "_"), and "question: choice" on each 0/1 column of a select_multiple.
    syntax using/
    tempfile cmds data
    tempname fh
    quietly save `data'
    import excel using `"`using'"', sheet("choices") firstrow allstring clear
    rename (list_name name) (list code)
    rename label* label
    file open `fh' using `cmds', write text replace
    forvalues i = 1/`=_N' {
        local l = subinstr(list[`i'], "-", "_", .)
        local c = code[`i']
        local t = subinstr(label[`i'], `"""', "'", .)
        if real("`c'") < . {
            file write `fh' `"capture label define `l' `c' `"`t'"', modify"' _n
            local codes_`l' `codes_`l'' `c'
            local lab_`l'_`c' `"`t'"'
        }
    }
    import excel using `"`using'"', sheet("survey") firstrow allstring clear
    rename label* label
    replace label = subinstr(subinstr(label, char(36) + "{", "[", .), "}", "]", .)
    replace label = subinstr(label, `"""', "'", .)
    forvalues i = 1/`=_N' {
        local v = lower(name[`i'])
        local ty = word(type[`i'], 1)
        local li = subinstr(word(type[`i'], 2), "-", "_", .)
        local t = usubstr(label[`i'], 1, 80)
        if "`v'" == "" | inlist("`ty'", "begin_group", "end_group", "begin_repeat", "end_repeat", "note") continue
        if `"`t'"' != "" file write `fh' `"capture label variable `v' `"`t'"'"' _n
        if "`ty'" == "select_one" file write `fh' `"capture label values `v' `li'"' _n
        if "`ty'" == "select_multiple" {
            local short = usubstr(word(label[`i'], 1), 1, 12)
            foreach c of local codes_`li' {
                local cl = usubstr(`"`lab_`li'_`c''"', 1, 60)
                file write `fh' `"capture label variable `v'`c' `"`short' `cl'"'"' _n
            }
        }
    }
    file close `fh'
    use `data', clear
    quietly do `cmds'
end

capture program drop check_log
program define check_log
    * check_log round step "what was checked" n_flagged "what was done"
    args round step what n action
    capture confirm file "$OUT/checks/checks.csv"
    tempname fh
    if _rc {
        file open `fh' using "$OUT/checks/checks.csv", write text replace
        file write `fh' "round,step,check,n,action" _n
    }
    else file open `fh' using "$OUT/checks/checks.csv", write text append
    file write `fh' `"`round',`step',"`what'",`n',"`action'""' _n
    file close `fh'
    if "`action'" == "stop" & `n' > 0 {
        di as error "CHECK FAILED (round `round', step `step'): `what' (`n'). The run stops here."
        exit 9
    }
end

capture program drop review_list
program define review_list
    * review_list round name if: the rows a person should look at before the round is closed (the run goes on);
    * written to output/checks/review/R##_name.csv. These lists hold household IDs: keep them with the team.
    syntax anything(name=args) [if]
    gettoken round name : args
    local name = strtrim("`name'")
    local rr : display %02.0f `round'
    capture mkdir "$OUT/checks/review"
    preserve
    if `"`if'"' != "" quietly keep `if'
    if _N > 0 export delimited using "$OUT/checks/review/R`rr'_`name'.csv", replace
    else capture erase "$OUT/checks/review/R`rr'_`name'.csv"
    restore
end

capture program drop js_table
program define js_table
    * js_table using file, name(DATA.key) [append]: writes the data in memory as  name = [{...}, ...];
    syntax using/, name(string) [append]
    tempname fh
    if "`append'" != "" file open `fh' using `"`using'"', write text append
    else file open `fh' using `"`using'"', write text replace
    quietly ds
    local vars `r(varlist)'
    file write `fh' "`name' = ["
    forvalues i = 1/`=_N' {
        if `i' > 1 file write `fh' ","
        file write `fh' _n "{"
        local first 1
        foreach v of local vars {
            if !`first' file write `fh' ","
            local first 0
            capture confirm string variable `v'
            if _rc {
                local x = `v'[`i']
                if missing(`x') local x null
                else {
                    local x = strtrim(string(`x', "%20.10g"))
                    if substr("`x'", 1, 1) == "." local x 0`x'
                    if substr("`x'", 1, 2) == "-." local x = "-0" + substr("`x'", 2, .)
                }
                file write `fh' `""`v'":`x'"'
            }
            else {
                local x = subinstr(subinstr(`v'[`i'], "\", "\\", .), `"""', `"\""', .)
                file write `fh' `""`v'":"`x'""'
            }
        }
        file write `fh' "}"
    }
    file write `fh' "];" _n
    file close `fh'
end

capture program drop xls2stata
program define xls2stata, rclass
    * An XLSForm logic expression (relevant or constraint column, with the ${ } already stripped from the names and
    * everything in lower case) as a Stata expression: r(expr), with r(ok) = 1. The translator knows =, !=, <, <=,
    * >, >=, and, or, not(), true(), false(), selected(x, 'c') (the option's 0/1 column) and "." for the question's
    * own value (self()). Anything else, such as indexed-repeat() or regex(), gives r(ok) = 0.
    syntax, expr(string) self(string)
    local e = ustrlower(`"`expr'"')
    foreach bad in "indexed-repeat" "position(" "count(" "count-selected" "selected-at" "pulldata" "jr:" "''" "regex(" "concat(" "if(" {
        if strpos(`"`e'"', "`bad'") {
            return scalar ok = 0
            exit
        }
    }
    while regexm(`"`e'"', "selected\(([a-z0-9_.]+), *'([0-9]+)'\)") {
        local v = regexs(1)
        local c = regexs(2)
        if "`v'" == "." local v `self'
        local e = regexr(`"`e'"', "selected\(([a-z0-9_.]+), *'([0-9]+)'\)", "(`v'`c'==1)")
    }
    foreach op in ">=" "<=" "!=" ">" "<" "=" {
        local e = subinstr(`"`e'"', ".`op'", "`self'`op'", .)
    }
    local e = subinstr(`"`e'"', "'", "", .)
    local e = subinstr(`"`e'"', " and ", " & ", .)
    local e = subinstr(`"`e'"', " or ", " | ", .)
    local e = subinstr(`"`e'"', "not(", "!(", .)
    local e = subinstr(`"`e'"', "true()", "1", .)
    local e = subinstr(`"`e'"', "false()", "0", .)
    while regexm(`"`e'"', "^(.*[^<>=!])=([^=].*)$") {
        local e = regexs(1) + "==" + regexs(2)
    }
    return local expr `"`e'"'
    return scalar ok = 1
end
