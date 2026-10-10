# Thyantra Billing: Play Store listing

Everything Play Console asks for, ready to paste. Files referenced are in this folder.

## App details

| Field | Value |
|---|---|
| App name | Thyantra Billing |
| Package | `com.thyantra.billing` (permanent) |
| Category | Business |
| Contact email | hello@thyantra.com |
| Website | https://thyantra.com |
| Privacy policy | https://thyantra.com/billing-privacy-policy |
| Price | Free |
| Ads | No |

**Short description (80 characters max)**

> Billing, stock and customer credit for small shops. Works fully offline.

**Full description**

> Thyantra Billing helps small shops record sales, track stock and manage customer credit, all on your phone, with no internet or account needed.
>
> **Fast billing**
> • Tap products to add them to the bill, adjust quantities and complete the sale
> • Printable receipts, with your shop name, through any Android-supported printer
> • Credit sales ("pay later") recorded against the customer
>
> **Stock that stays right**
> • Stock goes down automatically with every sale
> • Prices and stock are re-checked when the sale is confirmed, so nothing is oversold
> • Low-stock and out-of-stock warnings
>
> **Customer credit ledger**
> • See who owes what at a glance
> • Record payments; full transaction history per customer
>
> **Sales reports**
> • Today's and yesterday's sales, monthly trend, top-selling products
> • Export sales to CSV for your accountant
>
> **Your data stays with you**
> • Everything is stored only on your phone. We never see it.
> • Back up to Google Drive or email whenever you like, and restore on a new phone
> • Rupee, Dollar, Euro and Pound currencies; light and dark themes

## Graphics

| Asset | File |
|---|---|
| App icon (512 × 512) | `icon-512.png` |
| Feature graphic (1024 × 500) | `feature-graphic-1024x500.png` |
| Phone screenshots | `screenshots/1-sales.png` … `6-dark-mode.png` (real app, 1080 × 2400) |

## Data safety form

The app has no server, no SDK that transmits data, and no analytics or crash reporting.

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No.** Data is processed only on the device; Google's definition of "collected" covers data sent off the device. |
| Is all user data encrypted in transit? | Not applicable (no user data is transmitted). |
| Do you provide a way for users to request that their data is deleted? | Users can delete records in the app, or uninstall / clear storage. |

Notes for the reviewer, if asked: product images load from https addresses the user types in; backups and CSV/receipt exports are files the user creates and shares with apps they choose.

## Content rating questionnaire

Category: **Utility, productivity, communication or other**. Answer **No** to every question (no violence, sexual content, gambling, user-to-user communication, sharing of location, or purchases). Expected rating: Everyone / 3+.

## Target audience

18 and over (business tool). Not designed for children.

## Release checklist

1. Deploy the Thyantra website so https://thyantra.com/billing-privacy-policy is live (page added in the `thyantra` repo at `app/billing-privacy-policy/page.tsx`).
2. `powershell -ExecutionPolicy Bypass -File scripts\create_upload_keystore.ps1` (once). Back up the keystore and password.
3. `powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1`, then upload `build\app\outputs\bundle\release\app-release.aab`.
4. In Play Console, opt in to **Play App Signing** (default), fill in the listing, Data safety and content rating from this file.
5. Start with an **Internal testing** track and install from Play on a real phone before promoting to Production.
6. Keep `build\symbols` for each release (needed to read crash stack traces in Play Console).
