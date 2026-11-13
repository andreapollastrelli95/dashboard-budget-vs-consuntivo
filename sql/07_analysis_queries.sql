/* =============================================================================
   Script 07 - query di analisi budget vs consuntivo
   ============================================================================= */
USE BudgetControl;
GO

DECLARE @Year SMALLINT = 2025, @Month TINYINT = 12;

/* 1. Conto economico per gruppo: Actual, Budget, Forecast, scostamenti (YTD) */
SELECT  a.PLGroup,
        SUM(v.Actual)                                                         AS Actual,
        SUM(v.Budget)                                                         AS Budget,
        SUM(v.Actual - v.Budget)                                              AS VarianceEUR,
        CAST(SUM(v.Actual - v.Budget) * 100.0 / NULLIF(ABS(SUM(v.Budget)), 0) AS DECIMAL(6,1)) AS VariancePct,
        SUM(v.VarianceFavorable)                                              AS FavorableImpact
FROM rpt.vw_BudgetVsActualMonthly v
JOIN dw.DimAccount a ON a.AccountKey = v.AccountKey
WHERE v.[Year] = @Year AND v.[Month] <= @Month
GROUP BY a.PLGroup
ORDER BY MIN(a.SortOrder);

/* 2. Margine operativo (EBIT) mensile e progressivo: actual vs budget */
WITH m AS (
    SELECT  v.[Month],
            SUM(v.Actual * a.PLSign) AS EbitA,
            SUM(v.Budget * a.PLSign) AS EbitB,
            SUM(CASE WHEN a.AccountType = 'Revenue' THEN v.Actual ELSE 0 END) AS RevA,
            SUM(CASE WHEN a.AccountType = 'Revenue' THEN v.Budget ELSE 0 END) AS RevB
    FROM rpt.vw_BudgetVsActualMonthly v
    JOIN dw.DimAccount a ON a.AccountKey = v.AccountKey
    WHERE v.[Year] = @Year
    GROUP BY v.[Month]
)
SELECT  [Month], EbitA, EbitB, EbitA - EbitB AS Variance,
        SUM(EbitA) OVER (ORDER BY [Month]) AS EbitA_YTD,
        SUM(EbitB) OVER (ORDER BY [Month]) AS EbitB_YTD,
        CAST(EbitA * 100.0 / NULLIF(RevA, 0) AS DECIMAL(5,1)) AS OperatingMarginA,
        CAST(EbitB * 100.0 / NULLIF(RevB, 0) AS DECIMAL(5,1)) AS OperatingMarginB
FROM m
ORDER BY [Month];

/* 3. Cost center performance: risultato vs budget, % di budget consumato, ranking */
WITH c AS (
    SELECT  cc.CostCenterName, cc.CostCenterType, cc.Manager,
            SUM(v.Actual * a.PLSign) AS ResultA,
            SUM(v.Budget * a.PLSign) AS ResultB,
            SUM(v.VarianceFavorable) AS VarFav,
            SUM(CASE WHEN a.PLSign = -1 THEN v.Actual ELSE 0 END) AS CostA,
            SUM(CASE WHEN a.PLSign = -1 THEN v.Budget ELSE 0 END) AS CostB
    FROM rpt.vw_BudgetVsActualMonthly v
    JOIN dw.DimAccount a     ON a.AccountKey     = v.AccountKey
    JOIN dw.DimCostCenter cc ON cc.CostCenterKey = v.CostCenterKey
    WHERE v.[Year] = @Year AND v.[Month] <= @Month
    GROUP BY cc.CostCenterName, cc.CostCenterType, cc.Manager
)
SELECT  CostCenterName, CostCenterType, Manager, ResultA, ResultB, VarFav,
        CAST(CostA * 100.0 / NULLIF(CostB, 0) AS DECIMAL(6,1))            AS CostBudgetUsedPct,
        RANK() OVER (ORDER BY VarFav DESC)                                AS PerformanceRank,
        CASE WHEN VarFav >= 0 THEN 'In linea / meglio'
             WHEN VarFav > -0.05 * ABS(ResultB) THEN 'Da monitorare'
             ELSE 'Fuori budget' END                                       AS Status
FROM c
ORDER BY VarFav;

/* 4. Le 10 voci (centro x conto) con lo scostamento sfavorevole piu' alto */
SELECT TOP (10)
        cc.CostCenterName, a.AccountName,
        SUM(v.Actual) AS Actual, SUM(v.Budget) AS Budget,
        SUM(v.VarianceFavorable) AS FavorableImpact,
        a.IsControllable
FROM rpt.vw_BudgetVsActualMonthly v
JOIN dw.DimAccount a     ON a.AccountKey     = v.AccountKey
JOIN dw.DimCostCenter cc ON cc.CostCenterKey = v.CostCenterKey
WHERE v.[Year] = @Year AND v.[Month] <= @Month
GROUP BY cc.CostCenterName, a.AccountName, a.IsControllable
ORDER BY SUM(v.VarianceFavorable) ASC;

/* 5. Scomposizione dello scostamento dei ricavi dei centri di ricavo:
      volume (ricavi) vs margine % (prezzo/mix) sul margine lordo */
WITH r AS (
    SELECT  cc.CostCenterName,
            SUM(CASE WHEN a.AccountType = 'Revenue' THEN v.Actual ELSE 0 END)  AS RevA,
            SUM(CASE WHEN a.AccountType = 'Revenue' THEN v.Budget ELSE 0 END)  AS RevB,
            SUM(CASE WHEN a.AccountType IN ('Revenue', 'COGS') THEN v.Actual * a.PLSign ELSE 0 END) AS GMA,
            SUM(CASE WHEN a.AccountType IN ('Revenue', 'COGS') THEN v.Budget * a.PLSign ELSE 0 END) AS GMB
    FROM rpt.vw_BudgetVsActualMonthly v
    JOIN dw.DimAccount a     ON a.AccountKey     = v.AccountKey
    JOIN dw.DimCostCenter cc ON cc.CostCenterKey = v.CostCenterKey
    WHERE v.[Year] = @Year AND v.[Month] <= @Month AND cc.CostCenterType = 'Centro di ricavo'
    GROUP BY cc.CostCenterName
)
SELECT  CostCenterName, RevA, RevB, GMA, GMB,
        CAST((RevA - RevB) * GMB / NULLIF(RevB, 0) AS DECIMAL(18,0))            AS VolumeEffect,
        CAST(RevA * (GMA / NULLIF(RevA, 0) - GMB / NULLIF(RevB, 0)) AS DECIMAL(18,0)) AS MarginRateEffect,
        GMA - GMB                                                               AS TotalGMVariance
FROM r
ORDER BY TotalGMVariance;

/* 6. Costo del personale e FTE: actual vs budget, costo medio per FTE */
WITH p AS (
    SELECT  v.CostCenterKey,
            SUM(CASE WHEN a.PLGroup = N'Costo del personale' THEN v.Actual ELSE 0 END) AS PersA,
            SUM(CASE WHEN a.PLGroup = N'Costo del personale' THEN v.Budget ELSE 0 END) AS PersB
    FROM rpt.vw_BudgetVsActualMonthly v
    JOIN dw.DimAccount a ON a.AccountKey = v.AccountKey
    WHERE v.[Year] = @Year AND v.[Month] <= @Month
    GROUP BY v.CostCenterKey
),
h AS (
    SELECT  f.CostCenterKey,
            AVG(CASE WHEN f.ScenarioKey = 1 THEN f.FTE END) AS FteA,
            AVG(CASE WHEN f.ScenarioKey = 2 THEN f.FTE END) AS FteB
    FROM dw.FactHeadcount f JOIN dw.DimDate d ON d.DateKey = f.DateKey
    WHERE d.[Year] = @Year AND d.[Month] <= @Month
    GROUP BY f.CostCenterKey
)
SELECT  cc.CostCenterName, h.FteA, h.FteB, p.PersA, p.PersB,
        CAST(p.PersA / NULLIF(h.FteA, 0) * 12.0 / @Month AS DECIMAL(18,0)) AS AnnualCostPerFTE_A,
        CAST(p.PersB / NULLIF(h.FteB, 0) * 12.0 / @Month AS DECIMAL(18,0)) AS AnnualCostPerFTE_B
FROM p
JOIN h ON h.CostCenterKey = p.CostCenterKey
JOIN dw.DimCostCenter cc ON cc.CostCenterKey = p.CostCenterKey
ORDER BY p.PersA - p.PersB DESC;

/* 7. Accuratezza del forecast di luglio: secondo semestre forecast vs actual per gruppo */
SELECT  a.PLGroup,
        SUM(v.Forecast) AS ForecastH2,
        SUM(v.Actual)   AS ActualH2,
        CAST((SUM(v.Actual) - SUM(v.Forecast)) * 100.0 / NULLIF(ABS(SUM(v.Forecast)), 0) AS DECIMAL(6,1)) AS ForecastErrorPct
FROM rpt.vw_BudgetVsActualMonthly v
JOIN dw.DimAccount a ON a.AccountKey = v.AccountKey
WHERE v.[Year] = 2025 AND v.[Month] BETWEEN 7 AND 12
GROUP BY a.PLGroup
ORDER BY MIN(a.SortOrder);

/* 8. Confronto con l'anno precedente: actual 2025 vs actual 2024 per centro */
SELECT  cc.CostCenterName,
        SUM(CASE WHEN v.[Year] = 2025 THEN v.Actual * a.PLSign ELSE 0 END) AS Result2025,
        SUM(CASE WHEN v.[Year] = 2024 THEN v.Actual * a.PLSign ELSE 0 END) AS Result2024
FROM rpt.vw_BudgetVsActualMonthly v
JOIN dw.DimAccount a     ON a.AccountKey     = v.AccountKey
JOIN dw.DimCostCenter cc ON cc.CostCenterKey = v.CostCenterKey
GROUP BY cc.CostCenterName
ORDER BY cc.CostCenterName;
GO
