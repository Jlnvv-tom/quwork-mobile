# QuWork Synchronization Gate

This is the mandatory gate for synchronizing the source repository into the QuWork product branch.

## Branch order

- `upstream`: source repository `ccch1mneyyy/dsh-go`.
- `origin`: the QuWork fork.
- `main`: the reviewed synchronization baseline.
- `quwork`: the QuWork product branch.

Synchronize in this order: inspect the worktree, fetch `upstream/main`, update this repository's `main`, then merge the generic upstream capability into `quwork`. Resolve QuWork product conflicts manually after every sync. Never overwrite user or other-task changes, and do not commit, push, or open a PR unless explicitly requested.

## Syncable capability

Generic protocol-compatible fixes in `packages/dsh_client/`, `packages/dsh_remote/`, `runtime/`, `runtime/bridge/`, tests, accessibility, performance, security, and build checks may be synchronized after reviewing callers, pins, and tests. A green upstream CI run does not prove QuWork login, real API access, model routing, or device behavior.

## Protected QuWork capability

- Product name: `QuWork`.
- Icon input: `/Users/wujihuan/work/rrzu/quwork-dsh-mobile/assets/mobile-push/icon-512.png`.
- Production account service: `https://llm.rrzu.com/`.
- Development account service: `https://dev-llm.rrzuji.com/`.
- Production model service: `https://llm.rrzu.com/v1`.
- Development model service: `https://dev-llm.rrzuji.com/v1`.
- Local configuration: `tooling/quwork.env`, ignored by Git; example: `tooling/quwork.env.example`.
- The product has one account system: QuWork. Users do not sign in to DeepSeek or enter a DeepSeek API key.
- After QuWork sign-in, models come from the QuWork entitlement API and requests use the `quwork` provider with `QUWORK_LLM_TOKEN`.
- Model usage, quota, and accounting belong to the QuWork service.
- The product UI must not expose DeepSeek, ChatGPT, Claude, or arbitrary API-key account entry points.
- Generic upstream providers may remain in the engine for sync compatibility, but must not be presented as QuWork product account options.

## Required change labels

Every task or PR description must identify:

1. Upstream-syncable capability.
2. QuWork product functionality.
3. Conflict-protection code that prevents upstream from replacing QuWork behavior.

If one file contains more than one category, list the affected symbols or configuration keys explicitly.

## Pre-merge checklist

- [ ] Latest `upstream/main` was reviewed and the branch is based on the latest local `main`.
- [ ] QuWork name and icon remain intact.
- [ ] `tooling/quwork.env` is ignored and is not staged.
- [ ] All account entry points lead to QuWork.
- [ ] No DeepSeek official key/account or ChatGPT/Claude sign-in is exposed.
- [ ] The default model route is `quwork` and the credential reference is `QUWORK_LLM_TOKEN`.
- [ ] Real dev API login, model listing, and model request validation are recorded; mocks do not replace real API acceptance.
- [ ] Relevant Dart, Flutter, engine, and l10n checks were run.
- [ ] Any missing real-account, captcha, device, or simulator validation is documented.

