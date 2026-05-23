# Chat Message Type

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines `application/x-ma-chat`: a point-to-point message type
for ephemeral, synchronous-style communication. It shares the same transport
and encryption requirements as `application/x-ma-message` but carries the
semantic that the sender expects the message to be displayed immediately,
not queued in a persistent mailbox.

## 1. Content Type

| Property | Value |
| --- | --- |
| Type string | `application/x-ma-chat` |
| Encryption | Required |
| Service | `/ma/inbox/0.0.1` |
| Persistence | Not expected (MAY be displayed and discarded) |

`application/x-ma-chat` MUST be transmitted as an encrypted `Envelope`
(see [ma-messaging-format-v1.md](../ma-messaging-format-v1.md) §4).
Receivers MUST reject unencrypted instances.

## 2. Semantics

`application/x-ma-chat` is the most specific type for interactive, real-time
text exchanges — analogous to a direct chat message or a MUD `say` command.

Receivers SHOULD display the message immediately upon receipt and are NOT
required to store it in a persistent mailbox. Applications that do not
differentiate between persistent and ephemeral messages MAY treat
`application/x-ma-chat` identically to `application/x-ma-message`.

`application/x-ma-message` remains the generic fallback for any point-to-point
envelope that does not match a more specific type. Senders MUST use
`application/x-ma-chat` when the intent is real-time, ephemeral exchange and
MUST NOT use it for messages that require durable delivery.

## 3. Content Body

The content body is an arbitrary byte sequence. The inner `content-type` field
of the message (distinct from the outer message type) determines how the body
is interpreted. `text/plain` is RECOMMENDED for free-form chat text.

## 4. Delivery

`application/x-ma-chat` messages are delivered via `/ma/inbox/0.0.1`.
The `to` field MUST identify the intended recipient as a `did:ma` DID-URL.
The `from` field MUST be present and signed with the sender's Ed25519
assertion key.

## 5. Relationship to `application/x-ma-message`

| Property | `x-ma-message` | `x-ma-chat` |
| --- | --- | --- |
| Encryption | Required | Required |
| Service | `/ma/inbox/0.0.1` | `/ma/inbox/0.0.1` |
| Persistence | Expected | Not expected |
| Use case | Durable, async (e.g. email) | Ephemeral, sync (e.g. direct chat) |
| Fallback type | Yes | No |
