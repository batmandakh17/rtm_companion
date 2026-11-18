* =============================================================================
* _setup.do: folders, round dates and helper programs used by every step.
* 00_master.do sets $RTM (this package's folder) and then runs this file.
* =============================================================================
version 16
set more off
set varabbrev off

if `"$RTM"' == "" {
    di as error `"Set the package folder first, e.g. global RTM "C:/work/rtm_companion" (00_master.do does this)."'
    exit 198
}
global DATA "$RTM/data"
global OUT  "$RTM/output"
global DO   "$RTM/do"
global PROGRAM "l2phl_syn"

* rounds and their first calling day: submissions dated earlier are practice interviews (step 3 drops them)
global ROUNDS 1 2 3
global START_1 "2026-03-02"
global START_2 "2026-04-06"
global START_3 "2026-05-04"

foreach d in "" /_raw /sample /modules /calls /weights /checks /dashboard /pii /logs {
    capture mkdir "$OUT`d'"
}
foreach r of global ROUNDS {
    local rr : display %02.0f `r'
    capture mkdir "$OUT/_raw/R`rr'"
    capture mkdir "$OUT/modules/R`rr'"
}

do "$DO/_programs.do"
