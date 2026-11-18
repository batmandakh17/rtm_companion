*! xls2stata: an XLSForm logic expression as a Stata expression
*! xls2stata, expr(string) self(varname)  ->  r(expr), r(ok) = 1
*! The expression (relevant or constraint column, with the ${ } already stripped from the names and everything in lower
*! case) is translated. The translator knows =, !=, <, <=, >, >=, and, or, not(), true(), false(), selected(x, 'c')
*! (the option's 0/1 column) and "." for the question's own value (self()). Anything else, such as indexed-repeat() or
*! regex(), gives r(ok) = 0, so the caller skips the question rather than guess.
program define xls2stata, rclass
	syntax, expr(string) self(string)
	loc e = ustrlower(`"`expr'"')
	foreach bad in "indexed-repeat" "position(" "count(" "count-selected" "selected-at" "pulldata" "jr:" "''" "regex(" "concat(" "if(" {
		if strpos(`"`e'"', "`bad'") {
			return scalar ok = 0
			exit
		}
	}
	while regexm(`"`e'"', "selected\(([a-z0-9_.]+), *'([0-9]+)'\)") {
		loc v = regexs(1)
		loc c = regexs(2)
		if ("`v'" == ".") loc v `self'
		loc e = regexr(`"`e'"', "selected\(([a-z0-9_.]+), *'([0-9]+)'\)", "(`v'`c'==1)")
	}
	foreach op in ">=" "<=" "!=" ">" "<" "=" {
		loc e = subinstr(`"`e'"', ".`op'", "`self'`op'", .)
	}
	loc e = subinstr(`"`e'"', "'", "", .)
	loc e = subinstr(`"`e'"', " and ", " & ", .)
	loc e = subinstr(`"`e'"', " or ", " | ", .)
	loc e = subinstr(`"`e'"', "not(", "!(", .)
	loc e = subinstr(`"`e'"', "true()", "1", .)
	loc e = subinstr(`"`e'"', "false()", "0", .)
	while regexm(`"`e'"', "^(.*[^<>=!])=([^=].*)$") {
		loc e = regexs(1) + "==" + regexs(2)
	}
	return local expr `"`e'"'
	return scalar ok = 1
end
