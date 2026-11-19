# QuWork Agent Development Guidelines

These rules apply to Codex, agents, and human developers working on the QuWork product.

## Before coding

Read `AGENTS.md`, `CONTRIBUTING.md`, `docs/architecture.md`, and `docs/quwork-sync-gate.md`. Inspect `git status`, protect existing uncommitted work, fetch the current `origin/main`, and fetch `upstream/main` when source synchronization is involved. Label every change as upstream-syncable capability, QuWork product functionality, or conflict-protection code.

## Account and model contract

- QuWork is the only product account system. Do not add DeepSeek official sign-in or API-key entry.
- After sign-in, configure the `quwork` provider using the model credential returned by the QuWork API.
- Models come from the QuWork entitlement API; static fake model data is not acceptable for production behavior.
- The default model must use `quwork`; model selection must not fall back to DeepSeek or another external account provider.
- Requests go through the QuWork `/v1` service with `QUWORK_LLM_TOKEN`. Never print the token in settings, logs, diagnostics, tests, or screenshots.
- Do not claim to show QuWork balance or usage unless the corresponding server endpoint is implemented and verified. Otherwise show that usage is tracked by the QuWork account.

## Real API validation

Use `https://dev-llm.rrzuji.com/` for development validation and `https://llm.rrzu.com/` for production validation. Login, model listing, and chat requests must use the real dev API; mocks are allowed only for isolated parsing tests, not for login or chat acceptance. Never record full phone numbers, codes, cookies, JWTs, API keys, or `llm_token`. Clearly distinguish simulator evidence from physical-device evidence.

## Code organization

- QuWork protocol code belongs in `packages/quwork_api/`.
- Account state belongs in `app/lib/state/quwork_auth_state.dart`.
- Model synchronization and routing belong in `app/lib/state/quwork_models_state.dart`.
- All account UI entry points lead to `QuWorkLoginPage`. An old `AccountPage` route may remain only as a compatibility alias and must not restore the DeepSeek UI.
- Modify l10n source parts, keep Chinese and English in sync, and run `python3 app/tool/l10n_merge.py`.
- Do not hand-edit generated files, `.dart_tool/`, `app/build/`, or runtime artifacts.

## Handoff

Report changed files and their change categories, run the relevant Dart, Flutter, unit, and l10n checks, record real dev API endpoints and outcomes without secrets, run `git diff --check`, verify `.gitignore`, and stage only explicit paths. Do not commit, push, create branches, or open PRs unless the user explicitly asks.

