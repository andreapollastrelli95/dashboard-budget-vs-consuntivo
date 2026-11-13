# -----------------------------------------------------------------------------
# Generazione dataset simulato - Arcadia Distribuzione S.r.l.
# Progetto: Budget vs Consuntivo per centro di costo
#
# Azienda commerciale B2B (forniture IT, ufficio e servizi di assistenza),
# 6 centri di ricavo e 7 centri di costo.
#
# Scenari:
#   Actual   2024-2025  registrazioni contabili (righe di prima nota)
#   Budget   2024-2025  mensile per centro di costo e conto
#   Forecast 2025       revisione 6+6 (consuntivo gen-giu + nuova stima lug-dic)
# Piu' l'organico (FTE) a budget e a consuntivo per centro di costo.
#
# Il budget 2025 e' costruito come lo costruirebbe il controllo di gestione:
# consuntivo 2024 x ipotesi di crescita per centro, fasato sulla stagionalita'
# 2024. Il consuntivo 2025 poi devia dal budget per motivi precisi (vedi sotto).
# -----------------------------------------------------------------------------
import os
from datetime import date, timedelta

import numpy as np
import pandas as pd

rng = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------ anagrafiche
cost_centers = pd.DataFrame([
    # code, nome, tipo, area, responsabile
    ("PC10", "Vendite Nord-Ovest",           "Centro di ricavo", "Commerciale", "L. Ferraris"),
    ("PC20", "Vendite Nord-Est",             "Centro di ricavo", "Commerciale", "M. Zanella"),
    ("PC30", "Vendite Centro",               "Centro di ricavo", "Commerciale", "S. Marini"),
    ("PC40", "Vendite Sud e Isole",          "Centro di ricavo", "Commerciale", "A. Esposito"),
    ("PC50", "Key Account / Grandi clienti", "Centro di ricavo", "Commerciale", "F. Colombo"),
    ("PC60", "E-commerce",                   "Centro di ricavo", "Commerciale", "G. Riva"),
    ("CC10", "Marketing",                    "Centro di costo",  "Commerciale", "E. Bassi"),
    ("CC20", "Logistica e magazzino",        "Centro di costo",  "Operations",  "R. Pellegrini"),
    ("CC30", "Assistenza tecnica",           "Centro di costo",  "Operations",  "D. Fontana"),
    ("CC40", "Amministrazione e finanza",    "Centro di costo",  "Struttura",   "C. Gallo"),
    ("CC50", "IT e sistemi",                 "Centro di costo",  "Struttura",   "P. Testa"),
    ("CC60", "Risorse umane",                "Centro di costo",  "Struttura",   "V. Longo"),
    ("CC70", "Direzione generale",           "Centro di costo",  "Struttura",   "A. Martini"),
], columns=["CostCenterCode", "CostCenterName", "CostCenterType", "BusinessArea", "Manager"])

accounts = pd.DataFrame([
    # code, nome, gruppo CE, tipo, controllabile, segno, ordine
    ("4010", "Ricavi vendita prodotti",              "Ricavi",                "Revenue", 1,  1, 10),
    ("4020", "Ricavi da servizi e assistenza",       "Ricavi",                "Revenue", 1,  1, 11),
    ("4090", "Sconti e premi a clienti",             "Ricavi",                "Revenue", 1,  1, 12),
    ("5010", "Acquisto merci",                       "Costo del venduto",     "COGS",    1, -1, 20),
    ("5020", "Trasporti su acquisti",                "Costo del venduto",     "COGS",    1, -1, 21),
    ("6010", "Retribuzioni",                         "Costo del personale",   "Opex",    1, -1, 30),
    ("6020", "Oneri sociali e TFR",                  "Costo del personale",   "Opex",    1, -1, 31),
    ("6110", "Provvigioni agenti",                   "Costi commerciali",     "Opex",    1, -1, 40),
    ("6120", "Trasporti su vendite",                 "Costi commerciali",     "Opex",    1, -1, 41),
    ("6130", "Pubblicità, fiere e digital",          "Costi commerciali",     "Opex",    1, -1, 42),
    ("6210", "Affitti e spese condominiali",         "Costi di struttura",    "Opex",    0, -1, 50),
    ("6220", "Utenze",                               "Costi di struttura",    "Opex",    1, -1, 51),
    ("6230", "Consulenze e servizi professionali",   "Costi di struttura",    "Opex",    1, -1, 52),
    ("6240", "Licenze software e cloud",             "Costi di struttura",    "Opex",    1, -1, 53),
    ("6250", "Viaggi e trasferte",                   "Costi di struttura",    "Opex",    1, -1, 54),
    ("6260", "Auto aziendali (noleggi e carburante)", "Costi di struttura",   "Opex",    1, -1, 55),
    ("6290", "Altri costi di gestione",              "Costi di struttura",    "Opex",    1, -1, 56),
    ("7010", "Ammortamenti",                         "Ammortamenti",          "D&A",     0, -1, 70),
], columns=["AccountCode", "AccountName", "PLGroup", "AccountType", "IsControllable", "PLSign", "SortOrder"])

# ------------------------------------------------------------------ parametri economici
months = pd.period_range("2024-01", "2025-12", freq="M")
season = np.array([.82, .92, 1.08, 1.0, 1.06, 1.08, 1.04, .62, 1.02, 1.12, 1.14, 1.10])
season = season / season.mean()

# ricavi prodotti 2024 (euro/anno) per centro di ricavo
rev24 = {"PC10": 9_300_000, "PC20": 7_700_000, "PC30": 5_900_000, "PC40": 3_900_000, "PC50": 8_600_000, "PC60": 2_700_000}
serv_share = {"PC10": .09, "PC20": .08, "PC30": .10, "PC40": .07, "PC50": .14, "PC60": .02}
gm24 = {"PC10": .285, "PC20": .29, "PC30": .28, "PC40": .265, "PC50": .225, "PC60": .32}   # margine su prodotti
disc = {"PC10": .021, "PC20": .02, "PC30": .018, "PC40": .016, "PC50": .034, "PC60": .004}  # premi a clienti

# ipotesi di budget 2025 (crescita ricavi)
bud_g = {"PC10": .05, "PC20": .06, "PC30": .04, "PC40": .08, "PC50": .09, "PC60": .25}
# consuntivo 2025 vs budget: fattore realizzato (vendite) e delta margine (pp)
act_vs_bud = {"PC10": 1.012, "PC20": .985, "PC30": 1.004, "PC40": .905, "PC50": .968, "PC60": 1.14}
gm_delta25 = {"PC10": -.004, "PC20": -.006, "PC30": -.002, "PC40": -.012, "PC50": -.011, "PC60": -.006}

# Key Account: contratto quadro con una grande banca slittato da aprile a luglio 2025
ka_shift = {4: .80, 5: .78, 6: .84, 7: 1.08, 8: 1.06, 9: 1.08, 10: 1.07, 11: 1.07, 12: 1.06}

# organico (FTE) 2024 per centro e retribuzione lorda annua media
fte24 = {"PC10": 9, "PC20": 8, "PC30": 7, "PC40": 5, "PC50": 6, "PC60": 4, "CC10": 5, "CC20": 18,
         "CC30": 14, "CC40": 8, "CC50": 5, "CC60": 3, "CC70": 3}
ral = {"PC10": 44_000, "PC20": 43_000, "PC30": 42_000, "PC40": 39_000, "PC50": 52_000, "PC60": 38_000,
       "CC10": 41_000, "CC20": 31_000, "CC30": 36_000, "CC40": 40_000, "CC50": 46_000, "CC60": 42_000, "CC70": 95_000}
fte_bud25_add = {"PC60": 2, "CC30": 3, "CC50": 1, "PC40": 1, "CC20": 1}      # assunzioni a budget 2025
hire_month_bud = {"PC60": 3, "CC30": 2, "CC50": 4, "PC40": 4, "CC20": 3}
hire_month_act = {"PC60": 3, "CC30": 7, "CC50": 9, "PC40": 11, "CC20": 3}    # ritardi nelle assunzioni

# costi operativi annui 2024 per (conto, centro)
opex24 = {
    ("6110", "PC10"): 0, ("6130", "CC10"): 520_000, ("6130", "PC60"): 260_000,
    ("6210", "CC20"): 410_000, ("6210", "CC70"): 290_000, ("6220", "CC20"): 95_000, ("6220", "CC70"): 60_000,
    ("6230", "CC40"): 145_000, ("6230", "CC70"): 180_000, ("6230", "CC60"): 70_000,
    ("6240", "CC50"): 210_000, ("6240", "PC60"): 55_000,
    ("6250", "PC10"): 48_000, ("6250", "PC20"): 52_000, ("6250", "PC30"): 41_000, ("6250", "PC40"): 46_000,
    ("6250", "PC50"): 64_000, ("6250", "CC30"): 58_000, ("6250", "CC70"): 35_000,
    ("6260", "PC10"): 62_000, ("6260", "PC20"): 58_000, ("6260", "PC30"): 49_000, ("6260", "PC40"): 40_000,
    ("6260", "PC50"): 44_000, ("6260", "CC30"): 96_000, ("6260", "CC70"): 28_000,
    ("6290", "CC40"): 85_000, ("6290", "CC20"): 60_000,
    ("7010", "CC20"): 240_000, ("7010", "CC50"): 150_000, ("7010", "CC70"): 60_000,
}
# budget 2025 sui costi: variazione vs 2024
opex_bud_g = {"6130": .10, "6210": .02, "6220": -.05, "6230": .03, "6240": .06, "6250": .03, "6260": .03, "6290": .0, "7010": .04}
# consuntivo 2025 vs budget (fattore)
opex_act_vs_bud = {("6130", "CC10"): .93, ("6130", "PC60"): 1.18, ("6230", "CC40"): 1.42,       # progetto nuovo ERP
                   ("6240", "CC50"): 1.31,                                                       # cybersecurity non a budget
                   ("6250", "PC50"): 1.22, ("6260", "CC30"): 1.09, ("6220", "CC20"): 1.08}

# ------------------------------------------------------------------ helper
def month_rows(y):
    return [p for p in months if p.year == y]


def budget_phase(total, prof):
    return total * prof / prof.sum()


# ------------------------------------------------------------------ 1. RICAVI e COGS mensili (consuntivo)
act_m = []   # (period, cc, account, amount positivo in segno naturale)
for cc, base in rev24.items():
    for p in months:
        y, m = p.year, p.month
        s = season[m - 1]
        if cc == "PC60":
            s = season[m - 1] * (1.25 if m in (11, 12) else 1)   # black friday / natale
        if y == 2024:
            prod = base / 12 * s * rng.normal(1, .035)
            gm = gm24[cc] + rng.normal(0, .006)
        else:
            prod = base * (1 + bud_g[cc]) / 12 * s * act_vs_bud[cc] * rng.normal(1, .035)
            if cc == "PC50":
                prod *= ka_shift.get(m, 1.0)
            if cc == "PC40":
                prod *= 1 - 0.012 * m / 12 * 6     # perdita progressiva di due clienti importanti
            gm = gm24[cc] + gm_delta25[cc] + rng.normal(0, .006)
        serv = prod * serv_share[cc] / (1 - serv_share[cc]) * rng.normal(1, .05)
        act_m += [(p, cc, "4010", prod), (p, cc, "4020", serv), (p, cc, "4090", -prod * disc[cc] * rng.normal(1, .08)),
                  (p, cc, "5010", prod * (1 - gm)), (p, cc, "5020", prod * .012 * rng.normal(1, .1))]
        # costi commerciali variabili
        act_m.append((p, cc, "6110", prod * (.03 if cc != "PC60" and cc != "PC50" else (.015 if cc == "PC50" else 0))))
        tr_rate = .021 if y == 2024 else .021 * 1.11       # aumento tariffe corrieri 2025
        if cc == "PC60":
            tr_rate *= 2.2
        act_m.append((p, "CC20" if cc != "PC60" else "PC60", "6120", prod * tr_rate * rng.normal(1, .05)))

# ------------------------------------------------------------------ 2. PERSONALE (consuntivo)
fte_rows = []
for cc, f in fte24.items():
    for p in months:
        y, m = p.year, p.month
        fte_act = f
        if y == 2025 and cc in fte_bud25_add and m >= hire_month_act[cc]:
            fte_act = f + fte_bud25_add[cc]
        if y == 2025 and cc == "CC20" and m >= 9:
            fte_act -= 1                                  # dimissione non sostituita
        r = ral[cc] * (1.0 if y == 2024 else 1.025)       # rinnovo CCNL commercio
        mult = 2.0 if m in (7, 12) else 1.0               # 14esima e 13esima
        sal = fte_act * r / 14 * mult * rng.normal(1, .015)
        if cc in ("PC10", "PC20", "PC30", "PC40", "PC50") and m in (3, 9):
            sal += fte_act * r * .06 * rng.normal(1, .1)   # premi semestrali venditori
        act_m += [(p, cc, "6010", sal), (p, cc, "6020", sal * .38)]
        fte_rows.append((p, cc, "Actual", fte_act))

# ------------------------------------------------------------------ 3. ALTRI COSTI (consuntivo)
for (acc, cc), base in opex24.items():
    if base == 0:
        continue
    for p in months:
        y, m = p.year, p.month
        mshape = 1.0
        if acc == "6130":
            mshape = {3: 1.6, 4: 1.3, 9: 1.4, 10: 1.5, 11: 1.6 if cc == "PC60" else 1.2, 8: .3}.get(m, .8)
        if acc == "6220":
            mshape = {1: 1.3, 2: 1.25, 7: 1.15, 8: 1.1, 12: 1.2}.get(m, .85)
        val = base / 12 * mshape
        if y == 2025:
            val *= (1 + opex_bud_g[acc]) * opex_act_vs_bud.get((acc, cc), 1.0)
            if acc == "6130" and cc == "CC10":
                val *= .78 if m <= 6 else 1.18          # campagne spostate nel secondo semestre
            if acc == "6230" and cc == "CC40":
                val *= 1.6 if 3 <= m <= 9 else .6       # progetto ERP
            if acc == "6240" and cc == "CC50" and m < 5:
                val /= 1.31                              # il progetto cyber parte a maggio
        act_m.append((p, cc, acc, val * rng.normal(1, .06)))

act_m = pd.DataFrame(act_m, columns=["Period", "CostCenterCode", "AccountCode", "Amount"])
act_m = act_m.groupby(["Period", "CostCenterCode", "AccountCode"], as_index=False).Amount.sum()
act_m = act_m[act_m.Amount.abs() > 0.5].reset_index(drop=True)

# ------------------------------------------------------------------ 4. BUDGET
# il budget dell'anno Y e' costruito sul consuntivo Y-1 (per il 2024 uso un "2023" stimato)
bud = []
bud_fte = []
act_tot = act_m.copy()
act_tot["Year"] = act_tot.Period.map(lambda p: p.year)
act_tot["Month"] = act_tot.Period.map(lambda p: p.month)
a24 = act_tot[act_tot.Year == 2024]
for (cc, acc), g in a24.groupby(["CostCenterCode", "AccountCode"]):
    prof = g.sort_values("Month").Amount.values
    total24 = prof.sum()
    # profilo mensile: stagionalita' del consuntivo 2024
    if acc in ("6010", "6020"):
        shape = np.array([1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2], dtype=float)
    else:
        shape = prof / prof.mean() if len(prof) == 12 and prof.mean() != 0 else np.ones(12)
    # budget 2024: consuntivo 2024 "atteso" con piccoli errori di previsione
    b24 = total24 * rng.normal(1.0, .03)
    # budget 2025
    if acc in ("4010", "4020", "4090", "5010", "5020", "6110", "6120"):
        driver = cc if cc.startswith("PC") else None
        if acc == "6120" and cc == "CC20":
            gfac = 1 + np.average(list(bud_g.values()), weights=list(rev24.values()))
            gfac *= 1.03                                  # tariffe corrieri a budget +3%
        elif acc == "6120":
            gfac = 1 + bud_g["PC60"]
        else:
            gfac = 1 + bud_g[cc]
        if acc == "5010":
            gfac *= (1 - (gm24[cc] - 0.003)) / (1 - gm24[cc])   # a budget margine +0,3pp (listini 2025)
        b25 = total24 * gfac
    elif acc in ("6010", "6020"):
        f25 = fte24[cc] + (fte_bud25_add.get(cc, 0) * (13 - hire_month_bud.get(cc, 13)) / 12)
        b25 = total24 * (f25 / fte24[cc]) * 1.025
        if acc == "6010" and cc.startswith("PC") and cc != "PC60":
            b25 *= 0.99
    else:
        b25 = total24 * (1 + opex_bud_g.get(acc, 0))
    for y, tot in ((2024, b24), (2025, b25)):
        ph = budget_phase(tot, shape)
        if acc in ("6010", "6020") and y == 2025 and cc in fte_bud25_add:
            # le nuove risorse entrano a budget dal mese di assunzione
            base_m = total24 * 1.025 / shape.sum() * shape
            extra = np.array([fte_bud25_add[cc] / fte24[cc] * total24 * 1.025 / shape.sum() * shape[i]
                              if i + 1 >= hire_month_bud[cc] else 0 for i in range(12)])
            ph = base_m + extra
        for i in range(12):
            bud.append((pd.Period(f"{y}-{i+1:02d}", "M"), cc, acc, "Budget", ph[i]))

for cc, f in fte24.items():
    for i in range(12):
        bud_fte.append((pd.Period(f"2024-{i+1:02d}", "M"), cc, "Budget", f))
        add = fte_bud25_add.get(cc, 0) if i + 1 >= hire_month_bud.get(cc, 13) else 0
        bud_fte.append((pd.Period(f"2025-{i+1:02d}", "M"), cc, "Budget", f + add))

bud = pd.DataFrame(bud, columns=["Period", "CostCenterCode", "AccountCode", "Scenario", "Amount"])

# ------------------------------------------------------------------ 5. FORECAST 6+6 (luglio 2025)
# gen-giu = consuntivo; lug-dic = budget corretto con le tendenze del primo semestre
fc = []
h1a = act_tot[(act_tot.Year == 2025) & (act_tot.Month <= 6)].groupby(["CostCenterCode", "AccountCode"]).Amount.sum()
h1b = bud[(bud.Period >= pd.Period("2025-01", "M")) & (bud.Period <= pd.Period("2025-06", "M"))].groupby(["CostCenterCode", "AccountCode"]).Amount.sum()
for r in act_tot[(act_tot.Year == 2025) & (act_tot.Month <= 6)].itertuples():
    fc.append((r.Period, r.CostCenterCode, r.AccountCode, "Forecast", r.Amount))
for r in bud[(bud.Period >= pd.Period("2025-07", "M"))].itertuples():
    k = (r.CostCenterCode, r.AccountCode)
    ratio = h1a.get(k, 0) / h1b[k] if h1b.get(k, 0) else 1.0
    # il controller recepisce solo meta' del trend (prudenza), tranne che per le note una tantum
    adj = 1 + (ratio - 1) * 0.5
    if k == ("6230", "CC40"):
        adj = 1.35
    if r.CostCenterCode == "PC50" and r.AccountCode in ("4010", "4020", "5010", "5020", "6110"):
        adj = 1.03                                     # contratto banca partito: recupero atteso
    if r.CostCenterCode == "PC40" and r.AccountCode in ("4010", "4020", "5010", "5020", "6110", "4090"):
        adj = min(adj, .9)
    fc.append((r.Period, r.CostCenterCode, r.AccountCode, "Forecast", r.Amount * adj))
fc = pd.DataFrame(fc, columns=bud.columns)
plan = pd.concat([bud, fc], ignore_index=True)

# ------------------------------------------------------------------ 6. CONSUNTIVO: righe di prima nota
# ogni importo mensile viene spezzato in documenti con data, numero e descrizione
customers_prefix = ["Studio", "Gruppo", "Comune di", "Azienda", "Istituto", "Ospedale", "Banca", "Hotel", "Officine", "Tecno"]
cust_suffix = ["Rossi", "Bianchi", "Verdi", "Lombardo", "Galli", "Conti", "Moretti", "Ricci", "Mancini", "Costa", "Fabbri", "Marino"]
vendors = {
    "5010": ["Esprinet S.p.A.", "Ingram Micro S.r.l.", "Computer Gross S.p.A.", "Tech Data Italia S.r.l.", "Brother Italia S.p.A."],
    "5020": ["BRT S.p.A.", "GLS Italy S.p.A."], "6120": ["BRT S.p.A.", "GLS Italy S.p.A.", "DHL Express Italy S.r.l.", "Poste Italiane - SDA"],
    "6130": ["Google Ireland Ltd", "Meta Platforms Ireland Ltd", "Fiera Milano S.p.A.", "Agenzia Creativa Punto S.r.l."],
    "6210": ["Immobiliare Pradella S.r.l.", "Condominio Business Park"], "6220": ["Enel Energia S.p.A.", "Hera Comm S.p.A."],
    "6230": ["Studio Associato Neri & Partners", "SAP Partner Consulting S.r.l.", "Studio Legale Amato", "PwC Advisory"],
    "6240": ["Microsoft Ireland Operations Ltd", "Zucchetti S.p.A.", "Amazon Web Services EMEA", "Cyber Shield S.r.l."],
    "6250": ["Trenitalia S.p.A.", "ITA Airways", "Booking.com B.V.", "Nota spese dipendenti"],
    "6260": ["Arval Service Lease Italia", "Leasys S.p.A.", "Eni S.p.A. - carte carburante"],
    "6290": ["Fornitori diversi"], "6110": ["Agenti Enasarco"], "7010": ["Ammortamento"], "6010": ["Cedolini"], "6020": ["Cedolini"],
}
lines = []
doc = 0
for r in act_m.itertuples():
    p = r.Period
    first = date(p.year, p.month, 1)
    last = date(p.year, p.month, p.days_in_month)
    acc = r.AccountCode
    if acc in ("4010", "4020", "4090", "5010"):
        n = {"4010": 120, "4020": 25, "4090": 2, "5010": 50}[acc] if r.CostCenterCode != "PC60" else {"4010": 340, "4020": 3, "4090": 1, "5010": 20}[acc]
        if r.CostCenterCode == "PC50":
            n = {"4010": 30, "4020": 10, "4090": 1, "5010": 20}[acc]
    elif acc in ("6010", "6020", "7010", "6110"):
        n = 1
    elif acc in ("5020", "6120"):
        n = 4
    else:
        n = int(rng.integers(1, 4))
    n = max(1, int(n * rng.uniform(.8, 1.2)))
    parts = rng.dirichlet(np.ones(n) * 2) * r.Amount
    for amt in parts:
        doc += 1
        if acc in ("6010", "6020", "7010", "6110"):
            d = last
        else:
            d = first + timedelta(days=int(rng.integers(0, (last - first).days + 1)))
            while d.weekday() >= 5:
                d -= timedelta(days=1)
                if d < first:
                    d = first + timedelta(days=2)
        if acc in ("4010", "4020", "4090"):
            cp = f"{rng.choice(customers_prefix)} {rng.choice(cust_suffix)}"
            desc = {"4010": "Fattura vendita", "4020": "Fattura servizi assistenza", "4090": "Nota credito premio cliente"}[acc]
            dn = f"FV{p.year}/{doc:06d}"
        else:
            cp = rng.choice(vendors.get(acc, ["Fornitori diversi"]))
            desc = {"6010": f"Retribuzioni {p.month:02d}/{p.year}", "6020": f"Contributi e TFR {p.month:02d}/{p.year}",
                    "7010": "Ammortamenti di competenza", "6110": "Provvigioni maturate"}.get(acc, "Fattura fornitore")
            dn = f"PN{p.year}/{doc:06d}"
        lines.append((dn, d.isoformat(), r.CostCenterCode, acc, round(float(amt), 2), desc, cp))

# scritture di assestamento di fine anno (ratei, accantonamenti, rettifiche)
for y in (2024, 2025):
    for cc, acc, amt, desc in (("CC40", "6290", 38_000 if y == 2024 else 52_000, "Accantonamento rischi su crediti"),
                               ("CC70", "6230", 25_000, "Rateo consulenze di competenza"),
                               ("CC20", "6120", -12_000 if y == 2024 else 18_500, "Rettifica fatture trasporti da ricevere"),
                               ("CC60", "6290", 9_500, "Rateo formazione")):
        doc += 1
        lines.append((f"AS{y}/{doc:06d}", f"{y}-12-31", cc, acc, float(amt), desc, "Scrittura di assestamento"))

gl = pd.DataFrame(lines, columns=["DocumentNumber", "PostingDate", "CostCenterCode", "AccountCode", "Amount",
                                  "Description", "Counterparty"])
gl = gl.sort_values(["PostingDate", "DocumentNumber"]).reset_index(drop=True)
gl.insert(0, "EntryID", range(1, len(gl) + 1))

plan["Year"] = plan.Period.map(lambda p: p.year)
plan["Month"] = plan.Period.map(lambda p: p.month)
plan_out = plan[["Scenario", "Year", "Month", "CostCenterCode", "AccountCode"]].assign(Amount=plan.Amount.round(2))

fte = pd.DataFrame(fte_rows + bud_fte, columns=["Period", "CostCenterCode", "Scenario", "FTE"])
fte["Year"] = fte.Period.map(lambda p: p.year)
fte["Month"] = fte.Period.map(lambda p: p.month)

cost_centers.to_csv(os.path.join(OUT, "cost_centers.csv"), index=False)
accounts.to_csv(os.path.join(OUT, "chart_of_accounts.csv"), index=False)
gl.to_csv(os.path.join(OUT, "gl_actual_entries.csv"), index=False)
plan_out.to_csv(os.path.join(OUT, "budget_forecast.csv"), index=False)
fte[["Scenario", "Year", "Month", "CostCenterCode", "FTE"]].to_csv(os.path.join(OUT, "headcount.csv"), index=False)

# ------------------------------------------------------------------ riepilogo
acc_sign = accounts.set_index("AccountCode")
a = gl.assign(Year=gl.PostingDate.str[:4].astype(int))
a["grp"] = a.AccountCode.map(acc_sign.AccountType)
b = plan_out.copy(); b["grp"] = b.AccountCode.map(acc_sign.AccountType)
print("righe prima nota:", len(gl), " righe budget/forecast:", len(plan_out))
print(a.pivot_table(index="grp", columns="Year", values="Amount", aggfunc="sum").round(0))
print(b.pivot_table(index="grp", columns=["Scenario", "Year"], values="Amount", aggfunc="sum").round(0))
