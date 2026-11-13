# Layout della dashboard

Canvas 1920 × 1080, stessa struttura e palette degli altri progetti del portfolio (blu notte `#1B2A41`, blu `#2E5C8A` per il consuntivo, azzurro `#9DB7D5` per il budget, ambra `#E0A100` per il forecast). Verde `#1E8E5A` e rosso `#C0392B` indicano solo **favorevole / sfavorevole**, mai "positivo / negativo" in senso aritmetico: un aumento dei costi è rosso.

## Filtri
Anno · Mese (il report mostra il progressivo gennaio-mese) · Area · Centro. Pagina di drill-through "Dettaglio centro" raggiungibile con clic destro da qualsiasi visual che mostri un centro.

## Pagina 1 - Sintesi
| Visual | Tipo | Misure |
|---|---|---|
| 6 KPI | Card con riferimento | Actual Revenue vs Budget Revenue, Actual Cost vs Budget Cost, Actual Operating Margin, Operating Margin Variance € e %, Actual Operating Margin % (vs budget e PY), Actual Gross Margin % (Gross Margin % Delta pp) |
| Ricavi mensili | Colonne raggruppate + linea | Mese; Budget Revenue, Actual Revenue; Forecast Revenue (solo H2) |
| Ponte EBIT | Cascata | Categoria Account[PLGroup]; Variance Fav €; inizio = Budget Operating Margin |
| Scostamento per centro | Barre | CostCenter; Variance Fav € (colore da Variance Color) |
| Commenti | Card multiriga | Management Comment Summary (SQL) oppure Dynamic Commentary (DAX) |

## Pagina 2 - Conto economico
Matrice: righe Account[PLGroup] → Account[Account] (ordinamento PLGroupSort, SortOrder); valori Actual, Budget, Variance Fav €, Variance Fav %, Forecast, Actual PY. Righe di subtotale (Margine lordo, EBITDA, EBIT) con un gruppo di calcolo o con una tabella layout come nel progetto P&L. Icone ▲▼ con `Variance Arrow` e colore da `Variance Color`.

## Pagina 3 - Centri di costo
| Visual | Tipo | Misure |
|---|---|---|
| 5 KPI | Card | Cost Centers Over Budget, variance centri di ricavo, variance centri di costo, Controllable Variance €, Budget Consumed % |
| Performance | Tabella | CostCenter, Manager, Cost Center Result Actual / Budget, Cost Center Performance € e %, Budget Consumed %, Variance Status |
| Heatmap | Matrice con formattazione condizionale dello sfondo | righe CostCenter, colonne mese, valore Variance Fav € |

## Pagina 4 - Dettaglio centro (drill-through)
KPI del centro, ricavi o costi mensili actual vs budget con scostamento cumulato (`Variance Fav €` cumulato con `DATESYTD`), tabella variance per conto, FTE actual / budget, `Management Comment Cost Center`.

## Pagina 5 - Organico e forecast
FTE Actual vs FTE Budget per centro, Personnel Cost e Cost per FTE, EBIT progressivo actual / budget / forecast (linee), tabella accuratezza forecast H2 per gruppo (`Forecast Accuracy %`).
