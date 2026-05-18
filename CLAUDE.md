# All Aboard — Claude Code Guide

## Repo layout
- `AllAboard/` — macOS app (Swift, Xcode project)
- `worker/` — Cloudflare Worker backend (TypeScript, Hono, D1)
- `scripts/` — release and build automation
- `appcast.xml` / `appcast-beta.xml` — Sparkle update feeds (committed, served via GitHub raw)

## Development branch
Work on feature branches, open PRs into `main`. See `AGENTS.md` for full branch strategy.

## Shipping a release
From a clean `main` working tree:
```
./scripts/release.sh 1.5.0
```
Bumps version, builds + notarizes DMG, updates appcast.xml, commits, tags, pushes, creates GitHub release. See `AGENTS.md` for one-time machine setup requirements.

## Deploying the worker
```
cd worker && npm run deploy
```
Secrets are managed via `wrangler secret put <NAME>`. Never committed.

## Stripe setup (important)
This app shares a Stripe account with Yap. The webhook handler (`worker/src/routes/stripe.ts`) filters events by `STRIPE_PRICE_ID` to prevent Yap subscriptions from granting All Aboard access. Any new subscription event handling must preserve this filter. Run `/stripe-webhook-check` in any new project to verify isolation is in place.

## Key environment secrets (worker)
- `SESSION_SECRET` — JWT signing
- `RESEND_API_KEY` — transactional email
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID` — billing
