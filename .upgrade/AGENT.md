# Upgrade task: Angular 8 to 21

You are upgrading the Angular app in `EFNgApp/EFNgApp/ClientApp` one major version per hop.
This file applies to every hop. The hop file you are given says which versions this hop covers.

## Rules
1. Work only inside `EFNgApp/EFNgApp/ClientApp`. Do not change anything outside it (backend, CI files, other apps).
2. Keep the app's behaviour the same. This is an upgrade, not a redesign: no new features, no restyling.
3. Use the framework's own upgrade tooling first (the commands in the hop file), then fix what is left.
4. Never delete or skip tests, or loosen type checking, to make a check pass.
5. Keep the lockfile in sync: every dependency change goes through `npm`.
6. Do not run `git commit` or `git push`; the workflow commits each hop for you.
7. Prefer the smallest change that is correct for the new version.

## Checks that must pass before the hop is done
Run them from `EFNgApp/EFNgApp/ClientApp`:
- install: `npm install`
- build: `npm run build`
- tests: `npm run test -- --watch=false --browsers=ChromeHeadless` (only required to pass if they passed at baseline)

The baseline (before any upgrade) is in `.upgrade/baseline.json` once the baseline job has run.
A check that already failed at baseline does not have to be fixed, but must not get worse.

## When you are done with a hop
Write `.upgrade/reports/<hop slug>.json` following `.upgrade/REPORT_SCHEMA.json`.
If you cannot finish, write the report with `"status": "blocked"` and a precise `blocked_reason`
(the failing command and the error), and stop. Do not leave the app half-migrated without saying so.
