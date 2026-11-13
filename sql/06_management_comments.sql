/* =============================================================================
   Script 06 - commenti manageriali automatici
   Per ogni mese genera, sul progressivo da inizio anno (YTD):
     - una sintesi a livello azienda (ricavi, margine, EBIT vs budget)
     - i 3 scostamenti sfavorevoli e i 2 favorevoli piu' rilevanti (centro x gruppo di conto,
       con ricavi e costo del venduto letti insieme come margine lordo)
     - una riga per ogni centro con la voce che spiega di piu' lo scostamento
     - le differenze di organico (FTE) rispetto al budget
     - il confronto con il forecast di fine anno
   Le soglie di rilevanza sono parametri della procedura.
   Il testo viene poi mostrato in Power BI con una semplice tabella / card.
   ============================================================================= */
USE BudgetControl;
GO

CREATE OR ALTER FUNCTION rpt.fnEuro (@v DECIMAL(18,2))
RETURNS NVARCHAR(30)
AS
BEGIN
    RETURN N'€ ' + FORMAT(@v, 'N0', 'it-IT');
END;
GO

CREATE OR ALTER FUNCTION rpt.fnPct (@v DECIMAL(18,6), @WithSign BIT)
RETURNS NVARCHAR(20)
AS
BEGIN
    RETURN CASE WHEN @WithSign = 1 AND @v > 0 THEN N'+' ELSE N'' END
           + FORMAT(@v * 100, 'N1', 'it-IT') + N'%';
END;
GO

CREATE OR ALTER PROCEDURE rpt.usp_GenerateManagementComments
    @Year             SMALLINT,
    @Month            TINYINT,
    @MinVarianceEuro  DECIMAL(18,2) = 20000,   -- sotto questa soglia non commento
    @MinVariancePct   DECIMAL(9,4)  = 0.03
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dw.ManagementComment WHERE [Year] = @Year AND [Month] = @Month;

    DECLARE @MonthName NVARCHAR(15) =
        (SELECT TOP (1) LOWER(MonthName) FROM dw.DimDate WHERE [Year] = @Year AND [Month] = @Month);

    /* base YTD per centro e conto */
    DROP TABLE IF EXISTS #ytd;
    SELECT  v.CostCenterKey, v.AccountKey, a.AccountName, a.PLGroup, a.AccountType, a.PLSign,
            SUM(v.Actual) AS Actual, SUM(v.Budget) AS Budget,
            SUM(v.VarianceFavorable) AS VarFav
    INTO #ytd
    FROM rpt.vw_BudgetVsActualMonthly v
    JOIN dw.DimAccount a ON a.AccountKey = v.AccountKey
    WHERE v.[Year] = @Year AND v.[Month] <= @Month
    GROUP BY v.CostCenterKey, v.AccountKey, a.AccountName, a.PLGroup, a.AccountType, a.PLSign;

    /* ---------------------------------------------------- 1. sintesi azienda */
    DECLARE @RevA DECIMAL(18,2), @RevB DECIMAL(18,2), @GMA DECIMAL(18,2), @GMB DECIMAL(18,2),
            @EbitA DECIMAL(18,2), @EbitB DECIMAL(18,2);

    SELECT  @RevA  = SUM(CASE WHEN AccountType = N'Revenue' THEN Actual ELSE 0 END),
            @RevB  = SUM(CASE WHEN AccountType = N'Revenue' THEN Budget ELSE 0 END),
            @GMA   = SUM(CASE WHEN AccountType IN (N'Revenue', N'COGS') THEN Actual * PLSign ELSE 0 END),
            @GMB   = SUM(CASE WHEN AccountType IN (N'Revenue', N'COGS') THEN Budget * PLSign ELSE 0 END),
            @EbitA = SUM(Actual * PLSign),
            @EbitB = SUM(Budget * PLSign)
    FROM #ytd;

    INSERT INTO dw.ManagementComment ([Year], [Month], CostCenterKey, CommentType, Priority, CommentText)
    VALUES (@Year, @Month, NULL, N'Sintesi', 1,
        CONCAT(N'Progressivo gennaio-', @MonthName, N' ', @Year, N': ricavi ', rpt.fnEuro(@RevA),
               N' contro ', rpt.fnEuro(@RevB), N' a budget (', rpt.fnPct(@RevA / NULLIF(@RevB, 0) - 1, 1), N'). ',
               N'Margine lordo al ', rpt.fnPct(@GMA / NULLIF(@RevA, 0), 0), N' (budget ', rpt.fnPct(@GMB / NULLIF(@RevB, 0), 0), N'). ',
               N'EBIT ', rpt.fnEuro(@EbitA), N' contro ', rpt.fnEuro(@EbitB), N' a budget: ',
               CASE WHEN @EbitA >= @EbitB THEN N'migliore di ' ELSE N'peggiore di ' END,
               rpt.fnEuro(ABS(@EbitA - @EbitB)), N' (', rpt.fnPct((@EbitA - @EbitB) / NULLIF(ABS(@EbitB), 0), 1), N').'));

    /* ---------------------------------------------------- 2. scostamenti principali (centro x gruppo) */
    -- ricavi e costo del venduto vanno letti insieme (margine lordo): commentarli separati
    -- farebbe sembrare "favorevole" un costo del venduto basso che dipende solo da minori vendite
    ;WITH base AS (
        SELECT  y.*,
                CASE WHEN y.PLGroup IN (N'Ricavi', N'Costo del venduto') THEN N'Margine lordo' ELSE y.PLGroup END AS CommentGroup
        FROM #ytd y
    ),
    grp AS (
        SELECT  b.CostCenterKey, b.CommentGroup AS PLGroup,
                SUM(b.Actual * b.PLSign) AS Actual, SUM(b.Budget * b.PLSign) AS Budget, SUM(b.VarFav) AS VarFav
        FROM base b
        GROUP BY b.CostCenterKey, b.CommentGroup
    ),
    driver AS (     -- conto che spiega di piu' lo scostamento dentro il gruppo
        SELECT  b.CostCenterKey, b.CommentGroup AS PLGroup, b.AccountName, b.VarFav,
                ROW_NUMBER() OVER (PARTITION BY b.CostCenterKey, b.CommentGroup ORDER BY ABS(b.VarFav) DESC) AS rn
        FROM base b
    ),
    ranked AS (
        SELECT  g.*, d.AccountName AS DriverAccount, d.VarFav AS DriverVar,
                ROW_NUMBER() OVER (ORDER BY g.VarFav ASC)  AS rnNeg,
                ROW_NUMBER() OVER (ORDER BY g.VarFav DESC) AS rnPos
        FROM grp g
        JOIN driver d ON d.CostCenterKey = g.CostCenterKey AND d.PLGroup = g.PLGroup AND d.rn = 1
        WHERE ABS(g.VarFav) >= @MinVarianceEuro
          AND ABS(g.Actual - g.Budget) >= @MinVariancePct * ABS(g.Budget)
    )
    INSERT INTO dw.ManagementComment ([Year], [Month], CostCenterKey, CommentType, Priority, CommentText)
    SELECT  @Year, @Month, r.CostCenterKey,
            CASE WHEN r.VarFav < 0 THEN N'Scostamento negativo' ELSE N'Scostamento positivo' END,
            CASE WHEN r.VarFav < 0 THEN 1 + r.rnNeg ELSE 5 + r.rnPos END,
            CONCAT(cc.CostCenterName, N' - ', LOWER(r.PLGroup), N': ', rpt.fnEuro(ABS(r.Actual)),
                   N' contro ', rpt.fnEuro(ABS(r.Budget)), N' a budget (',
                   rpt.fnPct((r.Actual - r.Budget) * SIGN(r.Actual) / NULLIF(ABS(r.Budget), 0), 1), N'), effetto ',
                   CASE WHEN r.VarFav < 0 THEN N'sfavorevole di ' ELSE N'favorevole di ' END, rpt.fnEuro(ABS(r.VarFav)),
                   N'. Voce principale: ', LOWER(r.DriverAccount), N' (', rpt.fnEuro(r.DriverVar), N'). ',
                   N'Responsabile: ', cc.Manager, N'.')
    FROM ranked r
    JOIN dw.DimCostCenter cc ON cc.CostCenterKey = r.CostCenterKey
    WHERE (r.VarFav < 0 AND r.rnNeg <= 3) OR (r.VarFav > 0 AND r.rnPos <= 2);

    /* ---------------------------------------------------- 3. una riga per centro */
    ;WITH c AS (
        SELECT  y.CostCenterKey,
                SUM(y.Actual * y.PLSign) AS ResultA,      -- contributo (centri di ricavo) o -costo (centri di costo)
                SUM(y.Budget * y.PLSign) AS ResultB,
                SUM(y.VarFav) AS VarFav
        FROM #ytd y
        GROUP BY y.CostCenterKey
    ),
    d AS (
        SELECT  y.CostCenterKey, y.AccountName, y.VarFav,
                ROW_NUMBER() OVER (PARTITION BY y.CostCenterKey ORDER BY ABS(y.VarFav) DESC) AS rn
        FROM #ytd y
    )
    INSERT INTO dw.ManagementComment ([Year], [Month], CostCenterKey, CommentType, Priority, CommentText)
    SELECT  @Year, @Month, c.CostCenterKey, N'Centro', 20,
            CONCAT(cc.CostCenterName,
                   CASE WHEN cc.CostCenterType = N'Centro di ricavo' THEN N': contributo ' ELSE N': costi ' END,
                   rpt.fnEuro(ABS(c.ResultA)), N' contro ', rpt.fnEuro(ABS(c.ResultB)), N' a budget, ',
                   CASE WHEN c.VarFav >= 0 THEN N'meglio del budget di ' ELSE N'peggio del budget di ' END,
                   rpt.fnEuro(ABS(c.VarFav)), N'. ',
                   CASE WHEN ABS(c.VarFav) < @MinVarianceEuro THEN N'In linea con le attese.'
                        ELSE CONCAT(N'Pesa soprattutto ', LOWER(d.AccountName), N' (', rpt.fnEuro(d.VarFav), N').') END)
    FROM c
    JOIN d ON d.CostCenterKey = c.CostCenterKey AND d.rn = 1
    JOIN dw.DimCostCenter cc ON cc.CostCenterKey = c.CostCenterKey;

    /* ---------------------------------------------------- 4. organico */
    ;WITH h AS (
        SELECT  f.CostCenterKey,
                AVG(CASE WHEN f.ScenarioKey = 1 THEN f.FTE END) AS FteA,
                AVG(CASE WHEN f.ScenarioKey = 2 THEN f.FTE END) AS FteB
        FROM dw.FactHeadcount f
        JOIN dw.DimDate dd ON dd.DateKey = f.DateKey
        WHERE dd.[Year] = @Year AND dd.[Month] <= @Month
        GROUP BY f.CostCenterKey
    ),
    pc AS (
        SELECT CostCenterKey, SUM(VarFav) AS VarFav
        FROM #ytd WHERE PLGroup = N'Costo del personale'
        GROUP BY CostCenterKey
    )
    INSERT INTO dw.ManagementComment ([Year], [Month], CostCenterKey, CommentType, Priority, CommentText)
    SELECT  @Year, @Month, h.CostCenterKey, N'Organico', 10,
            CONCAT(N'Organico ', cc.CostCenterName, N': in media ', FORMAT(h.FteA, 'N1', 'it-IT'), N' FTE contro ',
                   FORMAT(h.FteB, 'N1', 'it-IT'), N' a budget',
                   CASE WHEN h.FteA < h.FteB THEN N' (assunzioni in ritardo o posizioni scoperte)'
                        ELSE N' (risorse non previste a budget)' END,
                   N'; effetto sul costo del personale ', rpt.fnEuro(ISNULL(pc.VarFav, 0)), N'.')
    FROM h
    LEFT JOIN pc ON pc.CostCenterKey = h.CostCenterKey
    JOIN dw.DimCostCenter cc ON cc.CostCenterKey = h.CostCenterKey
    WHERE ABS(h.FteA - h.FteB) >= 0.5;

    /* ---------------------------------------------------- 5. forecast / chiusura */
    DECLARE @EbitFc DECIMAL(18,2), @EbitBud DECIMAL(18,2), @EbitActFY DECIMAL(18,2);
    SELECT  @EbitFc  = SUM(CASE WHEN p.ScenarioKey = 3 THEN p.SignedAmount END),
            @EbitBud = SUM(CASE WHEN p.ScenarioKey = 2 THEN p.SignedAmount END)
    FROM dw.FactPlan p JOIN dw.DimDate dd ON dd.DateKey = p.DateKey
    WHERE dd.[Year] = @Year;

    IF @EbitFc IS NOT NULL
    BEGIN
        IF @Month < 12
            INSERT INTO dw.ManagementComment ([Year], [Month], CostCenterKey, CommentType, Priority, CommentText)
            VALUES (@Year, @Month, NULL, N'Forecast', 9,
                CONCAT(N'Il forecast 6+6 stima un EBIT di fine anno di ', rpt.fnEuro(@EbitFc), N' contro ',
                       rpt.fnEuro(@EbitBud), N' a budget (', rpt.fnPct((@EbitFc - @EbitBud) / NULLIF(ABS(@EbitBud), 0), 1), N').'));
        ELSE
        BEGIN
            SELECT @EbitActFY = SUM(f.SignedAmount)
            FROM dw.FactActual f JOIN dw.DimDate dd ON dd.DateKey = f.DateKey
            WHERE dd.[Year] = @Year;

            INSERT INTO dw.ManagementComment ([Year], [Month], CostCenterKey, CommentType, Priority, CommentText)
            VALUES (@Year, @Month, NULL, N'Forecast', 9,
                CONCAT(N'Chiusura d''anno: EBIT ', rpt.fnEuro(@EbitActFY), N' contro ', rpt.fnEuro(@EbitFc),
                       N' del forecast di luglio e ', rpt.fnEuro(@EbitBud), N' del budget. ',
                       CASE WHEN @EbitActFY < @EbitFc
                            THEN N'Il secondo semestre e'' andato peggio di quanto stimato a luglio.'
                            ELSE N'Il secondo semestre ha recuperato rispetto alla stima di luglio.' END));
        END
    END;
END;
GO

/* genera i commenti per tutti i mesi con consuntivo */
DECLARE @y SMALLINT, @m TINYINT;
DECLARE months CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT d.[Year], d.[Month]
    FROM dw.FactActual f JOIN dw.DimDate d ON d.DateKey = f.DateKey
    WHERE d.[Year] IN (SELECT DISTINCT dd.[Year] FROM dw.FactPlan p JOIN dw.DimDate dd ON dd.DateKey = p.DateKey)
    ORDER BY d.[Year], d.[Month];
OPEN months;
FETCH NEXT FROM months INTO @y, @m;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC rpt.usp_GenerateManagementComments @Year = @y, @Month = @m;
    FETCH NEXT FROM months INTO @y, @m;
END;
CLOSE months;
DEALLOCATE months;

-- esempio: commenti di dicembre 2025 in ordine di priorita'
SELECT Priority, CommentType, CommentText
FROM dw.ManagementComment
WHERE [Year] = 2025 AND [Month] = 12
ORDER BY Priority, CommentID;
GO
