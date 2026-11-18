*! call_layout: the standard dial file's variables, order and labels (docs/call_log_standard.md)
*! Outcome codes are the L2PHL result codes (X15); other sources are mapped onto them.
program define call_layout
	la def outcome 1 "Complete" 2 "Partially complete, no more callback" 3 "Partially complete, callback" ///
		4 "Not yet started, callback" 5 "Refused" 6 "Nobody answering" 7 "Number does not exist" ///
		8 "Phone off / not in service" 9 "Does not know the household" 10 "Reference person cannot connect", replace
	la val outcome outcome
	cap drop dur_min complete
	g double dur_min = (dial_end - dial_start) / 60000
		replace dur_min = . if dur_min < 0
	g byte complete = inlist(outcome, 1, 2)
	la var program 		"Program"
	la var round 		"Round"
	la var hhid 		"Household ID"
	la var enumerator 	"Enumerator (program code)"
	la var seq 			"Dial number for the household this round (by time)"
	la var dial_start 	"Dial start (local time)"
	la var dial_end 	"Dial end (local time)"
	la var dur_min 		"Dial length (minutes)"
	la var outcome 		"Result of the dial"
	la var contact 		"Someone answered"
	la var complete 	"Dial ended in a complete interview"
	la var source 		"Source of the record"
	la var dial_id 		"Record ID in the source"
	keep  program round hhid enumerator seq dial_start dial_end dur_min outcome contact complete source dial_id
	order program round hhid enumerator seq dial_start dial_end dur_min outcome contact complete source dial_id
	sort hhid seq
	compress
end
