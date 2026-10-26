# Thyantra Billing — Backend + client wiring

## Context
Both clients store everything on the device: the web app in `localStorage` (`src/context/*Context.tsx`) and the Flutter app in SQLite (`mobile/lib/data/app_database.dart`). There is no server, so shops can't share data across devices or staff, and nothing is kept centrally.

Goal: build a multi-shop SaaS backend, connect the website to it (online), and connect the mobile app with **offline-first sync**. Every existing flow must keep its current rules:
- products CRUD
- cash and credit checkout (no overselling)
- customers with unique phone numbers, delete only at zero balance, payments no larger than the balance
- history and monthly reports
- settings
- backup and restore

**Decisions already taken:**
- NestJS 11 + Prisma 6 + Postgres 17, matching the SmartAgro stack.
- Multi-shop, with Owner and Cashier roles.
- Offline-first mobile with sync, and both clients wired up.
- An offline sale that oversells on sync is **accepted and the shortfall flagged**.
- Mobile sign-in is **optional**. Local-only mode stays.
- Password reset is **deferred**. Owners reset staff passwords; owner self-reset by email comes later and is noted as "to confirm".

## 1. Backend — separate top-level folder `backend/` (new)
The backend is fully self-contained in `backend/`, next to `src/` (website) and `mobile/` (app). It has its own `package.json`, `node_modules`, `tsconfig`, `.env`/`.env.example`, `docker-compose.yml`, `prisma/`, `src/`, `test/` and `README.md`. Nothing backend-related is added at the repo root; the root `.gitignore` only gains `backend/.env`. The first execution step saves this plan as `backend/docs/PLAN.md`.

```
backend/
  docs/PLAN.md          README.md          docker-compose.yml   .env.example
  package.json          tsconfig.json      nest-cli.json        jest-e2e.json
  prisma/schema.prisma  prisma/migrations/
  src/main.ts  src/app.module.ts
  src/common/   (prisma, auth guard, roles, money, shop-lock, errors)
  src/modules/  auth/ shop/ staff/ products/ customers/ sales/ reports/ backup/ sync/ health/
  test/         *.e2e-spec.ts
```

**Stack:**
- `@nestjs/*@^11.2` with the Fastify adapter.
- `prisma`/`@prisma/client@^6.19`, `nestjs-zod@^5` + `zod@^3.25`.
- `@nestjs/swagger@^11`, `@nestjs/jwt@^11`, `@fastify/cookie@^11`, `@fastify/helmet`, `@nestjs/throttler`, `bcryptjs`.
- Jest 29 + ts-jest.
- `docker-compose.yml` runs Postgres 17 (dev database plus a test database).

**Layout:** `src/modules/<module>/{module,controller,service,dto}.ts`, plus `src/common/` (Prisma service, auth guard, role decorator, money helpers, error filter). Controllers stay thin and the business rules live in services.

### Schema (`prisma/schema.prisma`)
- **Shop**: `name`, `currency`, `currencySymbol`, timestamps.
- **User**: `shopId`, `email` (unique), `name`, `passwordHash`, `role` (OWNER/CASHIER), `isActive`.
- **RefreshToken**: hashed token, `family`, `expiresAt`, `revokedAt`. Tokens are rotated; reusing an old token revokes the whole family.
- **Product**: `id` (client-generated UUID allowed), `shopId`, `name`, `price Decimal(14,2)`, `stock Int`, `image`, `usageCount`, `deletedAt` (soft delete, which sync needs as a tombstone), `seq`, `createdById`/`updatedById`, timestamps.
- **Customer**: `name`, `phone` (normalised), `pending Decimal(14,2)`, `deletedAt`, `seq`. Phone is unique per shop among non-deleted customers, via a partial unique index added in raw migration SQL.
- **CustomerAlias** `(aliasId → customerId)`: when two devices create the same phone number offline, the second create is merged into the first. Later operations that use the alias id are resolved to the real customer.
- **Sale**: `date`, `total`, `customerId?`, `isPending`, `source` (web/mobile), `deviceId?`, `createdById`, `seq`.
- **SaleItem**: snapshot of `productId`, `productName`, `unitPrice`, `quantity`, plus `shortfall Int`. The shortfall is set when an offline sale oversold.
- **CustomerTransaction**: `type` CREDIT/PAYMENT, `amount`, `description`, `date`, `saleId?`, `seq`.
- **ProcessedOp** `(shopId, opId)`: stores the result of each sync operation, so a repeated push is safe.
- A `change_seq` Postgres sequence and a trigger `BEFORE INSERT OR UPDATE SET seq = nextval(...)` on every table that syncs.

**Cross-cutting rules:**
- Money is `Decimal` in the DB. The API carries **integer minor units** (`priceMinor`, `totalMinor`, `pendingMinor`, `amountMinor`), the same names as `mobile/lib/models/models.dart`.
- Every write runs in `prisma.$transaction` and first takes `pg_advisory_xact_lock(hashtext(shopId))`. That serialises writes per shop, so stock and credit can't race and `seq` order matches commit order. Without it, the pull cursor could skip rows.
- Every query is scoped by `shopId` taken from the token, never from the request body.

### API (`/api/v1`, Swagger at `/api/docs`)
| Area | Endpoints | Rules (ported from the existing code) |
|---|---|---|
| auth | `POST signup` (creates shop + owner), `login`, `refresh`, `logout`, `GET me`, `POST change-password` | Web gets httpOnly cookies (access 15 min, refresh 30 days, SameSite=Lax) and must send an `X-Requested-With` header on writes. Mobile gets tokens in the response body (`client: 'mobile'`). Login attempts are rate-limited. |
| shop | `GET/PATCH /shop` | Owner only. Setting the currency also sets its symbol, and a blank name is ignored (as in `settings_provider.dart`). |
| staff | `GET/POST/PATCH/DELETE /staff` | Owner only. The owner sets the cashier's password and can reset it. An owner can't deactivate themselves. |
| products | `GET /products?search&inStock&sort=usage&limit`, `POST`, `PATCH /:id`, `DELETE /:id` | Writes are owner only. Name max 100 characters, stock 0–1,000,000, image must be https (from `validation.dart`). |
| customers | `GET`, `GET /:id` (with ledger), `POST`, `PATCH /:id`, `DELETE /:id`, `POST /:id/payments` | Phone is normalised and unique per shop. Delete is refused unless the balance is 0. A payment must be between 1 and the pending amount. |
| sales | `POST /sales` (checkout), `GET /sales?from&to&cursor&limit`, `GET /sales/:id` | Checkout sends `items[{productId, quantity, expectedUnitPriceMinor}]` and an optional `customer {id} \| {name, phone}`. Stock is decremented only if enough is left; otherwise the server returns **409** with a list of changes (same wording as `CartProvider.reconcile`). Usage counts go up, and a credit sale records a credit and creates the customer if new, all in one transaction. |
| reports | `GET /reports/monthly`, `/reports/top-products?year&month`, `/reports/summary` | Same results as `SalesHistoryContext`: grouped by product id, top 10, months 0-based. |
| backup | `GET /backup`, `POST /backup/restore` (owner) | Uses the mobile backup format (`app: thyantra_billing`, `formatVersion 1`). Restore also accepts old major-unit fields such as `price`, and is validated like `BackupService._validate`. |
| sync | `POST /sync/push`, `GET /sync/pull?since=` | See below. |
| health | `GET /health` | |

### Sync protocol
- **Push:** `{deviceId, ops:[{opId, type, payload, at}]}`. Operation types:
  - `product.upsert` / `product.delete`
  - `customer.create` / `customer.update` / `customer.delete`
  - `sale.create`
  - `payment.create`
  - `settings.update`
- Each operation runs in its own transaction and returns `applied`, `duplicate` (already processed), or `rejected{reason}`. A rejection never blocks the rest of the batch.
- **Conflict rules:**
  - `sale.create`: always accepted, at the client's price snapshot. Stock is set to `max(0, stock − qty)` and any shortfall is recorded and returned as a `warnings[]` entry.
  - `product.upsert`: carries `baseStock`. The server applies `stock += (stock − baseStock)`, floored at 0, so an offline stock edit doesn't wipe out sales made elsewhere. Name and price use last write wins.
  - `customer.create` with an existing phone: merged. The response includes `mergedInto`.
  - `payment.create` larger than the balance: rejected (most likely the same payment recorded on two devices).
  - `customer.delete` while a balance is pending: rejected.
  - Owner-only operations from a cashier: rejected.
- **Pull:** returns every product, customer, sale, transaction and the shop settings with `seq > since`, including tombstones, plus a new `cursor`. Results are paged (`hasMore`).

### Tests (`backend/test/*.e2e-spec.ts`, real Postgres from docker-compose)
- Auth: signup, login, refresh rotation, reuse detection.
- Isolation: one shop can't read another shop's data.
- Checkout: cash, credit with an existing customer, credit with a new customer, 409 on stock or price change, and concurrent checkouts that must not oversell.
- Customers and payments: unique phone, delete refused while a balance is pending, overpayment refused.
- Reports.
- Backup round-trip.
- Sync: idempotent replay, shortfall, `baseStock` merge, customer merge, pull cursor order.
- Roles: cashier gets 403 on owner-only actions.

## 2. Website wiring (`src/`)
- `src/lib/api/client.ts`: a typed fetch wrapper (`credentials: 'include'`, `X-Requested-With`, one automatic refresh on 401). It converts minor units to the web's existing major-unit numbers at the boundary, so components stay untouched. The Vite dev proxy forwards `/api` to `localhost:3000`.
- `src/context/AuthContext.tsx` plus new `LoginPage` and `SignupPage`. Routes are guarded. `Header.tsx` gets the user menu and logout, and nav items are hidden by role.
- Each context is rewritten to use **TanStack Query** (already installed) against the API, with the same exported hook names:
  - `ProductContext.completeSale` becomes an async `checkout(items, customer?)` that calls `POST /sales`.
  - `SalesPage.tsx` lines 96–128 collapse into a single call and handle the 409 by refreshing the cart.
  - `SalesHistoryContext` reads its reports from the server.
  - `CustomerContext` uses the server endpoints.
- `SettingsPage.tsx` gains:
  - Staff management (owner only).
  - **"Import data from this browser"**, shown when old `shop_*` localStorage keys exist. It builds a backup JSON and calls `/backup/restore`.

## 3. Mobile wiring (`mobile/lib/`)
**Add dependencies:** `http`, `flutter_secure_storage`.

**Database** (`data/app_database.dart`), schema version 2 with `onUpgrade`:
- New `outbox(op_id, type, payload, created_at)` and `sync_state(key, value)` tables.
- Each write method also inserts its outbox operation in the **same SQLite transaction**, but only while signed in (a flag on `AppDatabase`).
- `applyPull(changes)` runs only when the outbox is empty, as a single transaction of upserts and deletes.

**Services:**
- `services/api_client.dart`: base URL in `app_info.dart`, bearer token, automatic refresh, tokens kept in secure storage.
- `services/sync_service.dart`: push the outbox, apply the per-operation results, then pull, then reload providers through their existing `replaceAll`.
  - Sync runs at startup, two seconds after any write (debounced), every 60 seconds, and from a manual "Sync now".
  - Rejections and shortfall warnings reach the user through the existing `storageIssues` toast channel.
  - A merged customer id is remapped locally.

**UI and providers:**
- `providers/auth_provider.dart` plus the Settings screen get an **Account & sync** section: sign in, create shop, sign out, last synced time, pending count.
- **First sign-in on a device that already has data:**
  - If the server shop is empty, the local data is uploaded through `/backup/restore`.
  - Otherwise the user confirms "Replace this phone's data with the shop's data".
- Owner-only actions are hidden for cashiers: product add/edit/delete, customer delete, settings, restore.
- `SettingsProvider.updateSettings` enqueues `settings.update`. A restore while signed in goes to the server first.

## Verification
1. `cd backend && docker compose up -d && npm i && npx prisma migrate dev && npm run test:e2e`. Every e2e spec must pass, including the concurrency and sync tests.
2. `npm run start:dev`, then click through Swagger at `localhost:3000/api/docs`.
3. Web: `npm run dev` at the repo root, then walk through signup → add product → cash sale → credit sale with a new customer → payment → history charts → staff create → log in as cashier (owner actions hidden or blocked) → import from localStorage. Plus `npm run build` and `npm run lint`.
4. Mobile: **Flutter isn't installed on this machine**, so the mobile code can't be compiled or tested here. You'll need to run `flutter pub get && flutter analyze && flutter test` and a device sync test. Dart unit tests for the outbox and `applyPull` will be added under `mobile/test/` using the existing `sqflite_common_ffi` setup.

## Execution
Build and test the backend first, because it fixes the API contract. Then wire the web (me) and mobile (a forked agent with the same context) in parallel. Commit only when you ask.
