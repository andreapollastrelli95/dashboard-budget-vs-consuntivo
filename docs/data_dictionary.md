# Data dictionary

## dw.FactActual (consuntivo)
Grain: riga di prima nota.

| Colonna | Descrizione |
|---|---|
| DateKey | data di registrazione |
| CostCenterKey | centro di costo / ricavo |
| AccountKey | conto economico |
| DocumentNumber | FV = fattura di vendita, PN = prima nota / fattura fornitore, AS = scrittura di assestamento |
| Amount | importo in segno naturale (costi positivi, sconti a clienti negativi) |
| SignedAmount | Amount × PLSign: ricavi positivi, costi negativi |
| Description, Counterparty | causale e controparte |

## dw.FactPlan (budget e forecast)
Grain: mese × centro × conto × scenario. DateKey = primo giorno del mese.

| Colonna | Descrizione |
|---|---|
| ScenarioKey | 2 = Budget, 3 = Forecast 6+6 |
| Amount, SignedAmount | come in FactActual |

## dw.FactHeadcount
Grain: mese × centro × scenario (1 = Actual, 2 = Budget). FTE medi del mese.

## dw.ManagementComment
Commenti generati dalla procedura `rpt.usp_GenerateManagementComments`.

| Colonna | Descrizione |
|---|---|
| Year, Month | mese di riferimento (il commento riguarda il progressivo gennaio-mese) |
| CostCenterKey | NULL per i commenti a livello azienda |
| CommentType | Sintesi, Scostamento negativo, Scostamento positivo, Centro, Organico, Forecast |
| Priority | ordine di lettura |
| CommentText | testo |

## Dimensioni

**DimCostCenter**

| Codice | Centro | Tipo | Area | Responsabile |
|---|---|---|---|---|
| PC10 | Vendite Nord-Ovest | Centro di ricavo | Commerciale | L. Ferraris |
| PC20 | Vendite Nord-Est | Centro di ricavo | Commerciale | M. Zanella |
| PC30 | Vendite Centro | Centro di ricavo | Commerciale | S. Marini |
| PC40 | Vendite Sud e Isole | Centro di ricavo | Commerciale | A. Esposito |
| PC50 | Key Account / Grandi clienti | Centro di ricavo | Commerciale | F. Colombo |
| PC60 | E-commerce | Centro di ricavo | Commerciale | G. Riva |
| CC10 | Marketing | Centro di costo | Commerciale | E. Bassi |
| CC20 | Logistica e magazzino | Centro di costo | Operations | R. Pellegrini |
| CC30 | Assistenza tecnica | Centro di costo | Operations | D. Fontana |
| CC40 | Amministrazione e finanza | Centro di costo | Struttura | C. Gallo |
| CC50 | IT e sistemi | Centro di costo | Struttura | P. Testa |
| CC60 | Risorse umane | Centro di costo | Struttura | V. Longo |
| CC70 | Direzione generale | Centro di costo | Struttura | A. Martini |

**DimAccount**

| Conto | Descrizione | Gruppo | Controllabile |
|---|---|---|---|
| 4010 | Ricavi vendita prodotti | Ricavi | sì |
| 4020 | Ricavi da servizi e assistenza | Ricavi | sì |
| 4090 | Sconti e premi a clienti | Ricavi | sì |
| 5010 | Acquisto merci | Costo del venduto | sì |
| 5020 | Trasporti su acquisti | Costo del venduto | sì |
| 6010 | Retribuzioni | Costo del personale | sì |
| 6020 | Oneri sociali e TFR | Costo del personale | sì |
| 6110 | Provvigioni agenti | Costi commerciali | sì |
| 6120 | Trasporti su vendite | Costi commerciali | sì |
| 6130 | Pubblicità, fiere e digital | Costi commerciali | sì |
| 6210 | Affitti e spese condominiali | Costi di struttura | no |
| 6220 | Utenze | Costi di struttura | sì |
| 6230 | Consulenze e servizi professionali | Costi di struttura | sì |
| 6240 | Licenze software e cloud | Costi di struttura | sì |
| 6250 | Viaggi e trasferte | Costi di struttura | sì |
| 6260 | Auto aziendali (noleggi e carburante) | Costi di struttura | sì |
| 6290 | Altri costi di gestione | Costi di struttura | sì |
| 7010 | Ammortamenti | Ammortamenti | no |

Nota: semplificando, l'acquisto merci è registrato già come costo del venduto (nessuna variazione di rimanenze nel perimetro).

**DimScenario**: 1 Actual, 2 Budget, 3 Forecast (6+6).
