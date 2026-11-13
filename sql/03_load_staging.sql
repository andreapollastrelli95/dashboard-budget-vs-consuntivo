/* =============================================================================
   Script 03 - caricamento CSV in staging (BULK INSERT)
   Prima di eseguire: impostare @DataPath con la cartella "data" del repository.
   Nota: il percorso deve essere visibile dal servizio SQL Server, non dal client.
   FORMAT = 'CSV' richiede SQL Server 2017 o successivo.
   ============================================================================= */
USE BudgetControl;
GO
SET NOCOUNT ON;

DECLARE @DataPath NVARCHAR(400) = N'C:\Projects\dashboard-budget-vs-consuntivo\data\';   -- <-- modificare
DECLARE @sql NVARCHAR(MAX);

DECLARE @files TABLE (TableName SYSNAME, FileName NVARCHAR(200));
INSERT INTO @files VALUES
    (N'stg.CostCenters',      N'cost_centers.csv'),
    (N'stg.ChartOfAccounts',  N'chart_of_accounts.csv'),
    (N'stg.GLActualEntries',  N'gl_actual_entries.csv'),
    (N'stg.BudgetForecast',   N'budget_forecast.csv'),
    (N'stg.Headcount',        N'headcount.csv');

DECLARE @t SYSNAME, @f NVARCHAR(200);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT TableName, FileName FROM @files;
OPEN cur;
FETCH NEXT FROM cur INTO @t, @f;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'TRUNCATE TABLE ' + @t + N';
    BULK INSERT ' + @t + N'
    FROM ''' + @DataPath + @f + N'''
    WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'',
          CODEPAGE = ''65001'', FIELDQUOTE = ''"'', TABLOCK);';
    EXEC sys.sp_executesql @sql;
    PRINT CONCAT(@t, N' caricata');
    FETCH NEXT FROM cur INTO @t, @f;
END;
CLOSE cur;
DEALLOCATE cur;

-- conteggio righe caricate
SELECT 'stg.GLActualEntries' AS TableName, COUNT(*) AS RowsLoaded FROM stg.GLActualEntries
UNION ALL SELECT 'stg.BudgetForecast', COUNT(*) FROM stg.BudgetForecast
UNION ALL SELECT 'stg.Headcount',      COUNT(*) FROM stg.Headcount
UNION ALL SELECT 'stg.CostCenters',    COUNT(*) FROM stg.CostCenters;
GO
