Repository Code Guidelines (Default Rule)
======================================

Purpose
-------
Establish minimal, enforceable rules for all new scripts and runbooks so they remain Azure-compatible, maintainable, and safe to run in production.

Default Rule (apply to all new scripts)
---------------------------------------
- Azure compatible: use Az modules for cloud operations; detect Automation vs local environment and behave accordingly.
- Top-of-file configuration block: declare runtime parameters and required Automation variables (include `ServiceOffering` or `PT_ServiceOfferingId`, `StartDate`/`StartYearWeek`, `EndDate`/`EndYearWeek`).
- Clear comments: brief synopsis, description, required Automation variables, and notes on common failure points (auth, storage, table writes, AI calls).
- Structured & short: prefer small focused functions, avoid monolithic scripts; split responsibilities (fetch, classify, persist).
- Scalable & idempotent: design with pagination, batching, and idempotent writes (InsertOrReplace or Upsert). Use lookback windows rather than unbounded queries.
- Logging & observability: consistent timestamp format, log levels, and optional blob logging; include RunGeneratedAtUtc in artifacts.
- Template-driven prompts: read prompt templates from `templates/` (local) or configured blob container; enforce canonical allowlists.
- Safety gates: require a PR label (`runbook-update`) for edits to protected runbooks; CI should block unlabeled edits.
- Testing: provide a local runner/harness and document how to run it with `LocalConfig-ProductivityTools.psd1` and `LocalSecrets-ProductivityTools.psd1`.

How to use
----------
- Add this checklist to new runbooks' header. Use the repository CI (protect-runbooks.yml) to enforce protected-file edits.

Rationale
---------
Consistency ensures dashboards and downstream consumers receive stable canonical labels and reduces accidental regressions from ad-hoc edits.

Created: 2026-06-24
