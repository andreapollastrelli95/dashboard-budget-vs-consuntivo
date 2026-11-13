/* =============================================================================
   Script 04 - caricamento DW (stg -> dw)
   ============================================================================= */
USE BudgetControl;
GO

CREATE OR ALTER PROCEDURE dw.usp_LoadBudgetControl
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE dw.FactActual;
        DELETE FROM dw.FactPlan;
        DELETE FROM dw.FactHeadcount;
        DELETE FROM dw.ManagementComment;
        DELETE FROM dw.DimScenario;
        DELETE FROM dw.DimAccount;     DBCC CHECKIDENT ('dw.DimAccount', RESEED, 0) WITH NO_INFOMSGS;
        DELETE FROM dw.DimCostCenter;  DBCC CHECKIDENT ('dw.DimCostCenter', RESEED, 0) WITH NO_INFOMSGS;

        INSERT INTO dw.DimScenario (ScenarioKey, ScenarioName, ScenarioDesc) VALUES
            (1, N'Actual',   N'Consuntivo da contabilita'' generale'),
            (2, N'Budget',   N'Budget approvato dal CdA (novembre anno precedente)'),
            (3, N'Forecast', N'Forecast 6+6: consuntivo gen-giu + stima lug-dic (luglio)');

        INSERT INTO dw.DimCostCenter (CostCenterCode, CostCenterName, CostCenterType, BusinessArea, Manager)
        SELECT CostCenterCode, CostCenterName, CostCenterType, BusinessArea, Manager
        FROM stg.CostCenters;

        INSERT INTO dw.DimAccount (AccountCode, AccountName, PLGroup, AccountType, IsControllable, PLSign, SortOrder)
        SELECT AccountCode, AccountName, PLGroup, AccountType,
               TRY_CONVERT(BIT, IsControllable), TRY_CONVERT(SMALLINT, PLSign), TRY_CONVERT(INT, SortOrder)
        FROM stg.ChartOfAccounts;

        /* consuntivo: righe di prima nota */
        INSERT INTO dw.FactActual (DateKey, CostCenterKey, AccountKey, DocumentNumber, Amount, SignedAmount,
                                   Description, Counterparty)
        SELECT  CONVERT(INT, CONVERT(CHAR(8), TRY_CONVERT(DATE, g.PostingDate), 112)),
                cc.CostCenterKey,
                a.AccountKey,
                g.DocumentNumber,
                v.Amount,
                v.Amount * a.PLSign,
                g.Description,
                NULLIF(g.Counterparty, N'')
        FROM stg.GLActualEntries g
        CROSS APPLY (SELECT TRY_CONVERT(DECIMAL(18,2), g.Amount) AS Amount) v
        JOIN dw.DimCostCenter cc ON cc.CostCenterCode = g.CostCenterCode
        JOIN dw.DimAccount    a  ON a.AccountCode     = g.AccountCode;

        /* budget e forecast mensili: data = primo giorno del mese */
        INSERT INTO dw.FactPlan (DateKey, CostCenterKey, AccountKey, ScenarioKey, Amount, SignedAmount)
        SELECT  CONVERT(INT, CONVERT(CHAR(8), DATEFROMPARTS(TRY_CONVERT(INT, b.[Year]), TRY_CONVERT(INT, b.[Month]), 1), 112)),
                cc.CostCenterKey,
                a.AccountKey,
                s.ScenarioKey,
                SUM(v.Amount),
                SUM(v.Amount) * a.PLSign
        FROM stg.BudgetForecast b
        CROSS APPLY (SELECT TRY_CONVERT(DECIMAL(18,2), b.Amount) AS Amount) v
        JOIN dw.DimCostCenter cc ON cc.CostCenterCode = b.CostCenterCode
        JOIN dw.DimAccount    a  ON a.AccountCode     = b.AccountCode
        JOIN dw.DimScenario   s  ON s.ScenarioName    = b.Scenario
        GROUP BY b.[Year], b.[Month], cc.CostCenterKey, a.AccountKey, s.ScenarioKey, a.PLSign;

        INSERT INTO dw.FactHeadcount (DateKey, CostCenterKey, ScenarioKey, FTE)
        SELECT  CONVERT(INT, CONVERT(CHAR(8), DATEFROMPARTS(TRY_CONVERT(INT, h.[Year]), TRY_CONVERT(INT, h.[Month]), 1), 112)),
                cc.CostCenterKey,
                s.ScenarioKey,
                TRY_CONVERT(DECIMAL(6,1), h.FTE)
        FROM stg.Headcount h
        JOIN dw.DimCostCenter cc ON cc.CostCenterCode = h.CostCenterCode
        JOIN dw.DimScenario   s  ON s.ScenarioName    = h.Scenario;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

EXEC dw.usp_LoadBudgetControl;
GO
