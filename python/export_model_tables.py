# -----------------------------------------------------------------------------
# Esporta le tabelle del modello Power BI in CSV (cartella data/model).
# Replica la logica degli script SQL 02, 04, 05 e 06 (calendario, schema dw,
# viste rpt e commenti manageriali) per poter usare il report anche senza
# SQL Server: Power BI legge direttamente questi file.
# -----------------------------------------------------------------------------
import os
import numpy as np
import pandas as pd

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
OUT = os.path.join(BASE, "model")
os.makedirs(OUT, exist_ok=True)

MESI = ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto",
        "Settembre", "Ottobre", "Novembre", "Dicembre"]
MIN_EURO = 20000      # soglie della procedura rpt.usp_GenerateManagementComments
MIN_PCT = 0.03


def save(df, name):
    df.to_csv(os.path.join(OUT, name), index=False, date_format="%Y-%m-%d")


def key(s):
    return s.dt.strftime("%Y%m%d").astype(int)


# ------------------------------------------------------------------ dimensioni
dates = pd.DataFrame({"Date": pd.date_range("2024-01-01", "2025-12-31")})
dates["DateKey"] = key(dates["Date"])
dates["Year"] = dates["Date"].dt.year
dates["Quarter"] = dates["Date"].dt.quarter
dates["QuarterLabel"] = "Q" + dates["Quarter"].astype(str)
dates["Month"] = dates["Date"].dt.month
dates["MonthName"] = dates["Month"].map(lambda m: MESI[m - 1])
dates["MonthShort"] = dates["MonthName"].str[:3]
dates["YearMonth"] = dates["Year"] * 100 + dates["Month"]
dates["YearMonthLabel"] = dates["MonthShort"] + " " + dates["Year"].astype(str)
dates["Half"] = np.where(dates["Month"] <= 6, "H1", "H2")
save(dates[["DateKey", "Date", "Year", "Quarter", "QuarterLabel", "Month", "MonthName",
            "MonthShort", "YearMonth", "YearMonthLabel", "Half"]], "calendar.csv")

cc = pd.read_csv(os.path.join(BASE, "cost_centers.csv"))
cc.insert(0, "CostCenterKey", range(1, len(cc) + 1))
cc["CostCenter"] = cc["CostCenterCode"] + " - " + cc["CostCenterName"]
cc["CostCenterSort"] = np.where(cc["CostCenterType"] == "Centro di ricavo", 100, 200) \
    + cc["CostCenterCode"].str[-2:].astype(int)
save(cc[["CostCenterKey", "CostCenterCode", "CostCenter", "CostCenterName", "CostCenterType",
         "BusinessArea", "Manager", "CostCenterSort"]], "cost_center.csv")

acc = pd.read_csv(os.path.join(BASE, "chart_of_accounts.csv"))
acc.insert(0, "AccountKey", range(1, len(acc) + 1))
acc["Account"] = acc["AccountCode"].astype(str) + " - " + acc["AccountName"]
ordine = {"Ricavi": 1, "Costo del venduto": 2, "Costo del personale": 3,
          "Costi commerciali": 4, "Costi di struttura": 5}
acc["PLGroupSort"] = acc["PLGroup"].map(ordine).fillna(6).astype(int)
acc["IsControllable"] = acc["IsControllable"].astype(bool)
save(acc[["AccountKey", "AccountCode", "Account", "AccountName", "PLGroup", "AccountType",
          "IsControllable", "PLSign", "SortOrder", "PLGroupSort"]], "account.csv")

scen = pd.DataFrame({
    "ScenarioKey": [1, 2, 3],
    "ScenarioName": ["Actual", "Budget", "Forecast"],
    "ScenarioDesc": ["Consuntivo da contabilita' generale",
                     "Budget approvato dal CdA (novembre anno precedente)",
                     "Forecast 6+6: consuntivo gen-giu + stima lug-dic (luglio)"]})
save(scen, "scenario.csv")

ccmap = dict(zip(cc["CostCenterCode"], cc["CostCenterKey"]))
acmap = dict(zip(acc["AccountCode"], acc["AccountKey"]))
sign = dict(zip(acc["AccountKey"], acc["PLSign"]))
scmap = dict(zip(scen["ScenarioName"], scen["ScenarioKey"]))

# --------------------------------------------------------------------- fatti
gl = pd.read_csv(os.path.join(BASE, "gl_actual_entries.csv"), parse_dates=["PostingDate"])
fa = pd.DataFrame({
    "DateKey": key(gl["PostingDate"]),
    "CostCenterKey": gl["CostCenterCode"].map(ccmap),
    "AccountKey": gl["AccountCode"].map(acmap),
    "DocumentNumber": gl["DocumentNumber"],
    "Amount": gl["Amount"].round(2),
    "Description": gl["Description"],
    "Counterparty": gl["Counterparty"],
})
fa["SignedAmount"] = (fa["Amount"] * fa["AccountKey"].map(sign)).round(2)
fa["EntryType"] = np.where(fa["DocumentNumber"].str.startswith("FV"), "Fattura di vendita",
                  np.where(fa["DocumentNumber"].str.startswith("AS"), "Scrittura di assestamento",
                           "Prima nota / fornitore"))
assert fa[["CostCenterKey", "AccountKey"]].notna().all().all()
save(fa[["DateKey", "CostCenterKey", "AccountKey", "DocumentNumber", "Amount", "SignedAmount",
         "Description", "Counterparty", "EntryType"]], "fact_actual.csv")

bf = pd.read_csv(os.path.join(BASE, "budget_forecast.csv"))
bf["DateKey"] = bf["Year"] * 10000 + bf["Month"] * 100 + 1
bf["CostCenterKey"] = bf["CostCenterCode"].map(ccmap)
bf["AccountKey"] = bf["AccountCode"].map(acmap)
bf["ScenarioKey"] = bf["Scenario"].map(scmap)
fp = (bf.groupby(["DateKey", "CostCenterKey", "AccountKey", "ScenarioKey"], as_index=False)["Amount"].sum())
fp["Amount"] = fp["Amount"].round(2)
fp["SignedAmount"] = (fp["Amount"] * fp["AccountKey"].map(sign)).round(2)
save(fp, "fact_plan.csv")

hc = pd.read_csv(os.path.join(BASE, "headcount.csv"))
fh = pd.DataFrame({
    "DateKey": hc["Year"] * 10000 + hc["Month"] * 100 + 1,
    "CostCenterKey": hc["CostCenterCode"].map(ccmap),
    "ScenarioKey": hc["Scenario"].map(scmap),
    "FTE": hc["FTE"],
})
save(fh, "fact_headcount.csv")

# ------------------------------------------------- vista mensile (rpt.vw_...)
act_m = fa.assign(Year=fa["DateKey"] // 10000, Month=fa["DateKey"] // 100 % 100) \
    .groupby(["Year", "Month", "CostCenterKey", "AccountKey"], as_index=False)["Amount"].sum() \
    .rename(columns={"Amount": "Actual"})
pl = fp.assign(Year=fp["DateKey"] // 10000, Month=fp["DateKey"] // 100 % 100)
bud_m = pl[pl.ScenarioKey == 2].groupby(["Year", "Month", "CostCenterKey", "AccountKey"], as_index=False)["Amount"].sum() \
    .rename(columns={"Amount": "Budget"})
view = act_m.merge(bud_m, how="outer", on=["Year", "Month", "CostCenterKey", "AccountKey"]).fillna({"Actual": 0, "Budget": 0})
view["PLSign"] = view["AccountKey"].map(sign)
view["VarFav"] = (view["Actual"] - view["Budget"]) * view["PLSign"]
view = view.merge(acc[["AccountKey", "AccountName", "PLGroup", "AccountType"]], on="AccountKey")

# --------------------------------------------- commenti manageriali (script 06)


def eur(v):
    return "€ " + f"{v:,.0f}".replace(",", ".")


def pct(v, with_sign):
    s = f"{v * 100:,.1f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return ("+" if with_sign and v > 0 else "") + s + "%"


def num1(v):
    return f"{v:,.1f}".replace(",", "X").replace(".", ",").replace("X", ".")


def sgn(x):
    return (x > 0) - (x < 0)


ccname = dict(zip(cc["CostCenterKey"], cc["CostCenterName"]))
cctype = dict(zip(cc["CostCenterKey"], cc["CostCenterType"]))
ccmgr = dict(zip(cc["CostCenterKey"], cc["Manager"]))
rows = []
months = sorted({(int(y), int(m)) for y, m in act_m[["Year", "Month"]].itertuples(index=False)
                 if y in set(pl["Year"])})
for Y, M in months:
    mn = MESI[M - 1].lower()
    y = view[(view.Year == Y) & (view.Month <= M)].groupby(
        ["CostCenterKey", "AccountKey", "AccountName", "PLGroup", "AccountType", "PLSign"], as_index=False)[
        ["Actual", "Budget", "VarFav"]].sum()
    y["A_s"] = y["Actual"] * y["PLSign"]
    y["B_s"] = y["Budget"] * y["PLSign"]
    # 1. sintesi
    revA = y.loc[y.AccountType == "Revenue", "Actual"].sum()
    revB = y.loc[y.AccountType == "Revenue", "Budget"].sum()
    gm = y.AccountType.isin(["Revenue", "COGS"])
    gmA, gmB = y.loc[gm, "A_s"].sum(), y.loc[gm, "B_s"].sum()
    ebA, ebB = y["A_s"].sum(), y["B_s"].sum()
    rows.append((Y, M, None, "Sintesi", 1,
        f"Progressivo gennaio-{mn} {Y}: ricavi {eur(revA)} contro {eur(revB)} a budget ({pct(revA / revB - 1, True)}). "
        f"Margine lordo al {pct(gmA / revA, False)} (budget {pct(gmB / revB, False)}). "
        f"EBIT {eur(ebA)} contro {eur(ebB)} a budget: {'migliore di ' if ebA >= ebB else 'peggiore di '}"
        f"{eur(abs(ebA - ebB))} ({pct((ebA - ebB) / abs(ebB), True)})."))
    # 2. scostamenti principali (centro x gruppo, ricavi e costo del venduto insieme)
    y["CG"] = np.where(y.PLGroup.isin(["Ricavi", "Costo del venduto"]), "Margine lordo", y.PLGroup)
    grp = y.groupby(["CostCenterKey", "CG"], as_index=False).agg(
        Actual=("A_s", "sum"), Budget=("B_s", "sum"), VarFav=("VarFav", "sum"))
    y["abs_v"] = y["VarFav"].abs()
    drv = y.sort_values("abs_v", ascending=False).groupby(["CostCenterKey", "CG"], as_index=False).first()[
        ["CostCenterKey", "CG", "AccountName", "VarFav"]].rename(columns={"AccountName": "Drv", "VarFav": "DrvVar"})
    g = grp.merge(drv, on=["CostCenterKey", "CG"])
    g = g[(g.VarFav.abs() >= MIN_EURO) & ((g.Actual - g.Budget).abs() >= MIN_PCT * g.Budget.abs())].copy()
    g["rnNeg"] = g["VarFav"].rank(method="first", ascending=True)
    g["rnPos"] = g["VarFav"].rank(method="first", ascending=False)
    for r in g.itertuples():
        if (r.VarFav < 0 and r.rnNeg <= 3) or (r.VarFav > 0 and r.rnPos <= 2):
            k = int(r.CostCenterKey)
            rows.append((Y, M, k, "Scostamento negativo" if r.VarFav < 0 else "Scostamento positivo",
                1 + int(r.rnNeg) if r.VarFav < 0 else 5 + int(r.rnPos),
                f"{ccname[k]} - {r.CG.lower()}: {eur(abs(r.Actual))} contro {eur(abs(r.Budget))} a budget "
                f"({pct((r.Actual - r.Budget) * sgn(r.Actual) / abs(r.Budget), True)}), effetto "
                f"{'sfavorevole di ' if r.VarFav < 0 else 'favorevole di '}{eur(abs(r.VarFav))}. "
                f"Voce principale: {r.Drv.lower()} ({eur(r.DrvVar)}). Responsabile: {ccmgr[k]}."))
    # 3. una riga per centro
    c = y.groupby("CostCenterKey", as_index=False).agg(RA=("A_s", "sum"), RB=("B_s", "sum"), VarFav=("VarFav", "sum"))
    d1 = y.sort_values("abs_v", ascending=False).groupby("CostCenterKey", as_index=False).first()[
        ["CostCenterKey", "AccountName", "VarFav"]].rename(columns={"AccountName": "Drv", "VarFav": "DrvVar"})
    for r in c.merge(d1, on="CostCenterKey").itertuples():
        k = int(r.CostCenterKey)
        coda = ("In linea con le attese." if abs(r.VarFav) < MIN_EURO
                else f"Pesa soprattutto {r.Drv.lower()} ({eur(r.DrvVar)}).")
        rows.append((Y, M, k, "Centro", 20,
            f"{ccname[k]}{': contributo ' if cctype[k] == 'Centro di ricavo' else ': costi '}"
            f"{eur(abs(r.RA))} contro {eur(abs(r.RB))} a budget, "
            f"{'meglio del budget di ' if r.VarFav >= 0 else 'peggio del budget di '}{eur(abs(r.VarFav))}. {coda}"))
    # 4. organico
    hh = fh.assign(Year=fh["DateKey"] // 10000, Month=fh["DateKey"] // 100 % 100)
    hh = hh[(hh.Year == Y) & (hh.Month <= M)]
    fte = hh.pivot_table(index="CostCenterKey", columns="ScenarioKey", values="FTE", aggfunc="mean")
    pcv = y[y.PLGroup == "Costo del personale"].groupby("CostCenterKey")["VarFav"].sum()
    for k, r in fte.iterrows():
        if pd.notna(r.get(1)) and pd.notna(r.get(2)) and abs(r[1] - r[2]) >= 0.5:
            rows.append((Y, M, int(k), "Organico", 10,
                f"Organico {ccname[int(k)]}: in media {num1(r[1])} FTE contro {num1(r[2])} a budget"
                f"{' (assunzioni in ritardo o posizioni scoperte)' if r[1] < r[2] else ' (risorse non previste a budget)'}"
                f"; effetto sul costo del personale {eur(pcv.get(k, 0))}."))
    # 5. forecast / chiusura
    py = pl[pl.Year == Y]
    if (py.ScenarioKey == 3).any():
        fc = py.loc[py.ScenarioKey == 3, "SignedAmount"].sum()
        bd = py.loc[py.ScenarioKey == 2, "SignedAmount"].sum()
        if M < 12:
            rows.append((Y, M, None, "Forecast", 9,
                f"Il forecast 6+6 stima un EBIT di fine anno di {eur(fc)} contro {eur(bd)} a budget "
                f"({pct((fc - bd) / abs(bd), True)})."))
        else:
            fy = fa.loc[fa["DateKey"] // 10000 == Y, "SignedAmount"].sum()
            rows.append((Y, M, None, "Forecast", 9,
                f"Chiusura d'anno: EBIT {eur(fy)} contro {eur(fc)} del forecast di luglio e {eur(bd)} del budget. "
                + ("Il secondo semestre e' andato peggio di quanto stimato a luglio." if fy < fc
                   else "Il secondo semestre ha recuperato rispetto alla stima di luglio.")))

mc = pd.DataFrame(rows, columns=["Year", "Month", "CostCenterKey", "CommentType", "Priority", "CommentText"])
mc["CostCenterKey"] = mc["CostCenterKey"].astype("Int64")
save(mc, "management_comment.csv")

print({f: len(pd.read_csv(os.path.join(OUT, f))) for f in sorted(os.listdir(OUT))})
