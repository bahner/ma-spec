# ma-spec

Formal specification documents for the `did:ma` decentralized identifier method,
intended for use with
[W3C DID method registration](https://www.w3.org/TR/did-spec-registries/).

## Documents

- [DID Method Specification](did-method-spec.md) — Method syntax, CRUD
  operations, verifiable data registry, security and privacy considerations.
  This is the primary registration document per
  [W3C DID Core Section 8](https://www.w3.org/TR/did-core/#methods).
- [DID Document Format](did-document-format.md) — Document structure, `MultiKey`
  verification method type, `MultiformatSignature2023` proof type,
  core serialization rules, and a complete core example document.
- [Extension Fields Format](did-ma-fields-format.md) — Method-specific `ma`
  namespace: reserved field names, structural constraints, and implementation
  profile requirements.
- [Messaging Format](messaging-format.md) — Signed CBOR messages, content types,
  encryption envelopes, replay protection, and transport-agnostic correlation
  semantics.

Realm-specific specifications (type profiles, ACL, transport, world DAG
structure) live in
[ma-realms/spec](https://github.com/bahner/ma-realms/tree/main/spec).

## Status

Draft. Not yet submitted for registration.
