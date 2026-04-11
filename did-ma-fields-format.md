# did:ma Extension Fields (`ma` namespace)

**Version:** 0.0.1
**Status:** Draft

## Abstract

This document specifies the `ma` method-specific extension namespace used inside
`did:ma` DID documents.

The base DID document structure, proof format, and serialization rules are
specified in `did-document-format.md`.

## 1. Namespace Rules

All `did:ma` method-specific fields MUST appear under the top-level `ma` key.
No method-specific fields are permitted outside this namespace.

When present, `ma` MUST be a JSON object.

## 2. Field Definitions

The `ma` object contains optional fields. Unknown fields MUST be ignored by
consumers unless a stricter profile says otherwise.

| Property | JSON Key | Type | Requirement | Description |
| --- | --- | --- | --- | --- |
| Inbox | `inbox` | string | agent, world | Identifier of the currently active inbox/mailbox. |
| Requested TTL | `requestedTTL` | integer | agent | Preferred message retention/caching window in seconds for inbox recipients. |
| Language | `language` | string | agent | Preferred language priority list in GNU `LANGUAGE` format (colon-separated locales, for example `nb_NO:en_UK:en`). |
| Type | `type` | string | * | Subject/entity type label. Allowed values: `avatar`, `agent`, `world`, `room`, `object`. |
| Transports | `transports` | object or array | agent,world  | Transport/protocol capability hints. |

All fields are optional and are omitted from serialization when null.

## 3. Correlation With Base DID Format

The base DID document format remains authoritative for:

- `@context`, `id`, `controller`
- `verificationMethod`, `assertionMethod`, `keyAgreement`
- `proof`
- JSON/CBOR serialization rules

This extension document only defines the schema under `ma`.

## 4. Example (`ma` section only)

```json
{
  "ma": {
    "currentInbox": "/iroh/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/ma/inbox/1",
    "world": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr",
    "transports": {
		"/iroh/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/ma/inbox/1",
    }
  }
}
```

## 5. Notes on Profiles

Runtime profiles (for example world simulation behavior, command UX, or lane
policy) are not defined here. They may define stricter constraints on these
fields in profile-specific documents.
