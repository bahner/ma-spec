# ma-spec

Formal specification documents for the `did:ma` decentralized identifier method,
intended for use with
[W3C DID method registration](https://www.w3.org/TR/did-spec-registries/).

See [HISTORY.md](HISTORY.md) for the design philosophy and influences behind
`did:ma`.

## Documents

The base documents define the identity and messaging layer. Read these first:

- [DID Method Specification](did-method-spec.md) — Method syntax, CRUD
  operations, verifiable data registry, security and privacy considerations.
  This is the primary registration document per
  [W3C DID v1.1 Section 7](https://www.w3.org/TR/did-1.1/#methods).
- [DID Document Format](did-document-format.md) — Document structure, `Multikey`
  verification method type, `MultiformatSignature2023` proof type,
  core serialization rules, and a complete core example document.
- [Extension Fields Format](did-ma-fields-format.md) — Method-specific `ma`
  namespace: reserved field names, structural constraints, and implementation
  profile requirements.
- [Messaging Format](messaging-format.md) — Signed CBOR messages, content types,
  encryption envelopes, replay protection, and transport-agnostic correlation
  semantics.

## Core Runtime Specifications

**If you are building on `did:ma`, read these next.** The [core/](core/)
directory specifies the runtime primitives that developers actually use: inbox,
outbox, service model, pub/sub, and transport advertisement. The base documents
above define the wire format; the core specs define how to send and receive
messages in practice.

The reference implementation is [`ma-core`](https://github.com/bahner/rust-ma-core)
(Rust).

- [Services and Transport](core/services.md) — Inbox, outbox, service model,
  protocol identifiers, service registration, and transport advertisement.
- [Pub/Sub Transport](core/pubsub.md) — Gossip pub/sub transport, topic
  primitive, well-known topics, sender blocking, and transport abstraction.

## Status

Draft. Not yet submitted for registration.

Current draft set is aligned with W3C DID v1.1 (`@context`, media type, and
`Multikey` naming).
