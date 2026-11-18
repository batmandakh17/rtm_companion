* =============================================================================
* 62_dashboard.do: the dashboard. Every table from steps 3, 4 and 6 goes into one JavaScript data file next to a
* fixed page (dashboard_template.html), so the dashboard opens from the folder with a double-click, offline, and a
* new round only needs the do-files rerun. Nothing is computed in the page; it only draws what Stata wrote.
* In:  output/calls/calls_*.csv, output/dashboard/indicators.csv, shock_types.csv, explorer.csv,
*      output/sample/sample_summary.csv, output/weights/summary_R##.csv,
*      output/checks/checks.csv, do/6_dashboard/dashboard_template.html
* Out: output/dashboard/index.html, output/dashboard/dashboard_data.js
* =============================================================================
local js "$OUT/dashboard/dashboard_data.js"
tempname fh
file open `fh' using "`js'", write text replace
file write `fh' "window.DATA = {};" _n
file write `fh' `"DATA.meta = {"program":"$PROGRAM","title":"L2PHL synthetic example","made":"`c(current_date)'","rounds":["'
local first 1
foreach r of global ROUNDS {
    if !`first' file write `fh' ","
    local first 0
    file write `fh' `"{"round":`r',"start":"${START_`r'}"}"'
}
file write `fh' "]};" _n
file close `fh'

foreach t in by_round by_dialno outcomes by_hour by_weekday by_day enumerators {
    import delimited "$OUT/calls/calls_`t'.csv", clear varnames(1) asdouble
    js_table using "`js'", name(DATA.`t') append
}
foreach t in indicators shock_types explorer {
    import delimited "$OUT/dashboard/`t'.csv", clear varnames(1) bindquote(strict) asdouble
    js_table using "`js'", name(DATA.`t') append
}
import delimited "$OUT/sample/sample_summary.csv", clear varnames(1) asdouble
js_table using "`js'", name(DATA.sample) append
clear
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    preserve
    import delimited "$OUT/weights/summary_R`rr'.csv", clear varnames(1) asdouble
    tempfile w`r'
    save `w`r''
    restore
    append using `w`r''
}
js_table using "`js'", name(DATA.weights) append
foreach t in audit {
    clear
    foreach r of global ROUNDS {
        local rr : display %02.0f `r'
        preserve
        import delimited "$OUT/checks/form_audit_R`rr'.csv", clear varnames(1) bindquote(strict) asdouble
        tempfile a`r'
        save `a`r''
        restore
        append using `a`r''
    }
    js_table using "`js'", name(DATA.audit) append
}
import delimited "$OUT/checks/form_changes.csv", clear varnames(1) bindquote(strict) asdouble
js_table using "`js'", name(DATA.form_changes) append
import delimited "$OUT/calls/calls_panel.csv", clear varnames(1) asdouble
js_table using "`js'", name(DATA.panel) append
import delimited "$OUT/calls/enumerator_monitor.csv", clear varnames(1) asdouble
js_table using "`js'", name(DATA.monitor) append
* the review lists a person should read, with their row counts
local files : dir "$OUT/checks/review" files "*.csv"
local files : list sort files
clear
set obs `: word count `files''
gen str60 file = ""
gen long rows = .
local i 0
foreach f of local files {
    local ++i
    preserve
    import delimited "$OUT/checks/review/`f'", clear varnames(1)
    local n = _N
    restore
    quietly replace file = "`f'" in `i'
    quietly replace rows = `n' in `i'
}
js_table using "`js'", name(DATA.reviews) append
import delimited "$OUT/checks/checks.csv", clear varnames(1) bindquote(strict) asdouble
js_table using "`js'", name(DATA.checks) append

copy "$DO/6_dashboard/dashboard_template.html" "$OUT/dashboard/index.html", replace
di as result "62_dashboard: open output/dashboard/index.html"
