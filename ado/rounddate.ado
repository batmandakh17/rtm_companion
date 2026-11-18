*! rounddate: the date that names a round's dated subfolders, as L2PHL's $date
*! rounddate 0  ->  r(date) the last baseline interview day (CAPI/raw/baseline_households.csv), as YYYYMMDD
*! rounddate 2  ->  r(date) the date of round 2's latest KoBo export in CATI/Round02/xls, r(file) its file name
*! The data in memory are left as they are.
program define rounddate, rclass
	args r
	loc r = real("`r'")
	if (`r' == 0) {
		tempname fr
		frame create `fr'
		frame `fr' {
			qui import delimited "$capi/raw/baseline_households.csv", clear stringcols(_all)
			g d = date(interview_date, "YMD")
			qui su d
			loc dmax = r(max)
		}
		frame drop `fr'
		return local date : di %tdCCYYNNDD `dmax'
		exit
	}
	loc rr : di %02.0f `r'
	loc files : dir "$cati/Round`rr'/xls" files "*_-_all_versions_-_*.xlsx"
	loc files : list sort files
	loc n : word count `files'
	if (`n' == 0) {
		di as error "round `r': no KoBo export in CATI/Round`rr'/xls"
		exit 601
	}
	loc f : word `n' of `files'
	loc stamp = substr("`f'", -24, 19)						// ..._-_2026-03-22-18-00-00.xlsx
	return local date = substr("`stamp'", 1, 4) + substr("`stamp'", 6, 2) + substr("`stamp'", 9, 2)
	return local file "`f'"
end
