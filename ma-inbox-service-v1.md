# Inbox Service Protocol

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines the `/ma/inbox/0.0.1` service protocol: its accepted
content types, delivery semantics, TTL handling, and protocol mismatch rules.

**Applicable to:** Any `did:ma` actor that receives point-to-point or
broadcast messages — full 間 runtimes, minimal actors (fortune-cookie,
sensor feeds), and browser-based actors (ego). All actors SHOULD implement
this service; it is the only service required for receiving text and chat
messages.

## 1. Service Protocol

`/ma/inbox/0.0.1` is the general-purpose message delivery channel. It accepts
any signed, well-formed `application/x-ma-*` message or `text/plain` payload
that the receiver chooses to handle.

Service-specific protocols (`/ma/rpc/0.0.1`, `/ma/crud/0.0.1`,
`/ma/ipfs/0.0.1`) carry their own content types and MUST NOT be delivered via
this service.

## 2. Accepted Content Types

| Type | Encryption | Notes |
| --- | --- | --- |
| `application/x-ma-message` | Required | Generic point-to-point envelope |
| `application/x-ma-broadcast` | Forbidden | Signed broadcast; `to` SHOULD be absent |
| `application/x-ma-chat` | Required | Ephemeral real-time message; see [ma-chat-messages-v1.md](ma-chat-messages-v1.md) |
| `application/x-ma-emote` | Required | Emote/action message; see [ma-emote-messages-v1.md](ma-emote-messages-v1.md) |
| `text/plain` | Required | Raw UTF-8 text; no semantic beyond human-readable content |

Additional `application/x-ma-*` types defined by messaging profiles (under
`messaging/`) are delivered via this service unless their specification
explicitly assigns them to a different protocol.

Receivers MUST reject messages whose `contentType` belongs to another service
(e.g. `application/x-ma-rpc`, `application/x-ma-crud-*`).

## 3. Delivery Semantics

### 3.1 Ordering

Messages are delivered in the order they arrive on the iroh QUIC stream.
No global ordering across multiple senders is guaranteed.

### 3.2 Persistence

Receivers MAY persist messages in a local mailbox. Persistence policy is
implementation-defined. `application/x-ma-chat` explicitly opts out of
required persistence (see [ma-chat-messages-v1.md](ma-chat-messages-v1.md) §1).

### 3.3 Replies

A reply MUST set `replyTo` to the originating message `id`
(see [ma-messaging-format-v1.md](ma-messaging-format-v1.md) §1.3). Replies are
delivered via the same `/ma/inbox/0.0.1` service.

## 4. TTL and Expiry

Each message carries an `exp` field (nanosecond epoch timestamp). Receivers:

1. MUST discard messages whose `exp` has passed at the time of receipt.
2. SHOULD prune persisted messages whose `exp` has passed on startup or
   periodic maintenance.
3. MUST treat `exp = 0` as never-expiring.

The default TTL is one hour (`now + 3_600_000_000_000 ns`), as defined in
[ma-messaging-format-v1.md](ma-messaging-format-v1.md) §1.1.

## 5. Access Control

Receivers MAY apply an ACL (see [ma-acl-v1.md](ma-acl-v1.md))
to incoming messages using the `inbox` capability. Replies (`replyTo` set)
SHOULD bypass ACL checks — they are correlated responses, not unsolicited
messages.

## 6. Protocol Mismatch

If a message arrives on `/ma/inbox/0.0.1` with a `contentType` that belongs
to a different service, the receiver MUST drop it silently. No error reply
is sent.

If a receiver does not recognise a `contentType` at all, it MAY drop the
message silently or deliver it to a catch-all handler.

## References

- [did:ma Messaging Format](ma-messaging-format-v1.md)
- [Chat Message Type](ma-chat-messages-v1.md)
- [Emote Message Type](ma-emote-messages-v1.md)
- [ACL Model v1](ma-acl-v1.md)
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
