// =============================================================================
//  Power Query (M) - Budget vs Consuntivo
//  Parametri: ServerName, DatabaseName
// =============================================================================

// ServerName   = "localhost"       meta [IsParameterQuery = true, Type = "Text"]
// DatabaseName = "BudgetControl"   meta [IsParameterQuery = true, Type = "Text"]

// ---- fnGetView ---------------------------------------------------------------
(ViewName as text) as table =>
let
    Source = Sql.Database(ServerName, DatabaseName),
    View   = Source{[Schema = "rpt", Item = ViewName]}[Data]
in
    View


// ---- Calendar ----------------------------------------------------------------
let
    Source  = fnGetView("Calendar"),
    Types   = Table.TransformColumnTypes(Source, {{"Date", type date}, {"Year", Int64.Type},
                  {"Month", Int64.Type}, {"YearMonth", Int64.Type}}),
    // semestre: serve per leggere il forecast 6+6 (H1 consuntivo, H2 stima)
    Half    = Table.AddColumn(Types, "Half", each if [Month] <= 6 then "H1" else "H2", type text)
in
    Half


// ---- CostCenter --------------------------------------------------------------
let
    Source = fnGetView("CostCenter"),
    // ordinamento: prima i centri di ricavo, poi i centri di costo per area
    Sort   = Table.AddColumn(Source, "CostCenterSort",
                 each (if [CostCenterType] = "Centro di ricavo" then 100 else 200)
                      + Number.From(Text.End([CostCenterCode], 2)), Int64.Type)
in
    Sort


// ---- Account / Scenario ------------------------------------------------------
let
    Source = fnGetView("Account"),
    Types  = Table.TransformColumnTypes(Source, {{"IsControllable", type logical}, {"PLSign", Int64.Type}})
in
    Types

let Source = fnGetView("Scenario") in Source


// ---- FactActual --------------------------------------------------------------
let
    Source  = fnGetView("FactActual"),
    Types   = Table.TransformColumnTypes(Source, {{"Amount", Currency.Type}, {"SignedAmount", Currency.Type}}),
    // tipo di registrazione dal prefisso del numero documento (utile nel dettaglio)
    DocType = Table.AddColumn(Types, "EntryType", each
                  if Text.StartsWith([DocumentNumber], "FV") then "Fattura di vendita"
                  else if Text.StartsWith([DocumentNumber], "AS") then "Scrittura di assestamento"
                  else "Prima nota / fornitore", type text)
in
    DocType


// ---- FactPlan / FactHeadcount ------------------------------------------------
let
    Source = fnGetView("FactPlan"),
    Types  = Table.TransformColumnTypes(Source, {{"Amount", Currency.Type}, {"SignedAmount", Currency.Type}})
in
    Types

let
    Source = fnGetView("FactHeadcount"),
    Types  = Table.TransformColumnTypes(Source, {{"FTE", type number}})
in
    Types


// ---- ManagementComment (tabella scollegata) ---------------------------------
let
    Source = fnGetView("ManagementComment"),
    Types  = Table.TransformColumnTypes(Source, {{"Year", Int64.Type}, {"Month", Int64.Type},
                 {"Priority", Int64.Type}, {"CostCenterKey", Int64.Type}})
in
    Types
