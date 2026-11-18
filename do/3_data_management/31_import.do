* =============================================================================
* 31_import.do (round): every sheet of the round's KoBoToolbox export into Stata, as it is.
* The export is the .xlsx KoBo writes with "XML values and headers": one sheet for the form's main level (one row per
* submission, here one per call attempt) and one sheet per repeat group (rows linked to their submission by
* _parent_index = the main sheet's _index). If the folder holds several exports, the latest (by file name) is read.
* In:  data/raw/R##, the file named <form>_-_all_versions_-_<date>.xlsx
* Out: output/_raw/R##/<sheet>.dta (main.dta for the main sheet). Still holds names and numbers: never share _raw.
* =============================================================================
args r
local rr : display %02.0f `r'
local dir "$DATA/raw/R`rr'"
local files : dir "`dir'" files "*_-_all_versions_-_*.xlsx"
local files : list sort files
local n : word count `files'
if `n' == 0 {
    di as error "31_import: no KoBo export in `dir'"
    exit 601
}
local f : word `n' of `files'

quietly import excel using "`dir'/`f'", describe
local ns = r(N_worksheet)
forvalues i = 1/`ns' {
    local sh`i' = r(worksheet_`i')
}
forvalues i = 1/`ns' {
    kobo_import using "`dir'/`f'", sheet("`sh`i''") form("$DATA/form/L2PHL_SYN_CATI_R`rr'.xlsx") keepstring(oldcp oldrespo replacement_hhid)
    local name = cond(`i' == 1, "main", "`sh`i''")
    gen int round = `r'
    save "$OUT/_raw/R`rr'/`name'.dta", replace
    check_log `r' 3 "rows read from sheet `sh`i''" `=_N' "imported"
}
di as result "31_import R`rr': `ns' sheets from `f'"
