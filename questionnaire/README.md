# Questionnaire and KoBo form

For each round, what the field team and the reviewers get in the L2 programs:

| File | What it is |
|---|---|
| `kobo/R##/L2PHL_SYN_CATI_R##.xlsx` | The KoBoToolbox form (XLSForm) as uploaded. The same file as `data/form/L2PHL_SYN_CATI_R##.xlsx`, which the do-files read. |
| `kobo/R##/households.csv`, `kobo/R##/preload.csv` | The two media files the form reads: the list behind the household question (`select_one_from_file`) and the previous round's roster and contacts (`pulldata`). The same files as `data/raw/R##/media`. |
| `L2PHL_SYN_CATI_R##@<round start>.docx` | The questionnaire as a Word document, in the layout the L2 programs use. |
| `L2PHL_SYN_CATI_R##@<round start>.pdf` | The same questionnaire as a PDF. |

Everything is built from the form itself by `tools/make_questionnaire.py`, so the document and the deployed form cannot drift apart. The three forms convert with pyxform (the converter KoBoToolbox runs on upload) without warnings.

The XLSForm's sheets are colour-coded (see its `legend` sheet): the L2PHL fills for groups, repeats and calculated fields, one colour per question type, a yellow name cell on rows new since the previous round, and the choice lists banded. KoBoToolbox reads the values only.

## The document's layout

- A title block with the round and its calling days, then a colour legend and the list of preloaded and calculated fields (filled by the form, never asked).
- One shaded heading per module, with the condition under which the module is asked and, on the right, the module file it feeds (`docs/module_files.md`).
- Three columns per question: the variable name with the condition under which it is asked (grey italics, from the form's `relevant` column); the question text; the coded answer options with dot leaders, or the answer type and its limits (from the `constraint` column). A repeat group is a shaded row saying what it repeats over.
- `>>> name` beside an option marks the question asked only on that answer, when it is not the next question in the form.
- Colours: questions in blue are new in this round; questions in green were asked in the previous round and are paused in this one (so round 2 shows health in blue and finance in green, and round 3 the reverse).

## Deploying the form

1. In KoBoToolbox, create a project by uploading the XLSForm.
2. Add `households.csv` and `preload.csv` as form media (Settings, Media), then deploy.
3. Each new round: upload the next round's XLSForm as a new project (the L2PHL practice: one project per round), with the household list and the preload that step 36 of the workflow builds from the previous round's data.

## Rebuilding the documents

```
python3 tools/make_questionnaire.py
```

Needs Python 3 with openpyxl and python-docx. The PDF is printed from an HTML twin with Google Chrome; without Chrome the script writes the Word file only, which can be printed to PDF from Word.
