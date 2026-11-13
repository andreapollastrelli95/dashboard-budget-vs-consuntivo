/* =============================================================================
   Progetto : Budget vs Consuntivo
   Azienda  : Arcadia Distribuzione S.r.l. (dati simulati)
   Script   : 01 - database, schemi, tabelle
   Target   : SQL Server 2019 o successivo
   ============================================================================= */

IF DB_ID(N'BudgetControl') IS NULL
    CREATE DATABASE BudgetControl;
GO
USE BudgetControl;
GO

IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg AUTHORIZATION dbo;');
IF SCHEMA_ID(N'dw')  IS NULL EXEC (N'CREATE SCHEMA dw  AUTHORIZATION dbo;');
IF SCHEMA_ID(N'rpt') IS NULL EXEC (N'CREATE SCHEMA rpt AUTHORIZATION dbo;');
GO

/* ------------------------------------------------------------------ STAGING */
DROP TABLE IF EXISTS stg.CostCenters;
CREATE TABLE stg.CostCenters (CostCenterCode NVARCHAR(10), CostCenterName NVARCHAR(100), CostCenterType NVARCHAR(30),
                              BusinessArea NVARCHAR(30), Manager NVARCHAR(100));

DROP TABLE IF EXISTS stg.ChartOfAccounts;
CREATE TABLE stg.ChartOfAccounts (AccountCode NVARCHAR(10), AccountName NVARCHAR(150), PLGroup NVARCHAR(50),
                                  AccountType NVARCHAR(20), IsControllable NVARCHAR(5), PLSign NVARCHAR(5), SortOrder NVARCHAR(10));

DROP TABLE IF EXISTS stg.GLActualEntries;
CREATE TABLE stg.GLActualEntries (EntryID NVARCHAR(20), DocumentNumber NVARCHAR(30), PostingDate NVARCHAR(20),
                                  CostCenterCode NVARCHAR(10), AccountCode NVARCHAR(10), Amount NVARCHAR(30),
                                  Description NVARCHAR(200), Counterparty NVARCHAR(200));

DROP TABLE IF EXISTS stg.BudgetForecast;
CREATE TABLE stg.BudgetForecast (Scenario NVARCHAR(20), [Year] NVARCHAR(5), [Month] NVARCHAR(3), CostCenterCode NVARCHAR(10),
                                 AccountCode NVARCHAR(10), Amount NVARCHAR(30));

DROP TABLE IF EXISTS stg.Headcount;
CREATE TABLE stg.Headcount (Scenario NVARCHAR(20), [Year] NVARCHAR(5), [Month] NVARCHAR(3), CostCenterCode NVARCHAR(10), FTE NVARCHAR(10));
GO

/* ------------------------------------------------------------------ DW */
DROP TABLE IF EXISTS dw.ManagementComment;
DROP TABLE IF EXISTS dw.FactHeadcount;
DROP TABLE IF EXISTS dw.FactPlan;
DROP TABLE IF EXISTS dw.FactActual;
DROP TABLE IF EXISTS dw.DimScenario;
DROP TABLE IF EXISTS dw.DimAccount;
DROP TABLE IF EXISTS dw.DimCostCenter;
DROP TABLE IF EXISTS dw.DimDate;
GO

CREATE TABLE dw.DimDate (
    DateKey INT NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY, [Date] DATE NOT NULL, [Year] SMALLINT NOT NULL,
    [Quarter] TINYINT NOT NULL, QuarterLabel CHAR(2) NOT NULL, [Month] TINYINT NOT NULL, MonthName NVARCHAR(15) NOT NULL,
    MonthShort NVARCHAR(3) NOT NULL, YearMonth INT NOT NULL, YearMonthLabel NVARCHAR(10) NOT NULL,
    WeekOfYear TINYINT NOT NULL, DayOfWeek TINYINT NOT NULL, DayName NVARCHAR(10) NOT NULL,
    IsWeekend BIT NOT NULL, IsHoliday BIT NOT NULL, IsWorkingDay BIT NOT NULL,
    MonthStartDate DATE NOT NULL, MonthEndDate DATE NOT NULL
);

CREATE TABLE dw.DimCostCenter (
    CostCenterKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimCostCenter PRIMARY KEY,
    CostCenterCode  NVARCHAR(10)  NOT NULL CONSTRAINT UQ_DimCostCenter UNIQUE,
    CostCenterName  NVARCHAR(100) NOT NULL,
    CostCenterType  NVARCHAR(30)  NOT NULL,       -- Centro di ricavo / Centro di costo
    BusinessArea    NVARCHAR(30)  NOT NULL,       -- Commerciale / Operations / Struttura
    Manager         NVARCHAR(100) NOT NULL
);

CREATE TABLE dw.DimAccount (
    AccountKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimAccount PRIMARY KEY,
    AccountCode     NVARCHAR(10)  NOT NULL CONSTRAINT UQ_DimAccount UNIQUE,
    AccountName     NVARCHAR(150) NOT NULL,
    PLGroup         NVARCHAR(50)  NOT NULL,       -- Ricavi, Costo del venduto, Costo del personale, ...
    AccountType     NVARCHAR(20)  NOT NULL,       -- Revenue / COGS / Opex / D&A
    IsControllable  BIT           NOT NULL,       -- il responsabile del centro puo' influenzarlo?
    PLSign          SMALLINT      NOT NULL,       -- +1 ricavi, -1 costi
    SortOrder       INT           NOT NULL
);

CREATE TABLE dw.DimScenario (
    ScenarioKey     TINYINT       NOT NULL CONSTRAINT PK_DimScenario PRIMARY KEY,
    ScenarioName    NVARCHAR(20)  NOT NULL,
    ScenarioDesc    NVARCHAR(100) NOT NULL
);

-- grain: riga di prima nota (consuntivo)
CREATE TABLE dw.FactActual (
    ActualKey       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactActual PRIMARY KEY NONCLUSTERED,
    DateKey         INT           NOT NULL CONSTRAINT FK_FA_Date       REFERENCES dw.DimDate(DateKey),
    CostCenterKey   INT           NOT NULL CONSTRAINT FK_FA_CostCenter REFERENCES dw.DimCostCenter(CostCenterKey),
    AccountKey      INT           NOT NULL CONSTRAINT FK_FA_Account    REFERENCES dw.DimAccount(AccountKey),
    DocumentNumber  NVARCHAR(30)  NOT NULL,
    Amount          DECIMAL(18,2) NOT NULL,       -- segno naturale (sconti a clienti negativi)
    SignedAmount    DECIMAL(18,2) NOT NULL,       -- segno da conto economico
    Description     NVARCHAR(200) NULL,
    Counterparty    NVARCHAR(200) NULL
);

-- grain: mese x centro x conto x scenario (Budget / Forecast). DateKey = primo giorno del mese
CREATE TABLE dw.FactPlan (
    DateKey         INT           NOT NULL CONSTRAINT FK_FP_Date       REFERENCES dw.DimDate(DateKey),
    CostCenterKey   INT           NOT NULL CONSTRAINT FK_FP_CostCenter REFERENCES dw.DimCostCenter(CostCenterKey),
    AccountKey      INT           NOT NULL CONSTRAINT FK_FP_Account    REFERENCES dw.DimAccount(AccountKey),
    ScenarioKey     TINYINT       NOT NULL CONSTRAINT FK_FP_Scenario   REFERENCES dw.DimScenario(ScenarioKey),
    Amount          DECIMAL(18,2) NOT NULL,
    SignedAmount    DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_FactPlan PRIMARY KEY (ScenarioKey, DateKey, CostCenterKey, AccountKey)
);

-- grain: mese x centro x scenario (Actual / Budget)
CREATE TABLE dw.FactHeadcount (
    DateKey         INT           NOT NULL CONSTRAINT FK_FH_Date       REFERENCES dw.DimDate(DateKey),
    CostCenterKey   INT           NOT NULL CONSTRAINT FK_FH_CostCenter REFERENCES dw.DimCostCenter(CostCenterKey),
    ScenarioKey     TINYINT       NOT NULL CONSTRAINT FK_FH_Scenario   REFERENCES dw.DimScenario(ScenarioKey),
    FTE             DECIMAL(6,1)  NOT NULL,
    CONSTRAINT PK_FactHeadcount PRIMARY KEY (ScenarioKey, DateKey, CostCenterKey)
);

-- commenti manageriali generati dalla procedura rpt.usp_GenerateManagementComments
CREATE TABLE dw.ManagementComment (
    CommentID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ManagementComment PRIMARY KEY,
    [Year]          SMALLINT      NOT NULL,
    [Month]         TINYINT       NOT NULL,       -- commento riferito al progressivo (YTD) a questo mese
    CostCenterKey   INT           NULL,           -- NULL = commento a livello azienda
    CommentType     NVARCHAR(30)  NOT NULL,       -- Sintesi / Scostamento negativo / Scostamento positivo / Organico / Forecast
    Priority        TINYINT       NOT NULL,       -- 1 = da leggere per primo
    CommentText     NVARCHAR(600) NOT NULL,
    CreatedAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_ManagementComment_CreatedAt DEFAULT (SYSDATETIME())
);
GO

CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactActual ON dw.FactActual;
GO
