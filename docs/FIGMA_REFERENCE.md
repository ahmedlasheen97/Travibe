# Travibe Figma reference

Design: [Travibe](https://www.figma.com/design/SI9VCqSKenZVSy5mFZQ8eH/Travibe?node-id=0-1)

File key: `SI9VCqSKenZVSy5mFZQ8eH`. Requested entry node: `0:1`.

## Access status — 2026-10-13

Access could not be verified. The Figma MCP `get_metadata` request for `0:1`
returned: “Looks like you don't have edit access to this file.” The MCP
`whoami` check identified `alasheen784@gmail.com`. The other available Figma
connection returned an authentication/retry response twice without metadata.

No Figma node was successfully inspected. No frame metadata, design context,
or screenshots were returned. Mobile screen names and IDs remain unverified;
the presence or absence of Comments and Replies designs cannot be determined.
The MCP's edit-access requirement does not authorize editing the Figma file.

## Flutter mappings

These names describe the existing Flutter views, not verified Figma frame names.

| Flutter view | Figma screen / node ID | Flutter file |
| --- | --- | --- |
| Comments | Unverified — access blocked | `lib/features/comments/screens/comments_screen.dart` (`CommentsScreen`, `parentId == null`) |
| Replies | Unverified — access blocked | `lib/features/comments/screens/comments_screen.dart` (`CommentsScreen`, non-null `parentId`; opened by `_openReplies`) |

The existing UI contains a count-bearing Comments app bar, avatar/comment rows,
timestamps, reply navigation, permission-controlled edit/delete menus, and a
text composer. Replies reuse the screen and display the parent comment above
the thread. Loading, errors, pagination, synchronization, and restoration states
also appear in this screen. No visual differences can be established until
the relevant designs are accessible; no Flutter UI was changed during this review.

Existing behavior is managed by `lib/features/comments/cubit/comments_cubit.dart`
and `comments_state.dart`; data access uses
`lib/features/comments/data/comments_repo.dart` and `comment_model.dart`.
These files are mapping references, not Figma-verified components.

## Next design review

1. Resolve access for the connected Figma account and retry metadata at `0:1`.
2. Identify the actual mobile frames and record their exact names and node IDs.
3. Load the `figma-design-to-code` skill and obtain design context with screenshots
   for Comments and Replies, if present. Inspect only relevant frames.
4. Compare verified design details with Flutter, preserve existing behavior,
   and update this document with the nodes actually inspected and validation results.

## Send Post review — 2026-10-16

Two read-only metadata attempts at `0:1` returned “Authentication for Figma was
requested and accepted. Retry this tool call now.” Neither returned metadata.
No rate-limit response was received; no further calls were made. The Send Post
frame ID, screenshot, assets, dimensions and spacing remain unverified.

`lib/features/shares/widgets/send_post_sheet.dart` follows the user's written
reference (dark rounded sheet, handle, Send Post title, search, horizontal people,
Copy Link and More Options) using existing Travibe theme tokens, handle and avatar
widgets. It is an approximation pending design access, not verified Figma alignment.
No Figma content was changed. See `docs/SHARE_POST.md` for behavior and API limits.

## Other User Profile review — 2026-11-08

The metadata request for `0:1` returned the Figma Starter-plan MCP tool-call
limit. No profile frame/node or screenshot could be inspected. The workspace
contains Chat and Notifications screenshots but no supplied profile reference
paths were identified. Screenshot locations were requested from the user.

The public-profile integration therefore retains existing Travibe components and
uses the user's written functional requirements. Screenshot fidelity is not
verified. No Figma content was changed. See `docs/OTHER_USER_PROFILE.md`.
