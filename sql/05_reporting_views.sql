/* =============================================================================
   Script 05 - viste di reporting
   ============================================================================= */
USE BudgetControl;
GO

CREATE OR ALTER VIEW rpt.Calendar AS
SELECT DateKey, [Date], [Year], [Quarter], QuarterLabel, [Month], MonthName, MonthShort, YearMonth, YearMonthLabel
FROM dw.DimDate
WHERE [Year] BETWEEN 2024 AND 2025;
GO

CREATE OR ALTER VIEW rpt.CostCenter AS
SELECT CostCenterKey, CostCenterCode, CostCenterCode + N' - ' + CostCenterName AS CostCenter,
       CostCenterName, CostCenterType, BusinessArea, Manager
FROM dw.DimCostCenter;
GO

CREATE OR ALTER VIEW rpt.Account AS
SELECT AccountKey, AccountCode, AccountCode + N' - ' + AccountName AS Account, AccountName,
       PLGroup, AccountType, IsControllable, PLSign, SortOrder,
       CASE PLGroup WHEN N'Ricavi' THEN 1 WHEN N'Costo del venduto' THEN 2 WHEN N'Costo del personale' THEN 3
                    WHEN N'Costi commerciali' THEN 4 WHEN N'Costi di struttura' THEN 5 ELSE 6 END AS PLGroupSort
FROM dw.DimAccount;
GO

CREATE OR ALTER VIEW rpt.Scenario AS
SELECT ScenarioKey, ScenarioName, ScenarioDesc FROM dw.DimScenario;
GO

CREATE OR ALTER VIEW rpt.FactActual AS
SELECT DateKey, CostCenterKey, AccountKey, DocumentNumber, Amount, SignedAmount, Description, Counterparty
FROM dw.FactActual;
GO

CREATE OR ALTER VIEW rpt.FactPlan AS
SELECT DateKey, CostCenterKey, AccountKey, ScenarioKey, Amount, SignedAmount
FROM dw.FactPlan;
GO

CREATE OR ALTER VIEW rpt.FactHeadcount AS
SELECT DateKey, CostCenterKey, ScenarioKey, FTE FROM dw.FactHeadcount;
GO

CREATE OR ALTER VIEW rpt.ManagementComment AS
SELECT c.[Year], c.[Month], c.CostCenterKey, c.CommentType, c.Priority, c.CommentText
FROM dw.ManagementComment c;
GO

/* vista di confronto mensile Budget / Forecast / Actual per centro e conto
   (base delle query di analisi e utile per estrazioni in Excel) */
CREATE OR ALTER VIEW rpt.vw_BudgetVsActualMonthly AS
WITH act AS (
    SELECT d.[Year], d.[Month], f.CostCenterKey, f.AccountKey, SUM(f.Amount) AS Actual
    FROM dw.FactActual f
    JOIN dw.DimDate d ON d.DateKey = f.DateKey
    GROUP BY d.[Year], d.[Month], f.CostCenterKey, f.AccountKey
),
pln AS (
    SELECT d.[Year], d.[Month], p.CostCenterKey, p.AccountKey,
           SUM(CASE WHEN p.ScenarioKey = 2 THEN p.Amount END) AS Budget,
           SUM(CASE WHEN p.ScenarioKey = 3 THEN p.Amount END) AS Forecast
    FROM dw.FactPlan p
    JOIN dw.DimDate d ON d.DateKey = p.DateKey
    GROUP BY d.[Year], d.[Month], p.CostCenterKey, p.AccountKey
)
SELECT  COALESCE(a.[Year], p.[Year])                   AS [Year],
        COALESCE(a.[Month], p.[Month])                 AS [Month],
        COALESCE(a.CostCenterKey, p.CostCenterKey)     AS CostCenterKey,
        COALESCE(a.AccountKey, p.AccountKey)           AS AccountKey,
        ISNULL(a.Actual, 0)                            AS Actual,
        ISNULL(p.Budget, 0)                            AS Budget,
        p.Forecast,
        ISNULL(a.Actual, 0) - ISNULL(p.Budget, 0)      AS VarianceAmount,
        (ISNULL(a.Actual, 0) - ISNULL(p.Budget, 0)) * ac.PLSign AS VarianceFavorable   -- > 0 favorevole
FROM act a
FULL OUTER JOIN pln p
       ON p.[Year] = a.[Year] AND p.[Month] = a.[Month]
      AND p.CostCenterKey = a.CostCenterKey AND p.AccountKey = a.AccountKey
JOIN dw.DimAccount ac ON ac.AccountKey = COALESCE(a.AccountKey, p.AccountKey);
GO
