*! setround: the round's globals and folders, as the L2PHL preamble sets them
*! setround 1  ->  $R 01, $pR 00, $xls (the round's export folder), $kobofile, $form, and the round's output folders
*!                 $zzz (export in Stata), $dta (module files), $call, $fix (checks), $wgt, $pii; $pdta and $ppii are the
*!                 previous round's dta and pii folders (the preload this round reads sits in $ppii)
program define setround
	args r
	loc r = real("`r'")
	glo R  : di %02.0f `r'
	glo pR : di %02.0f `r' - 1

	glo xls 	 "$data/raw/R$R"
	glo kobofile "L2PHL_SYN_CATI_R$R"
	glo form	 "$data/form/${kobofile}.xlsx"

	cap mkdir "$out/R$R"
	foreach dir in zzz dta call fix wgt pii {
		cap mkdir "$out/R$R/`dir'"
		glo `dir' "$out/R$R/`dir'"
	}
	glo pdta "$out/R$pR/dta"
	glo ppii "$out/R$pR/pii"
end
