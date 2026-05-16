# Emote Message Type

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines `application/x-ma-emote`: a point-to-point message type
for third-person action text — the classic IRC `/me` construct. An emote
describes what the sender *does* rather than what they *say*.

## 1. Content Type

| Property | Value |
| --- | --- |
| Type string | `application/x-ma-emote` |
| Encryption | Required |
| Service | `/ma/inbox/0.0.1` |
| Persistence | Not expected (MAY be displayed and discarded) |

`application/x-ma-emote` MUST be transmitted as an encrypted `Envelope`
(see [messaging-format.md](../messaging-format.md) §4).
Receivers MUST reject unencrypted instances.

## 2. Semantics

`application/x-ma-emote` carries a third-person action description. The body
is an arbitrary UTF-8 string representing what the sender is *doing* or
*expressing* — not what they are saying. Applications SHOULD render it
prefixed with the sender's identity in the style of:

```
* @sender <body>
```

For example, if `@fjodor` sends an emote with body `waves hello`, it renders:

```
* @fjodor waves hello
```

Receivers SHOULD display the message immediately upon receipt and are NOT
required to store it in a persistent mailbox.

## 3. Content Body

The content body is a UTF-8 text string (`text/plain` content type RECOMMENDED)
describing the action. The body MUST NOT include the sender's name — that is
derived from the `from` field of the message and prepended by the receiver.

## 4. Delivery

`application/x-ma-emote` messages are delivered via `/ma/inbox/0.0.1`.
The `to` field MUST identify the intended recipient as a `did:ma` DID-URL.
The `from` field MUST be present and signed with the sender's Ed25519
assertion key.

## 5. Relationship to other ephemeral types

| Type | Display convention | Semantics |
| --- | --- | --- |
| `x-ma-chat` | `← @sender: body` | Direct speech |
| `x-ma-emote` | `* @sender body` | Third-person action |
| `x-ma-message` | (stored in mailbox) | Durable async |
