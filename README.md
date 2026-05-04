# 間-spec

Formal specification documents for the `did:ma` decentralized identifier
method, intended for use with
[W3C DID method registration](https://www.w3.org/TR/did-spec-registries/).

`did:ma` is a self-sovereign identity method built on IPFS/IPNS for identity
resolution, CBOR/dag-cbor for wire encoding, Ed25519 for signatures, and iroh
for peer-to-peer transport. Every entity has a globally resolvable DID. Every
interaction is a signed message. There is no shared state, no central server,
no synchronous return channel.

See [HISTORY.md](HISTORY.md) for the design philosophy and influences.

## Document Map

### Identity and Messaging

These documents define the `did:ma` identity layer — DID syntax, document
format, and base message format. They are intentionally minimal: the DID
document and the message envelope are the only shared contracts every
implementation must agree on.

- [did:ma Method Specification](did-ma-spec.md) — Method syntax (`did:ma:<ipns-key>#<fragment>`),
  DID document structure, `Multikey` verification methods, `MultiformatSignature2023`
  proof type (Ed25519 over BLAKE3, multicodec-prefixed), dag-cbor serialization,
  CRUD operations, verifiable data registry, security and privacy considerations.
- [Messaging Format](messaging-format.md) — Signed CBOR message envelope,
  foundational content types (`x-ma-doc`, `x-ma-broadcast`, `x-ma-message`),
  encryption envelope, replay protection, correlation semantics.

### Core Extensions

The core documents define field extensions, service protocols, and transport
profiles. Implementations pick up what they need; nothing in `core/` is
required unless the relevant service or transport is advertised.

- [ma Field Extensions](core/ma-did-ma-fields.md) — The `ma` key in DID
  documents: `ma.services` (inbox, rpc, ipfs), `ma.kind` hint, transport
  profiles, conformance.
- [RPC Service Protocol](core/ma-rpc-service-v1.md) — `/ma/rpc/0.0.1`:
  `application/x-ma-rpc` and `application/x-ma-rpc-reply` content types,
  CBOR term format (atoms and tuples), reply conventions, protocol mismatch
  handling.
- [iroh Transport Profile](core/iroh-transport.md) — `ma.iroh` field
  requirements, endpoint normalisation, startup reconciliation, connect
  resolution. iroh is currently the only standardised transport.
- [Pub/Sub Transport](core/pubsub.md) — Optional gossip layer (iroh-gossip)
  for discovery and announcements. Not required; absent when unavailable.

### Runtime

> **Work in progress.** These documents are incomplete and unstable.
> Do not use them as a basis for implementation yet.

## Status

Draft. Not yet submitted for W3C DID method registration.

Aligned with W3C DID v1.1 (`@context`, media type, `Multikey` naming).
