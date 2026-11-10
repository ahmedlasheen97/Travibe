# Profile Stage 5 — avatar upload and confirmed media contract

Updated 2026-10-21. This report uses the latest Media API contract supplied by the
backend developer through the user. It supersedes the stale media schemas in
`docs/openapi.json`; that file has not been overwritten. The supplied documentation
examples are not captured live responses. A later
user-provided runtime diagnostics now confirm top-level media for both deployed
finalize (HTTP 200, processing) and GET status (HTTP 200, ready). Presign HTTP 201,
PUT HTTP 200 and profile PATCH/refresh HTTP 200 are also reported by the user.
No new deployed API/storage call was made from this environment. End-to-end
deployment success remains unverified. Figma styling, Profile fields, Stories, Home and Buddies are unchanged.

## Confirmed contract and parser mapping

All endpoint paths are relative to `/api/v1/`.

| Endpoint / field | Confirmed contract and client behavior |
| --- | --- |
| POST media/presign | Sends actual filename, byte-derived content_type and size in bytes. The existing required request fields remain unchanged. No model binding or extra upload field is invented. |
| Presign response | Observed HTTP 201. Top-level media, upload_url, upload_method, upload_headers and expires_at. MediaPresign parses media.id as a positive integer and the known status. Empty upload_headers is valid; mixed string/list header values from the earlier supplied response are also supported. |
| Storage request | Raw original bytes to the exact signed PUT URL, with required returned headers. Never JSON or multipart. |
| POST media/{id}/finalize | HTTP 200. Documentation uses data:{id,type,status,...}; newly confirmed deployed response uses media:{id,status:processing,...}. UploadMedia.fromFinalizeEnvelope now accepts either wrapper through the same strict resource validation as GET. |
| Finalize 409 | May already have been finalized. The client checks GET status for the same ID and never repeats finalize or PUT to resolve the conflict. |
| Finalize 422 | Validation failure or missing uploaded object. Preserve the API validation error and local draft; no PATCH or automatic retry. A subsequent explicit Save can request a new media authorization/upload. |
| GET media/{id} | Documentation uses data:{id,type,status,...}; deployed runtime diagnostics show media:{id,status,...}. UploadMedia.fromEnvelope accepts either wrapper, requires a positive integer ID and known status, and rejects ambiguous/malformed responses. Poll until ready or failed. |
| Lifecycle | pending → finalize/async processing → ready or failed. The client does not claim a media ID until GET reports ready. |
| URL fields | Documented as strings. Their presence does not prove object availability and they are not fetched before ready. They are not used as upload destinations. |
| PATCH profile | Existing confirmed partial avatar_media_id update, combined with other changed fields, followed by canonical GET profile refresh. No new PATCH response assumptions are made. |

Allowed image MIME types are image/jpeg, image/png, image/gif and image/webp.
Selection validates decoding and detects MIME from bytes rather than extensions.
Unsupported HEIC/HEIF is not renamed or silently uploaded as PNG. The default
maximum remains 20 MB, subject to deployed configuration; no exact deployed byte
ceiling is known. The actual byte count is sent to presign and backend validation
is authoritative. Signed authorization expires at expires_at, normally after ten
minutes. Expired authorization is rejected before PUT.

## Findings and focused fixes

### Confirmed GET envelope mismatch

The supplied runtime log shows HTTP 200 application/json with a top-level media
object, integer id and ready status. The old GET parser required data, so it
rejected the valid ready object before the workflow could PATCH the profile.
This is now a **confirmed client parsing mismatch**, not a processing failure.

GET parsing now accepts exactly one of data or media. It never silently falls
through from a malformed data field to another wrapper, and rejects both wrappers
present at once. ID must be a positive integer (no numeric-string/double coercion),
status must be pending/processing/ready/failed. ID/status remain this projection's
required fields; returned type, MIME/name/error/timestamp fields, URL strings,
byte size and dimensions are validated against their expected types. Processing
metadata is not invented or made mandatory. Unknown extra fields remain ignored.

Both normal polling and read-only recovery use this parser. Ready returns the
existing ID, allowing the unchanged avatar PATCH/canonical refresh to continue.
The presign parser and its top-level upload fields are unchanged.

### Confirmed finalize mismatch and first-Save fix

The user's subsequent runtime evidence independently confirms finalize HTTP 200
with a top-level media object and status=processing. The finalize parser still
required data, causing a valid successful response to throw FormatException.
The old catch then labelled every retained media record “uncertain,” even though
the PUT had already returned HTTP 200. This is the confirmed first-Save failure.

Finalize now supports the verified media wrapper and documented data wrapper.
Both share strict validation of exactly one envelope, positive integer ID, known
status and the types of returned metadata. Presign parsing is unchanged.
HTTP 200 processing finalization now proceeds to status polling in the same Save
operation. A ready GET returns the ID for PATCH/canonical refresh and navigation,
without an intermediate error or a second Save tap.

Recovery was also tightened: the service retains a ready record rather than
clearing it immediately, and matches the selected photo by byte contents as well
as object identity. An equivalent newly created Uint8List therefore reuses the
same ready ID through GET instead of starting a new presign/PUT/finalize. A truly
changed image is not mistaken for the cached selection. The editor's existing
ready-ID cache still prevents re-upload on a failed profile PATCH retry.

A separate put-confirmed flag distinguishes outcomes. A genuine transport timeout
may still produce an uncertainty message. A malformed server response after a
confirmed PUT reports an unexpected response; delayed processing reports that the
existing upload is still processing. Neither is falsely described as an uncertain
storage upload. Genuine failures retain preview and all pending form edits.
Documented finalize 409 reconciliation and 422 validation handling remain intact.

The reported duplicate second upload is consistent with the lost/identity-only
recovery weaknesses, but no new device trace has been captured after this fix.
The one-tap test below verifies the corrected request sequence and counts locally;
it is not an assertion that the updated client has already succeeded in deployment.

### Storage receiveTimeout

The inspected storage configuration remains unchanged:

- Connect/send/receive timeouts: 30/60/30 seconds. No blind timeout increase.
- Immutable Uint8List bytes pass through Dio's raw binary path with their actual
  length; the transport computes Content-Length. A signed length must match.
- Dio's default MIME-inference interceptor is explicitly removed. No unsigned
  Content-Type is added. Returned signed Content-Type is preserved and must agree
  with the selected MIME; conflicting headers fail without modifying a signature.
- Returned Host must match the signed URL authority, then is generated by the
  native transport rather than manually forwarding a header array. Other returned
  header values and the exact signed URL/query are preserved.
- The storage client has no Laravel Bearer interceptor/default API headers.
  Redirects are disabled. Existing handling accepts 2xx; tests explicitly cover
  HTTP 200, 201 and empty 204 responses before finalize.
- Confirmed failed/non-2xx PUT responses never advance directly to finalize.

A receive timeout means no complete response within 30 seconds. It does **not**
establish whether the bytes were stored. Adapter tests demonstrate that all bytes
may have been sent before the exception. Backend storage/access logs, object
existence/size/MIME and response-completion timing are required to explain the
actual timeout. No signature rejection, proxy failure or storage failure is
claimed without that evidence.

## Safe recovery and state preservation

- Photo selection is local; upload begins only on Save. Both avatar-only and
  avatar-plus-field edits enable Save. Unchanged forms send no empty PATCH.
- Save stages remain uploading, verifying, processing and saving within the
  existing layout. Duplicate saves/selections and competing navigation are blocked.
- Receive/send timeouts, connection loss, unknown transport failures and storage
  HTTP 408/5xx retain the unresolved media ID and original local bytes. The first
  ambiguous PUT failure never triggers finalize or another upload.
- A subsequent explicit Save checks GET for that ID first. Pending is inconclusive
  because presign creates the record before storage: writes remain blocked rather
  than guessing that a pending object is absent or safe to finalize. Malformed or
  unavailable status responses cannot justify new writes either.
- Processing for the same selection resumes bounded polling. Ready permits the
  same ID to be used in PATCH. Failed resolves the previous upload and allows a
  fresh explicit retry. A replaced selection cannot bypass an unresolved record.
- After a successful PUT, an ambiguous/malformed finalize result or processing
  timeout retains the ID without losing confirmed-upload state. Retry reconciles
  through GET, without repeating PUT/finalize. A ready ID is also retained for
  reuse by the same image, including an equal but distinct byte buffer. A documented finalize 409 uses the same read-only recovery path
  immediately, including when the first GET still reports pending.
- Polling is bounded to 15 attempts with two-second gaps. Presign/finalize API
  futures have 30-second deadlines; GET status has a 15-second deadline. These
  are client policies, not claimed backend timing guarantees.
- Ready media is cached for the unchanged selection if PATCH fails, avoiding a
  duplicate upload during profile validation/network retry. Only this verified
  upload path can supply avatar_media_id; draft-injected IDs are excluded.
- Upload/finalize/processing/PATCH failures preserve the existing canonical
  profile/avatar, selected photo and other unsaved fields. Profile 401/422 handling,
  validation, null-versus-omitted semantics and slug mappings remain intact.
- Confirmed PATCH refreshes the existing owner ProfileCubit and returns to Profile.
  A failed follow-up GET uses the existing Profile retry state, without repeating
  an already committed PATCH. Independent caches in unrelated features are not
  rewritten by this feature.
- Session revisions, owner identity and disposal guards prevent late responses
  from advancing the pipeline. Storage is cancelled on session invalidation/close.
  The recovery context remains in-memory, scoped to the open editor/service; it
  is not a durable cross-restart upload queue. Do not restart/reselect to bypass
  a pending uncertainty—resolve the server record first.

## Safe diagnostics

Request observation is opt-in for media/Profile calls and debug-only. Logs show
fixed stages/categories, numeric HTTP status, recognized response Content-Type,
elapsed milliseconds and a schema tree of allowed keys/value types. Known media
status values may appear; URL/string contents, unknown key names, signed headers,
tokens, credentials, raw exceptions and raw response bodies never appear. A bounded
JSON-string shape can be decoded for diagnostics only; parsing behavior remains
strict. Previously removed authentication response/token prints remain removed.

No native configuration, dependency or permission change is needed by this fix.
Recreate the service via a fresh app session before a new diagnostic test. After
an ambiguous upload, keep the editor/context intact while reconciling it.

## Files changed in this first-Save fix

- lib/core/media/media_upload_model.dart — finalize accepts both verified wrappers
  using the existing strict shared validator; presign parsing is unchanged.
- lib/core/media/media_upload_service.dart — retain/reuse ready IDs, compare image
  content rather than only object identity, and distinguish confirmed PUT,
  response-format errors, processing delay and transport uncertainty.
- test/core/media/media_upload_test.dart — update finalize envelope expectations,
  ready-byte-copy reuse and accurate errors after a confirmed upload.
- test/features/profile/avatar_first_save_test.dart — one Save tap drives the real
  Dio/service/repository/Cubit path against adapters returning the exact reported
  HTTP statuses and media wrappers, with exact write counts.
- docs/PROFILE_STAGE5.md — root cause, final contract, recovery and verification.

No Edit Profile UI, Profile fields, native configuration, Stories, Home, Buddies,
Laravel or Figma code was changed in this fix.

## Verification and remaining backend evidence

- Targeted Dart analysis of media, API observation, Profile repository/Cubits and
  media/Profile tests: **no issues found**.
- The standard flutter test --no-pub test/features/profile test/core/media command
  was attempted but could not load tests because the sandbox denies localhost
  socket binding.
- All ten actual focused test files ran with the temporary no-socket
  frontend-server/flutter_tester harness: **123 passed, 0 failed**. This comprises
  63 existing Stage 1–4 regressions, 26 avatar/edit cases, 27 media contract/
  transport/recovery cases, six service-to-Profile integration cases and one new
  first-Save widget test.
- Three new cases cover ready-ID reuse across equal byte buffers, accurate
  confirmed-upload processing feedback, and the exact first-Save sequence:
  presign 201 → raw PUT 200 → finalize 200 media.processing → GET 200 media.ready →
  profile PATCH 200 → profile refresh 200. The widget test taps Save exactly once
  and asserts one presign, one storage PUT and one finalize, an updated canonical
  avatar, and return from Edit Profile with no uncertainty message.
- Updated regressions accept both finalize envelopes, reject malformed responses,
  and assert a confirmed PUT parsing error is not labelled transport uncertainty.
  Existing tests preserve 409/422, avatar-only/combined Save, profile PATCH failure
  retry without upload, stale/session/disposal protection, strict media metadata,
  signed headers/no Bearer and genuine ambiguous-timeout recovery.
- Adapter fixture values are synthetic but reproduce the HTTP statuses and
  envelopes supplied from runtime evidence. No new live server call was made.
  Temporary runner/logs: /private/tmp/travibe-avatar-firstsave-*.

Still required before claiming deployed success:

1. Run a real gallery selection → presign → storage PUT → finalize → GET ready →
   avatar PATCH → profile refresh, including avatar-only and combined edits.
2. Verify that the updated app completes a first Save without another presign or
   PUT. Both deployed media-envelope mismatches are now confirmed and fixed.
   Any remaining response-format error needs its new safe stage/status/shape log.
3. Check storage/proxy/object evidence for the timed-out media. A pending database
   status alone does not prove object existence. Clarify an object-verification or
   idempotent recovery procedure before automating any pending-record finalize.
4. Confirm deployed per-format byte limits and normal processing duration; the
   documented default and illustrative status examples do not prove those values.
5. Device-check gallery permissions, orientation/unsupported formats, real native
   Host generation/signed-header acceptance, network interruption, duplicate taps,
   Back/discard and logout/account changes during each stage.

No deployed end-to-end success or full-project test-suite pass is claimed.
