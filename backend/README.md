# Thyantra Billing — Backend

API and sync server for the billing website (`../src`) and the Flutter app (`../mobile`).
Each shop is a separate tenant with Owner and Cashier logins. The website works online against
this API. The app keeps working offline and syncs when it can.

**Stack:** NestJS 11 (Fastify) · Prisma 6 · PostgreSQL 17 · Zod 3 (nestjs-zod) · Jest e2e against real Postgres.

## Run locally

```sh
cd backend
cp .env.example .env          # then set JWT_ACCESS_SECRET
npm install
npm run db:up                 # Postgres 17 in Docker on localhost:55432 (dev + test databases)
npm run db:deploy             # apply migrations
npm run start:dev             # http://localhost:3100  ·  API docs: http://localhost:3100/api/docs
npm run test:e2e              # 41 end-to-end tests on the billing_test database
```

Website: from the repo root, `npm run dev` on port 8080. Vite proxies `/api` to port 3100, so the
session cookies are same-origin.
App: points at `http://10.0.2.2:3100/api/v1` (Android emulator). Override it with
`--dart-define=API_BASE_URL=...`.

## Design rules

- **Money**: stored as `Decimal(14,2)`. The API carries **integer minor units** (`priceMinor`,
  `totalMinor`, `pendingMinor`, `amountMinor`), the same as the app. Floats never touch money.
- **Every write** runs in one transaction holding a per-shop advisory lock (`PrismaService.withShopLock`).
  This means:
  - stock can't be oversold;
  - balances can't race;
  - the sync cursor follows commit order.
- **Tenancy**: `shopId` always comes from the session, never from the request. Client ids
  (products, customers, sales) are unique per shop only.
- **Soft delete** for products and customers, so syncing devices learn about deletions.
- **Validation**: Zod schemas in each module's `dto.ts`. They use the same limits as the apps
  (name ≤ 100, stock ≤ 10 lakh, https images, phone 7–15 digits, normalised).

## Auth

| Client | How |
|---|---|
| Web | httpOnly cookies (`tb_access` 15 min, `tb_refresh` 30 days, SameSite=Lax). Writes must send `X-Requested-With`. |
| Mobile | `client: "mobile"` on login, signup and refresh returns `accessToken` and `refreshToken` in the body. Send `Authorization: Bearer`. |

- Refresh tokens rotate on every use. Reusing an old one revokes that whole login.
- Deactivating a user or changing their role takes effect on their next request.
- **Owner-only:** products (write), customer delete, shop settings, staff, backup and restore.
- **Cashiers:** sell, add and edit customers, take payments, and view everything.
- **Password reset by email is not built yet** (no email provider chosen; to confirm). Owners
  reset staff passwords from Staff.

## Endpoints (`/api/v1`)

| Area | Endpoints |
|---|---|
| auth | `POST signup, login, refresh, logout, change-password` · `GET me` |
| shop | `GET /shop` · `PATCH /shop` (owner) |
| staff | `GET, POST /staff` · `PATCH, DELETE /staff/:id` (owner) |
| products | `GET /products?search&inStock&sort=usage` · `GET /products/:id` · `POST` · `PATCH /:id` · `DELETE /:id` |
| customers | `GET /customers?include=transactions` · `GET /:id` (with ledger) · `POST` · `PATCH /:id` · `DELETE /:id` · `POST /:id/payments` |
| sales | `POST /sales` (checkout) · `GET /sales?from&to&limit&cursor` · `GET /sales/:id` |
| reports | `GET /reports/monthly`, `/reports/top-products?year&month`, `/reports/summary` (with `tz`, default `Asia/Kolkata`) |
| backup | `GET /backup` · `POST /backup/restore[?sanitize=true]` (owner) |
| sync | `POST /sync/push` · `GET /sync/pull?cursor&limit` |
| health | `GET /health` |

**Checkout** (`POST /sales`) does everything in one transaction:
1. Checks every line against current stock and price (`expectedUnitPriceMinor`).
2. Creates the credit customer if new.
3. Lowers stock and raises usage counts.
4. Saves the sale and adds the credit to the customer's balance.

If anything changed, it returns **409 `cart_changed`** with a `changes[]` list (the same wording as
the app) and current `products`, and nothing is sold.

Errors always look like `{ statusCode, code, message, ... }`. Clients switch on `code`, for example:
- `cart_changed`
- `phone_taken`
- `pending_balance`
- `payment_exceeds_pending`
- `customer_missing`
- `validation_failed` (comes with `issues[]`)

## Offline sync

**Push.** `POST /sync/push` takes `{ deviceId, ops: [{ opId, type, payload }] }`, applied in order.
- Each op is its own transaction and runs **exactly once**: its result is stored under `opId`, and a
  retry gets back the same result with `replayed: true`.
- A rejected op does not stop the ops after it.

| Op | Rule |
|---|---|
| `sale.create` | **Always accepted** at the price charged. If another device sold the stock first, stock stops at 0, the line records a `shortfall`, and a warning comes back for the owner to recount. |
| `product.upsert` | Sends `baseStock`. The server applies the *difference*, so offline restocking doesn't erase sales made elsewhere. Name and price: last write wins. Rejected if the product was deleted. |
| `customer.create` | If the phone already belongs to a customer, the new id is merged into theirs (`mergedInto`). Later ops using either id reach the same ledger. |
| `payment.create` | Rejected if larger than the balance. This is most likely the same payment recorded on two phones. |
| `customer.delete` | Rejected while a balance is pending. |
| owner-only ops from a cashier | Rejected (`forbidden`). |

**Pull.** `GET /sync/pull?cursor=` returns, oldest first and in pages (`hasMore`):
- products, customers, sales and transactions changed after the cursor, with tombstones (`deleted: true`);
- the shop settings.

No cursor, or a restore since the last pull, gives `reset: true`: the device replaces its data with
the download.

## Production notes

- Set `NODE_ENV=production`, a random `JWT_ACCESS_SECRET` of at least 32 characters (the server
  refuses to start otherwise), `COOKIE_SECURE=true`, and `CORS_ORIGINS` set to the website's origin.
- Run `npm run build && npm run db:deploy && npm start` behind HTTPS.
- Throttling: 600 requests a minute per IP, and 10 a minute on credential endpoints.
- Backups up to 25 MB are accepted.
- Hosting, monitoring and database backups are **to confirm**. `docker-compose.yml` is for local
  use only.
