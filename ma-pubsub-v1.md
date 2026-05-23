# Pub/Sub Transport: ma-core

**Version:** 0.0.1
**Status:** Draft

## Abstract

This document specifies the gossip pub/sub transport layer for 間 endpoints.
Pub/sub is an optional supplement to point-to-point messaging. It is never
required. If the underlying implementation (iroh gossip, libp2p gossipsub)
is unavailable, pub/sub is simply absent — no service degrades, no contract
breaks.

Pub/sub is junk mail: cheap to send, delivered to everyone who subscribes,
and useful primarily for discovery and announcements. Important operations
use point-to-point messaging via inbox and outbox.

There is no broadcast service. Worlds and rooms that need to deliver broadcast
messages to specific actors do so via point-to-point inbox delivery — one
message per recipient. Pub/sub is a separate, opt-in gossip layer.

## 1. Topic

A topic is a first-class ma-core primitive. It represents a named gossip
channel that endpoints can publish to and subscribe to. Topics are identified
by a BLAKE3 hash of their name string.

### 1.1 Identity

    TopicId = blake3(topic_string)

The topic string is a human-readable name (e.g. `/ma/broadcast/0.0.1`). The
`TopicId` is the BLAKE3 digest of that string, used as the gossip channel
identifier. Two endpoints that hash the same string will join the same topic.

### 1.2 Lifecycle

Create a topic:

    t = Topic("/ma/broadcast/0.0.1")

Subscribe — begin receiving messages. Creates an internal inbox (§1.3):

    t.subscribe()

Or subscribe with an existing inbox, so messages from multiple sources
(network services, other topics) converge into a single queue:

    t.subscribe(my_inbox)

Publish a signed message to all subscribers. Fire-and-forget — this is NOT
an outbox operation:

    t.publish(message)

Read received messages from the topic's inbox:

    messages = t.drain()

Stop receiving:

    t.unsubscribe()

### 1.3 Inbox Integration

Every subscribed topic delivers messages to an inbox (see
[services.md](services.md) §2). If no inbox is provided at subscribe time,
the topic creates one internally. If an existing inbox is provided, the topic
delivers to that inbox instead.

This means callers only need to interact with inboxes. Whether a message
arrived via point-to-point connection, gossip topic, or local injection — the
caller reads it from an inbox with `drain()`.

### 1.4 Validation

Messages received via gossip are validated before inbox delivery. Topics
enforce stricter rules than a general inbox:

1. Deserialize CBOR message payload.
2. Content type MUST be `application/x-ma-broadcast`. Reject all others.
3. The `to` field MUST be absent or empty. Reject messages with a recipient.
4. Validate signature against sender's DID document.
5. Check TTL — reject expired messages.

In particular, `application/x-ma-message` (encrypted, with recipient) MUST
be rejected. Topics are public gossip channels — encrypted point-to-point
messages have no place here.

Invalid messages are dropped silently and never reach the inbox.

There is no replay guard at the gossip layer. Gossip transports may deliver
duplicate messages. Application-layer deduplication by message `id` is the
caller's responsibility if needed.

### 1.5 Sender Blocking

Receivers MAY maintain a block list of sender DIDs. Messages from blocked
senders are dropped before inbox delivery. This is a local policy decision —
there is no protocol-level block mechanism.

Because all topic messages are signed and carry the sender's DID in the `from`
field, blocking is straightforward: check `from` against the block list before
any other validation.

### 1.6 Spam Disclaimer

Pub/sub is an open gossip channel. Any endpoint can publish to any topic.
The protocol provides no spam prevention, no rate limiting, and no admission
control at the transport level.

**The receiver is solely responsible for filtering unwanted messages.** This
includes maintaining block lists (§1.5), limiting inbox capacity
([services.md](services.md) §2.1), and discarding messages from unknown or
untrusted senders as local policy dictates.

By subscribing to a topic, an endpoint accepts this responsibility.

## 2. Well-Known Topic

### 2.1 `/ma/broadcast/0.0.1`

The well-known broadcast topic is the seed channel for discovery and
announcements in the 間 ecosystem.

    TopicId = blake3("/ma/broadcast/0.0.1")

Messages published to this topic MUST use the `application/x-ma-broadcast`
content type (see [ma-messaging-format-v1.md](../ma-messaging-format-v1.md) §2).

**Typical subscribers:** actors. Actors subscribe to discover worlds,
receive announcements, and find peers.

**Typical non-subscribers:** worlds. Worlds publish to the broadcast topic
but do not subscribe. When a world needs to deliver a broadcast to a specific
actor, it sends the message point-to-point via the actor's inbox — not via
gossip.

## 3. Custom Topics

Endpoints MAY create additional topics dynamically. Custom topic strings
SHOULD follow the `/ma/<name>/<version>` convention for interoperability.

**Exercise restraint.** Each topic adds mesh overhead — subscription
maintenance, message fanout, bandwidth. Avoid creating topics for use cases
that are better served by point-to-point messaging. A good rule of thumb:
if fewer than three endpoints would subscribe, use inbox/outbox instead.

## 4. Typical Usage

| Role | Behaviour |
| --- | --- |
| Actor | Primary gossip consumer. Subscribes to `/ma/broadcast/0.0.1` for discovery. |
| World | Primary gossip producer. Publishes announcements. Does not subscribe. |
| Agent | MAY subscribe to topics on behalf of its principal. |

Gossip is for discovery, not operations. Anything that matters — commands,
state changes, sensitive data — goes through point-to-point inbox/outbox with
encryption and replay protection.

## 5. Transport Abstraction

ma-core defines the topic interface. The underlying gossip implementation is
hidden behind this interface. Current implementations:

| Implementation | Status |
| --- | --- |
| iroh-gossip | Default, built-in |

If the gossip implementation is replaced or removed, the topic interface
remains stable. Callers are unaffected as long as they use `Topic`, not the
underlying transport directly.

## 6. Disambiguation

Two concepts share the `/ma/broadcast/0.0.1` string:

| Concept | What it is | Where specified |
| --- | --- | --- |
| **Content type** `application/x-ma-broadcast` | A message format: signed, not encrypted, no recipient. | [Messaging Format](../ma-messaging-format-v1.md) §2 |
| **Topic** `/ma/broadcast/0.0.1` | A gossip channel: delivers broadcast messages via pub/sub. | This document, §2 |

The content type defines what a broadcast message IS. The topic is the gossip
delivery mechanism. Broadcast messages can also be delivered point-to-point via
inbox — the content type is the same regardless of delivery mechanism.

## References

- [did:ma Method Specification](../did-method-spec.md)
- [did:ma Messaging Format](../ma-messaging-format-v1.md) — `application/x-ma-broadcast`
  content type
- [Services and Transport](services.md) — inbox primitive, service model,
  transport advertisement
