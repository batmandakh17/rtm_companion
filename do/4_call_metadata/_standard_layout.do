* _standard_layout.do: the standard dial file's variables, order and labels (docs/call_log_standard.md).
* Outcome codes are the L2PHL result codes (X15); other sources are mapped onto them.
label define outcome 1 "Complete" 2 "Partially complete, no more callback" 3 "Partially complete, callback" ///
    4 "Not yet started, callback" 5 "Refused" 6 "Nobody answering" 7 "Number does not exist" ///
    8 "Phone off / not in service" 9 "Does not know the household" 10 "Reference person cannot connect", replace
label values outcome outcome
capture drop dur_min complete
gen double dur_min = (dial_end - dial_start) / 60000
replace dur_min = . if dur_min < 0
gen byte complete = inlist(outcome, 1, 2)
label variable program "Program"
label variable round "Round"
label variable hhid "Household ID"
label variable enumerator "Enumerator (program code)"
label variable seq "Dial number for the household this round (by time)"
label variable dial_start "Dial start (local time)"
label variable dial_end "Dial end (local time)"
label variable dur_min "Dial length (minutes)"
label variable outcome "Result of the dial"
label variable contact "Someone answered"
label variable complete "Dial ended in a complete interview"
label variable source "Source of the record"
label variable dial_id "Record ID in the source"
keep program round hhid enumerator seq dial_start dial_end dur_min outcome contact complete source dial_id
order program round hhid enumerator seq dial_start dial_end dur_min outcome contact complete source dial_id
sort hhid seq
compress
