# Home responsive UI

Implemented in the existing Home screen. Feed/Stories repositories, Cubit request
and pagination contracts, Root navigation, follow/block state, startup routing,
1500ms splash, dependencies and native launch files were not changed.

## ScreenUtil and AppSizes

The existing `MyApp` already wraps MaterialApp in one ScreenUtilInit using the
project's 390 × 844 design size, with minTextAdapt and splitScreenMode enabled.
That setup, routing, localization, theme and Plus Jakarta Sans configuration
remain intact. No second initializer was introduced.

The existing AppSizes class now provides dynamic `w64` and `h64` getters and
opt-in adaptive width/height/radius/font helpers backed by `.w`, `.h`, `.r`, `.sp`.
Legacy static fields and their callers remain unchanged. New helpers calculate
after initialization and recalculate when metrics change. Dimensions are bounded
to 85–115% of their reference values, and base fonts to 90–110%, so landscape and
large screens do not produce tiny controls or huge cards. System text scaling is
still applied in full; it is not capped by these bounds on the base design size.

Home uses these helpers for header/story/tab typography, dimensions, spacing,
feed margins and opted-in PostCard styling. Its content is centered within a
720px maximum width on larger displays; that is a layout constraint, not a value
to multiply by ScreenUtil's scale. Profile and other PostCard callers retain
their existing default geometry via `responsive: false`.

## Stories: 64px avatar, larger ring

At the 390 × 844 reference size:

- Avatar image/fallback: **64 × 64 logical pixels**.
- Ring layout frame: **72 × 72**; a 2px segmented foreground stroke overlays
  the 64px image edge, with transparent 3-degree gaps and no background track.
- Story cell: 80px wide, with names underneath.

The avatar uses one shared diameter derived from `min(AppSizes.w64, AppSizes.h64)`,
bounded to 56–72px. Both axes use that same diameter. The surrounding frame
retains its previous radius-scaled dimensions, preserving cell/name positions.
The 20px plus badge overlaps the bottom-right circumference. Active segments
follow individual story expiry/viewed data; see STORIES_EDITOR_AUDIT.md for the
latest ring geometry. This replaces the earlier padded-ring description.

Existing HomeUserAvatar ClipOval, network-image cache, failed/missing-image
fallback, viewed/unviewed colors, YourStoryButton ownership/menu behavior, plus
badge, creation sheet, viewer and pagination callbacks are retained. Names are
single-line with ellipsis and full semantics. The previous story-name text-scaler
cap was removed; row height is calculated from the inherited text style and
actual system text scaler. The inherited line-height must be included in this
measurement, or a larger avatar can leave a small overflow in some hosts.

## Feed tabs and Search

HomeTabs uses a full-width Stack with a centered tab group and independently
right-aligned Search. Symmetric space is reserved for Search's 44px touch target
plus a 4px adaptive clearance on both sides; Search therefore cannot shift the
group away from Home's horizontal center. The existing centered 720px maximum
Home column also shares the screen center on tablet layouts.

The inter-tab gap is `AppSizes.adaptiveWidth(16)`: exactly **16 logical pixels at
390 × 844**, bounded to 13.6–18.4px at the tested responsive sizes. Labels use
their measured selected/unselected text widths and do not expand across the row.
When large system text exceeds the symmetric available width, cells constrain
proportionally and text can ellipsize; full accessible labels and system text
scaling remain intact. The Search target never overlaps the group. Search's
visible SVG stays aligned with the label centers, accounting for dot space.
No extra header height or gap before posts was introduced.

The existing selected white dot, semibold/regular tab styles, labels and Search
route remain. The dot is 6px at reference size. Header height grows only when
text scaling requires it; there is no extra reserved spacer for Search/loading.
The optional SearchRepo injection follows the existing repository injection
pattern and allows route navigation to use mocked current-user responses in
widget tests. Production still uses the same SearchScreen and endpoints.

## Shared header, stories persistence and feed caches

Previously, Following replaced HomeStories with a lone own avatar, and a
selected-tab key on RefreshIndicator recreated the scroll subtree. Both branches
have been removed: there is one stable Stories/StoryEntry subtree above both
feeds, with a constant PageStorageKey on its horizontal list.

Switching tabs now:

- Keeps the same Stories element, horizontal ScrollPosition, loaded collection,
  viewed flags and image cache; no Stories refetch or skeleton restart occurs.
- Loads a feed only if its Cubit is still initial. Returning to an existing feed
  reuses cached posts and its cursor instead of starting another traversal.
- Preserves the existing Following refresh when a confirmed follow mutation has
  made its data dirty. Publication/block/unblock refresh paths are unchanged.
- Saves a vertical offset per feed and restores it after layout, clamped to the
  actual content extent. Offsets are cleared on session changes.

The shared header retains its existing scroll-away behavior and the feed tabs
remain pinned. Stories are included in that header for both feeds, rather than
being part of either feed body. Returning to a previously scrolled feed retains
its position. Story viewing/creation can still refresh canonical data through the
existing callbacks; tab switching does not.

## Loading and post layout

Initial feed loading now uses the installed **shimmer** dependency (not a new
Skeletonizer dependency), following the existing Profile skeleton approach.
`HomeFeedSkeleton` renders presentation-only shapes in the feed sliver: two dark
cards with author/avatar, timestamp, caption, 220px reference media region and
action placeholders. Card fill, 16px padding, 20px radius, 40px author avatar,
feed margins and first-card top spacing match the real Home card geometry.
There are no fake PostModels, synthetic repository entries or new API calls.
Actual card height still depends on returned captions/media; skeletons approximate
a typical media post rather than predicting unknown content.

Initially loading Stories with no cached groups append circular avatar/name
bones after the real, functional Add Story cell. Bones use the same shared
avatar/ring diameters (64/72px at reference size), cell widths, list spacing and
scaled name line box. The existing horizontal ListView, key and own-story control
remain mounted. Cached Stories are never replaced with skeletons during refresh.

Skeleton base/highlight colors are #232323/#303030 with an 1800ms shimmer period;
there is no white shimmer. Decorative bones ignore pointer/semantics, the feed
announces “Loading posts”, and animations stop under reduced-motion settings.
The real header, tabs and Root bottom navigation remain visible and interactive.

Loading states are deliberately separate:

| State | Presentation |
| --- | --- |
| PostsInitial / PostsLoading without cached posts | Post skeletons, no top Cupertino indicator |
| Uncached tab request | Post skeletons below the shared header/tabs; Stories retain their state/scroll |
| Cached feed tab | Cached posts immediately; no skeleton or refresh request |
| Successful empty feed | Existing empty/add/discovery presentation |
| Initial request failure | Existing error/retry UI; retry re-enters skeleton loading |
| Pull-to-refresh / Home re-tap | Exactly one floating orange Cupertino indicator; cached content remains |
| Background publication/follow/block refresh | Existing cached-content behavior, no explicit-refresh spinner |
| Cursor pagination | Existing footer indicator and posts; no feed skeleton or top spinner |

The established top CupertinoActivityIndicator is now gated exclusively by the
existing `_explicitRefreshes` tracking. Its 30px frame, radius 15 and
`DarkColors.primaryColor` remain unchanged in an IgnorePointer/Positioned overlay
below SafeArea, contributing no layout height. RefreshIndicator.noSpinner prevents
a second native indicator. Requests coalesce per feed; completion/failure clears
the overlay, and session changes/disposal retain their safeguards.
Pull-to-refresh retains the ancillary account/Stories refresh policy; Home re-tap
refreshes only the active feed. Repository, Cubit and cursor contracts are unchanged.

Only Home opts into responsive PostCard/ActionIconButton styling and the new
`homePresentation` caption/spacing option. Media keep BoxFit.cover and error placeholders, and
post/location text uses flexible vertical space. The Home action group can wrap
when large counts/text do not fit one row, while Like/Comments/Share/Save callbacks,
counts, pending state and semantics remain unchanged. The default layouts used
by Profile and other screens are retained. Auxiliary suggested/trending sections
were inspected and exercised during scrolling without replacing their content
or request behavior.

## Full-page pull-to-refresh and captions update

### One coordinated vertical scrollable

The refresh owner remains `RefreshIndicator.noSpinner` around the existing
CustomScrollView and ScrollController. The fixed-height SliverAppBar /
FlexibleSpaceBar wrapper was replaced with a normal SliverToBoxAdapter containing
the same greeting, subtitle, header actions and Stories/StoryEntry subtree.
Header height now comes from its actual children. There is no nested vertical
scrollable or recreated Stories key.

The scroll structure is now:

1. SliverToBoxAdapter: greeting/header actions, existing spacing, Stories and names.
2. SliverPersistentHeader: existing centered feed tabs/Search, still pinned on
   ordinary upward scrolling and moving with the page during top overscroll.
3. Existing feed slivers: skeletons, empty/retry presentation or PostCard list,
   with suggestions and pagination unchanged.

`BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())` makes the entire
page visibly move during a pull, including on short/empty feeds and platforms
whose default physics clamp overscroll. Bottom navigation stays outside this
viewport. Resting header/tab/post geometry remains unchanged. The notification
predicate accepts only depth-zero vertical notifications; horizontal Stories
and media paging do not initiate refresh. Pagination ignores out-of-range/top
scroll positions so a pull cannot accidentally start a cursor request.

The existing refresh contract is retained: pull refreshes the selected feed and
already-supported ancillary Stories/account/suggestions; Home re-tap refreshes
the selected feed. Repeated requests coalesce. Pulling while an initial request
is pending shares that request rather than dispatching another first-page read.

Exactly one existing orange radius-15 CupertinoActivityIndicator remains in a
30px floating overlay below SafeArea. It reserves no layout height; no Material
spinner or CupertinoSliverRefreshControl was added. Cached posts and Stories
stay visible during refresh; initial no-cache loading retains the dark skeletons.
Success/failure, session changes and disposal retain their cleanup safeguards.

### Home PostCard spacing and typography

Home explicitly passes `homePresentation: true` to the shared PostCard.
The default is false, retaining Profile/other callers' existing caption and
spacing behavior independently of the earlier `responsive` option.

- Author row → caption: `AppSizes.adaptiveHeight(20)` (20px at 390 × 844).
- Final visible content → interaction row: **exactly 20 logical pixels**, without
  ScreenUtil scaling or a second spacer. This follows whichever content is last:
  caption, location badge, single image, carousel, or author row for an empty post.
- Existing horizontal padding uses the existing adaptive 16px reference value.
- Caption is white, Plus Jakarta Sans, existing 14px reference font and 1.4 line
  height. Author/timestamp styles, media fit/radii and action callbacks are intact.
- Home skeleton card bones use matching header/caption and action spacing;
  skeleton loading behavior and animation remain unchanged.

### Four-line expandable caption

`HomePostCaption` uses TextPainter with the actual width, inherited style,
locale, text scaler and paragraph direction to determine overflow. Short text
has no expansion link, regardless of raw character length. More than four
measured lines produce a collapsed RichText via Text.rich.

The collapsed prefix is found by binary search over Unicode **grapheme clusters**
using Flutter's existing exported characters library. Each candidate includes
the orange, semibold `read more...` span during measurement, so the complete link
fits in the final four-line layout. There is no additional automatic ellipsis.
Combining marks, skin tones, ZWJ/family emoji and line breaks are preserved; the
expanded text is the exact original string, followed by an orange `show less`.

TapGestureRecognizer belongs only to the inline action and is disposed with the
widget. Accessibility retains the full original caption and exposes the link's
tap action. Paragraph base direction follows the first Unicode letter (including
Arabic/Hebrew); Flutter's bidi renderer handles mixed runs. System text scaling
is applied in full. This has widget/layout coverage, not a new Simulator Arabic
visual signoff.

Expansion is scoped to the stable post ID and original content. The existing
PageStorage bucket stores the boolean under `(home-caption, id, text)` to retain
it across remounts/cached tab returns; another post's Like update does not reset
it. New text or a different ID has independent state. No repository or API is
called, and no programmatic feed-scroll jump is made when toggling.

Collapsed measurement is cached by text, width, TextStyle, TextScaler, direction
and locale. An unrelated rebuild with the same layout reuses that result rather
than running the grapheme search on every frame. The existing legacy caption
implementation remains the shared PostCard default outside Home.

### Files changed for this update

- `lib/features/home/screens/home_screen.dart`
- `lib/core/widgets/post_card.dart`
- `lib/core/widgets/home_post_caption.dart` (new)
- `lib/features/home/widgets/home_loading_skeleton.dart`
- `test/features/home/home_loading_polish_test.dart`
- `test/features/home/home_post_caption_test.dart` (new)
- `test/features/home/home_responsive_ui_test.dart`
- `docs/HOME_RESPONSIVE_UI.md`

### Verification for this update

- All **171 Home tests passed** in the final regression run, including 41 new
  cases across full-page gestures, captions and cached tab return.
- Broader final result: **894 passed, 3 failed**. Coverage included Home,
  Stories/editor/upload/export/gestures, shared media transport, cursor pagination,
  follow/likes/saved/shares, block/feed synchronization, Profile account actions/UI,
  Buddies, onboarding/splash, shared Back and loading widgets.
- The only failures are the unchanged `story_other_viewer_test.dart` reply-composer
  tests: composer/control layout, typing/Done and keyboard dismissal. A separate
  current run reproduced **12 passed, the same 3 failed**. They remain the existing
  emoji/send-icon/dismiss-control expectation mismatches; no fix is claimed.
- Targeted analysis of all seven changed Dart files: **no issues found**.
- `dart format --output=none --set-exit-if-changed`: seven files clean.
- Gesture tests measure equal downward movement of greeting, Stories, names,
  tabs and posts while bottom-navigation bounds stay fixed. Both feeds are tested
  with long, short, empty and initial-loading results. Vertical drags can begin
  over every section; horizontal story drags retain their offset without refresh.
  A pull during initial loading coalesces with the pending read. Cached refresh
  retains card elements and bounds, with exactly one orange Cupertino indicator.
- Caption tests cover white/Plus Jakarta Sans styling; four measured lines;
  orange inline links; full expansion and collapse; emoji/grapheme/newline
  preservation; accessible full content and a tappable semantic link; independent
  IDs, remount persistence and another post's Like rebuild; all four post actions;
  legacy non-Home behavior; no feed/Stories request or scroll jump on expansion;
  and preservation after a cached feed-tab return.
- Geometry checks measure the final 20px gap for caption, location, single-image,
  carousel and author-only cards. Header-to-caption spacing is 20px at reference.
- Responsive Home/initial-loading layouts pass at 320/375/393/430px widths,
  844 × 390 landscape and 1024 × 768 tablet, with 1×/2× text scaling. Arabic/mixed
  RTL captions also pass layout and inline interaction checks at all those widths;
  English text in an RTL app retains an LTR paragraph.
- Simulator verification was not performed; access was previously denied in this
  session. Figma metadata remains rate-limited, so no screenshot parity, device
  rendering or performance verification is claimed.

Final commands:

```sh
flutter test --no-pub test/features/home test/features/stories test/core/pagination test/core/media test/features/follow test/features/likes test/features/saved test/features/shares test/features/block/block_feed_sync_test.dart test/features/profile/profile_account_actions_test.dart test/features/profile/profile_ui_polish_test.dart test/features/buddies test/features/onboarding test/core/widgets/back_button_widget_test.dart test/core/widgets/travibe_loading_indicator_test.dart --reporter expanded
flutter test --no-pub test/features/stories/story_other_viewer_test.dart --reporter expanded
```

The verification sections below are historical and remain identified with their
prior updates.

## Own-post follow-action correction

Home previously passed `showFollowButton: true` for every post. PostCard did not
receive the author's stable ID, and FollowActionBuilder gates block/pending
status rather than establishing ownership. An own post with `is_following: false`
therefore rendered Follow. Profile separately hid actions for an owner route,
which did not solve the shared author-header case.

PostCard now receives the model's `authorId` and makes the shared header decision.
It uses the existing app-level **CurrentUserCubit.profile.id**, already loaded
from the authenticated `/user` resource. Home can also supply its already-confirmed
HomeAccount ID, explicitly bound to the matching PreferencesManager.sessionRevision.
No new preference key, identity service, profile fetch or backend change was added.

IDs are normalized from integer/string representations into canonical positive
integer strings using BigInt. Whitespace and leading zeros are handled; missing,
zero, fractional, boolean and malformed values are not ownership evidence.
Unresolved identity suppresses a model-backed follow control until it can safely
be shown, without treating an unknown author as the authenticated user.

The follow control and its adjacent 8px spacing are one conditional unit. Own
posts retain avatar, name, timestamp, expanded author-information space and the
same three-dot callback; there is no blank follow placeholder. Other confirmed
authors retain the same FollowActionBuilder callback, styles, pending state,
error handling and block restrictions. Static legacy cards with no author
metadata retain their existing API; all follow-enabled model-backed call sites
(Home and ProfilePostsSliver) pass the real author ID.

Only the author-action subtree listens to identity/session changes, preserving
caption and media state. CurrentUserCubit already clears identity on logout or
account replacement and rejects stale responses. Home's fallback ID is ignored
once its accepted session revision becomes stale. The callback itself rechecks
live ownership before invocation, so a retained pre-switch handler cannot issue
a follow request for the new current user before the next paint.

Newly published data receives the same check on its first PostCard render. The
existing publication refresh flow and both feed caches are unchanged; no manual
refresh is needed to hide Follow and no separate delayed correction is used.
Post options/permissions, captions, spacing, Stories, refresh UI and pagination
were not changed by this correction.

Files changed:

- `lib/core/widgets/post_card.dart`
- `lib/features/home/screens/home_screen.dart`
- `lib/features/profile/widgets/profile_posts_sliver.dart`
- `test/features/home/post_card_ownership_test.dart` (new)
- `test/features/home/home_post_ownership_test.dart` (new)
- `test/features/home/post_card_follow_style_test.dart`
- `test/features/profile/profile_posts_widget_test.dart`
- `docs/HOME_RESPONSIVE_UI.md`

Verification:

- Focused PostCard/Home/Profile run: **29 passed, 0 failed**.
- Broad relevant regressions: **525 passed, 0 failed** across Home, follow,
  Profile (including account/session/logout/deletion), create-post, block/feed
  synchronization, onboarding/startup and saved posts.
- Separate authentication/registration regressions: **34 passed, 0 failed**.
- Targeted `flutter analyze --no-pub` on all seven changed Dart files:
  **no issues found**. Dart formatting is clean.
- New coverage verifies own Follow/Following removal for integer/string/zero-padded
  IDs, unchanged header/options geometry, name collisions, another author's
  follow/pending/unfollow, block-pending restrictions, unknown identity, missing/
  malformed author IDs, stale account responses, logout and retained callbacks,
  session-bound Home fallback without a new read, publication/refresh in both
  feeds, and the own Profile PostCard.
- The neutral Home follow-style fixture now establishes an authenticated test
  session before expecting another author's Follow control, matching production.
- No Simulator visual verification was performed for this behavior correction.

Commands:

```sh
flutter test --no-pub test/features/home test/features/follow test/features/profile test/features/create_post test/features/block/block_feed_sync_test.dart test/features/onboarding test/features/saved --reporter expanded
flutter test --no-pub test/features/auth --reporter expanded
```

The previously reported Story Viewer reply-composer failures were outside these
runs; no Story Viewer code/tests were changed and no fix is claimed.

## Files changed in the tabs/skeleton update

- `lib/features/home/screens/home_screen.dart`
- `lib/features/home/widgets/home_stories.dart`
- `lib/features/home/widgets/home_tabs.dart`
- `lib/features/home/widgets/home_loading_skeleton.dart` (new)
- `test/features/home/home_loading_polish_test.dart`
- `test/features/home/home_experience_test.dart`
- `docs/HOME_RESPONSIVE_UI.md`

Earlier responsiveness work also updated AppSizes, HomeTopBar, opted-in
PostCard/ActionIconButton sizing and responsive/Stories component tests. Those
components, root initialization, Profile and Buddies are unchanged in this update.

## Verification

- `dart format --output=none --set-exit-if-changed` on all six changed Dart
  files: clean (zero changes).
- Targeted `flutter analyze --no-pub` on those six files: **no issues found**.
- Final broad regression run: **804 passed, 3 failed**. All Home tests passed,
  including the 16 newly added spacing/skeleton cases and updated loading tests.
  Coverage includes Stories, cursor pagination, follow/likes/saved/shares,
  block/feed synchronization, Profile account actions/UI, Buddies,
  onboarding/splash, shared back buttons and loading indicators.
- Initial skeleton and populated layouts passed at 320, 375, 393 and 430px
  portrait widths, 844 × 390 landscape and 1024 × 768, at 1×/2× text scaling.
  Tests check circular bones, compact tabs/Search alignment, reduced-motion and
  dark shimmer styling, structural card parts, no overflow, preserved story
  element/scroll position, cache reuse and no duplicate tab requests.
- Refresh/re-tap tests verify exactly one radius-15 orange Cupertino indicator,
  unchanged content bounds, cached cards, failure cleanup, scroll preservation
  and coalescing. Pagination tests preserve the opaque cursor and footer UI.
- The three failures are in the unchanged
  `test/features/stories/story_other_viewer_test.dart`:
  - `other-user row has composer and independent heart/options; owner controls unchanged`
  - `typing pauses progress, Done resumes and preserves the current draft without sending`
  - `dismiss keyboard works; story change clears the ephemeral draft`
- Separately running that file reproduced **12 passed, the same 3 failed**.
  Assertions expect an older emoji asset, no focused send icon, and a
  `Dismiss keyboard` control that the current reply composer does not provide.
  These match the previous run's failures. The viewer/reply implementation and
  its tests were not modified, and these failures are not claimed as fixed.

Final broad command:

```sh
flutter test --no-pub test/features/home test/features/stories test/core/pagination test/features/follow test/features/likes test/features/saved test/features/shares test/features/block/block_feed_sync_test.dart test/features/profile/profile_account_actions_test.dart test/features/profile/profile_ui_polish_test.dart test/features/buddies test/features/onboarding test/core/widgets/back_button_widget_test.dart test/core/widgets/travibe_loading_indicator_test.dart --reporter expanded
```

Separate viewer command:

```sh
flutter test --no-pub test/features/stories/story_other_viewer_test.dart --reporter expanded
```

## Follow-up: centered tabs verification

This follow-up changed only:

- `lib/features/home/widgets/home_tabs.dart`
- `test/features/home/home_loading_polish_test.dart`
- `test/features/home/home_responsive_ui_test.dart`
- `docs/HOME_RESPONSIVE_UI.md`

`flutter test --no-pub test/features/home --reporter expanded`: **130 passed,
0 failed**. Tests verify the group center equals the full screen center and
Search retains its right inset at 320, 375, 393 and 430px widths, plus landscape
and tablet, at 1×/2× text scaling. Existing tab selection, Search navigation,
Stories persistence, skeleton, explicit refresh/re-tap and pagination checks pass.
Targeted analysis of the three changed Dart files found no issues. `dart format`
was run on those files. Skeleton/loading code, repositories, Root and navigation
were unchanged. The broader run and separate viewer results above predate this
centering-only follow-up; the known viewer failures were not changed or rerun.
No Simulator visual verification was performed for the follow-up.

## Reference and Simulator status

AGENTS.md and the existing Figma reference/access notes were consulted. The
existing 390 × 844 root configuration supplies the design dimensions. A new
read-only Figma metadata attempt returned the Starter-plan MCP limit, so no Home
frame IDs, screenshots or visual comparison are claimed. The layout follows the
user's explicit requested arrangement.

Simulator access in the preceding responsiveness work was attempted through
Computer Use and returned “Computer Use
was not approved to use Simulator.” Therefore no before/after Simulator comparison,
new Simulator screenshots or physical-device performance verification is claimed.
All responsive/layout observations in this change come from mocked widget tests.
