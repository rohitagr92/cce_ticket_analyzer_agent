# AI Incident Analyzer — Web App Change Log

This document records the changes made to implement:
1. Service-Offering-specific data retention/cleanup (Prod Tools before WW19, Email and
   Calendaring before WW27, Content Engineering ("Content Sharing") before WW26).
2. Fully dynamic Work Week (WW) handling (no hardcoded weeks), with per-Service-Offering
   WW dropdowns.
3. A shared WW selection kept in sync across the Summary, Ops Report+, and AI
   Recommendation tabs.
4. A dynamic Service Offering dropdown (driven by `config.json`) plus a visible
   "Service" indicator.
5. An incident search bar on Ops Report+ that combines with existing filters.
6. Scheduled-run compatibility (report/index JSON structure unchanged).

No unrelated refactors, renames, or feature removals were made. No secrets/keys were
added to the repo.

## Summary of changes

| Area | File | Line(s) | Change Made | Why Needed | Validation |
|---|---|---|---|---|---|
| Retention cutoff map | `web/index.html` | 1028-1039 | Added `SERVICE_WW_CUTOFF` map (`Productivity Tools` -> `2026-W19`, `Email and Calendaring` -> `2026-W27`, `Content Engineering` -> `2026-W26`) and `isWeekAllowedForService(week, svcName)` helper. | Central, single source of truth for the per-Service-Offering retention rule (req. 1), instead of scattering cutoff checks across tabs. | `node --check` on extracted `<script>` passes; manually traced that weeks below each cutoff are excluded per service. |
| Retention enforcement | `web/index.html` | `ensureTableLoaded()`, ~1041-1063 | Table entities are filtered through `isWeekAllowedForService()` before being cached into `allEntities`/`aggregated`, so every tab (Summary, Reports+, Trends+, Root Cause, Ops Report+, AI Recs) is automatically scoped, since they all read from the same cached data. | Single enforcement point guarantees requirement 1 applies everywhere without per-tab duplication and without breaking existing tab logic. | Reviewed all tab load functions confirm they read from `ensureTableLoaded()`/`aggregated`, not a raw unfiltered fetch. |
| Shared WW/Service state | `web/index.html` | 1064-1198 | Added `SHARED_FILTER` state object, `SHARED_FILTER_SYNCING` re-entrancy guard, `applySharedFilterServiceIfValid()`, `applySharedFilterWeeksIfValid()`, `pushSharedFilter()`, and `resyncSummaryFromShared()` / `resyncOpsPlusFromShared()` / `resyncAirRecsFromShared()`. | Implements requirement 3: keeps the WW (and Service) selection synchronized across Summary, Ops Report+, and AI Recommendation without a framework/build step, respecting that each tab lazy-loads once and keeps its own DOM controls. | Manually traced call graph: changing the selector on any of the three tabs calls `pushSharedFilter`, which immediately resyncs the other two tabs if already loaded, and seeds an as-yet-unloaded tab the first time it loads. |
| Dynamic week lookup | `web/index.html` | `weeksMatchingService()`, ~1199-1212 | New helper returning sorted distinct weeks for a given Service Offering, reusing the existing "Productivity Tools = blank-or-match" convention already used elsewhere in the file. | Provides one dynamic (non-hardcoded) source of WW options for every tab's dropdown (req. 2). | Cross-checked against pre-existing `opxMatchesService`/`airMatchesService` logic for consistent service-matching semantics. |
| Dynamic Service dropdown | `web/index.html` | `populateServiceDropdown()`, ~1213-1230 | New helper that rebuilds a `<select>`'s options from the runtime `serviceConfigs` array (sourced from `config.json`), preserving the previous selection if still valid. | Removes hardcoded 3-option `<select>` lists on Trends+/Root Cause/Ops Report+/AI Recs so the dropdown always matches configured Service Offerings (req. 4). | Confirmed `serviceConfigs` is populated before any tab load function runs (loaded during app bootstrap). |
| Header service indicator | `web/index.html` | 464 | Added `<span>Service: <strong>End User Collaboration</strong></span>` under the page title. | Requirement 4's "Service" indicator; kept static/non-interactive since "Service" is a fixed umbrella label distinct from the per-tab "Service Offering" dropdowns. | Visual-only change; no existing styling/layout altered. |
| Ops Report+ search bar (HTML) | `web/index.html` | 751 | Added `<input type="search" id="opxSearch" placeholder="Search incident #, product, symptom, root cause…">` to the Ops Report+ filter toolbar. | Requirement 5: incident number + free-text search field. | Verified input placed alongside existing filter controls without disturbing their layout/styling. |
| Ops Report+ search logic | `web/index.html` | `opxApplySearch()` ~2679-2713, `opxGetFiltered()` ~2661-2678 | Added `opxApplySearch(entities)` (case-insensitive substring match against `RowKey`, `Category`, `Subcategory`, `PossibleRootCause`, `RootCause`, `DetailedRootCause`, `AIAnalysis`); wired into `opxGetFiltered()` so the search combines (AND-logic) with existing Service/WW/Product/Subcategory/RootCause filters. | Requirement 5: search must combine with existing filters, not replace them. | Traced `opxGetFiltered()` pipeline to confirm search runs alongside (not instead of) existing filter predicates. |
| Ops Report+ WW scoping | `web/index.html` | `opxWeeksInRange()` ~2714-2721, `opxBuildPatternStats()` ~2722-onward, `opxBuildSparkline()` ~3001-onward, `loadOpsPlus()` ~3354-onward | Changed week sources from global `aggregated.weeks` to `weeksMatchingService($('opxService').value)`; `loadOpsPlus()` now calls `populateServiceDropdown('opxService')`, `applySharedFilterServiceIfValid('opxService')` (seed from shared filter) **before** `opxRebuildFirstSeen()` (fixed an initial ordering bug so first-seen-week history isn't computed against a stale service), then `populateOpxWeeks(weeksMatchingService(...))`, `applySharedFilterWeeksIfValid(...)`, and adds a search-input listener and `pushSharedFilter('opx', ...)` calls on the Service/WeekFrom/WeekTo change handlers and the reset button (which also clears the search box). | Requirements 2 & 3: Ops Report+ WW/stat calculations must be scoped to the selected Service Offering, and its selection must participate in the shared cross-tab filter. | `node --check` passes; manually re-verified call order so `opxRebuildFirstSeen()` runs after the service value is finalized. |
| Trends+ dynamic scoping | `web/index.html` | `tpPopulateWeeks()` ~1699-1710, `loadTrendsPlus()` ~1869-onward | Replaced hardcoded `<option>` list with `populateServiceDropdown('tpService')`; weeks now sourced via `weeksMatchingService($('tpService').value)` on load, on Service change, and on reset. | Requirements 2 & 4 applied to Trends+. | Confirmed no other Trends+ behavior (chart rendering, existing filters) was altered. |
| Root Cause dynamic scoping | `web/index.html` | `rcPopulateWeeks()` ~1926-1937, `loadRootCause()` ~2154-onward | Same pattern as Trends+: dynamic Service dropdown + per-service WW scoping. | Requirements 2 & 4 applied to Root Cause. | Confirmed no other Root Cause behavior (charting, drilldowns) was altered. |
| AI Recs dynamic scoping + shared filter | `web/index.html` | `airAllWeeks` ~3539, `loadAirecs()` ~4316-onward | `airAllWeeks` now calls `weeksMatchingService(...)` instead of a global week list; `loadAirecs()` calls `populateServiceDropdown('airService')`, `applySharedFilterServiceIfValid('airService')`, `applySharedFilterWeeksIfValid(...)`, and adds `pushSharedFilter('air', ...)` to its Service/WeekFrom/WeekTo listeners and reset button. | Requirements 2, 3, 4 applied to AI Recommendation tab. | Traced listener wiring to confirm AI Recs pushes/receives shared filter changes correctly. |
| Summary shared-filter wiring | `web/index.html` | `loadSummary()` ~5505-onward | Added `applySharedFilterServiceIfValid('smService')` (seed) and `applySharedFilterWeeksIfValid('smFromWeek','smToWeek')`; exposed internal closures via module-level `smRebuildRangeRef`/`smRebuildDrillRef`/`smRenderRef` so `resyncSummaryFromShared()` can re-render Summary when another tab changes the shared filter; added `pushSharedFilter('sm', ...)` to the Service/From/To change listeners and the reset button. | Requirement 3: Summary participates in the same shared WW/Service state as Ops Report+ and AI Recs. | Manually traced that `resyncSummaryFromShared()` calls the exposed refs only after they've been assigned (i.e., only after Summary has loaded at least once). |

## Deliberate scope decisions / TODOs

- Trends+ and Root Cause dropdowns are **not** part of the cross-tab `SHARED_FILTER` sync,
  per the requirement explicitly scoping shared state to Summary, Ops Report+, and AI
  Recommendation only.
- The "Service" header badge (`End User Collaboration`) is a static label, not a
  functional dropdown — the per-tab "Service Offering" dropdowns already provide the
  functional selector requirement. `TODO:` if a global functional Service dropdown is
  later required (as opposed to the per-tab Service Offering dropdowns), wire it through
  `SHARED_FILTER.service`/`pushSharedFilter` the same way the WW range is handled.
- WW cutoff values assume the `2026` year prefix used throughout the current data set
  (`2026-W19`, `2026-W27`, `2026-W26`). `TODO:` if data spans a year boundary, replace the
  simple string comparison in `isWeekAllowedForService()` with a numeric (year, week)
  tuple comparison.
- "Content Engineering" in `config.json`/`serviceConfigs` is treated as the "Content
  Sharing" Service Offering referenced in the request (no other Service Offering name in
  the codebase matches "Content Sharing").
- Client-side cutoff filtering in `web/index.html` only **hides** pre-cutoff data in the
  UI. It does **not** delete anything from Azure Table/Blob Storage. Use
  `setup/Cleanup-OldWeeksByServiceOffering.ps1` (new script, see below) to physically
  remove old data from storage.

## New backend script

| Area | File | Change Made | Why Needed | Validation |
|---|---|---|---|---|
| Storage-level retention cleanup | `setup/Cleanup-OldWeeksByServiceOffering.ps1` (new) | New PowerShell script that deletes Azure Table Storage rows (`PartitionKey` before the Service Offering's cutoff week) and Blob Storage report artifacts (filename WW before cutoff) for **one** Service Offering's storage account/table/container per invocation. Defaults mirror the `SERVICE_WW_CUTOFF` map in `web/index.html`. Runs as a **dry run by default**; requires an explicit `-Execute` switch to actually delete, and supports `-WhatIf`/`-Confirm` via `SupportsShouldProcess`. | Requirement 1's storage-level retention/cleanup (the UI-side cutoff only hides data; this script is what actually reclaims/removes old rows and blobs per Service Offering, without risk of touching another offering's data). | Validated with `[System.Management.Automation.Language.Parser]::ParseFile()` (no syntax errors). Not executed against any live storage account by the agent — this is a destructive, hard-to-reverse operation and must be run intentionally by an operator (dry run first, then `-Execute`). |

## Scheduled-run / report generation compatibility (requirement 6)

- `setup/reporting/Build-ReportsIndex.ps1` builds `index.json` by scanning whatever HTML
  report blobs currently exist in a Service Offering's `results` container — its output
  schema (`reports`, `trends`, `runs` arrays) is unchanged, so it remains structurally
  compatible with `web/index.html` after these changes.
- Because report generation is a blob-scan (not hardcoded to specific weeks), once
  `Cleanup-OldWeeksByServiceOffering.ps1 -Execute` removes pre-cutoff blobs for a Service
  Offering, the **next** scheduled run of `Build-ReportsIndex.ps1` for that Service
  Offering's storage account will naturally omit them from `index.json` — no code change
  was required in that script.
- No existing runbook (`runbooks/*.ps1`, `content-engineering/runbooks/*.ps1`) writes a
  hardcoded WW value; they compute the current work week at run time, so future scheduled
  runs continue to populate Table Storage under the correct, non-hardcoded `PartitionKey`.
- All tabs read from `ensureTableLoaded()`/`aggregated`, whose shape (`weeks`, `byWeek`,
  etc.) was not changed — only the *values* passed through it are now cutoff-filtered.
  Existing/future scheduled-run JSON and HTML output remain structurally compatible.

## Validation performed

- `node --check` against the extracted `<script>` contents of `web/index.html` — passes
  (no JavaScript syntax errors) after all edits.
- `get_errors` run against `web/index.html` and the new `.ps1` script — no errors
  reported.
- `[System.Management.Automation.Language.Parser]::ParseFile()` run against
  `setup/Cleanup-OldWeeksByServiceOffering.ps1` — no syntax errors.
- Manual code review/call-graph tracing of the shared-filter push/resync wiring and the
  Ops Report+ load-order fix (service dropdown/shared-filter seeding now happens before
  `opxRebuildFirstSeen()`).
- **Not performed** (requires a live `config.json`/Azure Static Web App environment):
  browser-based manual QA of dropdown interactions, search results, and end-to-end
  cutoff behavior against real data. Recommended before/as part of deployment (see below).

## Deployment guidance

### Frontend (Azure Static Web App)

1. No build step is required — `web/index.html` is served as-is.
2. Ensure `web/config.json` (generated from `web/config.sample.json`) is present/updated
   in the deployment output with the current `serviceConfigs` entries (name, table/blob
   SAS, etc.) for all three Service Offerings.
3. Deploy via the existing Static Web App pipeline/CLI, e.g.:
   ```powershell
   swa deploy ./web --deployment-token <token> --env production
   ```
   or via `setup/Deploy-Web.ps1` if that is the repo's existing deployment entry point.
4. Smoke-test after deploy: load each tab (Summary, Reports+, Trends+, Root Cause, Ops
   Report+, AI Recs), confirm the Service Offering dropdown lists all configured
   offerings, WW dropdowns only show weeks at/after each offering's cutoff, changing WW/
   Service on Summary/Ops Report+/AI Recs stays in sync across those three tabs, and the
   Ops Report+ search box filters results as expected.

### Backend / scheduled runs

1. No changes are required to the existing Azure Automation runbooks
   (`runbooks/*.ps1`, `content-engineering/runbooks/*.ps1`) — they already compute WW
   dynamically.
2. If `setup/reporting/Build-ReportsIndex.ps1` / `Build-WeeklyReports.ps1` are already on
   a schedule, no redeployment is needed for this change; their output schema is
   unchanged.

### Storage cleanup (one-time, per Service Offering)

1. Dry run first (no `-Execute`) to review what would be removed:
   ```powershell
   ./setup/Cleanup-OldWeeksByServiceOffering.ps1 -ServiceOffering 'Productivity Tools'
   ./setup/Cleanup-OldWeeksByServiceOffering.ps1 -ServiceOffering 'Email and Calendaring'
   ./setup/Cleanup-OldWeeksByServiceOffering.ps1 -ServiceOffering 'Content Engineering'
   ```
2. Review the reported row/blob counts, then re-run with `-Execute` for each offering
   once satisfied.
3. Re-run `setup/reporting/Build-ReportsIndex.ps1` (per affected storage account) so
   `index.json` reflects the removed report blobs.

### Rollback

- Frontend: redeploy the previous `web/index.html` (via `git revert`/prior SWA
  deployment) — no data changes are involved, so rollback is immediate and safe.
- Storage cleanup: **irreversible** once `-Execute` is run — restore from a Table/Blob
  Storage backup or point-in-time restore (if enabled on the storage account) if data
  was removed in error. Always run the dry run first and review counts before
  `-Execute`.

## Risks / follow-ups

- The `SERVICE_WW_CUTOFF` map and the new script's default cutoffs are duplicated in two
  places (`web/index.html` and `setup/Cleanup-OldWeeksByServiceOffering.ps1`) since there
  is no shared config file read by both the browser and PowerShell today; keep them in
  sync if cutoffs change.
- `Cleanup-OldWeeksByServiceOffering.ps1` deletes Table rows/blobs and is **not** run
  automatically — an operator must run it deliberately (dry run, then `-Execute`).
- No automated/browser-based QA was performed against a live environment; recommend
  manual smoke-testing per the Deployment guidance section above before/after rollout.

## Production deployment + storage cleanup executed

- **Frontend deployed** to the production Azure Static Web App
  (`https://nice-wave-080119d1e.7.azurestaticapps.net`, resource `opsw-prodtools-reports`
  in resource group `OPSW-Ticket-Analyzer`) via
  `npx --yes @azure/static-web-apps-cli deploy .\web --deployment-token <token> --env production`.
  Deployment token retrieved via `Get-AzStaticWebAppSecret` (RBAC-based, no secret ever
  pasted into chat) — note the cmdlet returns the key at `.Property` as a JSON string
  (`(Get-AzStaticWebAppSecret ...).Property | ConvertFrom-Json | Select apiKey`), not a
  top-level `.ApiKey` property.
- **Bugfix**: `setup/Cleanup-OldWeeksByServiceOffering.ps1`'s `$defaults` hashtable had
  placeholder/guessed `StorageAccountName` values for two Service Offerings that did not
  match real Azure resources. Corrected against `Get-AzStorageAccount -ResourceGroupName
  'OPSW-Ticket-Analyzer'` output:
  - `Email and Calendaring`: `opswemailcalblob` -> `opswticketanal0571255553`
  - `Content Engineering`: `opswcontentengblob` -> `opswcontentenggblob` (double "gg")
  - `Productivity Tools` (`opswprodtoolsblob`) was already correct.
- **Cleanup executed** (dry run reviewed first for all three, then `-Execute`):
  - Productivity Tools: 269 table rows across 50 partitions + 5 report blobs deleted.
  - Email and Calendaring: 438 table rows across 5 partitions + 16 report blobs deleted.
  - Content Engineering: 0 rows / 0 blobs found before cutoff (nothing to remove).
  - `setup/reporting/Build-ReportsIndex.ps1` re-run for `opswprodtoolsblob` and
    `opswticketanal0571255553` afterward so `index.json` reflects the removed reports.

## Performance fix — web app load time

**Root cause**: `fetchTableEntities()` fetched each Service Offering's entire Azure Table
(via continuation-token paging, no server-side filter) **sequentially**, one offering at
a time, and only discarded pre-cutoff rows client-side via `isWeekAllowedForService()`
*after* every row had already been downloaded and parsed. With 3 Service Offerings this
meant 3x chained round-trip latency plus transferring/parsing rows that were guaranteed
to be thrown away.

Changes made (`web/index.html`):

| Change | Location | Why |
|---|---|---|
| Parallelized per-service fetch | `fetchTableEntities()` | Replaced the sequential `for (const svc of serviceConfigs) { await fetchOneTable(svc) }` loop with `Promise.all(serviceConfigs.map(...))` so all Service Offerings' tables load concurrently instead of one-at-a-time. |
| Server-side retention filter | `fetchOneTable()` | Added an OData `$filter=PartitionKey ge '<cutoff>'` (using the existing `SERVICE_WW_CUTOFF` map) to the table query URL, so Azure Table Storage excludes pre-cutoff rows itself instead of the browser downloading and then discarding them. This is defense-in-depth on top of the physical storage cleanup above (helps if a future cleanup run is delayed/missed). |
| Short-lived session cache | `ensureTableLoaded()`, new `readTableCache()`/`writeTableCache()` | Added a 5-minute `sessionStorage` cache (`aiIncidentAnalyzer.tableCache.v1`) so reloading or re-navigating the SPA within the same browser tab/session doesn't re-fetch the entire table over the network every time. TTL kept short so scheduled-run updates still surface promptly; falls back to a normal fetch if the cache is missing, stale, or `sessionStorage` is unavailable. |

**Validation**: `node --check` against the extracted `<script>` contents passes; `get_errors`
reports no issues. Redeployed to production via the same `swa deploy ... --env production`
command after the fix.
