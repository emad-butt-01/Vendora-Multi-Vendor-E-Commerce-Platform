# Vendora

Multi-vendor e-commerce platform — Final Year Project, built production-grade.

Three roles: **Buyer**, **Vendor**, **Admin**. Vendors register with NIC and get admin-approved before opening a shop; buyers browse, cart, checkout via Stripe, review; admins approve vendors and manage the platform. Plus notifications, buyer↔vendor chat, and rule-based recommendations.

## Stack

- **Frontend** — React 18 · Vite · Tailwind CSS · React Router v6 · Axios · TanStack Query · Zustand · Zod
- **Backend** — Node.js · Express (ESM) · MongoDB (Mongoose) · JWT · Multer + Cloudinary · Stripe · Socket.io · Joi
- **Tests** — Vitest (client) · Jest + Supertest (server)

## Repository layout

```
/vendora
  /client    React app (Vite)
  /server    Express API (ESM)
  /shared    Shared types/constants
  package.json
  .gitignore
  .env.example
  README.md
```

## Prerequisites

- Node.js **>= 18.18**
- npm **>= 9** (for workspaces)
- A running MongoDB (local at `mongodb://127.0.0.1:27017` or Atlas URI)

## Setup

```bash
# 1. install all workspace deps from the root
npm install

# 2. configure env
cp .env.example server/.env
cp .env.example client/.env
# then edit each file and keep only the relevant section
```

Server reads from `server/.env`, client reads from `client/.env` (Vite only exposes `VITE_*` vars).

## Run

```bash
# from repo root — runs server (5000) and client (5173) together
npm run dev

# or individually
npm run dev:server
npm run dev:client

# production build of the client
npm run build:client
```

## Seed the admin user

`/register` only accepts `role: 'buyer'` or `'vendor'`. The first admin must be created with the seed script.

```bash
# 1. set ADMIN_EMAIL + ADMIN_PASSWORD in server/.env
# 2. run from repo root
npm run seed:admin
```

The script is idempotent — re-running it with the same email is a no-op. If a non-admin user already owns the email it errors out instead of overwriting.

## End-to-end smoke tests

Standalone scripts walk full server flows against an in-memory MongoDB — useful when you don't have a local Mongo running. Each one exits non-zero on any failure.

```bash
npm run smoke:auth      # register / login / /me / refresh+rotation / reuse / logout / admin-seed
npm run smoke:vendor    # apply (with stubbed uploads) / admin approve / reject+reapply / suspend
npm run smoke:products  # categories CRUD / products CRUD / public catalog filters / stock auto-flips
npm run smoke:storefront # featured / top-rated / featured-categories / vendors list + detail / multi-category filter
npm run smoke:cart      # buyer cart CRUD / wishlist add+move-to-cart / address book + default-handling
npm run smoke:checkout  # multi-vendor order split / Stripe stub / handlePaymentSucceeded idempotency / handlePaymentFailed
npm run smoke:orders    # buyer list/detail/cancel + vendor list/detail/transitions/stats + auth guards
npm run smoke:reviews   # 5★ create / duplicate 409 / 3★ create / PATCH recompute / DELETE recompute / public list + distribution
npm run smoke:admin     # cross-vendor stats + users (suspend/unsuspend + login gate) + orders filters + sales/top-products/top-vendors reports
npm run smoke:cod       # Cash-on-Delivery happy path + paymentStatus collected on delivery + cancel-without-refund + Stripe path untouched
npm run smoke:notifications # buyer + vendor read API: list/unread-count/mark-read/mark-all/delete + cross-user 404 + filter chips
npm run smoke:recommendations # similar score-and-sort + for-you category preferences + cold-start fallback + trending aggregation + auth guards
npm run smoke:chat      # buyer↔vendor conversation start + idempotency + unread counters + seenAt stamps + 401/403/404 guards (HTTP only — Socket.io verified manually)
```

The vendor smoke uses `STORAGE_DRIVER=memory` to skip Cloudinary entirely. The first run of either downloads a portable Mongo binary (~100 MB) into `node_modules/.cache/mongodb-memory-server/`; subsequent runs are quick.

Verify:

- Client → http://localhost:5173
- API health → http://localhost:5000/api/v1/health

## Catalog

### Categories

Two-level hierarchy. Admins create top-level categories and one level of children; further nesting is rejected. Slugs are auto-generated from the name. Soft delete (sets `isActive=false`) — rejected if any active products still reference the category.

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET    | `/api/v1/categories`              | public | tree of top-level + children |
| POST   | `/api/v1/admin/categories`        | admin  | multipart: `name`, `parent?`, `image?` |
| GET    | `/api/v1/admin/categories`        | admin  | tree, optionally `?isActive=true` |
| GET    | `/api/v1/admin/categories/:id`    | admin  | single category |
| PATCH  | `/api/v1/admin/categories/:id`    | admin  | multipart: `name?`, `parent?`, `isActive?`, `image?` |
| DELETE | `/api/v1/admin/categories/:id`    | admin  | soft delete |

### Products

Each product belongs to a vendor and a category, has 1–5 Cloudinary images (subfolder `vendora/products/<id>/`), a status (`active` / `draft` / `out_of_stock`), and ratings aggregates. Stock changes auto-flip the status: dropping to 0 marks it `out_of_stock`, restocking from 0 reverts to `active`. Slug is auto-generated and unique per vendor.

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| POST   | `/api/v1/vendor/products`           | approved vendor | multipart, up to 5 `images` |
| GET    | `/api/v1/vendor/products`           | approved vendor | filters: `q`, `status`, `category`, `sort` |
| GET    | `/api/v1/vendor/products/:id`       | approved vendor | 404 (not 403) when product belongs to a different vendor |
| PATCH  | `/api/v1/vendor/products/:id`       | approved vendor | multipart: any field + `imagesToRemove[]` + new `images` |
| DELETE | `/api/v1/vendor/products/:id`       | approved vendor | also wipes Cloudinary images |
| GET    | `/api/v1/products`                  | public | only `status=active`; filters: `q`, `category` (slug), `vendor` (slug), `minPrice`, `maxPrice`, `minRating`; `sort=newest\|price_asc\|price_desc\|rating\|relevance` |
| GET    | `/api/v1/products/:slug`            | public | 404 if product is not active |
| GET    | `/api/v1/products/vendor/:slug/products` | public | storefront listing for one vendor |
| GET    | `/api/v1/products/featured`         | public | 8 latest active products with images |
| GET    | `/api/v1/products/top-rated`        | public | 8 active products with `ratingsCount >= 1`, sorted by `ratingsAvg` desc |
| GET    | `/api/v1/categories/featured`       | public | top-level categories with `productCount` aggregated across the subtree |
| GET    | `/api/v1/vendors`                   | public | approved vendors; filters: `q`, `category`; sort: `newest\|name\|rating`; paginated |
| GET    | `/api/v1/vendors/:slug`             | public | single approved vendor; 404 otherwise |

## Buyer Storefront

Public, read-only pages — no auth required. All filter / search / sort state lives in the URL via React Router's `useSearchParams`, so links are shareable and the browser back button does the right thing.

| Path | Purpose |
| --- | --- |
| `/` | Home — hero + featured categories, featured products, top rated (only when there are rated products), top vendors |
| `/products` | Browse all — sticky sidebar filters (categories multi-select, price min/max, min rating), debounced search, sort (newest / price / rating / relevance), numbered pagination with ellipsis. Mobile turns the sidebar into a "Filters" drawer. |
| `/products/:slug` | Product detail — image gallery (thumbnails + arrow keys + mobile swipe), price with strikethrough/discount badge, stock + quantity stepper, Add to Cart / Wishlist (toast prompts sign-in for guests until Step 6 wires the cart), tabs (Description / Reviews placeholder / Vendor card), "You may also like" |
| `/shops` | Vendor list — search by shop name, sort by newest / name / rating, paginated |
| `/shops/:slug` | Vendor shop — banner + logo + rating + product count + joined date, tabs (Products / About). Products tab reuses the browse component with vendor pre-selected. |
| `/search?q=...` | Search results — same component as `/products` with the query pre-filled |

Storefront caching uses TanStack Query with the URL params as the `queryKey`. Stale times: featured/categories/top-rated **5 min**, the live `/products` list **30 s** so demo edits show up quickly. Skeleton loaders match the actual layout (no spinners-of-doom).

## Cart & Wishlist

Buyer-only commerce primitives. All endpoints require auth; the cart and wishlist endpoints additionally require `role=buyer` (vendors and admins are blocked at the role gate). Each user has one cart and one wishlist, both created lazily on first interaction.

The cart line stores a `priceSnapshot` taken when the item is added so a vendor's later price change doesn't silently re-price what's already in someone's cart, and `vendorId` is denormalized so the UI can group by vendor without populating each line. When a product is deleted or set inactive, the line is flagged `unavailable: true` instead of being silently removed — the user sees what disappeared and decides.

Address handling is on the User document. Validation enforces `label` 2-30 chars, `line1` 5-200 chars, and required `phone`. The "at most one default" invariant is maintained in the address service via a session-wrapped unset-then-set; deleting the current default auto-promotes the most recently created remaining address.

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET    | `/api/v1/cart`                          | buyer | items populated with product, vendor, current price; `subtotal` excludes unavailable lines |
| POST   | `/api/v1/cart/items`                    | buyer | `{ productId, qty }`; increments if already present, capped at stock and at 99 |
| PATCH  | `/api/v1/cart/items/:productId`         | buyer | `{ qty }`; `qty=0` removes the item |
| DELETE | `/api/v1/cart/items/:productId`         | buyer | remove a single line |
| DELETE | `/api/v1/cart`                          | buyer | clear the cart |
| GET    | `/api/v1/wishlist`                      | buyer | populated wishlist with stock status |
| POST   | `/api/v1/wishlist/:productId`           | buyer | idempotent (re-adding is a no-op, returns 200) — capped at 100 |
| DELETE | `/api/v1/wishlist/:productId`           | buyer | remove |
| POST   | `/api/v1/wishlist/:productId/move-to-cart` | buyer | atomic move; rejects with 400 if out of stock |
| GET    | `/api/v1/users/me/addresses`            | any auth | list current user's addresses |
| POST   | `/api/v1/users/me/addresses`            | any auth | first address auto-default; `isDefault: true` unsets others |
| PATCH  | `/api/v1/users/me/addresses/:id`        | any auth | partial update; `isDefault: true` reassigns the default |
| DELETE | `/api/v1/users/me/addresses/:id`        | any auth | deleting the default auto-promotes the most recent remaining address |
| PATCH  | `/api/v1/users/me/addresses/:id/set-default` | any auth | convenience for the same default-handling logic |

Frontend pages: `/cart` (full vendor-grouped page with sticky order summary), `/wishlist` (grid with "move all available", per-card move-to-cart and remove), `/account/addresses` (list + add/edit modal + default handling). The header gains a cart drawer (slide-in from right, also reachable from the cart icon in the header), a heart icon for the wishlist (links to `/wishlist`), and a buyer dropdown with Addresses / Wishlist / Cart links. Both icons are hidden for vendors and admins.

A guest cart lives in `sessionStorage` so logged-out users can still add items to cart from product cards. On successful login or registration the guest items are POSTed to `/cart/items` in sequence (best-effort — items that fail a stock check are skipped) and `sessionStorage` is cleared. A "Cart synced" toast confirms the merge.

## Checkout & Payment

Multi-vendor checkout with Stripe. **The marketplace pattern matters here**: if a buyer's cart contains items from N vendors, checkout produces N `Order` documents — one per vendor — all linked to a single `PaymentIntent`. Each vendor gets a flat 200 PKR shipping fee added to their subtotal; the grand total across all vendors is what Stripe charges.

Order numbers are generated atomically from a Mongoose `Counter` doc (`{ _id: 'order', seq }`) via `findOneAndUpdate({$inc})` — formatted as `VND-<year>-<6-digit-zero-padded>`.

The shipping address on the order is a **snapshot** copied off the user's saved address. We never store an ObjectId ref — addresses get edited, deleted, or re-labelled, and the shipping label needs to keep saying what it said when the buyer ordered.

### Currency

PKR is a **2-decimal currency** in Stripe's API (Stripe's zero-decimal list — JPY, KRW, VND, BIF, CLP, … — does not include PKR). Convention inside `server/src/services/payment.service.js`: callers pass an integer **rupee** amount and the service multiplies by 100 (paisa) at the Stripe boundary only. Order docs and API responses stay in rupees. The doc comment at the top of that file is the load-bearing place to read before adding a new currency — an off-by-100 here is the most expensive bug in this repo.

### Endpoints

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| POST   | `/api/v1/checkout/create-payment-intent` | buyer | Stripe path. `{ addressId }` → `{ clientSecret, paymentIntentId, orderIds, total }`. Rate-limited to 10/min/buyer. Validates cart server-side; rejects with 400 + per-item details on stock/availability issues. |
| POST   | `/api/v1/checkout/place-cod`             | buyer | Cash-on-Delivery path. `{ addressId }` → `{ orderIds, total, paymentMethod: 'cod' }`. Skips Stripe entirely: orders are born `confirmed` (the COD twin of `paid`), stock is decremented inline, the cart is cleared, and each vendor gets a `new_order_cod` notification. Same rate limit as the Stripe path. |
| POST   | `/api/v1/checkout/webhook`               | Stripe (signature) | Mounted on `app` BEFORE `express.json()` with `express.raw()` because Stripe signature verification needs the raw body. Handles `payment_intent.succeeded` and `payment_intent.payment_failed`. Always returns 200; logs and swallows handler errors so Stripe stops retrying. |
| GET    | `/api/v1/orders`                         | buyer | paginated buyer's orders, vendor populated; filter `?status=paid&status=shipped` (multi) |
| GET    | `/api/v1/orders/:id`                     | buyer | single order — 404 if it doesn't belong to them |
| POST   | `/api/v1/orders/:id/cancel`              | buyer | `{ reason }` (5-300 chars). Allowed only when status ∈ `{paid, processing}`. Atomic: status flip + stock restore + history (in a Mongo txn), then Stripe refund + `refundId` write + `paymentStatus='refunded'` |
| GET    | `/api/v1/orders/by-payment-intent/:id`   | buyer | used by `/orders/success` to poll for the orders behind a PaymentIntent the buyer just confirmed |

### Vendor order endpoints

Approved-vendor only — the `requireApprovedVendor` gate loads the Vendor doc onto `req.vendor` so every query scopes to the caller's vendor id.

| Method | Path | Notes |
| --- | --- | --- |
| GET   | `/api/v1/vendor/orders`            | filters: `?status=…` (multi), `?search=…` (orderNumber or buyer name), `?sort=newest\|oldest_pending`, paginated |
| GET   | `/api/v1/vendor/orders/stats`      | `{ ordersTotal, ordersPending, revenueAll, revenue30d, productsTotal, productsActive }` — drives the dashboard cards |
| GET   | `/api/v1/vendor/orders/:id`        | 404 (not 403) when the order belongs to another vendor; populates buyer name + email |
| PATCH | `/api/v1/vendor/orders/:id/status` | `{ status, note?, trackingNumber? }`. Strict transition table: `paid → processing → shipped → delivered`. `trackingNumber` required when transitioning to `shipped`. Anything else returns 400 with a "Cannot transition from X to Y" message |

### Payment methods (Stripe + Cash on Delivery)

The `Order.paymentMethod` field (`'stripe' | 'cod'`) splits the lifecycle at the entry point. From `processing` onward both methods share the exact same fulfillment pipeline — only the entry-point status and the closing `paymentStatus` differ.

| | **Stripe** | **Cash on Delivery** |
| --- | --- | --- |
| Entry point | `pending_payment` → `paid` (after `payment_intent.succeeded` webhook) | `confirmed` (immediately on POST /place-cod; no PI, no webhook) |
| `paymentStatus` lifecycle | `pending` → `succeeded` → `refunded` (on cancel) | `unpaid` → `collected` (on delivered) → stays `unpaid` if cancelled |
| Stock decrement | On `payment_intent.succeeded` | Inline at order create (the order is committed) |
| Cancel (`paid|confirmed|processing`) | Stripe refund called, `refundId` stored, `paymentStatus='refunded'` | No Stripe call. `paymentStatus` stays `unpaid`, `refundId` null. History note marks "(COD — no refund needed)". |
| Vendor notification on create | `new_order` (from webhook) | `new_order_cod` (inline) |

The vendor transition table accepts **both** `paid → processing` and `confirmed → processing` so the same Mark-as-Processing button works for either method. When transitioning `shipped → delivered` for a COD order the service flips `paymentStatus` from `unpaid` to `collected` in the same write — that's where the cash is recorded as in-hand.

### Status state machine

```
                                             ┌── Stripe ───────────────────────────────┐
pending_payment ──webhook payment_intent.succeeded──▶ paid
       │                                                    │
       └─webhook payment_intent.payment_failed──▶ paymentStatus=failed (status stays pending_payment, buyer can retry)
                                                            │
                       ┌── COD ───────────────────────────┐ │
   POST /checkout/place-cod ──────────────▶ confirmed     │ │
                                                  │       │ │
                                                  └───────┼─┴───┐
                                                          │     ▼
                                                  vendor PATCH /processing
                                                          │
                                                  vendor PATCH + tracking /shipped
                                                          │
                                                  vendor PATCH /delivered
                                                  (COD: paymentStatus → collected)

paid | confirmed | processing ──buyer POST /:id/cancel──▶ cancelled
   Stripe: paymentStatus='refunded' + Stripe refund. COD: paymentStatus='unpaid' (no charge ever happened).
```

`statusHistory` accumulates every transition with `{ status, at, note, byUserId }` so the buyer's order detail timeline can render the full audit trail. Cancellation is a separate red card alongside the linear stepper rather than an extra step.

Notifications fired alongside transitions: `order_status_changed` (vendor → buyer on PATCH), `order_cancelled_by_buyer` (buyer → vendor on cancel), `refund_issued` (system → buyer on cancel). They go through `notification.service.notifyMany` with the meta linking back to the order.

### Reviews & ratings

Buyers leave a rating + title + comment on a product they ordered, but only after the order is `delivered`. One review per `(productId, buyerId, orderId)` triple — re-buying the product creates eligibility for a fresh review. Every create/update/delete recomputes the parent `Product`'s `ratingsAvg` (1-decimal) and `ratingsCount` from a `Review.aggregate`, which is the safe choice over incremental math (edits and deletes go wrong at the edges).

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET    | `/api/v1/reviews/product/:productId` | public | paginated; `?sort=newest\|highest\|lowest`; response includes `ratingsAvg`, `ratingsCount`, and a `{ 1..5: count }` distribution for the summary card |
| GET    | `/api/v1/reviews/mine?orderId=…`     | buyer  | the caller's own reviews, optionally scoped to an order — drives the "Write a review" / "Edit review" toggle on the order detail page |
| POST   | `/api/v1/reviews`                    | buyer  | `{ productId, orderId, rating(1-5), title(3-100), comment(10-1000) }`. Validates: order belongs to caller, status=`delivered`, product is in `order.items`. 409 if already reviewed. |
| PATCH  | `/api/v1/reviews/:id`                | author only | partial update of `rating`/`title`/`comment`. 403 for non-authors. |
| DELETE | `/api/v1/reviews/:id`                | author only | 403 for non-authors. Recomputes product ratings on success. |

Image upload (`images: [{url, publicId}]`) is on the model with a default of `[]` but isn't surfaced in the Step 9 UI — adding it later is a UI-only change, no migration.

### Admin endpoints

Admin-only — every endpoint sits behind `requireAuth + requireRole('admin')`. Mounted at `/api/v1/admin` alongside the existing vendor-approvals and categories routes.

| Method | Path | Notes |
| --- | --- | --- |
| GET   | `/api/v1/admin/stats` | One round-trip via `$facet`: user/vendor/product/order counts, all-time and 30-day revenue, and a 30-day `revenueByDay` array zero-filled for missing days so charts don't gap. |
| GET   | `/api/v1/admin/users` | filters: `?role=`, `?status=`, `?q=` (name or email, case-insensitive); sort `newest\|name`; paginated |
| GET   | `/api/v1/admin/users/:id` | full user record (passwordHash never serialized) |
| PATCH | `/api/v1/admin/users/:id/suspend` | sets `status='suspended'`. Self-suspend → 403; admin→admin → 403. The auth service already blocks suspended logins (and refresh-token rotation revokes their refresh chain). |
| PATCH | `/api/v1/admin/users/:id/unsuspend` | sets `status='active'` |
| GET   | `/api/v1/admin/orders` | cross-vendor list with filters `?status` (multi), `?vendor=<slug>`, `?buyer=<name-or-email>`, `?startDate`, `?endDate`; populates buyer + vendor |
| GET   | `/api/v1/admin/orders/:id` | populated order detail |
| GET   | `/api/v1/admin/reports/sales` | `?startDate&endDate&groupBy=day\|week\|month` (default last 30 days, day). Aggregated revenue + orderCount + avgOrderValue per period, **zero-filled for missing periods** |
| GET   | `/api/v1/admin/reports/top-products` | `?metric=revenue\|units&limit=10`. Aggregates from `Order.items`, joins back to `Product` + `Vendor` for display fields |
| GET   | `/api/v1/admin/reports/top-vendors` | `?metric=revenue\|orders&limit=10`. Includes `productsCount` per vendor via a `$lookup` sub-pipeline |

Revenue across all of these is the sum of `total` for orders in `{paid, processing, shipped, delivered}` — `cancelled` and `refunded` are excluded so refunds don't inflate GMV.

### Notifications (read API)

Notification rows are written by the existing checkout/order/review/COD flows (`order_paid`, `new_order`, `new_order_cod`, `payment_failed`, `order_status_changed`, `order_cancelled_by_buyer`, `refund_issued`). Step 10 adds the read API on top so the bell in the header has something to show.

| Method | Path | Notes |
| --- | --- | --- |
| GET    | `/api/v1/notifications`              | Caller's notifications, paginated. `?filter=all\|unread\|read` (default `all`); response also returns `unreadCount` so the bell + page can share one round-trip. |
| GET    | `/api/v1/notifications/unread-count` | `{ count }` — polled by the header bell every 30 s. |
| PATCH  | `/api/v1/notifications/:id/read`     | Marks one as read. Scoped to the caller via `findOneAndUpdate({ _id, userId })`, so a stranger gets 404 (not 403). |
| PATCH  | `/api/v1/notifications/read-all`     | Bulk mark-read of every unread row for the caller. Returns `{ matched, modified }`. |
| DELETE | `/api/v1/notifications/:id`          | Hard delete (no soft-delete column). 404 if it doesn't belong to the caller. |

The DB column is `read: Boolean` (already in the model from Step 7 writes); the API serializes it as `isRead` so the client doesn't have to remember which name is which. No model migration was needed.

The bell + dropdown live in `client/src/components/notifications/NotificationBell.jsx` and use TanStack Query with `refetchInterval: 30_000` on the unread-count query — cheap, simple, no Socket.io. Clicking a notification marks it read and navigates to its `link`. The full `/notifications` page reuses the same row component with All/Unread/Read chips and pagination.

### Recommendations

Pure-aggregation rule-based recommendations — no ML, no embeddings, no co-occurrence matrix maintenance. Three endpoints under `/api/v1/recommendations`:

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET | `/api/v1/recommendations/similar/:productId` | public | Up to 8 same-category active products. Score = +1 base for same category, +2 if same vendor, +3 if shares a tag (the tag bonus is reserved for when `Product.tags` lands — currently a no-op since the field doesn't exist yet). Tiebreakers: `ratingsAvg` desc, then `createdAt` desc (stand-in for the unbuilt `salesCount`). |
| GET | `/api/v1/recommendations/for-you` | buyer | Up to 12 personalised picks. Collects categories from the buyer's last-90-days committed orders + current wishlist, surfaces top-rated active products in those categories, excludes anything already ordered. Cold-start (no orders, no wishlist) falls back to platform-wide top-rated. |
| GET | `/api/v1/recommendations/trending` | public | Up to 12 most-ordered products in the last 30 days. `Order.aggregate` over `items` summing `qty` so a single order with `qty=5` counts as 5. |

Frontend touches: product detail's "You may also like" now calls `/similar/:id` (hidden when empty); the home page renders "Recommended for you, {firstName}" + "Trending now" rails for logged-in buyers, between the categories grid and Featured Products. Vendors and admins skip both rails since the personalised endpoint is buyer-only.

### Buyer ↔ Vendor chat

One-to-one threads tied to (buyerId, vendorId) — re-ordering from the same vendor reuses the same conversation. The `Conversation` row carries `lastMessageAt`, `lastMessagePreview`, and per-party unread counters (`unreadByBuyer`, `unreadByVendor`); `Message` rows store the body and a `seenAt` stamp set when the *other* party opens the thread.

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| GET   | `/api/v1/chat/conversations`           | buyer or vendor | Caller's threads, sorted by `lastMessageAt` desc, with unread count + `otherParty` (vendor `shopName/slug/logo` for buyers; buyer `name/email` for vendors) per row. |
| POST  | `/api/v1/chat/conversations`           | buyer | `{ vendorId, orderId? }` — get-or-create. Vendor-initiated conversations aren't supported; the vendor's "Message buyer" button on `/vendor/orders/:id` instead navigates to an existing thread or surfaces a "buyer must start the conversation first" hint when none exists. |
| GET   | `/api/v1/chat/conversations/:id`       | participant | Loads conversation + last 50 messages oldest-first. Side-effect: zeroes the caller's unread counter and stamps `seenAt = now` on every message they didn't send (powers the "Seen" tick on the sender's bubble). 404s for non-participants. |
| POST  | `/api/v1/chat/conversations/:id/messages` | participant | `{ body }` (1-2000 chars). Updates `lastMessageAt` + preview, increments the *other* party's unread counter, emits the new message to that user's socket room (best-effort; HTTP write succeeds regardless). |

### Realtime layer (Socket.io)

`socket.io` mounts on the same HTTP server alongside Express. The frontend connects to the **`/chat` namespace** at the Socket.io default path. JWT goes in the handshake auth (`socket.handshake.auth.token`) and is verified with the same `verifyAccessToken` used by the HTTP middleware — socket sessions live and die with the access token.

On connection each socket joins a per-user room `user:${userId}`. New-message HTTP writes call `setChatEmitter` registered at server boot; the chat service emits `message:new` with `{ conversationId, message }` to the recipient's room only. The client invalidates the relevant React Query keys on receipt — that's it, no manual cache splicing.

If Socket.io fails to initialize (port conflict, OOM, version skew) the API keeps running and the client falls back to polling: `/messages` re-fetches conversations every 15 s and the active conversation every 5 s. Either path is correct on its own; the realtime layer is a tightening, not a load-bearing dependency.

### Webhook handlers

- `payment_intent.succeeded` → flips every order with that PI id to `status='paid'` + `paymentStatus='succeeded'`, decrements stock per line item (which auto-flips products to `out_of_stock` when stock hits 0), clears the buyer's cart, fans out one `order_paid` notification to the buyer + one `new_order` per vendor. **Idempotent** — a replay finds nothing in `paymentStatus != 'succeeded'` and returns early without re-decrementing stock or re-notifying.
- `payment_intent.payment_failed` → marks `paymentStatus='failed'` and notifies the buyer. Status stays `pending_payment` so the user can retry from `/cart`.

### Local dev — Stripe CLI

The webhook needs to reach your dev server, but Stripe can't see `localhost` directly. The Stripe CLI proxies events for you and prints a temporary `whsec_…` to drop into env.

```bash
# 1. install once (https://stripe.com/docs/stripe-cli)
# 2. authenticate
stripe login

# 3. start the forwarder (separate terminal, kept running while you test)
npm run stripe:listen

# CLI prints something like:
#   Ready! Your webhook signing secret is whsec_xxxxxxxxxx (^C to quit)

# 4. paste that into server/.env as STRIPE_WEBHOOK_SECRET, then restart `npm run dev:server`
```

Set `STRIPE_SECRET_KEY` (server) and `VITE_STRIPE_PUBLISHABLE_KEY` (client) to your test-mode keys from the Stripe Dashboard. **Use `STRIPE_STUB=1`** to bypass Stripe entirely for offline dev or smoke tests — the payment service returns synthetic ids and the webhook signature verifier just `JSON.parse`s the body.

> **Test card** — `4242 4242 4242 4242`, any future expiry, any 3-digit CVC, any postal code. Stripe is in test mode; no real money moves. The Stripe Dashboard's *Payments* tab will show every PaymentIntent you create.

## Screenshots

> _placeholders — capture once UI is live_

- `docs/screenshots/admin-categories.png` — admin Categories tree with edit modal
- `docs/screenshots/vendor-products-list.png` — vendor Products list with filters
- `docs/screenshots/vendor-product-form.png` — vendor product editor with image dropzone
- `docs/screenshots/public-catalog.png` — public catalog with category + price filters

## Architecture

```
                          ┌──────────────────────┐
                          │    Browser (React)   │
                          │  Vite dev :5173      │
                          │  or built SPA :5000  │
                          └──────────┬───────────┘
                                     │ HTTPS
                                     ▼
   ┌──────────────────────────────────────────────────────────┐
   │                  Express API  (:5000)                    │
   │  /api/v1  ── auth · catalog · cart · checkout · orders   │
   │           ── reviews · notifications · admin · recos     │
   └──┬─────────────┬───────────────────────────┬─────────────┘
      │             │                           │
      ▼             ▼                           ▼
 ┌────────┐   ┌───────────┐                ┌─────────────┐
 │ Mongo  │   │  Stripe   │                │ Cloudinary  │
 │ orders │   │  PI + RB  │                │ vendor logos│
 │ users  │   │ webhooks  │                │ + product   │
 │ catalog│   │  (HMAC)   │                │ images      │
 └────────┘   └───────────┘                └─────────────┘
```

Single Express process serves both the API and (in production) the built React SPA from `client/dist` on port 5000. State is fully on Mongo via Mongoose; Stripe is stateful only on its side and reaches us via the signed `/api/v1/checkout/webhook` route mounted with `express.raw()` before the JSON parser. Cloudinary is the only other outbound integration — vendor logo + NIC + product images upload directly through `multer-storage-cloudinary`. There's no separate worker process or message queue: every checkout side-effect (stock decrement, cart clear, notifications) runs inside the webhook handler under one Mongo transaction (with a standalone fallback for `mongodb-memory-server`).

## Project structure

```
vendora/
├─ client/                 # React + Vite SPA
│  ├─ src/
│  │  ├─ components/       # ui/, storefront/, account/, admin/, orders/, …
│  │  ├─ hooks/            # useCart, useWishlist, useAuthBootstrap
│  │  ├─ layouts/          # AppLayout, AccountLayout, VendorLayout, AdminLayout
│  │  ├─ pages/            # Home, Products, Cart, Checkout, orders/, vendor/, admin/
│  │  ├─ services/         # axios wrappers per backend area
│  │  ├─ stores/           # Zustand (auth, cart)
│  │  └─ utils/, lib/      # shared helpers (formatPrice, axios instance)
│  └─ vite.config.js
├─ server/                 # Express API (ESM, no transpile)
│  ├─ src/
│  │  ├─ config/           # env.js, db.js, stripe.js
│  │  ├─ middleware/       # auth, validate, errorHandler, rateLimit, upload, vendor
│  │  ├─ models/           # Mongoose schemas (User, Vendor, Product, Cart, Order, …)
│  │  ├─ services/         # business logic — checkout, order, review, recos, admin/*
│  │  ├─ controllers/      # thin Express handlers
│  │  ├─ routes/           # router-per-area, mounted in routes/index.js
│  │  ├─ validators/       # Joi schemas
│  │  └─ utils/            # ApiError, asyncHandler, hash, slug
│  └─ scripts/             # seed-admin + smoke-*.js end-to-end pipelines
├─ shared/                 # constants/types reachable from both sides
├─ Dockerfile              # multi-stage: build client → run server + dist
├─ docker-compose.yml      # mongo + app, one-command demo
└─ README.md
```

## Deployment

The repo ships a multi-stage `Dockerfile` and `docker-compose.yml` that boot the entire stack with one command. The compose file pulls secrets from `server/.env` (which is gitignored), starts a `mongo:6` container with a persistent named volume, and a single `app` container built from the `Dockerfile`.

```bash
# 1. populate server/.env from .env.example (Stripe + Cloudinary keys at minimum)
cp .env.example server/.env
# 2. boot
docker-compose up --build
# 3. open
#    http://localhost:5000   ← SPA + API (the same container serves both)
```

The Dockerfile builds in two stages:

1. **build** — `node:18-alpine`, full workspace install, `npm run build:client` produces `client/dist`.
2. **runtime** — fresh `node:18-alpine`, runs as the unprivileged `node` user, reinstalls server-only deps with `--omit=dev`, copies `server/` source and the built `client/dist`. Server is started directly from source via Node's native ESM (no transpile). The runtime container sets `SERVE_CLIENT=1` which flips on the static-mount + SPA fallback in `server/src/app.js`, so the same Express process serves the React app on `/` and the API on `/api/v1/*`.

`MONGODB_URI` is overridden at the compose layer to point at the `mongo` service hostname (`mongodb://mongo:27017/vendora`); everything else flows through `env_file: ./server/.env`. The Stripe webhook URL for a real test loop is still `localhost:5000/api/v1/checkout/webhook`, reachable via `npm run stripe:listen` from the host.

For local development **don't** use Docker — run `npm run dev` from the repo root. Vite (5173) + Express (5000) with hot reload is much faster to iterate against, and Cloudinary uploads work the same way.

## Trade-offs and decisions

A few load-bearing calls and the reasoning behind each:

- **PKR is a 2-decimal currency in Stripe.** This is the most expensive lesson of the project — Stripe's zero-decimal list (JPY, KRW, VND, …) does *not* include PKR, so amounts must be multiplied by 100 before hitting the API. The conversion lives at exactly one boundary (`server/src/services/payment.service.js`); orders + the rest of the codebase keep money in rupees. The doc-block at the top of that file is the load-bearing place to read before adding a new currency.
- **Refresh-token rotation with reuse detection > long-lived sessions.** Access tokens are 15 min, refresh tokens are 7 days and stored as SHA-256 hashes in `RefreshToken`. Every refresh deletes the old row and issues a new pair; presenting an already-rotated token nukes the user's entire refresh chain. This catches replayed/stolen tokens at the cost of one extra round-trip every 15 minutes — worth it.
- **Mongo transactions for cancellation; Stripe refund outside the txn.** Stripe refunds aren't rollback-able. Cancellation does the DB work first (status flip + stock restore + history) inside `withTxn`, *then* calls Stripe — so a refund failure leaves the order cancelled but flagged for retry rather than making the DB and Stripe drift in opposite directions. There's a graceful fallback to non-transactional execution on standalone Mongo (which `mongodb-memory-server` defaults to) so smokes hit the same code path.
- **Cloudinary URLs over base64 / DB-stored bytes.** Vendor logos, NIC scans, and product images go straight to Cloudinary via `multer-storage-cloudinary`; we store only the URL + publicId. Image deletion on product delete cleans Cloudinary too. Base64-in-MongoDB would have been simpler at first but unworkable for a 5-image-per-product gallery.
- **Stripe + COD share the fulfillment pipeline; only the entry point differs.** `Order.paymentMethod` (`stripe` | `cod`) splits at the entry: Stripe orders enter at `paid` via webhook, COD orders enter at `confirmed` immediately. From `processing` onward both methods share the identical state machine. The vendor's "Mark as Processing" button works for either — one transition table covers both.
- **Deferred for time, not deprioritized for value.** Realtime websocket fan-out (Step 11 chat + push notifications) is the obvious post-FYP follow-on. The notification *write* paths and the read API are both shipped — only the streaming layer is missing, and adding Socket.io would mostly be glue between `notify()` and a per-user channel.

## Environment variables

See `.env.example` for the full list. Server-side only unless prefixed with `VITE_`.

| Var | Where | Purpose |
| --- | --- | --- |
| `NODE_ENV` | server | `development` / `production` |
| `PORT` | server | API port (default 5000) |
| `CLIENT_ORIGIN` | server | CORS allow-origin |
| `MONGODB_URI` | server | Mongo connection string |
| `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` | server | JWT signing secrets |
| `JWT_ACCESS_EXPIRES_IN` / `JWT_REFRESH_EXPIRES_IN` | server | Token lifetimes (default `15m` / `7d`) |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | server | Consumed by `npm run seed:admin` |
| `CLOUDINARY_CLOUD_NAME` / `CLOUDINARY_API_KEY` / `CLOUDINARY_API_SECRET` | server | Vendor logo + NIC uploads |
| `CLOUDINARY_FOLDER` | server | Optional, defaults to `vendora` |
| `STORAGE_DRIVER` | server | `cloudinary` (default) or `memory` for tests/offline |
| `STRIPE_SECRET_KEY` | server | Stripe test-mode secret (`sk_test_…`) |
| `STRIPE_WEBHOOK_SECRET` | server | `whsec_…` printed by `stripe listen` (or copied from the Dashboard for production) |
| `STRIPE_CURRENCY` | server | Default `pkr` — see "Currency" note in *Checkout & Payment* before changing |
| `STRIPE_STUB` | server | `1` to bypass Stripe entirely (smoke tests, offline dev) |
| `VITE_STRIPE_PUBLISHABLE_KEY` | client | Stripe test-mode publishable key (`pk_test_…`) |
| `VITE_API_BASE_URL` | client | Base URL for the Axios instance |

## Project status

- [x] **Step 1** — Monorepo scaffold: client + server + shared, health endpoint, AppLayout, env wiring
- [x] **Step 2** — Auth: register/login/refresh/logout/me, JWT 15m + 7d httpOnly cookie with rotation + reuse detection, role-aware route guards, admin seeder
- [x] **Step 3** — Vendor onboarding: Vendor model + state machine (pending/approved/rejected/suspended), Cloudinary uploads (multer-storage-cloudinary, memory driver for tests), `/vendor/apply` + `/vendor/me`, admin approval endpoints, vendor dashboard with re-apply, admin sidebar with Vendor Approvals + reusable Modal
- [x] **Step 4** — Catalog: Category model (2-level tree, slug auto-gen) with admin CRUD + public listing; Product model (vendor-scoped, 1-5 images, stock-driven status auto-flips, text+price filters); vendor product CRUD with image dropzone (drag-reorder, max 5); public read APIs at `/api/v1/products` (search, category/vendor/price/rating filters, sort by newest/price/rating/relevance); admin Categories page + vendor Products list/form
- [x] **Step 5** — Buyer storefront: Home (hero + featured categories/products/top-rated/top-vendors), `/products` browse (URL-driven filters, debounced search, sort, pagination, mobile drawer), `/products/:slug` detail (gallery + tabs + "you may also like"), `/shops` + `/shops/:slug` vendor pages, `/search` results, header search bar; new public endpoints `/products/featured`, `/products/top-rated`, `/categories/featured`, `/vendors`, `/vendors/:slug`
- [x] **Step 6** — Cart & Wishlist: per-user Cart and Wishlist models with role-gated endpoints; cart lines capture `priceSnapshot` + denormalized `vendorId` and flag missing/inactive products as `unavailable` rather than silently removing them; wishlist add is idempotent with a 100-item cap; address book on User with single-default invariant + auto-promotion on default-delete; reusable Drawer with focus trap; CartDrawer + `/cart` page with vendor grouping; `/wishlist` with move-to-cart; `/account/addresses` with modal form; guest cart in `sessionStorage` that merges into the server cart on login/register; ProductCard and product-detail Add-to-Cart / wishlist toggle wired through React Query with optimistic updates
- [x] **Step 7** — Checkout + Stripe integration + Orders: `Order` and `Counter` models with atomic `VND-YYYY-000001` numbering; `Notification` model (writes only — reads/streaming land in Step 10); `checkout.service` orchestrates a multi-vendor split — one Stripe PaymentIntent over the grand total, one `Order` per vendor with snapshotted line items + shipping address; `handlePaymentSucceeded` is idempotent (txn-wrapped flip-orders / decrement-stock / clear-cart / notify, with standalone-Mongo fallback); `payment.service` abstracts Stripe with a `STRIPE_STUB=1` bypass for tests; webhook mounted on `app` with `express.raw()` BEFORE `express.json()`; rate-limited `/checkout/create-payment-intent` (10/min/buyer); `/checkout` page (3 vertical sections + sticky right-side summary) wires Stripe Elements deferred PaymentIntent flow; `/orders/success` polls `/orders/by-payment-intent/:id` for up to 10s while the webhook lands; `/orders/failed` retry shell; `npm run stripe:listen` forwards Stripe events to the local server
- [x] **Step 8** — Order management: buyer list/detail/cancel + vendor list/detail/status-transitions + dashboard stats. `Order.refundId` added; `Notification` enum extended with `order_status_changed`, `order_cancelled_by_buyer`, `refund_issued`. `payment.service.createRefund` rolls in the rupees→paisa fix at the Stripe boundary so partial refunds match the PaymentIntent semantics. Cancel is two-phase to avoid Stripe/DB drift: DB txn first (status + stock + history), then Stripe refund, then `refundId` write — refund failures throw 500 but the cancel is already recorded for ops to retry. Vendor order routes mounted under `/vendor/orders` with `requireApprovedVendor`. Strict transition table enforced server-side and surfaced through the right-rail action panel on the vendor detail page. New shared components: `StatusBadge`, `StatusTimeline`, `OrderCard`. Sidebar links unhidden on both `AccountLayout` and `VendorLayout`. Vendor dashboard now renders live stat cards (Total Orders, Pending Fulfillment, Revenue 30d, Active Products) + a Recent Orders panel.
- [x] **Step 9** — Reviews & ratings: `Review` model with proof-of-purchase enforcement (must reference a delivered order whose items include the product) and a compound unique on `(productId, buyerId, orderId)` so a buyer can only review the same product again if they reorder + receive again. Public read at `/api/v1/reviews/product/:id` returns the page of reviews plus the live `ratingsAvg`, `ratingsCount`, and 1-5 distribution histogram for the summary card. Buyer-only writes (POST/PATCH/DELETE) — PATCH/DELETE additionally check `review.buyerId === req.user.id` and 403 otherwise. Every mutation calls `recomputeProductRatings(productId)` which re-aggregates over `Review` and writes `Product.ratingsAvg` (rounded to 1 decimal) + `ratingsCount` so we never drift on edits or deletes. Image upload field is on the model with default `[]` but deliberately not surfaced in the UI for this scoped pass. New shared components: `ProductReviews` (summary card + sort + pagination + list) and `ReviewModal` (interactive star selector + title + comment, switches between create/edit by props). Buyer order detail shows "Write a review" / "Edit review" per line item only when `status='delivered'`. Product card now hides the star block on unreviewed products and shows "No reviews yet" instead of `(0)` gray stars.
- [x] **Step 10** — Notifications: in-app read API on top of the existing write paths. `Notification` model unchanged (still `read: Boolean`; the API serializes it as `isRead` for client clarity). Endpoints under `/api/v1/notifications`: list with `all|unread|read` filter + `unreadCount` co-returned, `unread-count`, `:id/read`, `read-all`, `:id` (hard delete — no soft-delete column needed). Cross-user access 404s (not 403) via `findOneAndUpdate({ _id, userId })`. Header bell with red unread badge polls `/unread-count` every 30 s via TanStack Query — no Socket.io. Click-through marks-read + navigates. Full `/notifications` page shares the row component with All/Unread/Read filter chips, pagination, and per-row delete. Realtime delivery (websocket fan-out) deferred to a post-FYP iteration.
- [x] **Step 11** — Buyer ↔ Vendor chat: 1:1 conversation threads keyed on `(buyerId, vendorId)` (compound unique — re-ordering reuses the same thread), `Message` rows with body + `seenAt` stamp, per-party unread counters on the conversation. Endpoints under `/api/v1/chat`: list with `unreadTotal` co-returned, get-or-create (buyer-only `POST` per literal spec; the vendor's "Message buyer" button instead navigates to an existing thread), single-conversation read that zeroes the caller's unread + stamps `seenAt` on the other side's messages in one save, send-message that bumps `lastMessageAt` + preview + the *other* party's unread counter and emits `message:new` to the recipient's socket room. Realtime layer is `socket.io` on the existing HTTP server with a `/chat` namespace and JWT-handshake auth — emit is best-effort, HTTP polling (5 s on active conversation, 15 s on the list) is the always-on fallback. Frontend: `/messages` two-pane page, header speech-bubble icon with unread badge polling at 30 s, "Contact seller" on buyer order detail, "Message buyer" on vendor order detail.
- [x] **Step 12** — Admin dashboard & reports: `/api/v1/admin/stats` (single `$facet` round-trip → user/vendor/product/order counts + all-time and 30-day revenue + zero-filled `revenueByDay`), cross-vendor `/admin/orders` with `?status&vendor&buyer&startDate&endDate` filters, `/admin/users` with role + status + search + suspend/unsuspend (the auth service already blocks suspended logins; admins can't suspend themselves or other admins), and three reports endpoints — sales-over-time (groupBy day/week/month, zero-filled periods), top-products (revenue or units, joined back to product+vendor for display), top-vendors (revenue or orders, with `productsCount`). Frontend adds an `/admin` dashboard home with live stat cards + Recharts revenue line chart + orders-by-status horizontal bar + recent-orders + pending-vendors panels; full `/admin/users`, `/admin/orders`, `/admin/orders/:id`, and `/admin/reports` pages with three tabs (Sales / Top Products / Top Vendors). Native `<input type="date">` pair instead of a heavy date-picker library. CSV export + unified Action List dropped from the original spec for time.
- [x] **Step 13** — Rule-based product recommendations: three public/auth endpoints under `/api/v1/recommendations` — `/similar/:productId` (same-category candidates scored +1 base / +2 same-vendor / +3 shared-tag, tiebroken by `ratingsAvg` then `createdAt`; tag bonus is reserved for when `Product.tags` lands), `/for-you` (buyer-only — pulls categories from last-90-day committed orders + wishlist, returns highest-rated active products in those categories minus already-ordered, falls back to platform-wide top-rated for cold-start buyers), `/trending` (top 12 by order-line `qty` aggregated over the last 30 days). Frontend rewires product detail's "You may also like" to use `/similar` and adds "Recommended for you" + "Trending now" rails on the home page for logged-in buyers (hidden for vendors/admins/guests). No ML, no embeddings, no co-occurrence matrix — pure aggregation.
- [x] **Step 14** — Hardening (focused): multi-stage `Dockerfile` + `docker-compose.yml` for one-command demo deployment (`docker-compose up --build`), `.dockerignore`, fail-fast environment validation in `server/src/config/env.js` (production requires MONGODB_URI / JWT_ACCESS_SECRET / JWT_REFRESH_SECRET / STRIPE_SECRET_KEY explicitly; Cloudinary keys required whenever `STORAGE_DRIVER=cloudinary` regardless of NODE_ENV; STRIPE_STUB=1 waives the Stripe key, STORAGE_DRIVER=memory waives Cloudinary), env-gated SPA-from-API static mount in `app.js` (`SERVE_CLIENT=1`) so the same Express process serves both `client/dist` and `/api/v1` in production. README expanded with Architecture / Project structure / Deployment / Trade-offs sections. CI/CD pipeline, GitHub Actions, and Jest unit-test expansion deliberately deferred — the existing 7 smoke scripts cover every realistic regression path end-to-end.
