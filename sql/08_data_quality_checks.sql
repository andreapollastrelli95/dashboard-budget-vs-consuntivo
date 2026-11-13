/* =============================================================================
   Script 08 - controlli e quadrature
   ============================================================================= */
USE BudgetControl;
GO

/* 1. Quadratura consuntivo staging vs DW, per anno */
SELECT  LEFT(PostingDate, 4) AS [Year], SUM(TRY_CONVERT(DECIMAL(18,2), Amount)) AS StgAmount
FROM stg.GLActualEntries GROUP BY LEFT(PostingDate, 4);
SELECT  d.[Year], SUM(f.Amount) AS DwAmount
FROM dw.FactActual f JOIN dw.DimDate d ON d.DateKey = f.DateKey GROUP BY d.[Year];

/* 2. Righe di staging che non trovano centro o conto (vengono scartate dal caricamento) */
SELECT g.CostCenterCode, g.AccountCode, COUNT(*) AS Rows_
FROM stg.GLActualEntries g
LEFT JOIN dw.DimCostCenter cc ON cc.CostCenterCode = g.CostCenterCode
LEFT JOIN dw.DimAccount a     ON a.AccountCode     = g.AccountCode
WHERE cc.CostCenterKey IS NULL OR a.AccountKey IS NULL
GROUP BY g.CostCenterCode, g.AccountCode;

/* 3. Combinazioni centro x conto con consuntivo ma senza budget (costi non previsti) */
SELECT cc.CostCenterName, a.AccountName, SUM(v.Actual) AS ActualWithoutBudget
FROM rpt.vw_BudgetVsActualMonthly v
JOIN dw.DimCostCenter cc ON cc.CostCenterKey = v.CostCenterKey
JOIN dw.DimAccount a     ON a.AccountKey     = v.AccountKey
WHERE v.[Year] = 2025
GROUP BY cc.CostCenterName, a.AccountName
HAVING SUM(v.Budget) = 0 AND SUM(v.Actual) <> 0;

/* 4. Il forecast gen-giu deve coincidere con il consuntivo gen-giu */
SELECT  SUM(v.Forecast) AS ForecastH1, SUM(v.Actual) AS ActualH1, SUM(v.Forecast) - SUM(v.Actual) AS Diff
FROM rpt.vw_BudgetVsActualMonthly v
WHERE v.[Year] = 2025 AND v.[Month] <= 6;

/* 5. Mesi mancanti nel budget (ogni combinazione deve avere 12 mesi) */
SELECT s.ScenarioName, d.[Year], p.CostCenterKey, p.AccountKey, COUNT(*) AS Months
FROM dw.FactPlan p
JOIN dw.DimDate d     ON d.DateKey = p.DateKey
JOIN dw.DimScenario s ON s.ScenarioKey = p.ScenarioKey
GROUP BY s.ScenarioName, d.[Year], p.CostCenterKey, p.AccountKey
HAVING COUNT(*) <> 12;

/* 6. Segni anomali: costi negativi o ricavi negativi (esclusi sconti e rettifiche) */
SELECT a.AccountCode, a.AccountName, f.DocumentNumber, f.Amount, f.Description
FROM dw.FactActual f
JOIN dw.DimAccount a ON a.AccountKey = f.AccountKey
WHERE (a.AccountType <> N'Revenue' AND f.Amount < 0 AND f.DocumentNumber NOT LIKE N'AS%')
   OR (a.AccountCode IN (N'4010', N'4020') AND f.Amount < 0);

/* 7. Ogni centro deve avere organico a budget e a consuntivo per ogni mese */
SELECT cc.CostCenterName, s.ScenarioName, COUNT(*) AS Months
FROM dw.FactHeadcount h
JOIN dw.DimCostCenter cc ON cc.CostCenterKey = h.CostCenterKey
JOIN dw.DimScenario s    ON s.ScenarioKey    = h.ScenarioKey
GROUP BY cc.CostCenterName, s.ScenarioName
HAVING COUNT(*) <> 24;
GO
