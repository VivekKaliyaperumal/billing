# Billing App – Flutter mobile

Flutter port of the React billing (POS) web app in this repo. The UI and behaviour match the web app; it is frontend only, with no backend.

## Run

```sh
cd mobile
flutter pub get
flutter run            # on a connected Android/iOS device or emulator
flutter test           # unit tests for cart, stock, credit, currency, history, CSV
```

## Data

Data is stored on the device with `shared_preferences`, using the same keys as the web app's localStorage:

| Key | Contents |
|---|---|
| `shop_products` | products |
| `shop_sales_history` | sales history |
| `shop_customers` | customers |
| `shop_settings` | shop name and currency |
| `shop-ui-theme` | light or dark theme |

On first launch only the 8 default products are loaded.

## Layout

| Folder | Contents |
|---|---|
| `lib/theme/` | design tokens copied from `src/index.css`, in light and dark |
| `lib/models/` | ported from `src/types/product.ts` |
| `lib/providers/` | ported from the React contexts in `src/context/` |
| `lib/screens/` | Sales, Products, History, Customers, Settings |
| `lib/widgets/` | shared shadcn-style button, card, dialog, select and toast |

## Mobile adaptations

- **Navigation:** a bottom navigation bar instead of the web top nav.
- **Cart:** a floating "Current Sale" bar that opens the cart sheet. On screens 900px or wider, the cart sits beside the product grid as on the web.
- **Print:** generates the receipt as a PDF and opens the system print sheet (the web app uses `window.print()`).
- **Export CSV:** produces the same CSV as the web app and opens the share sheet.
- **Product edit/delete:** the buttons are always visible, because a phone has no hover.
