* =============================================================================
* 00_master.do: the whole real-time monitoring workflow, from the sampling frame to the dashboard, on synthetic data
* modelled on the L2PHL phone panel. Run this file; every output lands in output/.
*
*   Step 1  Frame and baseline           data/frame, data/baseline (provided; a face-to-face survey)
*   Step 2  Sample                       do/2_sample          (baseline PSUs, baseline weights, phone panel)
*   Step 3  Data management              do/3_data_management (KoBoToolbox export -> module files, checks, next preload)
*   Step 4  Call metadata                do/4_call_metadata   (form records or call-centre log -> one standard call file)
*   Step 5  Round weights                do/5_weights         (replacements, nonresponse, raking to totals)
*   Step 6  Dashboard                    do/6_dashboard       (output/dashboard/index.html)
*
* Stata 16 or later; no user-written commands. About 15 seconds.
* =============================================================================
clear all

* ---------------------------------------------------------------- the package folder (edit if you do not run from it)
if `"$RTM"' == "" global RTM `"`c(pwd)'"'
capture confirm file `"$RTM/do/_setup.do"'
if _rc {
    di as error `"Cannot find do/_setup.do under "$RTM". Set: global RTM "<folder of this file>""'
    exit 601
}
do `"$RTM/do/_setup.do"'
capture erase "$OUT/checks/checks.csv"
capture log close master
log using "$OUT/logs/master.log", replace text name(master)

* ---------------------------------------------------------------- step 2: sample (baseline weights, phone panel)
do "$DO/2_sample/21_select_psu.do"
do "$DO/2_sample/22_baseline_weights.do"
do "$DO/2_sample/23_phone_subsample.do"

* ---------------------------------------------------------------- steps 3-5, round by round
foreach r of global ROUNDS {
    do "$DO/3_data_management/31_import.do" `r'
    do "$DO/3_data_management/32_passport.do" `r'
    do "$DO/3_data_management/33_roster.do" `r'
    do "$DO/3_data_management/34_modules.do" `r'
    do "$DO/3_data_management/35_checks.do" `r'
    do "$DO/3_data_management/36_preload.do" `r'
    do "$DO/3_data_management/37_form_audit.do" `r'
    do "$DO/4_call_metadata/41_dials_from_kobo.do" `r'
    do "$DO/4_call_metadata/42_dials_from_callcentre.do" `r'
    do "$DO/4_call_metadata/43_cases.do" `r'
    do "$DO/5_weights/51_round_weights.do" `r'
}

* ---------------------------------------------------------------- across rounds
do "$DO/3_data_management/38_form_changes.do"
do "$DO/4_call_metadata/44_call_indicators.do"
do "$DO/4_call_metadata/45_enumerator_monitor.do"
do "$DO/6_dashboard/61_indicators.do"
do "$DO/6_dashboard/62_dashboard.do"

log close master
di as result _n "Done. Open output/dashboard/index.html; data checks are in output/checks/checks.csv."
