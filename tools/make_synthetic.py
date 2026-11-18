"""Makes every input file of the package from a seed: a synthetic country (frame and census totals, CAPI/ado), a
baseline face-to-face survey (CAPI/raw), and three monthly phone rounds as KoBoToolbox exports (CATI/Round##/xls),
one submission per call attempt, in the layout of the L2PHL phone rounds, with the media files the forms read
(CATI/Round##/kobo). The same dials are also written as a call-centre system log, so step 4 can show that two sources
give one standard call file. Nothing here comes from a real survey: names, numbers, places and answers are made up.

You do not need this script to run the workflow; the package already holds its output. Rerun it only to change the
example.

usage: python3 tools/make_synthetic.py            (needs openpyxl; run make_form.py first)
"""
import csv
import datetime as dt
import json
import math
import os
import random

import openpyxl

import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_form import CHOICES  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAPI = os.path.join(ROOT, "CAPI")                   # the baseline: ado (frame, census), raw (the interviews)
CATI = os.path.join(ROOT, "CATI")                   # the phone rounds: KOBO (forms), ado, Round## (xls, kobo)
SEED = 20261114
TZ = dt.timezone(dt.timedelta(hours=8))
PROGRAM = "L2PHL_SYN"

# ---------------------------------------------------------------- design (step 2 reads the same values from its parameter block)
REGIONS = [1, 2, 3, 4]
LOCALES = [1, 2]                                    # 1 urban, 2 rural
PSU_PER_STRATUM = 15                                # PSUs selected per stratum at baseline
HH_PER_PSU = 15                                     # households interviewed per PSU at baseline (random walk, no listing)
MAIN_PER_PSU = {1: 6, 2: 7}                         # phone subsample per PSU: 6 urban, 7 rural (L2PHL); the rest are replacements
STARTS = {(1, 1): 0.2718, (1, 2): 0.5772, (2, 1): 0.1414, (2, 2): 0.8862, (3, 1): 0.3183, (3, 2): 0.6931, (4, 1): 0.4142, (4, 2): 0.7071}
ROUND_START = {1: dt.date(2026, 3, 2), 2: dt.date(2026, 4, 6), 3: dt.date(2026, 5, 4)}
CALL_DAYS = 18                                      # calling days per round, Monday to Saturday
MAX_DIALS = 6
N_ENUM = 12
MAXMEM = 15


def stratum(region, locale):
    return 10 * region + locale


def logistic(x):
    return 1 / (1 + math.exp(-x))


def write_csv(path, rows, cols, delimiter=","):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols, delimiter=delimiter, lineterminator="\n", extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: ("" if r.get(k) is None else r.get(k)) for k in cols})


# ---------------------------------------------------------------- 1. frame and census totals
def make_frame(rng):
    frame, psu_id = [], 0
    for reg in REGIONS:
        for loc in LOCALES:
            n = rng.randint(230, 290) if loc == 2 else rng.randint(170, 220)
            for _ in range(n):
                psu_id += 1
                hh = int(rng.lognormvariate(math.log(330 if loc == 1 else 190), 0.45))
                hh = max(40, min(hh, 1200))
                size = (4.0 if loc == 1 else 4.5) + rng.uniform(-0.4, 0.4)
                frame.append({"psu": 100000 + reg * 10000 + psu_id, "region": reg, "locale": loc, "stratum": stratum(reg, loc),
                              "hh_census": hh, "pop_census": int(round(hh * size))})
    frame.sort(key=lambda r: (r["stratum"], r["psu"]))
    return frame


def select_psus(frame):
    """Systematic PPS within strata, frame order, measure of size = census households, recorded random starts. The
    number of selection points in (prev, cum] is floor(cum*n/T - start) - floor(prev*n/T - start)."""
    chosen = []
    for s in sorted({r["stratum"] for r in frame}):
        rows = [r for r in frame if r["stratum"] == s]
        tot, n = sum(r["hh_census"] for r in rows), PSU_PER_STRATUM
        start = STARTS[(s // 10, s % 10)]
        cum = 0
        for r in rows:
            prev, cum = cum, cum + r["hh_census"]
            hits = math.floor(cum * n / tot - start) - math.floor(prev * n / tot - start)
            assert hits <= 1, "a certainty PSU: make the frame's PSUs smaller"
            if hits == 1:
                chosen.append(r)
        assert sum(1 for r in chosen if r["stratum"] == s) == n
    return chosen


# ---------------------------------------------------------------- 2. baseline households and members
def make_people(rng, loc):
    size = max(1, min(12, int(round(rng.gauss(4.2 if loc == 1 else 4.7, 1.8)))))
    head_sex = 1 if rng.random() < 0.78 else 2
    head_age = rng.randint(24, 78)
    m = [{"sex": head_sex, "age": head_age, "rel": 1}]
    if size >= 2 and rng.random() < 0.8:
        m.append({"sex": 3 - head_sex, "age": max(18, head_age + rng.randint(-8, 4)), "rel": 2})
    while len(m) < size:
        if rng.random() < 0.72 and head_age > 30:
            m.append({"sex": rng.choice([1, 2]), "age": max(0, min(head_age - 18, rng.randint(0, 30))), "rel": 3})
        elif head_age > 50 and rng.random() < 0.5:
            m.append({"sex": rng.choice([1, 2]), "age": rng.randint(0, 12), "rel": 6})
        elif rng.random() < 0.3:
            m.append({"sex": rng.choice([1, 2]), "age": min(95, head_age + rng.randint(18, 30)), "rel": 7})
        else:
            m.append({"sex": rng.choice([1, 2]), "age": rng.randint(5, 70), "rel": rng.choice([4, 8, 8, 11])})
    return m


def works(rng, p, loc, w):
    if p["age"] < 15:
        return None
    base = -0.3 + (0.9 if p["sex"] == 1 else -0.2) + (0.6 if 25 <= p["age"] <= 59 else -1.0 if p["age"] >= 65 else 0)
    base += (0.25 if loc == 2 else 0) + 0.15 * w
    return 1 if rng.random() < logistic(base) else 2


def make_baseline(rng, chosen):
    hhs, members, used_ids, used_phones = [], [], set(), set()
    for psu in sorted(chosen, key=lambda r: r["psu"]):
        for k in range(HH_PER_PSU):
            while True:
                hid = rng.randint(10001, 99999)
                if hid not in used_ids:
                    used_ids.add(hid)
                    break
            loc = psu["locale"]
            w = rng.gauss(0.45 if loc == 1 else -0.35, 1.0) + 0.15 * (psu["region"] == 1)
            people = make_people(rng, loc)
            has_phone = rng.random() < (0.95 if loc == 1 else 0.88)
            phone = ""
            if has_phone:
                while True:
                    phone = "000" + "".join(str(rng.randint(0, 9)) for _ in range(9))
                    if phone not in used_phones:
                        used_phones.add(phone)
                        break
            respo = 1 if rng.random() < 0.6 or len(people) == 1 else 2
            day = dt.date(2025, 9, 15) + dt.timedelta(days=rng.randint(0, 34))
            h = {"hhid": hid, "psu": psu["psu"], "region": psu["region"], "locale": loc, "stratum": psu["stratum"],
                 "interview_date": day.isoformat(), "hhsize": len(people), "has_phone": int(has_phone), "cp": phone,
                 "respo_fmid": respo, "name": f"Person {hid}-{respo}", "u": round(rng.random(), 6),
                 "_w": w, "_c": rng.gauss(0, 0.9), "_r": rng.gauss(0, 1), "_people": []}
            for i, p in enumerate(people, start=1):
                p = dict(p, fmid=i, name=f"Person {hid}-{i}", perm=1)
                p["emp"] = works(rng, p, loc, w)
                h["_people"].append(p)
                members.append({"hhid": hid, "fmid": i, "name": p["name"], "sex": p["sex"], "age": p["age"], "relationship": p["rel"],
                                "worked_last_week": "" if p["emp"] is None else p["emp"]})
            hhs.append(h)
    return hhs, members


def phone_sample(hhs):
    """Step 2's rule (L2PHL): in each PSU, households with a phone ranked by the baseline key u; the first 6 (urban) or 7
    (rural) are the main sample, the rest are replacements in rank order."""
    by_psu = {}
    for h in hhs:
        if h["has_phone"]:
            by_psu.setdefault(h["psu"], []).append(h)
    for psu, lst in by_psu.items():
        lst.sort(key=lambda h: (h["u"], h["hhid"]))
        k = MAIN_PER_PSU[lst[0]["locale"]]
        for i, h in enumerate(lst):
            h["sample"] = 1 if i < k else 2
            h["rank"] = 0 if i < k else i - k + 1
    return by_psu


# ---------------------------------------------------------------- 3. the phone rounds
def call_days(r):
    d, days = ROUND_START[r], []
    while len(days) < CALL_DAYS:
        if d.weekday() != 6:
            days.append(d)
        d += dt.timedelta(days=1)
    return days


HOURS = list(range(8, 21))
HOUR_W = [3, 8, 10, 9, 5, 7, 9, 9, 9, 9, 8, 6, 3]


def kobo_dt(t):
    return t.strftime("%Y-%m-%dT%H:%M:%S.") + f"{t.microsecond // 1000:03d}+08:00"


def utc_naive(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")


def simulate_case(rng, h, r, days, first_day):
    """The dials of one household in one round. Returns a list of dials (dicts) in time order."""
    dials, di = [], first_day
    dead = rng.random() < (0.04 if r == 1 else 0.02)
    hour = rng.choices(HOURS, HOUR_W)[0]
    t = dt.datetime.combine(days[di], dt.time(hour, rng.randint(0, 59), rng.randint(0, 59)), TZ)
    refuse_p = logistic(-3.2 + 0.6 * h["_r"] + (0.3 if r == 1 else 0))
    for seq in range(1, MAX_DIALS + 1):
        d = {"seq": seq, "start": t}
        evening = t.hour >= 17
        sat = t.weekday() == 5
        if dead:
            x15 = rng.choice([7, 7, 8])
            d.update(x15=x15, call_status1=2, dur=rng.uniform(0.2, 0.8))
        elif rng.random() < logistic(0.1 + h["_c"] + 0.45 * evening + 0.35 * sat - 0.15 * (seq - 1)):
            if rng.random() < 0.05:
                d.update(x15=rng.choice([9, 10]), call_status1=1, Z17=2, dur=rng.uniform(0.8, 2.5))
            elif rng.random() < refuse_p:
                d.update(x15=5, call_status1=1, Z17=1, Z9=2, Z18=rng.choices([1, 2, 3, 4, 96], [40, 30, 10, 15, 5])[0], dur=rng.uniform(1, 4))
            else:
                u = rng.random()
                base = rng.lognormvariate(math.log(26 + 3 * (r == 2)), 0.3)
                if u < 0.06:
                    d.update(x15=4, call_status1=1, Z17=1, Z9=1, dur=rng.uniform(1, 3))
                elif u < 0.09:
                    d.update(x15=3, call_status1=1, Z17=1, Z9=1, dur=base * rng.uniform(0.2, 0.5))
                elif u < 0.11:
                    d.update(x15=2, call_status1=1, Z17=1, Z9=1, dur=base * rng.uniform(0.6, 0.9))
                else:
                    d.update(x15=1, call_status1=1, Z17=1, Z9=1, dur=base)
        else:
            d.update(x15=rng.choice([6, 6, 6, 8]), call_status1=2, dur=rng.uniform(0.3, 1.2))
        d["end"] = t + dt.timedelta(minutes=d["dur"])
        dials.append(d)
        if d["x15"] in (1, 2, 5) or (dead and seq >= 2):
            break
        # the next dial: callbacks the next calling day at the agreed hour, other dials later the same day or the next day
        if d["x15"] in (3, 4) or t.hour >= 17 or rng.random() < 0.45:
            di += 1 if d["x15"] in (3, 4) else rng.choice([1, 1, 2, 3])
            if di >= len(days):
                break
            hour = t.hour if d["x15"] in (3, 4) else rng.choices(HOURS, HOUR_W)[0]
            t = dt.datetime.combine(days[di], dt.time(hour, rng.randint(0, 59), rng.randint(0, 59)), TZ)
        else:
            t = d["end"] + dt.timedelta(hours=rng.uniform(2, 4))
            if t.hour > 20 or t.date() != d["start"].date():
                di += 1
                if di >= len(days):
                    break
                t = dt.datetime.combine(days[di], dt.time(rng.choice([9, 10, 14]), rng.randint(0, 59)), TZ)
    return dials


SHOCK_W = {1: 6, 2: 2, 3: 4, 4: 1, 6: 1, 8: 3, 9: 2, 10: 1, 11: 14, 12: 2, 13: 5, 14: 3, 15: 2, 16: 1, 17: 1, 19: 2, 20: 7, 21: 2, 22: 2, 96: 1}
COPE_W = {1: 2, 3: 12, 4: 3, 5: 4, 6: 2, 7: 3, 8: 8, 9: 1, 10: 5, 11: 4, 12: 4, 13: 12, 14: 7, 15: 4, 17: 10, 18: 1, 96: 1}
FIES_T = {"A": -0.4, "F": -0.1, "G": 0.2, "B": 0.7, "H": 1.1, "C": 1.4, "D": 2.0, "E": 2.7}
LANG = {1: 2, 2: 3, 3: 4, 4: 5}
SHOCK_LABEL = dict(CHOICES["shocks"])


def pick_multi(rng, weights, k):
    keys, ws, out = list(weights), list(weights.values()), []
    while len(out) < k:
        c = rng.choices(keys, ws)[0]
        if c not in out:
            out.append(c)
    return sorted(out)


def interview(rng, h, r, modules):
    """Answers for one completed interview; updates the household's state (members, employment)."""
    a = {"Z20": 1 if rng.random() < 0.98 else 2}
    if a["Z20"] == 2:
        a.update(Z21="Synthetic address", Z1=h["region"], Z5=h["locale"])
    shock_level = {1: 0.25, 2: 0.33, 3: 0.2}[r] + (0.08 if h["_w"] < -0.5 else 0)
    old, new, emp_old, emp_new, left_now = [], [], [], [], set()
    # roster: every member listed so far (left members have perm 0 and no question)
    for p in h["_people"]:
        row = {"fmid": p["fmid"], "fmidname": p["name"], "fmidage": p["age"], "fmidsex": p["sex"], "fmidpermanent": p["perm"]}
        if p["perm"] == 1:
            u = rng.random()
            if u < 0.012 and p["rel"] != 1:
                row["D5a_"] = 2
                left_now.add(p["fmid"])
                row["D25"] = rng.choices([1, 2, 3, 96], [60, 20, 12, 8])[0]
                if row["D25"] == 96:
                    row["D25_oth"] = "Other reason"
                p["perm"] = 0
            elif u < 0.017:
                row["D5a_"] = 4
                row["D28"] = max(0, p["age"] + rng.choice([-2, -1, 1, 2]))
                p["age"] = row["D28"]
            elif u < 0.020:
                row["D5a_"] = 5
                row["D33"] = 3 - p["sex"]
                p["sex"] = row["D33"]
            else:
                row["D5a_"] = 1
        old.append(row)
    a["D29"] = 1 if rng.random() < 0.035 else 2
    if a["D29"] == 1:
        k = len(h["_people"]) + 1
        if k <= MAXMEM:
            baby = rng.random() < 0.55
            age = 0 if baby else rng.randint(16, 40)
            p = {"fmid": k, "name": f"Person {h['hhid']}-{k}", "sex": rng.choice([1, 2]), "age": age, "rel": 6 if baby else rng.choice([2, 5, 8]),
                 "perm": 1, "emp": None}
            nm = {"D30": p["name"], "D31": p["sex"], "D32": age, "D6": p["rel"], "M13_": 40 if baby else rng.choice([2, 10, 12, 9])}
            new.append((nm, p))
        else:
            a["D29"] = 2
    a["newmembers_ct"] = len(new)
    # shocks
    a["SH1"] = 1 if rng.random() < shock_level else 2
    sh2 = []
    if a["SH1"] == 1:
        w = dict(SHOCK_W)
        if r == 2 and h["region"] in (3, 4):
            w[1] = 30
        a["SH1b_"] = pick_multi(rng, w, rng.choices([1, 2, 3], [60, 30, 10])[0])
        if 96 in a["SH1b_"]:
            a["SH1b_oth"] = "Other shock"
        for s in a["SH1b_"]:
            row = {"SH1b_ans": s, "SH1b_ansname": SHOCK_LABEL[s], "SH2_": pick_multi(rng, COPE_W, rng.choices([1, 2, 3], [50, 35, 15])[0])}
            if 96 in row["SH2_"]:
                row["SH2_oth"] = "Other way"
            sh2.append(row)
    job_shock = a["SH1"] == 1 and 13 in a.get("SH1b_", [])
    # employment, members listed at the last interview
    for p in h["_people"]:
        gone_before = p["perm"] == 0 and p["fmid"] not in left_now
        row = {"employ_fmid": p["fmid"], "employ_fmidname": p["name"], "fmid_employment": "" if (p["emp"] is None or gone_before) else p["emp"],
               "employ_left": 1 if p["fmid"] in left_now else 0}
        if p["emp"] is not None and p["perm"] == 1:
            employed = employment_answers(rng, row, p, old=True, job_shock=job_shock)
            p["emp"] = 1 if employed else 2
        emp_old.append(row)
    for nm, p in new:
        row = {"employ_fmid_new": len(emp_new) + 1, "employ_fmidname_new": p["name"], "employ_age_new": p["age"]}
        if p["age"] >= 15:
            employed = employment_answers(rng, row, p, old=False, job_shock=False)
            p["emp"] = 1 if employed else 2
        emp_new.append(row)
        h["_people"].append(p)
    if "finance" in modules:
        w = h["_w"]
        a["F17"] = 1 if rng.random() < logistic(-0.4 + 0.9 * w) else 2
        if a["F17"] == 1:
            a["F1"] = 1 if rng.random() < 0.55 else rng.choices([2, 98], [95, 5])[0]
        a["F18"] = 1 if rng.random() < logistic(0.2 + 0.6 * w) else 2
        if a["F18"] == 1:
            a["F2"] = 1 if rng.random() < 0.7 else rng.choices([2, 98], [95, 5])[0]
        a["F3"] = rng.choices([1, 2, 98], [logistic(-0.8 + 0.8 * w) * 100, (1 - logistic(-0.8 + 0.8 * w)) * 100, 2])[0]
        a["F6"] = rng.choices([1, 2, 98], [logistic(-0.6 + 0.9 * w) * 100, (1 - logistic(-0.6 + 0.9 * w)) * 100, 2])[0]
        a["F7"] = rng.choices([1, 2, 98, 99], [12 + 8 * (a["SH1"] == 1), 85, 1, 2])[0]
        if a["F7"] == 1:
            a["F10"] = rng.choices([1, 2, 99], [70, 20, 10])[0]
    if "health" in modules:
        a["H2"] = rng.choices([1, 2, 3, 4, 98], [6, 22, 3, 68, 1])[0]
        if a["H2"] < 4:
            a["H2A"] = rng.choices([1, 2, 98], [86, 13, 1])[0]
            if a["H2A"] == 2:
                a["H3"] = rng.choices([1, 2, 3, 4, 5, 6, 96], [55, 10, 8, 15, 2, 5, 5])[0]
                if a["H3"] == 96:
                    a["H3_oth"] = "Other reason"
    sev = -0.9 * h["_w"] + (0.7 if a["SH1"] == 1 else 0) + rng.gauss(0, 0.6) - 0.2
    for k, thr in FIES_T.items():
        a[f"F08_{k}"] = 1 if sev + rng.gauss(0, 0.5) > thr else 2
    a["X11"] = 1 if rng.random() < 0.97 else 2
    a["X14"] = h["cp"]
    a["X20"] = rng.choices([1, 2, 3, 4, 5, 7, 8], [30, 15, 3, 25, 18, 7, 2])[0]
    return a, old, [nm for nm, _ in new], sh2, emp_old, emp_new


def employment_answers(rng, row, p, old, job_shock):
    s = "" if old else "_new"
    was = p["emp"]
    if old and was == 1:
        u = rng.random()
        lose = 0.05 + (0.25 if job_shock else 0)
        row["A24"] = 2 if u < lose else (1 if u < lose + 0.03 else 4)
        if row["A24"] == 4:
            employed = True
        else:
            row["A1"] = 1 if row["A24"] == 1 or rng.random() < 0.15 else 2
            employed = row["A1"] == 1
    else:
        if old:
            row["A27"] = 1 if rng.random() < 0.08 else 2
            p_work = 0.9 if row["A27"] == 1 else 0.04
        else:
            p_work = logistic(-0.2 + (0.9 if p["sex"] == 1 else -0.3))
        row[f"A1{s}"] = 1 if rng.random() < p_work else 2
        employed = row[f"A1{s}"] == 1
    if not employed:
        row[f"A26{s}"] = rng.choices([1, 2, 3, 4], [6, 22, 3, 69])[0]
        if row[f"A26{s}"] == 1:
            employed = True
        elif row[f"A26{s}"] in (2, 4):
            row[f"A3{s}"] = rng.choices([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 96], [8, 3, 4, 3, 6, 6, 8, 12, 25, 5, 5, 12, 3])[0]
            if row[f"A3{s}"] == 96:
                row[f"A3_oth{s}"] = "Other reason"
    if employed:
        row[f"A5{s}"] = rng.choices([1, 2, 3, 4, 96], [30, 22, 10, 8, 30])[0]
        if row[f"A5{s}"] == 96:
            row[f"A5_oth{s}"] = "Other industry"
        row[f"A6{s}"] = rng.choices([1, 2, 3, 4, 5, 6, 7], [5, 35, 8, 30, 4, 8, 10])[0]
        row[f"A10{s}"] = rng.choices([3, 4, 5, 6, 7], [5, 8, 35, 37, 15])[0]
        row[f"A11{s}"] = max(1, min(84, int(rng.gauss(7.5 * row[f"A10{s}"], 8))))
    return employed


# ---------------------------------------------------------------- 4. writing a KoBoToolbox export
def form_layout(r):
    """Columns of the export by sheet, from the round's form: questions and calculates in form order (notes and groups
    are not exported), each select_multiple followed by one 0/1 column per option."""
    wb = openpyxl.load_workbook(os.path.join(CATI, "KOBO", f"L2PHL_SYN_CATI_R{r:02d}.xlsx"), read_only=True)
    rows = list(wb["survey"].iter_rows(values_only=True))[1:]
    choices = {}
    for ln, name, _ in list(wb["choices"].iter_rows(values_only=True))[1:]:
        choices.setdefault(ln, []).append(name)
    main = f"{PROGRAM}_CATI_R{r:02d}"
    sheets, stack, kinds = {main: []}, [main], {}
    for row in rows:
        t, name = (row[0] or "").strip(), row[1]
        if t == "begin_repeat":
            stack.append(name)
            sheets[name] = []
            continue
        if t == "end_repeat":
            stack.pop()
            continue
        if t in ("begin_group", "end_group", "note") or not t:
            continue
        sheets[stack[-1]].append(name)
        kinds[name] = t.split()[0]
        if t.startswith("select_multiple"):
            for c in choices[t.split()[1]]:
                sheets[stack[-1]].append(f"{name}/{c}")
    meta_main = ["_id", "_uuid", "_submission_time", "_validation_status", "_notes", "_status", "_submitted_by", "__version__", "_tags", "_index"]
    meta_rep = ["_index", "_parent_table_name", "_parent_index", "_submission__id", "_submission__uuid", "_submission__submission_time",
                "_submission__validation_status", "_submission__notes", "_submission__status", "_submission__submitted_by",
                "_submission___version__", "_submission__tags"]
    return main, sheets, kinds, meta_main, meta_rep


def cell(v, kind):
    if v is None or v == "":
        return None
    if isinstance(v, list):
        return " ".join(str(x) for x in v)
    if kind in ("select_one", "select_one_from_file", "text", "calculate"):
        return str(v)
    return v


def expand_multi(rec, cols):
    for c in cols:
        if "/" in c:
            base, code = c.split("/")
            if base in rec and isinstance(rec[base], list):
                rec[c] = 1 if int(code) in rec[base] else 0
    return rec


def write_export(r, subs, path):
    main, sheets, kinds, meta_main, meta_rep = form_layout(r)
    wb = openpyxl.Workbook(write_only=True)
    out = {name: wb.create_sheet(name[:31]) for name in sheets}
    for name, cols in sheets.items():
        out[name].append(cols + (meta_main if name == main else meta_rep))
    counters = {name: 0 for name in sheets}
    version = f"v{PROGRAM}R{r:02d}2026"
    for i, s in enumerate(subs, start=1):
        rec = expand_multi(dict(s["main"]), sheets[main])
        meta = {"_id": s["_id"], "_uuid": s["_uuid"], "_submission_time": s["_submission_time"], "_validation_status": "", "_notes": "",
                "_status": "submitted_via_web", "_submitted_by": "l2phl_syn_cati", "__version__": version, "_tags": "", "_index": i}
        out[main].append([cell(rec.get(c), kinds.get(c.split("/")[0])) if "/" not in c else rec.get(c) for c in sheets[main]] + [meta[m] for m in meta_main])
        for rep, rows in s["repeats"].items():
            for row in rows:
                counters[rep] += 1
                row = expand_multi(dict(row), sheets[rep])
                m = {"_index": counters[rep], "_parent_table_name": main, "_parent_index": i, "_submission__id": s["_id"], "_submission__uuid": s["_uuid"],
                     "_submission__submission_time": s["_submission_time"], "_submission__validation_status": "", "_submission__notes": "",
                     "_submission__status": "submitted_via_web", "_submission__submitted_by": "l2phl_syn_cati", "_submission___version__": version,
                     "_submission__tags": ""}
                out[rep].append([cell(row.get(c), kinds.get(c.split("/")[0])) if "/" not in c else row.get(c) for c in sheets[rep]] + [m[k] for k in meta_rep])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    wb.save(path)
    return counters


CC_STATUS = {1: "SCS", 2: "PRC", 3: "PRS", 4: "CBK", 5: "RFS", 6: "NOA", 7: "NEX", 8: "OFF", 9: "DKH", 10: "REF"}


def preload_rows(hhs_in_round):
    rows = []
    for h in hhs_in_round:
        row = {"hhid": h["hhid"], "hhsize": sum(p["perm"] for p in h["_people"]), "fmid_max": len(h["_people"]), "sample": h["sample"],
               "round_lastint": h["round_lastint"], "name": h["name"], "cp": h["cp"], "psu": h["psu"], "stratum": h["stratum"]}
        if h["round_lastint"] > 0:
            row["sample"] = 1                          # after round 1 every household is simply in the panel
        for p in h["_people"]:
            k = p["fmid"]
            row.update({f"name{k}": p["name"], f"age{k}": p["age"], f"sex{k}": p["sex"], f"perm{k}": p["perm"],
                        f"emp{k}": "" if (p["emp"] is None or p["perm"] == 0) else p["emp"]})
        rows.append(row)
    return rows


PRELOAD_COLS = ["hhid", "hhsize", "fmid_max", "sample", "round_lastint", "name", "cp", "psu", "stratum"] + \
    [f"{v}{k}" for k in range(1, MAXMEM + 1) for v in ("name", "age", "sex", "perm", "emp")]


# ---------------------------------------------------------------- main
def main():
    rng = random.Random(SEED)
    frame = make_frame(random.Random(SEED + 1))
    chosen = select_psus(frame)
    hhs, members = make_baseline(random.Random(SEED + 2), chosen)
    by_psu = phone_sample(hhs)
    H = {h["hhid"]: h for h in hhs}
    for h in hhs:
        h.setdefault("sample", 0)
        h["round_lastint"] = 0

    write_csv(os.path.join(CAPI, "ado", "frame_psu.csv"), frame, ["psu", "region", "locale", "stratum", "hh_census", "pop_census"])
    tot = {}
    for f in frame:
        t = tot.setdefault(f["stratum"], {"stratum": f["stratum"], "region": f["region"], "locale": f["locale"], "households": 0, "persons": 0})
        t["households"] += f["hh_census"]
        t["persons"] += f["pop_census"]
    write_csv(os.path.join(CAPI, "ado", "census_totals.csv"), sorted(tot.values(), key=lambda x: x["stratum"]),
              ["stratum", "region", "locale", "households", "persons"])
    write_csv(os.path.join(CAPI, "raw", "baseline_households.csv"), hhs,
              ["hhid", "psu", "region", "locale", "stratum", "interview_date", "hhsize", "has_phone", "cp", "respo_fmid", "name", "u"])
    write_csv(os.path.join(CAPI, "raw", "baseline_members.csv"), members, ["hhid", "fmid", "name", "sex", "age", "relationship", "worked_last_week"])

    # enumerators: PSUs dealt out in turn, so each enumerator has PSUs in every region
    psus = sorted(by_psu)
    enum_of_psu = {p: 101 + (i % N_ENUM) for i, p in enumerate(psus)}
    speed = {101 + i: random.Random(SEED + 50 + i).uniform(0.8, 1.2) for i in range(N_ENUM)}
    enums = [{"int_id": 100 + i, "enumerator": f"E{i:02d}", "callcenter_operator": f"CATI{i:02d}"} for i in range(1, N_ENUM + 1)]
    write_csv(os.path.join(CATI, "ado", "enumerators.csv"), enums, ["int_id", "enumerator", "callcenter_operator"])

    expected, panel = [], []
    for r in (1, 2, 3):
        rr = random.Random(SEED + 100 * r)
        days = call_days(r)
        modules = {1: ["finance"], 2: ["health"], 3: ["finance"]}[r]
        if r == 1:
            queue = [h for h in hhs if h.get("sample") == 1]
        else:
            queue = [H[x] for x in panel]
        # the preload the form reads this round (pulldata media) and the household list for the hhid question
        media = os.path.join(CATI, f"Round{r:02d}", "kobo")
        listed = queue + ([h for h in hhs if h.get("sample") == 2] if r == 1 else [])
        write_csv(os.path.join(media, "preload.csv"), preload_rows(sorted(listed, key=lambda h: h["hhid"])), PRELOAD_COLS)
        write_csv(os.path.join(media, "households.csv"), [{"name": h["hhid"], "label": str(h["hhid"])} for h in sorted(listed, key=lambda h: h["hhid"])],
                  ["name", "label"])
        # dials: every case gets a first-dial day spread over the first ten calling days, by enumerator
        cases = []
        by_enum = {}
        for h in queue:
            by_enum.setdefault(enum_of_psu[h["psu"]], []).append(h)
        for e, lst in sorted(by_enum.items()):
            rr.shuffle(lst)
            for i, h in enumerate(lst):
                cases.append((e, h, min(9, int(i / len(lst) * 10 / speed[e]))))
        completed, subs, cc_rows, all_dials = [], [], [], []
        pending = list(cases)
        tried_rep = set()
        while pending:
            e, h, fd = pending.pop(0)
            dials = simulate_case(rr, h, r, days, fd)
            done = any(d["x15"] in (1, 2) for d in dials)
            for d in dials:
                all_dials.append((e, h, d))
            if done:
                completed.append(h["hhid"])
            elif r == 1 and h["sample"] == 1 or (r == 1 and h.get("replaces")):
                # L2PHL rule in round 1: a main household that refuses, has a dead number or is not reached is replaced by the
                # next replacement of its PSU, called by the same enumerator
                orig = h.get("replaces") or h["hhid"]
                reps = [x for x in by_psu[h["psu"]] if x["sample"] == 2 and x["hhid"] not in tried_rep]
                last_day = max(d["start"] for d in dials).date()
                nxt = days.index(last_day) + 1 if last_day in days else len(days)
                if reps and nxt < len(days) - 2:
                    rep = reps[0]
                    tried_rep.add(rep["hhid"])
                    rep["replaces"] = orig
                    pending.append((e, rep, nxt))
        # submissions, one per dial, in time order
        all_dials.sort(key=lambda x: x[2]["start"])
        n_id = 700000 * r
        attempts = {}
        for e, h, d in all_dials:
            n_id += 1
            attempts[h["hhid"]] = attempts.get(h["hhid"], 0) + 1
            end = d["end"] + dt.timedelta(seconds=rr.randint(20, 150))
            subt = end + dt.timedelta(minutes=rr.randint(1, 360))
            m = {"start": kobo_dt(d["start"]), "end": kobo_dt(end), "deviceid": f"collect:syn{e}", "int_id": e, "hhid": h["hhid"],
                 "hhsize": sum(p["perm"] for p in h["_people"]), "fmid_max": len(h["_people"]), "sample": h["sample"] if r == 1 else 1,
                 "round_lastint": h["round_lastint"], "oldrespo": h["name"], "oldcp": h["cp"],
                 "replacement_hhid": h.get("replaces", "") if (r == 1 and h["sample"] == 2) else "",
                 "D3": LANG[h["region"]] if rr.random() < 0.85 else 1,
                 "Z6": d["start"].strftime("%Y-%m-%d"), "Z7": d["start"].strftime("%H:%M:%S.000+08:00"), "Z8": min(attempts[h["hhid"]], 3),
                 "call_status1": d["call_status1"], "Z17": d.get("Z17", ""), "Z9": d.get("Z9", ""), "Z18": d.get("Z18", ""),
                 "Z18_oth": "Other reason" if d.get("Z18") == 96 else "", "X15": d["x15"], "X16": ""}
            reps = {}
            if d["x15"] in (1, 2):
                a, old, new, sh2, emp_old, emp_new = interview(rr, h, r, modules)
                m.update(a)
                reps = {"old_": old, "newmembers": new, "sh2_": sh2, "employ_": emp_old, "employ_new": emp_new}
                h["round_lastint"] = r
            subs.append({"main": m, "repeats": reps, "_id": n_id, "_uuid": f"syn-{r}-{n_id}", "_submission_time": utc_naive(subt), "_dial": d,
                         "_e": e, "_h": h})
            cc_rows.append({"id": n_id, "operator_id": f"CATI{e - 100:02d}", "hh_id": h["hhid"], "round": r, "dialing_phone": h["cp"],
                            "start_time": d["start"].strftime("%Y-%m-%d %H:%M:%S"), "end_time": d["end"].strftime("%Y-%m-%d %H:%M:%S"),
                            "status": CC_STATUS[d["x15"]], "comment": ""})
        # planted problems of the kind real exports have (docs/synthetic_data.md lists them; step 3 finds them)
        q = random.Random(SEED + 900 + r)
        comp = [s for s in subs if s["main"]["X15"] in (1, 2)]
        n_test = 3 if r == 1 else 0
        tests = []
        for k in range(n_test):                      # practice interviews the day before fieldwork
            src = comp[k]
            t = dt.datetime.combine(ROUND_START[r] - dt.timedelta(days=1), dt.time(10 + k, 5), TZ)
            dup = json.loads(json.dumps({"main": src["main"], "repeats": src["repeats"]}, default=str))
            dup["main"].update(start=kobo_dt(t), end=kobo_dt(t + dt.timedelta(minutes=24)), Z6=t.strftime("%Y-%m-%d"), Z7=t.strftime("%H:%M:%S.000+08:00"), Z8=1)
            n_id += 1
            tests.append({**dup, "_id": n_id, "_uuid": f"syn-{r}-{n_id}", "_submission_time": utc_naive(t + dt.timedelta(minutes=30))})
        dups = []
        for src in q.sample(comp, 4):                # the same interview sent twice
            n_id += 1
            later = dt.datetime.fromisoformat(src["_submission_time"]) + dt.timedelta(minutes=q.randint(2, 50))
            dups.append({"main": src["main"], "repeats": src["repeats"], "_id": n_id, "_uuid": f"syn-{r}-{n_id}", "_submission_time": later.strftime("%Y-%m-%dT%H:%M:%S")})
        for src in q.sample([s for s in subs if s["main"]["X15"] not in (1, 2)], 2):   # device clock: end before start
            st = dt.datetime.fromisoformat(src["main"]["start"])
            src["main"]["end"] = kobo_dt(st - dt.timedelta(minutes=q.randint(5, 40)))
        # form-logic problems: step 3's skip-logic audit (37_form_audit.do) reads the rules from the form and finds them
        for src in q.sample([x for x in comp if x["main"].get("Z20") == 1], 3):   # a new address typed although the household had not moved
            src["main"]["Z21"] = "Synthetic address"
        for src in q.sample(comp, 4):                                             # a required answer left empty
            src["main"].pop("F08_C", None)
        emp = [x for x in comp if any("A11" in row for row in x["repeats"]["employ_"])]
        for i, src in enumerate(q.sample(emp, 3)):                                # hours and days outside the form's limits
            row = next(row for row in src["repeats"]["employ_"] if "A11" in row)
            if i < 2:
                row["A11"] = q.randint(170, 250)
            else:
                row["A10"] = 9
        short = 0
        for src in q.sample(comp, 3):               # a complete coded on a dial under three minutes
            st = dt.datetime.fromisoformat(src["main"]["start"])
            src["main"]["end"] = kobo_dt(st + dt.timedelta(seconds=q.randint(60, 150)))
            for c in cc_rows:
                if c["id"] == src["_id"]:
                    c["end_time"] = (st + dt.timedelta(seconds=q.randint(40, 120))).strftime("%Y-%m-%d %H:%M:%S")
            short += 1
        out = sorted(subs + tests + dups, key=lambda s: s["_submission_time"])
        last = days[-1] + dt.timedelta(days=1)
        fname = f"{PROGRAM}_CATI_R{r:02d}_-_all_versions_-_False_-_{last.isoformat()}-18-00-00.xlsx"
        counts = write_export(r, out, os.path.join(CATI, f"Round{r:02d}", "xls", fname))
        # the same dials in a call-centre system's log (semicolon CSV); one operator code typed with a hyphen
        for c in cc_rows:
            if c["operator_id"] == "CATI07" and c["id"] % 5 == 0:
                c["operator_id"] = "CATI-07"
        write_csv(os.path.join(CATI, f"Round{r:02d}", "xls", "callcenter", f"calllog_R{r:02d}.csv"), cc_rows,
                  ["id", "operator_id", "hh_id", "round", "dialing_phone", "start_time", "end_time", "status", "comment"], delimiter=";")
        if r == 1:
            panel = sorted(set(completed))
        expected.append({"round": r, "submissions": len(out), "dials": len(subs), "test_submissions": len(tests), "duplicate_submissions": len(dups),
                         "negative_durations": 2, "short_completes": short, "routing_broken": 3, "required_missing": 4, "out_of_range": 3, "households_called": len({s["_h"]["hhid"] for s in subs}),
                         "completes": len(set(completed)), "replacements_called": sum(1 for s in {x["_h"]["hhid"]: x for x in subs}.values() if s["_h"]["sample"] == 2),
                         "roster_rows": counts["old_"], "file": fname})
        print(f"R{r}: {len(subs)} dials, {len(set(completed))} completes, {len(out)} submissions in the export ({fname})")
    # the preload a team would build for round 4: step 3 rebuilds it from round 3's module files and checks it against this
    queue = [H[x] for x in panel]
    write_csv(os.path.join(CATI, "Round04", "kobo", "preload.csv"), preload_rows(sorted(queue, key=lambda h: h["hhid"])), PRELOAD_COLS)
    write_csv(os.path.join(ROOT, "tests", "expected_counts.csv"), expected, list(expected[0]))
    print(f"frame {len(frame)} PSUs; baseline {len(hhs)} households, {len(members)} members; phone sample main "
          f"{sum(1 for h in hhs if h.get('sample') == 1)}, replacements {sum(1 for h in hhs if h.get('sample') == 2)}")


if __name__ == "__main__":
    main()
