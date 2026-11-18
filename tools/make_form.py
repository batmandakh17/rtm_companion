"""Builds the example phone-round questionnaire (XLSForm) for rounds 1-3: data/form/L2PHL_SYN_CATI_R0#.xlsx.

The form is a shortened version of the L2PHL round-10 phone questionnaire: the same variable names, choice lists and
codes for the questions kept, one submission per call attempt, preloaded household data read with pulldata(). Modules:
call record (all rounds), roster, shocks, employment, food insecurity (all rounds), finance (rounds 1 and 3) and
health (round 2), so the workflow has a rotating module to handle. Everything identifying is synthetic.

usage: python3 tools/make_form.py
"""
import os

import openpyxl
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "form")
ROUNDS = {1: ["finance"], 2: ["health"], 3: ["finance"]}       # rotating modules by round
MAXMEM = 15                                                    # preload columns name1..name15

# The colour code of the sheets, so a reader sees the form's structure at a glance. The fills of groups, repeats and
# calculated fields are the ones the L2PHL form uses; the question types then get one colour each. The colours change
# nothing in the form: KoBoToolbox reads the cell values only.
FILLS = {
    ("begin_group", "end_group"): ("D2DBE5", "module (group)"),
    ("begin_repeat", "end_repeat"): ("CCC1DA", "repeat group"),
    ("calculate",): ("FDEADA", "calculated or preloaded field, never asked"),
    ("select_one", "select_one_from_file"): ("DDEBF7", "single choice"),
    ("select_multiple",): ("BDD7EE", "multiple choice"),
    ("integer", "decimal"): ("E2EFDA", "number"),
    ("text",): ("FFF2CC", "free text"),
    ("date", "time"): ("EDEDED", "date or time"),
    ("note",): ("F2F2F2", "note read to the respondent or shown to the interviewer"),
}
FILL_OF = {kind: fill for kinds, (fill, _) in FILLS.items() for kind in kinds}
NEW_FILL = "FFFF00"                                            # name cell of a row not in the previous round's form
HEADER_FILL, HEADER_FONT, META_FONT = "44546A", "FFFFFF", "7F7F7F"
WIDTHS = {"type": 30, "name": 24, "label::English (en)": 72, "relevant": 38, "constraint": 24, "calculation": 52,
          "repeat_count": 18, "required": 10, "appearance": 14, "list_name": 20, "form_title": 22, "form_id": 22,
          "version": 14, "default_language": 18}


def style_header(ws):
    for i, c in enumerate(ws[1], 1):
        c.font = Font(bold=True, color=HEADER_FONT)
        c.fill = PatternFill("solid", fgColor=HEADER_FILL)
        ws.column_dimensions[get_column_letter(i)].width = WIDTHS.get(str(c.value), 14)
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions


def style_survey(ws, prev_names):
    """One fill per kind of row across the used columns; module and repeat openings in bold; metadata rows in grey;
    a yellow name cell on every row that the previous round's form did not have."""
    style_header(ws)
    for row in ws.iter_rows(min_row=2, max_col=ws.max_column):
        kind = str(row[0].value or "").split(" ")[0]
        fill = FILL_OF.get(kind)
        meta = kind in ("start", "end", "deviceid")
        for c in row:
            if fill:
                c.fill = PatternFill("solid", fgColor=fill)
            c.alignment = Alignment(wrap_text=True, vertical="top")
            c.font = Font(bold=kind in ("begin_group", "begin_repeat"), italic=kind == "note",
                          color=META_FONT if meta or kind == "note" else None)
        name = row[1].value
        if prev_names is not None and name and name not in prev_names and kind not in ("end_group", "end_repeat"):
            row[1].fill = PatternFill("solid", fgColor=NEW_FILL)


def style_choices(ws):
    """Lists banded in alternating grey and white, so where one list ends and the next begins is visible."""
    style_header(ws)
    band, last = False, None
    for row in ws.iter_rows(min_row=2, max_col=ws.max_column):
        if row[0].value != last:
            band, last = not band, row[0].value
        for c in row:
            c.alignment = Alignment(vertical="top")
            if band:
                c.fill = PatternFill("solid", fgColor="F2F2F2")


def legend_sheet(wb):
    ws = wb.create_sheet("legend")
    ws.append(["Colour code of the survey sheet (not read by KoBoToolbox)"])
    ws["A1"].font = Font(bold=True)
    ws.append([])
    for kinds, (fill, meaning) in FILLS.items():
        ws.append([", ".join(kinds), meaning])
        ws.cell(row=ws.max_row, column=1).fill = PatternFill("solid", fgColor=fill)
    ws.append(["yellow name cell", "a row that the previous round's form did not have (new question, or a module that returned)"])
    ws.cell(row=ws.max_row, column=1).fill = PatternFill("solid", fgColor=NEW_FILL)
    ws.append(["grey text", "metadata (start, end, deviceid) and notes"])
    ws.cell(row=ws.max_row, column=1).font = Font(color=META_FONT)
    ws.append(["bold", "the opening row of a module or a repeat group"])
    ws.cell(row=ws.max_row, column=1).font = Font(bold=True)
    ws.append([])
    ws.append(["choices sheet", "lists banded grey and white in turn"])
    ws.column_dimensions["A"].width = 34
    ws.column_dimensions["B"].width = 90

EMPLOYED = "${A24}=4 or ${A1}=1 or ${A26}=1"

# (type, name, label, relevant, constraint, calculation, repeat_count, required, appearance)
CALL = [
    ("start", "start", "", "", "", "", "", "", ""),
    ("end", "end", "", "", "", "", "", "", ""),
    ("deviceid", "deviceid", "", "", "", "", "", "", ""),
    ("begin_group", "group_intro", "Call record", "", "", "", "", "", ""),
    ("select_one int_id", "int_id", "Interviewer's ID", "", "", "", "", "yes", ""),
    ("select_one_from_file households.csv", "hhid", "Please enter HHID", "", "", "", "", "yes", "minimal"),
    ("calculate", "hhsize", "", "", "", "pulldata('preload', 'hhsize', 'hhid', ${hhid})", "", "", ""),
    ("calculate", "fmid_max", "", "", "", "pulldata('preload', 'fmid_max', 'hhid', ${hhid})", "", "", ""),
    ("calculate", "sample", "", "", "", "pulldata('preload', 'sample', 'hhid', ${hhid})", "", "", ""),
    ("calculate", "round_lastint", "", "", "", "pulldata('preload', 'round_lastint', 'hhid', ${hhid})", "", "", ""),
    ("calculate", "oldrespo", "", "", "", "pulldata('preload', 'name', 'hhid', ${hhid})", "", "", ""),
    ("calculate", "oldcp", "", "", "", "pulldata('preload', 'cp', 'hhid', ${hhid})", "", "", ""),
    ("note", "oldrespo_contact", "Respondent (last interview): ${oldrespo}, mobile no.: ${oldcp}", "", "", "", "", "", ""),
    ("text", "replacement_hhid", "This is a Replacement HHID. What HHID was replaced?", "${sample}=2", "", "", "", "yes", ""),
    ("select_one surveylang", "D3", "D3. SURVEY LANGUAGE", "", "", "", "", "yes", ""),
    ("date", "Z6", "Z6. DATE OF INTERVIEW", "", "", "", "", "yes", ""),
    ("time", "Z7", "Z7. TIME OF INTERVIEW", "", "", "", "", "yes", ""),
    ("select_one attempt", "Z8", "Z8. CALL ATTEMPT #", "", "", "", "", "yes", ""),
    ("select_one call_status1", "call_status1", "Did you speak with someone?", "", "", "", "", "yes", ""),
    ("select_one yes-no", "Z17", "Z17. Were you able to speak with the correct respondent?", "${call_status1}=1", "", "", "", "yes", ""),
    ("select_one agree", "Z9", "Z9. One of my colleagues recently called you for an interview. May we continue with this month's interview?", "${Z17}=1", "", "", "", "yes", ""),
    ("select_one reason_ref", "Z18", "Z18. May I know why?", "${Z9}=2", "", "", "", "yes", ""),
    ("text", "Z18_oth", "Other (specify)", "${Z18}=96", "", "", "", "yes", ""),
    ("select_one yes-no", "Z20", "Z20. May I also ask if you still live in the same address?", "${Z9}=1", "", "", "", "yes", ""),
    ("text", "Z21", "Z21. What is your new address?", "${Z20}=2", "", "", "", "yes", ""),
    ("select_one region", "Z1", "Z1. REGION", "${Z20}=2", "", "", "", "yes", ""),
    ("select_one locale", "Z5", "Z5. LOCALE", "${Z20}=2", "", "", "", "yes", ""),
    ("end_group", "", "", "", "", "", "", "", ""),
]

ROSTER = [
    ("begin_group", "group_demogs", "Household roster", "${Z9}=1", "", "", "", "", ""),
    ("begin_repeat", "old_", "Members listed at the last interview", "", "", "", "${fmid_max}", "", ""),
    ("calculate", "fmid", "", "", "", "position(..)", "", "", ""),
    ("calculate", "fmidname", "", "", "", "pulldata('preload', concat('name', ${fmid}), 'hhid', ${hhid})", "", "", ""),
    ("calculate", "fmidage", "", "", "", "pulldata('preload', concat('age', ${fmid}), 'hhid', ${hhid})", "", "", ""),
    ("calculate", "fmidsex", "", "", "", "pulldata('preload', concat('sex', ${fmid}), 'hhid', ${hhid})", "", "", ""),
    ("calculate", "fmidpermanent", "", "", "", "pulldata('preload', concat('perm', ${fmid}), 'hhid', ${hhid})", "", "", ""),
    ("select_one confirm_mem", "D5a_", "D5a. I will read out the name, age and sex of the members. Is ${fmidname} (${fmidage}) still a member of the household?", "${fmidpermanent}=1", "", "", "", "yes", ""),
    ("select_one leave_reason", "D25", "D25. Please, tell me, why did ${fmidname} leave the household?", "${D5a_}=2", "", "", "", "yes", ""),
    ("text", "D25_oth", "D25. Others, specify:", "${D25}=96", "", "", "", "yes", ""),
    ("text", "D27", "D27. Can you please tell me the correct name of ${fmidname}?", "${D5a_}=3", "", "", "", "yes", ""),
    ("integer", "D28", "D28. Can you please tell me the correct age of ${fmidname}?", "${D5a_}=4", ".>=0 and .<=120", "", "", "yes", ""),
    ("select_one gender", "D33", "D33. Can you please tell me the correct sex of ${fmidname}?", "${D5a_}=5", "", "", "", "yes", ""),
    ("end_repeat", "", "", "", "", "", "", "", ""),
    ("select_one yes-none", "D29", "D29. Are there any other (new) household members not listed?", "", "", "", "", "yes", ""),
    ("begin_repeat", "newmembers", "New household members", "${D29}=1", "", "", "", "", ""),
    ("text", "D30", "D30. May I know the name of the new HH member?", "", "", "", "", "yes", ""),
    ("select_one gender", "D31", "D31. Is ${D30} male or female?", "", "", "", "", "yes", ""),
    ("integer", "D32", "D32. How old is ${D30} on his/her last birthday?", "", ".>=0 and .<=120", "", "", "yes", ""),
    ("select_one relationship", "D6", "D6. What is ${D30}'s relationship to the household head?", "", "", "", "", "yes", ""),
    ("select_one movein", "M13_", "M13. Why did ${D30} move in here in the PAST 30 DAYS?", "", "", "", "", "yes", ""),
    ("text", "M13_oth", "M13. Others, specify", "${M13_}=96", "", "", "", "yes", ""),
    ("end_repeat", "", "", "", "", "", "", "", ""),
    ("calculate", "newmembers_ct", "", "", "", "count(${newmembers})", "", "", ""),
    ("end_group", "", "", "", "", "", "", "", ""),
]

SHOCKS = [
    ("begin_group", "group_shocks", "Shocks", "${Z9}=1", "", "", "", "", ""),
    ("select_one yes-no", "SH1", "SH1. In the PAST 30 DAYS, have you or any of your household members been exposed to any shock?", "", "", "", "", "yes", ""),
    ("select_multiple shocks", "SH1b_", "SH1b. What types of shock was your household exposed to in the PAST 30 DAYS?", "${SH1}=1", "", "", "", "yes", ""),
    ("text", "SH1b_oth", "SH1b_oth. Others, please specify", "selected(${SH1b_},'96')", "", "", "", "yes", ""),
    ("begin_repeat", "sh2_", "Coping, by shock", "${SH1}=1", "", "", "count-selected(${SH1b_})", "", ""),
    ("calculate", "SH1b_ans", "", "", "", "selected-at(${SH1b_}, position(..)-1)", "", "", ""),
    ("calculate", "SH1b_ansname", "", "", "", "jr:choice-name(${SH1b_ans}, '${SH1b_}')", "", "", ""),
    ("select_multiple copingmech", "SH2_", "SH2. You mentioned that you experienced ${SH1b_ansname}. How did your household cope with it?", "", "", "", "", "yes", ""),
    ("text", "SH2_oth", "SH2_oth. Others, please specify", "selected(${SH2_},'96')", "", "", "", "yes", ""),
    ("end_repeat", "", "", "", "", "", "", "", ""),
    ("end_group", "", "", "", "", "", "", "", ""),
]


def employment(suffix, old):
    s = suffix
    rows = []
    if old:
        rows += [
            ("calculate", "employ_fmid", "", "", "", "position(..)", "", "", ""),
            ("calculate", "employ_fmidname", "", "", "", "pulldata('preload', concat('name', ${employ_fmid}), 'hhid', ${hhid})", "", "", ""),
            ("calculate", "fmid_employment", "", "", "", "pulldata('preload', concat('emp', ${employ_fmid}), 'hhid', ${hhid})", "", "", ""),
            ("calculate", "employ_left", "", "", "", "if(indexed-repeat(${D5a_}, ${old_}, ${employ_fmid})=2, 1, 0)", "", "", ""),
            ("select_one change_employ", "A24", "A24. Last month, ${employ_fmidname} was working. Has this changed?", "${fmid_employment}=1 and ${employ_left}=0", "", "", "", "yes", ""),
            ("select_one employ_status", "A27", "A27. Last month, ${employ_fmidname} was not working. Has this changed?", "${fmid_employment}=2 and ${employ_left}=0", "", "", "", "yes", ""),
        ]
        a1rel = "${A24}=1 or ${A24}=2 or ${A27}=1 or ${A27}=2"
        emp = EMPLOYED
    else:
        rows += [("calculate", "employ_fmid_new", "", "", "", "position(..)", "", "", ""),
                 ("calculate", "employ_fmidname_new", "", "", "", "indexed-repeat(${D30}, ${newmembers}, ${employ_fmid_new})", "", "", ""),
                 ("calculate", "employ_age_new", "", "", "", "indexed-repeat(${D32}, ${newmembers}, ${employ_fmid_new})", "", "", "")]
        a1rel = "${employ_age_new}>=15"
        emp = "${A1_new}=1 or ${A26_new}=1"
    rows += [
        ("select_one yes-no", f"A1{s}", "A1. Did this member do any work for at least one hour LAST WEEK?", a1rel, "", "", "", "yes", ""),
        ("select_one employ_status2", f"A26{s}", "A26. Please tell me which of these is applicable to this member.", f"${{A1{s}}}=2", "", "", "", "yes", ""),
        ("select_one reason_nojob", f"A3{s}", "A3. What is the main reason why this member did not work?", f"${{A26{s}}}=2 or ${{A26{s}}}=4", "", "", "", "yes", ""),
        ("text", f"A3_oth{s}", "A3. Others, please specify", f"${{A3{s}}}=96", "", "", "", "yes", ""),
        ("select_one industry", f"A5{s}", "A5. In what kind of industry did this member work?", emp, "", "", "", "yes", ""),
        ("text", f"A5_oth{s}", "A5. Others, please specify", f"${{A5{s}}}=96", "", "", "", "yes", ""),
        ("select_one class_worker", f"A6{s}", "A6. What was the class of worker of this member?", emp, "", "", "", "yes", ""),
        ("integer", f"A10{s}", "A10. How many days does this member usually work in a week?", emp, ".>=0 and .<=7", "", "", "yes", ""),
        ("integer", f"A11{s}", "A11. How many hours does this member usually work in a week?", emp, ".>=0 and .<=168", "", "", "yes", ""),
    ]
    return rows


EMPLOYMENT = ([("begin_group", "group_employment", "Employment (members aged 15 and over)", "${Z9}=1", "", "", "", "", ""),
               ("begin_repeat", "employ_", "Members listed at the last interview", "", "", "", "${fmid_max}", "", "")]
              + employment("", True)
              + [("end_repeat", "", "", "", "", "", "", "", ""),
                 ("begin_repeat", "employ_new", "New members", "${newmembers_ct}>0", "", "", "${newmembers_ct}", "", "")]
              + employment("_new", False)
              + [("end_repeat", "", "", "", "", "", "", "", ""), ("end_group", "", "", "", "", "", "", "", "")])

FINANCE = [
    ("begin_group", "group_finance", "Finance", "${Z9}=1", "", "", "", "", ""),
    ("select_one yes-nonev2", "F17", "F17. Do you or anyone in your household own a formal bank account?", "", "", "", "", "yes", ""),
    ("select_one yes-none-ref", "F1", "F1. Has anyone in your household received or deposited money in this account in the PAST MONTH?", "${F17}=1", "", "", "", "yes", ""),
    ("select_one yes-nonev2", "F18", "F18. Do you or anyone in your household own a mobile money account?", "", "", "", "", "yes", ""),
    ("select_one yes-none-ref", "F2", "F2. Has anyone in your household received or deposited money in this mobile money account in the PAST MONTH?", "${F18}=1", "", "", "", "yes", ""),
    ("select_one yes-no-ref", "F3", "F3. Given your financial commitments, were you able to save any money in the PAST MONTH?", "", "", "", "", "yes", ""),
    ("select_one yes-no-ref", "F6", "F6. Could your household currently pay an emergency expense equal to one month of income?", "", "", "", "", "yes", ""),
    ("select_one yes-no-ref-dk", "F7", "F7. Did you or any other member of your household apply or ask for a loan in the PAST MONTH?", "", "", "", "", "yes", ""),
    ("select_one yes-no-ref-dk", "F10", "F10. Was the loan approved?", "${F7}=1", "", "", "", "yes", ""),
    ("end_group", "", "", "", "", "", "", "", ""),
]

HEALTH = [
    ("begin_group", "group_health", "Health", "${Z9}=1", "", "", "", "", ""),
    ("select_one healthcare_service", "H2", "H2. In the past 3 months, has it been necessary, for any reason, for you or a member of your household to receive health care?", "", "", "", "", "yes", ""),
    ("select_one yes-no-dkref", "H2A", "H2A. Were you or the member of your household able to get the health care needed?", "${H2}<4", "", "", "", "yes", ""),
    ("select_one reason_nohealthcare", "H3", "H3. What was the main reason you or the member of your household could not get health care?", "${H2A}=2", "", "", "", "yes", ""),
    ("text", "H3_oth", "H3_oth. Others (specify)", "${H3}=96", "", "", "", "yes", ""),
    ("end_group", "", "", "", "", "", "", "", ""),
]

FIES = [("begin_group", "group_food", "Food insecurity (PAST 30 DAYS, because of lack of money or other resources)", "${Z9}=1", "", "", "", "", "")]
for k, lab in zip("ABCDEFGH", ["Worried about not having enough food to eat", "Ate less than you thought you should",
                               "Ran out of food", "Were hungry but did not eat", "Went without eating for a whole day",
                               "Unable to eat healthy and nutritious food", "Ate only a few kinds of food", "Had to skip a meal"]):
    FIES.append(("select_one yes-no", f"F08_{k}", f"F08_{k}. {lab} because of lack of money or other resources?", "", "", "", "", "yes", ""))
FIES.append(("end_group", "", "", "", "", "", "", "", ""))

CLOSING = [
    ("begin_group", "group_closing", "Closing", "${Z9}=1", "", "", "", "", ""),
    ("select_one yes-no", "X11", "X11. Thank you for participating! Our next call is next month. May we call you again?", "", "", "", "", "yes", ""),
    ("text", "X14", "X14. May I verify your mobile number so we can send a small token of appreciation?", "", "", "", "", "yes", "numbers"),
    ("select_one provider", "X20", "What is your network provider?", "", "", "", "", "yes", ""),
    ("end_group", "", "", "", "", "", "", "", ""),
    ("select_one Callrem", "X15", "X15. What is the result of the interview?", "", "", "", "", "yes", ""),
    ("text", "X16", "X16. Remarks", "", "", "", "", "", ""),
]

CHOICES = {
    "int_id": [(100 + i, f"E{i:02d}") for i in range(1, 13)],
    "surveylang": [(1, "English"), (2, "Tagalog"), (3, "Cebuano"), (4, "Hiligaynon"), (5, "Waray")],
    "attempt": [(1, "1st attempt"), (2, "2nd attempt"), (3, "3rd attempt")],
    "call_status1": [(1, "Yes"), (2, "No")],
    "yes-no": [(1, "Yes"), (2, "No")],
    "yes-none": [(1, "Yes"), (2, "No")],
    "agree": [(1, "I agree"), (2, "No, I do not agree")],
    "reason_ref": [(1, "No time/busy"), (2, "Do not want to share my personal information"), (3, "No answer/do not know"),
                   (4, "Call back at another time"), (96, "Other (specify)")],
    "region": [(1, "Region 1"), (2, "Region 2"), (3, "Region 3"), (4, "Region 4")],
    "locale": [(1, "Urban"), (2, "Rural")],
    "confirm_mem": [(1, "Yes"), (2, "No"), (3, "Yes, but Name is recorded incorrectly"), (4, "Yes, but Age is recorded incorrectly"),
                    (5, "Yes, but Sex is recorded incorrectly")],
    "leave_reason": [(1, "Moved out"), (2, "Married and moved out"), (3, "Died"), (96, "Other (specify)")],
    "gender": [(1, "Male"), (2, "Female")],
    "relationship": [(1, "Head"), (2, "Wife/Spouse"), (3, "Son/daughter"), (4, "Brother/sister"), (5, "Son-in-law/daughter-in-law"),
                     (6, "Grandson/granddaughter"), (7, "Father/Mother"), (8, "Other Relative"), (9, "Boarder"), (10, "Domestic helper"),
                     (11, "Non-relative")],
    "movein": [(1, "Schooling"), (2, "Employment/Job Change/Job Relocation"), (6, "Housing-related Reasons"), (9, "To Live with Parents"),
               (10, "To Join Spouse/Partner"), (11, "To Live with Children"), (12, "Marriage"), (14, "Health-related Reasons"),
               (16, "Natural calamities"), (40, "Due to child birth"), (96, "Others, specify")],
    "shocks": [(1, "Typhoons"), (2, "Droughts/El Niño"), (3, "Floods/La Niña"), (4, "Earthquakes"), (5, "Tsunami"), (6, "Landslides"),
               (7, "Volcanic eruptions"), (8, "Extreme heat"), (9, "Pest infestation, crop diseases"),
               (10, "Livestock diseases, African swine fever (ASF), Avian flu"), (11, "Inflation (increase of food/fuel/commodity prices)"),
               (12, "Lack of agricultural funds"), (13, "Unexpected loss of job"), (14, "Non-payment or delay in payment of income"),
               (15, "Collapse of business"), (16, "Fraud"), (17, "Fire"), (18, "Arrest"), (19, "Major injury"), (20, "Major illness"),
               (21, "Death"), (22, "Food shortage"), (96, "Other shocks")],
    "copingmech": [(1, "Sold assets / property"), (2, "Sold harvest in advance"), (3, "Borrowed from friends and family"),
                   (4, "Took a loan from a financial institution"), (5, "Took a loan from informal lenders"),
                   (6, "Credited purchases / Used a credit card"), (7, "Pawned assets / property"),
                   (8, "Received assistance from friends and family"), (9, "Received assistance from NGO or church"),
                   (10, "Received assistance from government"), (11, "Engaged in additional income generating activities"),
                   (12, "Increased hours of work"), (13, "Reduced food consumption or shifted to cheaper food"),
                   (14, "Reduced non-food consumption or shifted to cheaper items"), (15, "Delayed payment obligations"),
                   (16, "Took advanced payment from employer"), (17, "Relied on savings"), (18, "Was covered by insurance policy"),
                   (96, "Others (specify)")],
    "change_employ": [(1, "Yes, have a new job"), (2, "Yes, don't have a job now"), (4, "No change, same job")],
    "employ_status": [(1, "Yes, have a job now"), (2, "No change, no job")],
    "employ_status2": [(1, "Have a job or business during the past week"), (2, "Looking for a job"), (3, "Looking for more work"),
                       (4, "None of the above")],
    "reason_nojob": [(1, "Applied/searched and waiting to hear back"), (2, "Awaiting recall from a previous job"),
                     (3, "Waiting for the season to start"), (4, "Will start new job or business soon"),
                     (5, "Tired of looking for jobs, no jobs in area"), (6, "No jobs matching skills, lacks experience"),
                     (7, "Too young or too old"), (8, "In studies, training"), (9, "Family / household responsibilities"),
                     (10, "In agriculture / fishing for family use"), (11, "Own disability, injury, illness"),
                     (12, "Retired, pensioner, other sources of income"), (96, "Other (specify)")],
    "industry": [(1, "Agriculture, Forestry, and Fishing"), (2, "Wholesale and retail trade; repair of motor vehicles"),
                 (3, "Accommodation and food service activities"), (4, "Administrative and support service activities"),
                 (96, "Other, specify industry")],
    "class_worker": [(1, "Worked for private household"), (2, "Worked for private establishment"),
                     (3, "Worked for government/government corporation"), (4, "Self-employed without any paid employee"),
                     (5, "Employer in own business or family-operated farm or business"),
                     (6, "Worked with pay in own business or family-operated farm or business"),
                     (7, "Worked without pay in own business or family-operated farm or business")],
    "yes-nonev2": [(1, "Yes"), (2, "No")],
    "yes-none-ref": [(1, "Yes"), (2, "No"), (98, "Refused to answer")],
    "yes-no-ref": [(1, "Yes"), (2, "No"), (98, "Refused to answer")],
    "yes-no-ref-dk": [(1, "Yes"), (2, "No"), (98, "Refused to answer"), (99, "Don't know")],
    "healthcare_service": [(1, "Yes, inpatient"), (2, "Yes, outpatient"), (3, "Yes, both inpatient and outpatient"), (4, "No"),
                           (98, "Don't want to answer / Refused")],
    "yes-no-dkref": [(1, "Yes"), (2, "No"), (98, "Don't want to answer / Refused")],
    "reason_nohealthcare": [(1, "Lack of money / Cannot afford"), (2, "No medical personnel available"),
                            (3, "Turned away because facility was full"), (4, "Limited/ No transportation"),
                            (5, "Restriction to go outside"), (6, "Afraid"), (96, "Others (specify)")],
    "provider": [(1, "Globe"), (2, "TM"), (3, "GOMO"), (4, "Smart"), (5, "TNT"), (7, "Dito"), (8, "Sun"), (9, "Others (specify)")],
    "Callrem": [(1, "Complete"), (2, "Partially complete, no more callback"), (3, "Partially complete, scheduled another call"),
                (4, "Not yet started, with scheduled callback"), (5, "Refused"), (6, "Nobody answering / Just ringing"),
                (7, "Number does not exist / Not ringing"), (8, "Phone turned off / Not in service"), (9, "Don't know the household"),
                (10, "Reference person can't connect to the household")],
}


def survey_rows(r):
    rows = CALL + ROSTER + SHOCKS + EMPLOYMENT
    if "finance" in ROUNDS[r]:
        rows += FINANCE
    if "health" in ROUNDS[r]:
        rows += HEALTH
    return rows + FIES + CLOSING


def build(r):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "survey"
    ws.append(["type", "name", "label::English (en)", "relevant", "constraint", "calculation", "repeat_count", "required", "appearance"])
    for row in survey_rows(r):
        ws.append(list(row))
    wc = wb.create_sheet("choices")
    wc.append(["list_name", "name", "label::English (en)"])
    for ln, items in CHOICES.items():
        for code, lab in items:
            wc.append([ln, code, lab])
    st = wb.create_sheet("settings")
    st.append(["form_title", "form_id", "version", "default_language"])
    st.append([f"L2PHL_SYN_CATI_R{r:02d}", f"l2phl_syn_cati_r{r:02d}", f"2026{r + 2:02d}0101", "English (en)"])
    prev_names = {row[1] for row in survey_rows(r - 1)} if r - 1 in ROUNDS else None
    style_survey(ws, prev_names)
    style_choices(wc)
    style_header(st)
    legend_sheet(wb)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"L2PHL_SYN_CATI_R{r:02d}.xlsx")
    wb.save(path)
    return path, len(survey_rows(r))


if __name__ == "__main__":
    for r in ROUNDS:
        p, n = build(r)
        print(f"{os.path.relpath(p, ROOT)}: {n} survey rows")
