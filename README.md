# ma-spec

Formal specification documents for the `did:ma` decentralized identifier method,
intended for use with
[W3C DID method registration](https://www.w3.org/TR/did-spec-registries/).

## Documents

### Core did:ma specifications

- [DID Method Specification](did-method-spec.md) — Method syntax, CRUD
  operations, verifiable data registry, security and privacy considerations.
  This is the primary registration document per
  [W3C DID Core Section 8](https://www.w3.org/TR/did-core/#methods).

- [DID Document Format](did-document-format.md) — Document structure, `MultiKey`
  verification method type, `MultiformatSignature2023` proof type,
  core serialization rules, and a complete core example document.

- [did:ma Extension Fields](did-ma-fields-format.md) — Method-specific field
  schema for the top-level `ma` namespace in DID documents.

- [Messaging Format](messaging-format.md) — Signed CBOR messages, content types,
  encryption envelopes, replay protection, and transport-agnostic correlation
  semantics.

- [Access Control v1](access-control-v1.md) — Capability-based ACL model with
  wildcard patterns, per-subject capability grants, owner superuser semantics,
  and evaluation rules.

- [Language Pack Format](lang-pack-format.md) — `lang_cid` manifest schema,
  language-tag to CID mapping, fallback behavior, and merge/normalize workflow.

### Implementation profiles and usage documents

- [ma-publisher spec](ma-publisher-spec.md) — stateless publication service
  profile and actor command surface.

## Status

Draft. Not yet submitted for registration.
