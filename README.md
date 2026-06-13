# PosEx Mobile App (Flutter)

Native Android/iOS app for [PosEx](https://posex.lk).

## Features (current)

- **Login** — `POST /api/v1/auth/login` (username/email + password), JWT stored locally
- **Products** — `GET /api/v1/products/` scoped by `business_id` + `branch_id`
- Search, pull-to-refresh, infinite scroll pagination
- Product cards: image, name, item code, barcode, stock, price (LKR)

## API

Base URL: `https://posex.lk` (`lib/config/api_config.dart`)

| Action | Endpoint |
|--------|----------|
| Login | `POST /api/v1/auth/login` |
| Current user | `GET /api/v1/auth/me` |
| Products list | `GET /api/v1/products/?business_id=&branch_id=&search=` |

## Repos

- **Standalone:** https://github.com/msuzan55/posex-app
- **Monorepo copy:** `/var/www/suzanpro/posex-app`

Publish monorepo → standalone:

```bash
/var/www/suzanpro/scripts/publish-posex-app-to-git.sh "your message"
```

## Local dev

```bash
cd posex-app
flutter pub get
flutter run
flutter test
```

## CI (GitHub Actions)

`.github/workflows/build.yml` — analyze, test, build **Android APK** (no VPS build required).

Download APK from **Actions → Artifacts** after push.

## Project layout

```
lib/
├── config/api_config.dart
├── models/
├── services/          # auth + products API clients
├── providers/         # auth state
├── screens/           # splash, login, products
└── widgets/           # product card
```
