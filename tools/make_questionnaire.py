"""Writes each round's questionnaire as a Word document and a PDF from its XLSForm, and lays out the KoBo form as
uploaded (form plus media files) in questionnaire/kobo/R##.

The documents follow the layout the L2 programs use for their phone-round questionnaires: a title block with the round
and its dates, a colour legend, one shaded heading per module, and a three-column table in which each question has its
variable name with the condition under which it is asked (grey italics), the question text, and the coded answer options
with dot leaders. Questions new in this round are blue; questions asked in the previous round and paused in this one are
green. Everything comes from the form itself (data/form/L2PHL_SYN_CATI_R##.xlsx), so the document and the deployed form
cannot drift apart.

Outputs (questionnaire/):
  L2PHL_SYN_CATI_R##@<round start>.docx   the Word questionnaire (python-docx)
  L2PHL_SYN_CATI_R##@<round start>.pdf    the same page, printed from an HTML twin with headless Chrome
  kobo/R##/                                the XLSForm and its media files (households.csv, preload.csv), as uploaded

usage: python3 tools/make_questionnaire.py            (needs python-docx and openpyxl; Chrome for the PDF)
"""
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile

import openpyxl
from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_ALIGNMENT, WD_TAB_LEADER
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from make_synthetic import ROUND_START, call_days  # noqa: E402  (the round calendar, so the dates match the data)

PROGRAM = "L2PHL_SYN"
OUT = os.path.join(ROOT, "questionnaire")
FORM = os.path.join(ROOT, "data", "form", PROGRAM + "_CATI_R{rr}.xlsx")
MEDIA = os.path.join(ROOT, "data", "raw", "R{rr}", "media")
LABEL = "label::English (en)"

# module headings by group name, and the module file each group feeds (docs/module_files.md)
MODULES = {
    "group_intro": ("MODULE 0", "M00_passport"),
    "group_demogs": ("MODULE 1", "M01_roster"),
    "group_shocks": ("MODULE 3", "M03_shock"),
    "group_employment": ("MODULE 4", "M04_employment"),
    "group_finance": ("MODULE 6", "M06_finance"),
    "group_health": ("MODULE 7", "M07_health"),
    "group_food": ("MODULE 8", "M08_food"),
    "group_closing": ("CLOSING", "M00_passport"),
    None: ("CALL RESULT", "M00_passport"),
}
# how a ${field} inside a question's text is shown
PLACEHOLDERS = {"fmidname": "<NAME>", "fmidage": "<AGE>", "D30": "<NAME>", "employ_fmidname": "<NAME>",
                "SH1b_ansname": "<SHOCK>", "oldrespo": "<RESPONDENT>", "oldcp": "<MOBILE NO.>"}
QUESTION_TYPES = {"select_one", "select_multiple", "select_one_from_file", "integer", "decimal", "text", "date",
                  "time", "note"}
# colours (hex, no #)
BLUE, GREEN, GREY, BAR, BARTEXT, MODULE_FILL, REPEAT_FILL, RULE = "1F5FA8", "3A7D44", "7F7F7F", "DCE6F1", "1F5FA8", "D9D9D9", "F2F2F2", "A6A6A6"


# ---------------------------------------------------------------- reading the form
def read_form(path):
    wb = openpyxl.load_workbook(path, read_only=True)
    sheets = {}
    for name in ("survey", "choices", "settings"):
        rows = list(wb[name].iter_rows(values_only=True))
        hdr = [h for h in rows[0]]
        sheets[name] = [dict(zip(hdr, r)) for r in rows[1:] if any(c is not None for c in r)]
    choices = {}
    for c in sheets["choices"]:
        choices.setdefault(c["list_name"], []).append((str(c["name"]), c[LABEL] or ""))
    return sheets["survey"], choices, sheets["settings"][0]


def s(v):
    return "" if v is None else str(v).strip()


def strip_refs(expr):
    return re.sub(r"\$\{([A-Za-z0-9_]+)\}", r"\1", expr)


def cond_text(expr):
    """An XLSForm condition as a reader sees it: Z9 = 1; SH1b_ includes 96; A24 = 4 or A1 = 1."""
    e = s(expr)
    if not e:
        return ""
    e = re.sub(r"selected\(\$\{([A-Za-z0-9_]+)\}, *'([^']*)'\)", r"\1 includes \2", e)
    e = strip_refs(e)
    e = re.sub(r"\s*(>=|<=|!=|=|>|<)\s*", r" \1 ", e)
    return re.sub(r"\s+", " ", e).strip()


def constraint_text(expr):
    e = s(expr)
    m = re.fullmatch(r"\.\s*>=\s*(-?[0-9.]+)\s+and\s+\.\s*<=\s*(-?[0-9.]+)", e)
    if m:
        return f"[{m.group(1)}, {m.group(2)}]"
    return cond_text(e.replace(".", "value")) if e else ""


def label_text(text):
    return re.sub(r"\$\{([A-Za-z0-9_]+)\}", lambda m: PLACEHOLDERS.get(m.group(1), "<" + m.group(1).upper() + ">"),
                  s(text))


def repeat_text(row):
    rc = s(row.get("repeat_count"))
    if rc.startswith("count-selected("):
        return "once per answer selected in " + strip_refs(rc[len("count-selected("):-1])
    if rc:
        return "once per member, " + strip_refs(rc) + " times"
    return "repeated"


def structure(survey, choices):
    """The form as a list of blocks: module headings, repeat headings and questions, in form order."""
    blocks, group, group_cond, repeat, repeat_cond, depth = [], None, "", None, "", 0
    skips = skip_targets(survey)
    for row in survey:
        t, name = s(row.get("type")), s(row.get("name"))
        kind = t.split(" ")[0]
        if kind == "begin_group":
            group, group_cond = name, cond_text(row.get("relevant"))
            mod, mfile = MODULES.get(name, (name.upper(), ""))
            label = s(row.get(LABEL)) or name
            blocks.append({"kind": "module", "name": name, "title": mod if label.lower() == mod.lower() else f"{mod}: {label}",
                           "file": mfile, "cond": group_cond})
            continue
        if kind == "end_group":
            group, group_cond = None, ""
            continue
        if kind == "begin_repeat":
            repeat, repeat_cond = name, cond_text(row.get("relevant"))
            blocks.append({"kind": "repeat", "name": name, "title": s(row.get(LABEL)) or name, "cond": repeat_cond,
                           "count": repeat_text(row), "group": group})
            continue
        if kind == "end_repeat":
            repeat, repeat_cond = None, ""
            continue
        if kind == "calculate":
            blocks.append({"kind": "calc", "name": name, "calc": strip_refs(s(row.get("calculation"))), "group": group,
                           "repeat": repeat})
            continue
        if kind not in QUESTION_TYPES:
            continue
        if group is None:                               # questions outside every group: the result of the attempt
            group, group_cond = "group_result", ""
            mod, mfile = MODULES[None]
            blocks.append({"kind": "module", "name": group, "title": f"{mod}: Result of the call attempt",
                           "file": mfile, "cond": ""})
        q = {"kind": "q", "name": name, "type": kind, "label": label_text(row.get(LABEL)),
             "cond": cond_text(row.get("relevant")), "required": s(row.get("required")).lower() == "yes",
             "group": group, "repeat": repeat, "options": [], "answer": ""}
        if kind in ("select_one", "select_multiple"):
            q["options"] = [(lab, code, skips.get((name, code), "")) for code, lab in choices.get(t.split(" ")[1], [])]
            if kind == "select_multiple":
                q["answer"] = "select all that apply"
        elif kind == "select_one_from_file":
            q["answer"] = f"[list of households, {t.split(' ')[1]}]"
        elif kind in ("integer", "decimal"):
            q["answer"] = "number " + constraint_text(row.get("constraint"))
        elif kind == "text":
            q["answer"] = "text" + (" (numbers only)" if s(row.get("appearance")) == "numbers" else "")
        elif kind in ("date", "time"):
            q["answer"] = kind
        blocks.append(q)
    return blocks


def skip_targets(survey):
    """(question, code) -> the one question asked only when that code is chosen, when there is exactly one and it is
    not the next question in the form. Shown as '>>> name' beside the option, as the L2 questionnaires do."""
    names = [s(r.get("name")) for r in survey]
    found = {}
    for i, row in enumerate(survey):
        m = re.fullmatch(r"\$\{([A-Za-z0-9_]+)\}=([0-9]+)", s(row.get("relevant")))
        if m and s(row.get("type")).split(" ")[0] in QUESTION_TYPES:
            found.setdefault((m.group(1), m.group(2)), []).append((i, names[i]))
    out = {}
    for key, hits in found.items():
        if len(hits) == 1 and key[0] in names and hits[0][0] != names.index(key[0]) + 1:
            out[key] = hits[0][1]
    return out


def with_previous(blocks, prev_blocks):
    """Marks what is new this round (blue) and adds, in green, what the previous round asked and this one does not."""
    if prev_blocks is None:
        return blocks
    cur_names = {b["name"] for b in blocks if b["kind"] in ("q", "module", "repeat")}
    prev_names = {b["name"] for b in prev_blocks if b["kind"] in ("q", "module", "repeat")}
    out = []
    for b in blocks:
        b = dict(b)
        if b["kind"] in ("q", "module", "repeat") and b["name"] not in prev_names:
            b["colour"] = BLUE
        out.append(b)
    # paused questions, under their previous module; a paused module goes after the module that preceded it
    paused = [dict(b, colour=GREEN, paused=True) for b in prev_blocks
              if b["kind"] in ("q", "module", "repeat") and b["name"] not in cur_names]
    if not paused:
        return out
    by_group = {}
    for b in paused:
        by_group.setdefault(b.get("group") if b["kind"] != "module" else b["name"], []).append(b)
    result, anchor_prev = [], None
    prev_groups = [b["name"] for b in prev_blocks if b["kind"] == "module"]
    for b in out:
        result.append(b)
    for g, items in by_group.items():
        if g in cur_names:                              # the module still exists: append after its last block
            last = max(i for i, b in enumerate(result) if b.get("group") == g or (b["kind"] == "module" and b["name"] == g))
            result[last + 1:last + 1] = [x for x in items if x["kind"] != "module"]
        else:                                           # the whole module is paused: place it after its predecessor
            pos = prev_groups.index(g)
            before = [x for x in prev_groups[:pos] if x in cur_names]
            if before:
                a = before[-1]
                last = max(i for i, b in enumerate(result) if b.get("group") == a or (b["kind"] == "module" and b["name"] == a))
            else:
                last = -1
            result[last + 1:last + 1] = items
    return result


# ---------------------------------------------------------------- the document's text
def round_dates(r):
    days = call_days(r)
    a, b = days[0], days[-1]
    if a.month == b.month:
        return f"{a.day}–{b.day} {a.strftime('%B %Y')}"
    return f"{a.day} {a.strftime('%B')} – {b.day} {b.strftime('%B %Y')}"


def title_lines(r, settings):
    return [("SYNTHETIC HOUSEHOLD PHONE SURVEY (" + PROGRAM + ")", "title"),
            (f"ROUND {r}: {round_dates(r)}", "bar"),
            ("HOUSEHOLD PHONE SURVEY QUESTIONNAIRE", "title2"),
            ("COMPUTER-ASSISTED TELEPHONE INTERVIEW (CATI)", "title2"),
            (f"Form {settings['form_id']}, version {settings['version']}", "small")]


INTRO = ("This questionnaire belongs to the RTM companion package. It is a shortened version of the L2PHL phone "
         "questionnaire, keeping its variable names, choice lists and codes, and it is the questionnaire the package's "
         "synthetic data were generated from. One submission is one call attempt: the call record is filled on every "
         "attempt, and the modules only after consent (Z9 = 1). The KoBoToolbox form is the XLSForm in "
         "questionnaire/kobo/R{rr}, with the two files it reads: households.csv (the list behind the household "
         "question) and preload.csv (the previous round's roster and contacts, read with pulldata). Every name, number "
         "and place in the data is made up.")

LEGEND = [("Questions in black", "000000", "Current questions"),
          ("Questions in blue", BLUE, "New in this round"),
          ("Questions in green", GREEN, "Asked in the previous round, paused in this one"),
          ("Variable names in bold", "000000", "The names in the KoBo form and in the module files"),
          ("Notes in grey italics", GREY, "The condition under which the question is asked, from the form's relevant column")]


# ---------------------------------------------------------------- Word
# Word checks the order of the children of pPr, tcPr and tblPr, so each new element goes before its successors
PPR_AFTER_SHD = ["tabs", "suppressAutoHyphens", "kinsoku", "wordWrap", "overflowPunct", "topLinePunct", "autoSpaceDE",
                 "autoSpaceDN", "bidi", "adjustRightInd", "snapToGrid", "spacing", "ind", "contextualSpacing",
                 "mirrorIndents", "suppressOverlap", "jc", "textDirection", "textAlignment", "textboxTightWrap",
                 "outlineLvl", "divId", "cnfStyle", "rPr", "sectPr", "pPrChange"]
TCPR_AFTER_SHD = ["noWrap", "tcMar", "textDirection", "tcFitText", "vAlign", "hideMark", "headers", "cellIns",
                  "cellDel", "cellMerge", "tcPrChange"]
TBLPR_AFTER_BORDERS = ["shd", "tblLayout", "tblCellMar", "tblLook", "tblCaption", "tblDescription", "tblPrChange"]
TBLPR_AFTER_LAYOUT = ["tblCellMar", "tblLook", "tblCaption", "tblDescription", "tblPrChange"]


def insert_in_order(parent, child, successors):
    for el in parent:
        if el.tag.split("}")[1] in successors:
            el.addprevious(child)
            return
    parent.append(child)


def shade(cell_or_p, fill):
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    if hasattr(cell_or_p, "_tc"):
        insert_in_order(cell_or_p._tc.get_or_add_tcPr(), shd, TCPR_AFTER_SHD)
    else:
        insert_in_order(cell_or_p._p.get_or_add_pPr(), shd, PPR_AFTER_SHD)


def borders(table, inside_v=True, top_each=True):
    b = OxmlElement("w:tblBorders")
    for side, on in (("top", True), ("left", False), ("bottom", True), ("right", False),
                     ("insideH", top_each), ("insideV", inside_v)):
        e = OxmlElement(f"w:{side}")
        e.set(qn("w:val"), "single" if on else "nil")
        e.set(qn("w:sz"), "6" if side in ("top", "bottom") else "4")
        e.set(qn("w:color"), "404040" if side in ("top", "bottom") else RULE)
        b.append(e)
    insert_in_order(table._tbl.tblPr, b, TBLPR_AFTER_BORDERS)


def set_widths(table, widths):
    """Fixed column widths, written on the grid, the table and every cell (a merged cell gets the sum of its columns)."""
    tbl = table._tbl
    for gc, w in zip(tbl.tblGrid.findall(qn("w:gridCol")), widths):
        gc.set(qn("w:w"), str(Cm(w).twips))
    for row in table.rows:
        col = 0
        for tc in row._tr.tc_lst:
            span = tc.grid_span
            tc.width = Cm(sum(widths[col:col + span]))
            col += span
    tblW = tbl.tblPr.find(qn("w:tblW"))
    if tblW is None:
        tblW = OxmlElement("w:tblW")
        insert_in_order(tbl.tblPr, tblW, ["jc", "tblCellSpacing", "tblInd", "tblBorders"] + TBLPR_AFTER_BORDERS)
    tblW.set(qn("w:type"), "dxa")
    tblW.set(qn("w:w"), str(Cm(sum(widths)).twips))
    lay = OxmlElement("w:tblLayout")
    lay.set(qn("w:type"), "fixed")
    insert_in_order(tbl.tblPr, lay, TBLPR_AFTER_LAYOUT)


def run(p, text, bold=False, italic=False, colour=None, size=None):
    r = p.add_run(text)
    r.bold, r.italic = bold, italic
    if colour:
        r.font.color.rgb = RGBColor.from_string(colour)
    if size:
        r.font.size = Pt(size)
    return r


def field(p, code):
    f = OxmlElement("w:fldSimple")
    f.set(qn("w:instr"), code)
    r = OxmlElement("w:r")
    t = OxmlElement("w:t")
    t.text = "1"
    r.append(t)
    f.append(r)
    p._p.append(f)


def para(container, text="", **kw):
    p = container.add_paragraph()
    p.paragraph_format.space_after = Pt(kw.pop("after", 2))
    p.paragraph_format.space_before = Pt(kw.pop("before", 0))
    if kw.pop("center", False):
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    if text:
        run(p, text, **kw)
    return p


def write_docx(r, blocks, settings, path):
    rr = f"{r:02d}"
    doc = Document()
    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
    sec.left_margin = sec.right_margin = Cm(1.5)
    sec.top_margin, sec.bottom_margin = Cm(1.5), Cm(1.5)
    st = doc.styles["Normal"]
    st.font.name, st.font.size = "Arial", Pt(9)
    st.element.rPr.rFonts.set(qn("w:eastAsia"), "Arial")
    st.paragraph_format.space_after = Pt(0)
    zoom = doc.settings.element.find(qn("w:zoom"))
    if zoom is not None and zoom.get(qn("w:percent")) is None:
        zoom.set(qn("w:percent"), "100")
    # footer: file name and page x of y
    fp = sec.footer.paragraphs[0]
    fp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run(fp, f"{PROGRAM} CATI round {r} questionnaire (synthetic example) — page ", size=8, colour=GREY)
    field(fp, "PAGE")
    run(fp, " of ", size=8, colour=GREY)
    field(fp, "NUMPAGES")
    # title block
    for text, style in title_lines(r, settings):
        if style == "title":
            para(doc, text, bold=True, size=13, center=True, after=10)
        elif style == "bar":
            p = para(doc, text, bold=True, size=12, colour=BARTEXT, center=True, after=10)
            shade(p, BAR)
        elif style == "title2":
            para(doc, text, bold=True, size=11, center=True, after=0)
        else:
            para(doc, text, size=8, colour=GREY, center=True, before=4, after=8)
    para(doc, INTRO.format(rr=rr), after=8)
    # legend
    t = doc.add_table(rows=0, cols=3)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for text, colour, meaning in LEGEND:
        cells = t.add_row().cells
        p = cells[0].paragraphs[0]
        run(p, text, bold=True, size=8, colour="FFFFFF" if colour != "000000" else None)
        shade(cells[0], colour if colour != "000000" else "FFFFFF")
        if colour == "000000":
            p.runs[0].font.color.rgb = RGBColor(0, 0, 0)
        run(cells[1].paragraphs[0], meaning, size=8)
    set_widths(t, [4.0, 10.0, 4.0])
    para(doc, "", after=6)
    # preloaded and calculated fields
    calcs = [b for b in blocks if b["kind"] == "calc"]
    if calcs:
        para(doc, "Preloaded and calculated fields (not asked; filled by the form)", bold=True, size=9, before=4, after=2)
        t = doc.add_table(rows=0, cols=2)
        for b in calcs:
            cells = t.add_row().cells
            run(cells[0].paragraphs[0], b["name"], bold=True, size=8)
            if b["repeat"]:
                run(cells[0].paragraphs[0], f"\nin repeat {b['repeat']}", italic=True, size=7.5, colour=GREY)
            run(cells[1].paragraphs[0], b["calc"], size=8)
        borders(t)
        set_widths(t, [4.5, 13.5])
    # the questions
    table, qtables = None, []
    for b in blocks:
        if b["kind"] == "module":
            table = None
            para(doc, "", after=4)
            p = para(doc, "", before=2, after=0)
            p.paragraph_format.keep_with_next = True
            colour = b.get("colour")
            run(p, b["title"], bold=True, size=11, colour=colour)
            run(p, " (paused this round)" if b.get("paused") else "", bold=True, size=9, colour=colour)
            p.paragraph_format.tab_stops.add_tab_stop(Cm(18.0), WD_TAB_ALIGNMENT.RIGHT)
            run(p, "\t" + b["file"], size=8, colour=GREY)
            shade(p, MODULE_FILL)
            if b["cond"]:
                pc = para(doc, "asked if " + b["cond"], italic=True, size=8, colour=GREY, after=2)
                pc.paragraph_format.keep_with_next = True
            continue
        if b["kind"] == "calc":
            continue
        if table is None:
            table = doc.add_table(rows=0, cols=3)
            borders(table)
            qtables.append(table)
        if b["kind"] == "repeat":
            cells = table.add_row().cells
            m = cells[0].merge(cells[2])
            p = m.paragraphs[0]
            run(p, f"REPEAT {b['name']}: {b['title']}", bold=True, size=9, colour=b.get("colour"))
            run(p, f" — {b['count']}" + (f"; if {b['cond']}" if b["cond"] else ""), italic=True, size=8, colour=GREY)
            shade(m, REPEAT_FILL)
            continue
        cells = table.add_row().cells
        colour = b.get("colour")
        p = cells[0].paragraphs[0]
        run(p, b["name"], bold=True, colour=colour)
        if b["cond"]:
            run(p, "\nif " + b["cond"], italic=True, size=8, colour=GREY)
        if b["type"] == "note":
            run(cells[1].paragraphs[0], b["label"], italic=True, colour=colour or GREY)
            continue
        run(cells[1].paragraphs[0], b["label"], colour=colour)
        c3 = cells[2]
        first = True
        if b["answer"]:
            p = c3.paragraphs[0]
            run(p, b["answer"], italic=b["type"] in ("select_multiple",), colour=colour or (None if b["options"] else GREY))
            first = False
        for lab, code, skip in b["options"]:
            p = c3.paragraphs[0] if first else c3.add_paragraph()
            first = False
            p.paragraph_format.tab_stops.add_tab_stop(Cm(6.1), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.DOTS)
            p.paragraph_format.left_indent, p.paragraph_format.first_line_indent = Cm(0.3), Cm(-0.3)
            run(p, f"{lab}\t{code}", colour=colour)
            if skip:
                run(p, f"   >>> {skip}", bold=True, size=8, colour=colour)
    for t in qtables:
        set_widths(t, [3.4, 7.9, 6.7])
    doc.save(path)


# ---------------------------------------------------------------- HTML twin, printed to PDF
CSS = """
@page { size: A4; margin: 15mm 15mm 16mm 15mm; @bottom-right { content: "%(footer)s page " counter(page) " of " counter(pages); font: 7.5pt Arial, sans-serif; color: #7f7f7f; } }
body { font: 9pt/1.25 Arial, Helvetica, sans-serif; color: #000; margin: 0; }
h1 { font-size: 13pt; text-align: center; margin: 0 0 10pt; }
.bar { background: #dce6f1; color: #1f5fa8; font-weight: bold; font-size: 12pt; text-align: center; padding: 2pt; margin: 0 0 10pt; }
.t2 { font-weight: bold; font-size: 11pt; text-align: center; margin: 0; }
.small { font-size: 8pt; color: #7f7f7f; text-align: center; margin: 4pt 0 8pt; }
p.intro { margin: 0 0 8pt; }
table { border-collapse: collapse; width: 100%%; table-layout: fixed; }
table.legend { width: auto; margin: 0 auto 8pt; }
table.legend td { padding: 1pt 6pt; font-size: 8pt; }
table.legend td.sw { font-weight: bold; color: #fff; width: 4cm; }
table.calc td, table.q td { vertical-align: top; padding: 3pt 4pt; border-top: 0.5pt solid #a6a6a6; }
table.calc td + td, table.q td + td { border-left: 0.5pt solid #a6a6a6; }
table.calc { margin-bottom: 4pt; border-bottom: 1pt solid #404040; } table.calc td { font-size: 8pt; }
table.q { border-bottom: 1pt solid #404040; }
table.q tr:first-child td { border-top: 1pt solid #404040; }
.module { background: #d9d9d9; font-weight: bold; font-size: 11pt; padding: 2pt 4pt; margin: 10pt 0 0; display: flex; justify-content: space-between; align-items: baseline; break-after: avoid; }
.module .file { font-weight: normal; font-size: 8pt; color: #7f7f7f; }
.module .paused { font-size: 9pt; }
.cond { color: #7f7f7f; font-style: italic; font-size: 8pt; }
.modcond { margin: 1pt 0 2pt; }
td.rep { background: #f2f2f2; font-weight: bold; }
td.rep .cond { font-weight: normal; }
.name { font-weight: bold; }
.opt { display: flex; align-items: baseline; padding-left: 0.3cm; text-indent: -0.3cm; }
.opt .lbl { text-indent: 0; }
.opt .dots { flex: 1; border-bottom: 1px dotted #666; margin: 0 2px 3px; min-width: 8px; }
.opt .skip { font-weight: bold; font-size: 8pt; margin-left: 6pt; white-space: nowrap; }
.ans { color: #7f7f7f; }
.note { font-style: italic; color: #7f7f7f; }
.blue, .blue .ans { color: #1f5fa8; } .green, .green .ans { color: #3a7d44; }
tr { break-inside: auto; }
"""


def esc(t):
    return html.escape(s(t)).replace("\n", "<br>")


def write_html(r, blocks, settings, path):
    rr = f"{r:02d}"
    h = [f"<!doctype html><html><head><meta charset='utf-8'><title>{PROGRAM} CATI R{rr} questionnaire</title><style>",
         CSS % {"footer": f"{PROGRAM} CATI round {r} questionnaire (synthetic example) —"}, "</style></head><body>"]
    for text, style in title_lines(r, settings):
        tag = {"title": "h1", "bar": "p class='bar'", "title2": "p class='t2'", "small": "p class='small'"}[style]
        h.append(f"<{tag}>{esc(text)}</{tag.split(' ')[0]}>")
    h.append(f"<p class='intro'>{esc(INTRO.format(rr=rr))}</p>")
    h.append("<table class='legend'>")
    for text, colour, meaning in LEGEND:
        style = f"background:#{colour}" if colour != "000000" else "background:#fff;color:#000"
        h.append(f"<tr><td class='sw' style='{style}'>{esc(text)}</td><td>{esc(meaning)}</td></tr>")
    h.append("</table>")
    calcs = [b for b in blocks if b["kind"] == "calc"]
    if calcs:
        h.append("<p style='font-weight:bold;margin:4pt 0 2pt'>Preloaded and calculated fields (not asked; filled by the form)</p>")
        h.append("<table class='calc'><colgroup><col style='width:4.5cm'><col></colgroup>")
        for b in calcs:
            rep = f"<br><span class='cond'>in repeat {esc(b['repeat'])}</span>" if b["repeat"] else ""
            h.append(f"<tr><td><span class='name'>{esc(b['name'])}</span>{rep}</td><td>{esc(b['calc'])}</td></tr>")
        h.append("</table>")
    open_table = False
    for b in blocks:
        cls = {BLUE: "blue", GREEN: "green"}.get(b.get("colour"), "")
        if b["kind"] == "module":
            if open_table:
                h.append("</table>")
                open_table = False
            paused = " <span class='paused'>(paused this round)</span>" if b.get("paused") else ""
            h.append(f"<div class='module {cls}'><span>{esc(b['title'])}{paused}</span><span class='file'>{esc(b['file'])}</span></div>")
            if b["cond"]:
                h.append(f"<p class='cond modcond'>asked if {esc(b['cond'])}</p>")
            continue
        if b["kind"] == "calc":
            continue
        if not open_table:
            h.append("<table class='q'><colgroup><col style='width:3.4cm'><col style='width:7.9cm'><col style='width:6.7cm'></colgroup>")
            open_table = True
        if b["kind"] == "repeat":
            extra = f"; if {esc(b['cond'])}" if b["cond"] else ""
            h.append(f"<tr><td class='rep {cls}' colspan='3'>REPEAT {esc(b['name'])}: {esc(b['title'])} "
                     f"<span class='cond'>— {esc(b['count'])}{extra}</span></td></tr>")
            continue
        cond = f"<br><span class='cond'>if {esc(b['cond'])}</span>" if b["cond"] else ""
        c1 = f"<td class='{cls}'><span class='name'>{esc(b['name'])}</span>{cond}</td>"
        if b["type"] == "note":
            h.append(f"<tr>{c1}<td class='note {cls}'>{esc(b['label'])}</td><td></td></tr>")
            continue
        c3 = []
        if b["answer"]:
            c3.append(f"<div class='{'ans' if not b['options'] else ''}'>{esc(b['answer'])}</div>")
        for lab, code, skip in b["options"]:
            sk = f"<span class='skip'>&gt;&gt;&gt; {esc(skip)}</span>" if skip else ""
            c3.append(f"<div class='opt'><span class='lbl'>{esc(lab)}</span><span class='dots'></span><span>{esc(code)}</span>{sk}</div>")
        h.append(f"<tr>{c1}<td class='{cls}'>{esc(b['label'])}</td><td class='{cls}'>{''.join(c3)}</td></tr>")
    if open_table:
        h.append("</table>")
    h.append("</body></html>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(h))


def chrome():
    for c in ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", shutil.which("google-chrome"),
              shutil.which("chromium"), shutil.which("chromium-browser"), shutil.which("chrome")):
        if c and os.path.exists(c):
            return c
    return None


def print_pdf(html_path, pdf_path):
    c = chrome()
    if not c:
        print("   Chrome not found: no PDF written (print the Word file instead)")
        return False
    subprocess.run([c, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={pdf_path}",
                    "file://" + html_path], check=True, capture_output=True, timeout=120)
    return True


# ---------------------------------------------------------------- main
def main():
    os.makedirs(OUT, exist_ok=True)
    prev = None
    for r in sorted(ROUND_START):
        rr = f"{r:02d}"
        survey, choices, settings = read_form(FORM.format(rr=rr))
        blocks = structure(survey, choices)
        shown = with_previous(blocks, prev)
        stem = f"{PROGRAM}_CATI_R{rr}@{ROUND_START[r].strftime('%Y%m%d')}"
        docx_path = os.path.join(OUT, stem + ".docx")
        write_docx(r, shown, settings, docx_path)
        with tempfile.TemporaryDirectory() as tmp:
            html_path = os.path.join(tmp, stem + ".html")
            write_html(r, shown, settings, html_path)
            print_pdf(html_path, os.path.join(OUT, stem + ".pdf"))
        # the form as uploaded, with its media files
        kobo = os.path.join(OUT, "kobo", f"R{rr}")
        os.makedirs(kobo, exist_ok=True)
        shutil.copy2(FORM.format(rr=rr), kobo)
        for f in ("households.csv", "preload.csv"):
            shutil.copy2(os.path.join(MEDIA.format(rr=rr), f), kobo)
        nq = sum(1 for b in blocks if b["kind"] == "q")
        new = sum(1 for b in shown if b["kind"] == "q" and b.get("colour") == BLUE)
        paused = sum(1 for b in shown if b["kind"] == "q" and b.get("colour") == GREEN)
        print(f"R{rr}: {nq} questions, {new} new, {paused} paused -> {stem}.docx / .pdf, kobo/R{rr}/")
        prev = blocks


if __name__ == "__main__":
    main()
