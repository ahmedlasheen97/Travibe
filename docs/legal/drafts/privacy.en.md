# Privacy Policy

> Draft — requires legal review before publication. Bracketed items require confirmation. Travibe is the product name; the legal operator has not been identified in this draft.

Last updated: 14 November 2026 (draft)

Effective date: [To confirm before publication]

Document version: draft-2026-11-14.1

This draft explains data flows observed in the Travibe application and its documented API. It must be checked against actual server operations, provider contracts and applicable law. [To confirm: the responsible operator/controller, jurisdictions and legal grounds for processing.]

## 1. Information We Collect

Information used by the implemented features includes registration details, profile information, social content, account relationships, selected locations, device/session information and notification preferences. Some information comes from your input and some from feature activity. The sections below distinguish these uses. [To confirm: server-side logs, any additional collection, analytics or advertising practices; the client code alone cannot establish their absence.]

## 2. Account and Profile Information

Registration uses an email address, password, device name, language and acceptance choice. Profile features may use a name, username, avatar, nationality, city/country, gender, bio, languages, interests and travel styles. Settings include language, currency, account privacy, active status, buddy visibility and notifications. What others see depends on supported settings and server access rules. [To confirm: required fields and final audience disclosures.]

## 3. Posts, Stories, Messages and Media

The service processes content and media you submit, comments, likes, saves, follows, blocks and reports to support the related features. Messaging uses server APIs and realtime events, including message requests, typing, presence and delivery/read information where supported. Uploads use authorized storage requests. Do not assume end-to-end encryption or guaranteed screenshot prevention. [To confirm: storage providers, access controls, moderation access and media processing arrangements.]

## 4. Location Data and Permissions

You can select a city manually. The implemented device-location action requests operating-system permission when you choose to use it, obtains foreground coordinates and uses them to help resolve/update a location for relevant features. City search and reverse lookup send the typed query or coordinates to Photon at photon.komoot.io; these requests use separate transport without your Travibe bearer token. Camera, photo and microphone access is requested for related media actions. You can manage permissions in device settings. [To confirm: location visibility, provider terms and server retention.]

## 5. Device Information

Authentication uses a device name and session credentials. The app stores preferences, authentication/session state and some cached data on the device; chat history/drafts also use session-scoped memory. Operating-system notification permissions and device platform are used by push features. [To confirm: all server/network logs, diagnostic identifiers, cache lifetimes and device-data retention. No claim of encrypted local storage is made.]

## 6. Firebase and Push Notifications

Firebase Core and Firebase Cloud Messaging are integrated for push delivery. When available and permitted, an FCM registration token and device platform are registered with the authenticated Laravel account. Token refresh, permission changes, sign-out and account changes trigger synchronization or cleanup attempts. Apple push services are involved on iOS. Notifications can also be loaded from Laravel when push is unavailable. [To confirm: provider processing terms, delivery payload contents, notification display rules and retention.]

## 7. How Information Is Used

Implemented uses include account creation and verification, profile presentation, content sharing, social interactions, search/discovery, messaging, notifications, privacy settings and account management. Location choices support relevant city and buddy features. [To confirm: the legal basis for each purpose, any additional operational uses and whether any optional processing requires a separate choice. Registration acceptance is not described as blanket consent for all processing.]

## 8. Data Sharing

Content and profile information are made available to other users according to supported audience and access rules; messages are transmitted to the relevant conversation participants. Data is also processed through the service infrastructure, authorized media storage, Firebase/Apple push delivery and the city-lookup service described above. [To confirm: the full recipient/subprocessor list, hosting operators, legal disclosure practices and any sale, advertising or business-transfer practices. None is presumed from the app alone.]

## 9. Third-Party Travel Services

A travel provider you choose to visit may apply its own privacy policy and collect information directly. The inspected app does not establish a completed booking/payment integration or a list of booking partners. [To confirm before enabling any such service: provider identities, links, information exchanged, tracking and the allocation of responsibilities.]

## 10. Security

The client uses HTTPS API requests, authenticated access and session-aware request/state guards. These implementation measures do not establish every server-side safeguard or guarantee security. Do not share credentials or verification codes. [To confirm: hosting/storage security, encryption at rest, access monitoring, incident handling and breach-notification procedures.]

## 11. Data Retention

The app includes content-removal, story-expiry and account-deletion functions, but feature visibility is not proof that every backup, log or retained copy is erased. Some local caches are cleared with session changes; other preference behavior is feature-specific. [To confirm: purpose-based retention schedules for accounts, content, messages, reports, media, device tokens, logs and backups, including any legal holds. No fixed period is asserted.]

## 12. Account and Data Deletion

You can request account deletion through Settings using the authentication and confirmation steps shown there. The documented account endpoint describes deletion of the account and associated service records/media; the app clears the local session after a confirmed response. Signing out alone is not deletion. [To confirm: actual operational coverage, timing, exceptions, backups, legal retention and data already copied by other people. This draft does not promise complete immediate erasure everywhere.]

## 13. User Privacy Rights

Depending on the law that applies, you may have rights to access, correct, erase or obtain data, object to or restrict processing, withdraw consent where relevant, or complain to a competent authority. Existing profile, privacy, permission and deletion controls provide some choices within the app. [To confirm: applicable rights, request channel, identity verification, response deadlines and regulator details. These rights are not presented as identical in every jurisdiction.]

## 14. Children’s Privacy

[To confirm before publication: minimum age, intended audiences, any guardian-consent requirements and how information relating to children will be handled.] No age limit or parental-verification process is invented in this draft. Concerns about a child’s information should be directed to the privacy contact once it has been confirmed below.

## 15. International Transfers

Using hosting, storage and notification providers may involve processing in more than one country. [To confirm: actual storage/processing locations, relevant transfer rules and safeguards, and how users can obtain further information.] No particular hosting country, adequacy decision or contractual safeguard is assumed.

## 16. Policy Changes

Approved notices should identify their version and update/effective dates. [To confirm: publication and notification procedures, how material changes are communicated and any additional choices needed for a new use.] Preferred public hosting locations are not treated as live or approved until deployment is verified.

## 17. Contact Information

[To confirm before publication: responsible operator/controller’s legal identity, postal address, privacy email, rights-request channel and any required representative or data-protection contact.] Travibe is the product name and is not represented here as a registered legal entity.

