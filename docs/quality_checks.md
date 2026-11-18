# Quality checks

The workflow checks each round's data in three layers, following handbook Sections 3.2 and 4.3.2. Every count lands in `output/checks/checks.csv`; the dashboard's Quality checks tab shows them with the rule behind each one.

## 1. Processing checks (steps 3 to 5)

Written into the do-files that build the module files, the call files and the weights. Examples:
- practice submissions, duplicates, forms saved before they were opened;
- every household appears once and is in the register;
- the roster adds up (members present = last size − leavers + joiners);
- the two call sources agree dial by dial;
- the weights add up to the census.

A check that must never fail ends the run (`check_log ... "stop"`). Rows a rule cannot judge go to `output/checks/review` for a person to read.

## 2. The skip-logic audit (`37_form_audit.do`)

The audit reads every question's rules from the form itself: its routing (the `relevant` column, together with the conditions of the groups and repeats it sits in), whether it is `required`, and its `constraint`. It then counts, for each question and round:

| Count | Meaning |
|---|---|
| base | submissions where the routing says the question should have been asked |
| answered | submissions with an answer |
| routing broken | an answer where the routing says the question was not asked |
| required missing | a required question left empty where it should have been asked |
| out of range | an answer that fails the constraint |

Call-record questions (interviewer, household, date, attempt, who answered, consent, result) are audited on every call attempt. The other questions are audited on completed interviews only, because a partial interview stops early by design.

The translator (`xls2stata` in `do/_programs.do`) knows `${x}`, `=`, `!=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not()`, `true()`, `false()`, `selected(x, 'c')` and `.` for the question's own value. A rule that uses anything else, such as `indexed-repeat()` or `regex()`, is reported as "not translated", and the question is skipped rather than guessed. Because the rules come from the form, a new round's routing reaches the audit as soon as its form is in `data/form`.

The flags are also summed by enumerator (`form_audit_enum_R##.csv`) for the monitoring view, and every flagged row is listed by household in `output/checks/review/R##_form_flags.csv`: the household ID, the submission (`_id` in the export), the row in the repeat sheet, the enumerator code, the question, the flag and the answer as recorded. That list is for the team; the dashboard shows the counts only.

Reading a flag (handbook 4.3.2): read it against the routing first. A question can be empty because the respondent was rightly routed past it. Then give it a likely cause and an owner: a routing condition missing from the form goes to the questionnaire team; an answer that breaks a correct condition to the field team; a variable the condition needs but the data lack to the processing team.

## 3. The enumerator monitoring view (`45_enumerator_monitor.do`)

For each enumerator and round, side by side with the round's pooled value:
- pace: dials per interview, interviews per operator-day;
- how calls go: share of cases refused, median interview length, share of interviews under 60% of the round's median;
- what the enumerator adds to the answers (handbook 3.2.1): share of don't-know and refused codes, and two answer shares (reported a shock; four or more food insecurity experiences);
- form flags per 100 interviews, from the audit.

The dashboard marks a value more than 50% above, or a third below, the pooled value. That is a prompt to look at the recordings or call a few households back, not a verdict: caseloads differ by region and by the households each enumerator was given, and with ten to twenty enumerators one round's figures are noisy (handbook 3.2.3).

## 4. Panel balance and form changes

- `calls_panel.csv`: what became of each household called in each round (interviewed, reached but not finished, refused, never answered, number not working), and how many of the round-1 panel have been interviewed in every round so far.
- `form_changes.csv` (`38_form_changes.do`): questions added or dropped between rounds, a type or wording changed, a choice list with a different number of options, read from the forms themselves. A question that leaves and comes back is marked rotating.
