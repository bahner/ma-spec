# 間-spec

Formal specification documents for the `did:ma` decentralized identifier
method, intended for use with
[W3C DID method registration](https://www.w3.org/TR/did-spec-registries/).

`did:ma` is a self-sovereign identity method built on IPFS/IPNS for identity
resolution, CBOR/dag-cbor for wire encoding, Ed25519 for signatures, and iroh
for peer-to-peer transport. Every entity has a globally resolvable DID. Every
interaction is a signed message. There is no shared state, no central server,
no synchronous return channel.

## Architecture — three layers

The specifications are organized in layers. Each layer builds on the one
below it, and each is useful on its own. The lower the layer, the fewer
requirements it imposes.

```
┌────────────────────────────────────────────────────────────┐
│  clients          zion (browser), zscheme (CLI)            │
│                   → zscheme/                               │
├────────────────────────────────────────────────────────────┤
│  runtime          ma-runtime: a full actor framework       │
│                   → runtime/                               │
├────────────────────────────────────────────────────────────┤
│  core             recommended interop conventions:         │
│                   services, message types, ACL             │
│                   → core/                                  │
├────────────────────────────────────────────────────────────┤
│  identity         did:ma method + message envelope         │
│                   → did-ma-spec-v1.md (this directory)     │
└────────────────────────────────────────────────────────────┘
```

- **Identity (root).** [did:ma Method Specification](did-ma-spec-v1.md) and
  the [Messaging Format](core/ma-messaging-format-v1.md) are the only shared
  contracts every implementation must agree on. You can use `did:ma` as a
  plain DID method with signed messaging and ignore everything else in this
  repository.
- **Core ([core/](core/README.md)).** Recommended standards: service
  protocols (RPC, inbox, IPFS publishing), message types (chat,
  emote), the `ma` DID document fields, and the ACL model. Nothing here is
  required to use `did:ma` as a DID — but they are required to interoperate
  with a runtime, and strongly recommended for any implementation that wants
  to talk to others.
- **Runtime ([runtime/](runtime/README.md)).** The normative specification
  of *one* framework built on the layers below: `ma-runtime`, a full actor
  framework geared towards multi-user text-based virtual reality. Entities,
  kinds, plugins, standard actors, avatars, schedules, CRUD.
- **Clients ([zscheme/](zscheme/README.md)).** zion and zscheme are clients
  — users of the framework, not part of it. This layer specifies the
  embedded Scheme evaluator they share.

## Where should I look?

| You are… | Read |
|---|---|
| A user of zion / zscheme | The [zscheme handbook and reference](https://github.com/bahner/ma-scheme) — no spec reading required |
| A client developer | [core/](core/README.md), then [zscheme/](zscheme/README.md) |
| A runtime developer | [runtime/](runtime/README.md) and [core/](core/README.md) — build on the [ma-core](https://crates.io/crates/ma-core) Rust crate |
| A DID method implementor | [did-ma-spec-v1.md](did-ma-spec-v1.md) and [core/ma-messaging-format-v1.md](core/ma-messaging-format-v1.md) only |

## Document Map

### Identity and Messaging

These documents define the `did:ma` identity layer — DID syntax, document
format, and base message format. They are intentionally minimal: the DID
document and the message envelope are the only shared contracts every
implementation must agree on.

- [did:ma Method Specification](did-ma-spec-v1.md) — Method syntax (`did:ma:<ipns-key>#<fragment>`),
  DID document structure, `Multikey` verification methods, `MultiformatSignature2023`
  proof type (Ed25519 over BLAKE3, multicodec-prefixed), dag-cbor serialization,
  CRUD operations, verifiable data registry, security and privacy considerations.
- [Messaging Format](core/ma-messaging-format-v1.md) — Signed CBOR message envelope,
  foundational message types (`vnd.ma.doc`, `vnd.ma.broadcast`, `vnd.ma.message`),
  encryption envelope, replay protection, correlation semantics.

### Core conventions — [core/](core/README.md)

Field extensions, service protocols, message types, and the ACL model.
Recommended standards — not required for plain DID use, required for
runtime interoperability. See [core/README.md](core/README.md).

### Runtime — [runtime/](runtime/README.md)

The `ma-runtime` actor framework: manifest, entities and kinds, standard
actors, avatar, schedules, CRUD service.
See [runtime/README.md](runtime/README.md).

### Clients — [zscheme/](zscheme/README.md)

The embedded Scheme evaluator shared by the zion and zscheme clients.
See [zscheme/README.md](zscheme/README.md).

## Status

Version 1.0.0 Candidate Recommendation. Prepared for W3C DID method
registration review.

Aligned with W3C DID v1.1 (`@context`, media type, `Multikey` naming).
