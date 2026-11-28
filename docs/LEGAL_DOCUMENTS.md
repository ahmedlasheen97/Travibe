# Terms of Service and Privacy Policy

Updated 28 November 2026. The in-app screens show the same content as the
website (`https://travibeapp.com/terms`, `/privacy`), which is edited in the
admin panel (`/admin/legal-pages`). Nothing is bundled in the app any more;
the old drafts (`legal_content_{en,ar}.dart`, `docs/legal/drafts/`, the draft
banner and `tool/export_legal_documents.dart`) were removed.

## Source

There is no legal-pages API yet (requested in `BACKEND_REQUESTS.md`, "Legal:
API for the Terms and Privacy pages"). Until it ships the app reads the public
website HTML:

- `LegalPageSlug` (`lib/features/legal/data/legal_page.dart`): `terms`,
  `privacy`, with their website URL and a fallback title.
- `LegalHtmlParser`: reads `<html lang>`, the `<h1>`, `<time datetime>` and the
  `<div class="legal-prose">` body. Supports `p`, `strong`/`b`, `em`, `a`,
  `br`, `h1`–`h6`, `ul`/`ol`/`li`. A paragraph that is entirely bold is a
  section heading (the website writes headings as `<p><strong>1. …</strong></p>`).
  `mailto:` and Cloudflare `/cdn-cgi/l/email-protection` links become email
  spans; relative links resolve against `https://travibeapp.com`. Missing or
  empty prose is a `FormatException`.
- `LegalPagesRepo`: public Dio (no token, no session revision; the content is
  device-wide). `fetch` stores the parsed page as JSON in SharedPreferences
  (`legal_page_v1_<slug>`); `cached` reads it (corrupt → none).

When the API ships only `LegalPagesRepo.fetch` changes.

## Screens

`TermsOfServiceScreen` / `PrivacyPolicyScreen` (`features/profile/screens/`)
wrap `LegalPageScreen` (`features/legal/screens/`). They are opened from
Settings → Help & Legal, the Sign Up consent links and the public GoRouter
routes (`AppRoutes.termsOfService`, `AppRoutes.privacyPolicy`).

`LegalPageCubit` loads the cache first, then the website:

| Situation | UI |
| --- | --- |
| First load, nothing cached | White `AppActivityIndicator` |
| Loaded (fresh or cached) | Title, "Last updated: 25 November 2026", headings, paragraphs, "View on website" |
| Fetch fails, cache shown | Red toast "Couldn't load. Check your connection." + Refresh |
| Fetch fails, nothing cached | Same toast, plus "Couldn't load. Check your connection." and "Open in browser" |

- Shared `BackButtonWidget`, `AppSizes.legal*` sizes, `DarkColors`, Plus
  Jakarta Sans. Pull to refresh.
- Content direction follows the page's `lang` (English stays LTR in the Arabic
  app). The website is English-only today.
- Links are orange. `/terms` and `/privacy` on travibeapp.com open the native
  screen; other links open in the in-app browser (`LinkOpener`:
  `url_launcher`, `LaunchMode.inAppBrowserView` → SFSafariViewController /
  Chrome Custom Tabs). A failed open shows "Couldn't open the page. Check your
  connection."
- Text is selectable (`SelectionArea`). Tapping an email copies it and shows
  "Copied".

## Tests

`test/features/legal/` (parser, repo, cubit, screen; fakes in
`legal_fakes.dart`), `test/features/auth/terms_inline_test.dart` (Sign Up
links) and the Help & Legal test in
`test/features/profile/settings_privacy_test.dart`.
