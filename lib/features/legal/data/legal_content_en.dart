import 'legal_document.dart';

const _updated = 'Last updated: 14 November 2026 (draft)';
const _effective = 'Effective date: [To confirm before publication]';
const _review =
    'Draft — requires legal review before publication. Bracketed items require confirmation. Travibe is the product name; the legal operator has not been identified in this draft.';

const termsEn = LegalDocument(
  type: LegalDocumentType.terms,
  languageCode: 'en',
  title: 'Terms of Service',
  lastUpdatedText: _updated,
  effectiveDateText: _effective,
  versionLabel: 'Document version',
  reviewNotice: _review,
  introduction:
      'These draft terms describe proposed rules for using Travibe, a travel and social application. They are not a published agreement. [To confirm: the operator’s legal name, address, applicable law, dispute process and territories served.]',
  relatedDocumentLabel: 'Read the Privacy Policy',
  sections: [
    LegalSection(
      id: 'acceptance',
      heading: '1. Acceptance of Terms',
      body:
          'Review the approved terms and privacy notice before creating an account. The registration form records an affirmative terms-acceptance choice; opening a legal page does not select that choice. [To confirm: when the agreement becomes binding, the applicable document version and any process for renewed acceptance.]',
    ),
    LegalSection(
      id: 'eligibility',
      heading: '2. Eligibility and Accounts',
      body:
          'Provide accurate account information and keep it up to date. Access to some features requires email verification and profile setup. Do not impersonate someone else or create an account without authority to do so. [To confirm: minimum age, any guardian-consent requirements and regional eligibility rules. No age threshold is established by this draft.]',
    ),
    LegalSection(
      id: 'security',
      heading: '3. Account Security',
      body:
          'Keep your password and sign-in credentials private. Use the account security and sign-out controls when needed. If you suspect unauthorized access, use the available recovery tools and the contact channel once confirmed below. Avoid sharing access tokens or verification codes. This draft does not promise that all unauthorized activity can be prevented.',
    ),
    LegalSection(
      id: 'user-content',
      heading: '4. User-Generated Content',
      body:
          'You are responsible for posts, stories, comments, messages and media you submit. Share only material you have a right to use, and respect other people’s privacy and rights. Audience and privacy settings affect availability within Travibe; recipients may still keep copies or screenshots. Do not publish sensitive information about others without an appropriate basis.',
    ),
    LegalSection(
      id: 'ownership',
      heading: '5. Content Ownership and Permissions',
      body:
          'The intended approach is that you retain ownership of your content. Operating social features requires permission to host, process, display and transmit the content you choose to share. [For legal review: define a limited service-operation licence, its scope, duration, any sublicensing to service providers, and what happens after content or account deletion. This draft does not grant an unlimited ownership transfer.]',
    ),
    LegalSection(
      id: 'community',
      heading: '6. Community Guidelines',
      body:
          'Treat other people respectfully. Do not use Travibe for threats, harassment, hateful abuse, exploitation, unlawful content, non-consensual intimate material or deceptive impersonation. [For legal review: approve detailed community standards, moderation criteria, notice procedures and any appeal process before publication.]',
    ),
    LegalSection(
      id: 'social-messaging',
      heading: '7. Posts, Stories and Messaging',
      body:
          'Visibility, message requests, read information and availability depend on feature settings and access permissions. Story expiry in the application should not be understood as a promise that every stored copy is immediately erased. Do not assume messages are end-to-end encrypted or that recipients cannot copy them. [To confirm: final messaging, story lifecycle and moderation disclosures.]',
    ),
    LegalSection(
      id: 'reporting',
      heading: '8. Reporting and Blocking',
      body:
          'Use the available reporting and blocking controls for unwanted activity. Blocking affects supported interactions and content access; it cannot remove copies already held outside Travibe. A report does not guarantee a particular action or response time. [To confirm: review workflow, escalation contacts and any appeal or legally required complaint mechanisms.]',
    ),
    LegalSection(
      id: 'travel',
      heading: '9. Travel Discovery and Third-Party Booking',
      body:
          'Travel-related information and user recommendations may be incomplete or out of date. Verify safety, entry requirements, prices and booking conditions with authoritative sources and the relevant provider. This app implementation does not establish a Travibe booking or payment service. If an external travel service is offered, review its own terms before using it. [To confirm: any providers, commercial relationships and division of booking responsibilities.]',
    ),
    LegalSection(
      id: 'prohibited',
      heading: '10. Prohibited Activities',
      body:
          'Do not misuse accounts, send spam, distribute malware, evade access restrictions, probe other users’ private data or interfere with the service. Do not copy or collect data in ways that violate others’ rights or applicable rules. [For legal review: approve any additional automated-access, commercial-use and enforcement restrictions.]',
    ),
    LegalSection(
      id: 'intellectual-property',
      heading: '11. Intellectual Property',
      body:
          'Respect rights in the Travibe name, application design, software and third-party materials. Using the application does not itself transfer ownership of those materials. User content is addressed separately above. [To confirm: the relevant rights holders, permitted use of brand assets and an infringement-notice process.]',
    ),
    LegalSection(
      id: 'termination',
      heading: '12. Account Suspension and Termination',
      body:
          'Account deletion is available through Settings and requires the confirmation steps shown there. Signing out is different from deleting an account. [For legal review: specify grounds for restrictions or termination, notice and appeal rights, effects on content and any obligations that survive termination. Do not treat this draft as an unrestricted right to suspend accounts.]',
    ),
    LegalSection(
      id: 'liability',
      heading: '13. Disclaimers and Liability',
      body:
          'User content and travel information should be evaluated independently. Connectivity, software faults and third-party services may affect availability; do not rely on Travibe as an emergency service. [For legal review: determine lawful warranties, exclusions, liability limits and mandatory consumer protections for the applicable jurisdictions. No monetary liability cap or waiver of non-excludable rights is specified here.]',
    ),
    LegalSection(
      id: 'changes',
      heading: '14. Changes to Terms',
      body:
          'Approved documents should carry a version, last-updated date and effective date. [To confirm: how material changes will be communicated, any notice period and when renewed agreement is required.] This local draft is not a claim that a public web version has already been published.',
    ),
    LegalSection(
      id: 'contact',
      heading: '15. Contact Information',
      body:
          '[To confirm before publication: operator’s legal name, postal address, support/legal email and an appropriate channel for legal notices.] Travibe is used here only as the application’s product name. No registered company name or contact address is asserted.',
    ),
  ],
);

const privacyEn = LegalDocument(
  type: LegalDocumentType.privacy,
  languageCode: 'en',
  title: 'Privacy Policy',
  lastUpdatedText: _updated,
  effectiveDateText: _effective,
  versionLabel: 'Document version',
  reviewNotice: _review,
  introduction:
      'This draft explains data flows observed in the Travibe application and its documented API. It must be checked against actual server operations, provider contracts and applicable law. [To confirm: the responsible operator/controller, jurisdictions and legal grounds for processing.]',
  relatedDocumentLabel: 'Read the Terms of Service',
  sections: [
    LegalSection(
      id: 'collection',
      heading: '1. Information We Collect',
      body:
          'Information used by the implemented features includes registration details, profile information, social content, account relationships, selected locations, device/session information and notification preferences. Some information comes from your input and some from feature activity. The sections below distinguish these uses. [To confirm: server-side logs, any additional collection, analytics or advertising practices; the client code alone cannot establish their absence.]',
    ),
    LegalSection(
      id: 'profile',
      heading: '2. Account and Profile Information',
      body:
          'Registration uses an email address, password, device name, language and acceptance choice. Profile features may use a name, username, avatar, nationality, city/country, gender, bio, languages, interests and travel styles. Settings include language, currency, account privacy, active status, buddy visibility and notifications. What others see depends on supported settings and server access rules. [To confirm: required fields and final audience disclosures.]',
    ),
    LegalSection(
      id: 'content',
      heading: '3. Posts, Stories, Messages and Media',
      body:
          'The service processes content and media you submit, comments, likes, saves, follows, blocks and reports to support the related features. Messaging uses server APIs and realtime events, including message requests, typing, presence and delivery/read information where supported. Uploads use authorized storage requests. Do not assume end-to-end encryption or guaranteed screenshot prevention. [To confirm: storage providers, access controls, moderation access and media processing arrangements.]',
    ),
    LegalSection(
      id: 'location',
      heading: '4. Location Data and Permissions',
      body:
          'You can select a city manually. The implemented device-location action requests operating-system permission when you choose to use it, obtains foreground coordinates and uses them to help resolve/update a location for relevant features. City search and reverse lookup send the typed query or coordinates to Photon at photon.komoot.io; these requests use separate transport without your Travibe bearer token. Camera, photo and microphone access is requested for related media actions. You can manage permissions in device settings. [To confirm: location visibility, provider terms and server retention.]',
    ),
    LegalSection(
      id: 'device',
      heading: '5. Device Information',
      body:
          'Authentication uses a device name and session credentials. The app stores preferences, authentication/session state and some cached data on the device; chat history/drafts also use session-scoped memory. Operating-system notification permissions and device platform are used by push features. [To confirm: all server/network logs, diagnostic identifiers, cache lifetimes and device-data retention. No claim of encrypted local storage is made.]',
    ),
    LegalSection(
      id: 'firebase',
      heading: '6. Firebase and Push Notifications',
      body:
          'Firebase Core and Firebase Cloud Messaging are integrated for push delivery. When available and permitted, an FCM registration token and device platform are registered with the authenticated Laravel account. Token refresh, permission changes, sign-out and account changes trigger synchronization or cleanup attempts. Apple push services are involved on iOS. Notifications can also be loaded from Laravel when push is unavailable. [To confirm: provider processing terms, delivery payload contents, notification display rules and retention.]',
    ),
    LegalSection(
      id: 'use',
      heading: '7. How Information Is Used',
      body:
          'Implemented uses include account creation and verification, profile presentation, content sharing, social interactions, search/discovery, messaging, notifications, privacy settings and account management. Location choices support relevant city and buddy features. [To confirm: the legal basis for each purpose, any additional operational uses and whether any optional processing requires a separate choice. Registration acceptance is not described as blanket consent for all processing.]',
    ),
    LegalSection(
      id: 'sharing',
      heading: '8. Data Sharing',
      body:
          'Content and profile information are made available to other users according to supported audience and access rules; messages are transmitted to the relevant conversation participants. Data is also processed through the service infrastructure, authorized media storage, Firebase/Apple push delivery and the city-lookup service described above. [To confirm: the full recipient/subprocessor list, hosting operators, legal disclosure practices and any sale, advertising or business-transfer practices. None is presumed from the app alone.]',
    ),
    LegalSection(
      id: 'travel',
      heading: '9. Third-Party Travel Services',
      body:
          'A travel provider you choose to visit may apply its own privacy policy and collect information directly. The inspected app does not establish a completed booking/payment integration or a list of booking partners. [To confirm before enabling any such service: provider identities, links, information exchanged, tracking and the allocation of responsibilities.]',
    ),
    LegalSection(
      id: 'security',
      heading: '10. Security',
      body:
          'The client uses HTTPS API requests, authenticated access and session-aware request/state guards. These implementation measures do not establish every server-side safeguard or guarantee security. Do not share credentials or verification codes. [To confirm: hosting/storage security, encryption at rest, access monitoring, incident handling and breach-notification procedures.]',
    ),
    LegalSection(
      id: 'retention',
      heading: '11. Data Retention',
      body:
          'The app includes content-removal, story-expiry and account-deletion functions, but feature visibility is not proof that every backup, log or retained copy is erased. Some local caches are cleared with session changes; other preference behavior is feature-specific. [To confirm: purpose-based retention schedules for accounts, content, messages, reports, media, device tokens, logs and backups, including any legal holds. No fixed period is asserted.]',
    ),
    LegalSection(
      id: 'deletion',
      heading: '12. Account and Data Deletion',
      body:
          'You can request account deletion through Settings using the authentication and confirmation steps shown there. The documented account endpoint describes deletion of the account and associated service records/media; the app clears the local session after a confirmed response. Signing out alone is not deletion. [To confirm: actual operational coverage, timing, exceptions, backups, legal retention and data already copied by other people. This draft does not promise complete immediate erasure everywhere.]',
    ),
    LegalSection(
      id: 'rights',
      heading: '13. User Privacy Rights',
      body:
          'Depending on the law that applies, you may have rights to access, correct, erase or obtain data, object to or restrict processing, withdraw consent where relevant, or complain to a competent authority. Existing profile, privacy, permission and deletion controls provide some choices within the app. [To confirm: applicable rights, request channel, identity verification, response deadlines and regulator details. These rights are not presented as identical in every jurisdiction.]',
    ),
    LegalSection(
      id: 'children',
      heading: '14. Children’s Privacy',
      body:
          '[To confirm before publication: minimum age, intended audiences, any guardian-consent requirements and how information relating to children will be handled.] No age limit or parental-verification process is invented in this draft. Concerns about a child’s information should be directed to the privacy contact once it has been confirmed below.',
    ),
    LegalSection(
      id: 'transfers',
      heading: '15. International Transfers',
      body:
          'Using hosting, storage and notification providers may involve processing in more than one country. [To confirm: actual storage/processing locations, relevant transfer rules and safeguards, and how users can obtain further information.] No particular hosting country, adequacy decision or contractual safeguard is assumed.',
    ),
    LegalSection(
      id: 'changes',
      heading: '16. Policy Changes',
      body:
          'Approved notices should identify their version and update/effective dates. [To confirm: publication and notification procedures, how material changes are communicated and any additional choices needed for a new use.] Preferred public hosting locations are not treated as live or approved until deployment is verified.',
    ),
    LegalSection(
      id: 'contact',
      heading: '17. Contact Information',
      body:
          '[To confirm before publication: responsible operator/controller’s legal identity, postal address, privacy email, rights-request channel and any required representative or data-protection contact.] Travibe is the product name and is not represented here as a registered legal entity.',
    ),
  ],
);
