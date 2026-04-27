# ma-spec

Formal specification documents for the `did:ma` decentralized identifier method,
intended for use with
[W3C DID method registration](https://www.w3.org/TR/did-spec-registries/).

See [HISTORY.md](HISTORY.md) for the design philosophy and influences behind
`did:ma`.

## Documents

The base spec defines the `did:ma` identity layer — DID syntax, document
format, and wire-level messaging. The core spec defines the runtime primitives
that implement it — inbox, outbox, services, and pub/sub. If you are building
on `did:ma`, start with the core docs. Refer to the base docs when you need
the cryptographic or serialization details.

### Base Specification

- [DID Method Specification](did-method-spec.md) — Method syntax, CRUD
  operations, verifiable data registry, security and privacy considerations.
- [DID Document Format](did-document-format.md) — Document structure, `Multikey`
  verification methods, `MultiformatSignature2023` proof type, serialization.
- [Messaging Format](messaging-format.md) — Signed CBOR messages, content types,
  encryption envelopes, replay protection, correlation semantics.

### Core Runtime Specification

Reference implementation: [`ma-core`](https://github.com/bahner/rust-ma-core)
(Rust).

- [Field Extensions Format](runtime/did-ma-fields.md) — Unified `ma`
  namespace format and runtime requirements for `ma.services` and `ma.iroh`.
- [Pub/Sub Transport](runtime/pubsub.md) — Gossip pub/sub, topic primitive,
  well-known topics, sender blocking, transport abstraction.

## Status

Draft. Not yet submitted for registration.

Current draft set is aligned with W3C DID v1.1 (`@context`, media type, and
`Multikey` naming).
