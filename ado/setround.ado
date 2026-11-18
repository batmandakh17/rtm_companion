*! setround: the round's globals and folders, as the L2PHL preamble sets them
*! setround 2  ->  $R 02, $pR 01; $date the date of the round's latest export (rounddate) and $excel_file its name;
*!                 $xls the exports, $media the form's media files, $form and $kobofile the form; the dated output
*!                 folders $zzz $dta $call $fix $aud $wgt $pii under CATI/Round02; $stub the prefix of the round's
*!                 files (dta/<date>/l2phl_syn_<date>); $pdta and $ppii the previous round's dta and pii folders (the
*!                 preload and the roster master this round reads; round 1 reads the baseline's)
*! setround 0  ->  the baseline (CAPI): $date, and $dta (= $smpl), $pii, $fix under CAPI
program define setround
	args r
	loc r = real("`r'")
	glo R  : di %02.0f `r'
	glo pR : di %02.0f max(`r' - 1, 0)

	if (`r' == 0) {
		glo date "$capi_date"
		foreach dir in dta pii fix {
			cap mkdir "$capi/`dir'"
			cap mkdir "$capi/`dir'/$date"
			glo `dir' "$capi/`dir'/$date"
		}
		exit
	}

	glo wd_r "$cati/Round$R"
	rounddate `r'
	glo date 	   "`r(date)'"
	glo excel_file "`r(file)'"
	glo xls 	 "$wd_r/xls"
	glo media	 "$wd_r/kobo"
	glo kobofile "L2PHL_SYN_CATI_R$R"
	glo form	 "$kobo/${kobofile}.xlsx"

	cap mkdir "$wd_r"
	foreach dir in zzz dta call fix aud wgt pii {
		cap mkdir "$wd_r/`dir'"
		cap mkdir "$wd_r/`dir'/$date"
		glo `dir' "$wd_r/`dir'/$date"
	}
	glo stub "$dta/${dta_file}_${date}"

	if (`r' == 1) {
		glo pdta "$smpl"
		glo ppii "$capi/pii/$capi_date"
	}
	else {
		rounddate `=`r' - 1'
		glo pdta "$cati/Round$pR/dta/`r(date)'"
		glo ppii "$cati/Round$pR/pii/`r(date)'"
	}
end
