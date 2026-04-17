# ma-core Specifications

Implementation-level specifications for the `ma-core` runtime library.

`ma-core` builds on the base [`did:ma` method specification](../README.md)
and provides the messaging primitives, service model, and transport layer that
applications use to send and receive messages between DID-identified endpoints.

## Relationship to did:ma

The parent directory defines the foundational `did:ma` layer: DID syntax,
document format, extension fields, and messaging format. This directory
specifies the **runtime primitives** that sit on top of that base layer — the
inbox, outbox, service model, pub/sub topics, and transport advertisement that
application developers use directly.

## Documents

| Document | Scope |
| --- | --- |
| [services.md](services.md) | Inbox, outbox, service model, protocol identifiers, service registration, transport advertisement. |
| [pubsub.md](pubsub.md) | Gossip pub/sub transport, topic primitive, well-known topics, sender blocking, transport abstraction. |

The `application/x-ma-ipfs-request` content type used by the IPFS publishing
service is defined in the base [messaging format](../messaging-format.md) §2.2.

## Design Principles

- **Actor model.** Every entity communicates exclusively by sending asynchronous
  messages. No shared state, no synchronous calls, no return channels at the
  transport level.
- **One-way fire-and-forget.** The transport is strictly one-way. Correlation is
  expressed in message content (`replyTo`), not in the transport.
- **Strict validation.** Never mutate malformed data. Reject invalid messages
  before they enter an inbox.
- **BLAKE3 everywhere.** Content hashing, topic IDs, key derivation — all use
  BLAKE3.

## Reference Implementation

The Rust crate [`ma-core`](https://github.com/bahner/rust-ma-core) implements
these specifications.

## Status

Draft. All documents are versioned independently.
