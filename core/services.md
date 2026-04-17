# Services and Transport: ma-core

**Version:** 0.0.1
**Status:** Draft

## Abstract

This document specifies the service model used by ma endpoints. A service is a
named protocol registered on an endpoint, identified by a versioned protocol ID.
All message transport is one-way fire-and-forget. This document covers the inbox
primitive, point-to-point services, and their lifecycle. Gossip pub/sub is
specified separately in [pubsub.md](pubsub.md).

The ma messaging model is grounded in Carl Hewitt's Actor Model (1973). Every
entity in the system — world, agent, actor — is an actor: an autonomous unit
that communicates exclusively by sending asynchronous messages to other actors.
There are no shared-state primitives, no synchronous calls, and no return
channels at the transport level. An actor can, upon receiving a message:

1. Send messages to other actors it knows about.
2. Create new actors.
3. Update its own local state.

This maps directly to the ma architecture: each DID-identified endpoint has an
inbox that accepts signed messages and an outbox that sends them. There is no
request/response at the transport layer. If a higher-level protocol needs
correlation, it is expressed in message content — the transport remains
one-way and fire-and-forget, exactly as Hewitt defined it.

## 1. Service Model

A service is the ma equivalent of an entry in `/etc/services`: a named protocol
on an endpoint that handles incoming connections for a specific purpose.

### 1.1 Protocol Identifiers

Each service is identified by a versioned protocol ID string:

    /ma/<name>/<semver>

This follows the same convention used by IPFS protocols (e.g.
`/ipfs/bitswap/1.2.0`). Protocol IDs are public — they form part of the
service name and are advertised in DID document transport entries.

### 1.2 Service Contract

Every service declares a **protocol ID** — the identifier byte string
(e.g. `/ma/inbox/0.0.1`). The protocol ID is the service name. It is
self-descriptive and requires no additional label or metadata.

## 2. Inbox

The inbox is a standalone ma-core primitive — a bounded FIFO queue with
per-message TTL. It is not tied to any service or transport. Services use
inboxes, topics use inboxes, and application code can create inboxes directly.
Callers interact only with inboxes; the origin of a message (network, gossip,
local) is irrelevant once it is queued.

### 2.1 Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| Capacity | 256 | Maximum number of queued messages. Oldest evicted on overflow. |
| Message TTL | Per-message | Derived from `createdAt + ttl` in the message headers. |
| Pruning | On access | Expired entries removed when the queue is read. |

### 2.2 Acceptance Flow

Before a message enters the inbox, it is validated:

1. Deserialize CBOR message payload.
2. Validate signature against sender's DID document.
3. Check TTL — reject expired messages.
4. Check the replay guard — reject duplicate message IDs within the retention
   window (see [messaging-format.md](../messaging-format.md) §5).
5. Queue with expiry timestamp (`createdAt + ttl`).

Invalid messages are dropped silently. The inbox does not send responses.

### 2.3 Consumption

Callers read messages from the inbox via `drain()`, which returns all queued
messages and removes them from the queue. Expired entries are pruned
automatically before the result is returned.

## 3. Message Flow

All point-to-point transport is strictly one-way.

### 3.1 Outbox (Sending)

The outbox is not a service — it is a sending primitive. It performs:

1. Validate the `Message` (headers, signature).
2. Serialize to CBOR.
3. Transmit to the remote endpoint.

There is no acknowledgement, no response, no retry at the transport level. The
outbox is fire-and-forget.

### 3.2 No Request/Response

There is no request/response semantics at the transport level. If a higher-level
protocol needs correlation, it uses the `replyTo` field in the message headers
(see [messaging-format.md](../messaging-format.md) §1.2).
The transport layer has no knowledge of this.

## 4. Required Services

### 4.1 `/ma/inbox/0.0.1`

The inbox service is the only service an endpoint MUST register. It binds the
`/ma/inbox/0.0.1` protocol ID to an inbox (§2) for network reception: incoming
connections are read as length-prefixed frames and fed into the inbox's
acceptance flow (§2.2).

While the inbox service is sufficient for all communication, implementors are
encouraged to define additional, more specialized services. A purpose-built
service with its own protocol ID can enforce tighter validation, carry domain-
specific payloads, and be independently versioned — all without overloading the
general inbox.

## 5. Optional Services

### 5.1 `/ma/ipfs/0.0.1`

Publishes DID documents to IPFS/IPNS on behalf of clients that lack direct Kubo
access. The request payload is an `application/x-ma-ipfs-request` message
containing the DID document and an IPNS private key (see
[messaging-format.md](../messaging-format.md) §2.2.1).

This service is deployment-policy controlled. Endpoints offering it SHOULD
enforce access control, rate limits, and quotas appropriate to their deployment.

Availability of this service is OPTIONAL. Clients MUST NOT assume any endpoint
offers it.

## 6. Service Registration and Transport Advertisement

### 6.1 Registration

Services are registered on the endpoint's router by protocol ID. The router
dispatches incoming connections to the matching handler. Connections for
unregistered protocol IDs are rejected.

### 6.2 Transport Advertisement

Endpoints advertise their available services in DID documents using the
`ma.services` field. Each entry is a transport string composed of a transport
address followed by the protocol ID:

    <transport-address>/<protocol-id>

The transport address identifies how to reach the endpoint. The protocol ID
identifies which service to connect to. The format is transport-agnostic —
any addressing scheme may be used as long as the protocol ID suffix is
preserved.

Current transport examples:

| Transport | Address format | Full example |
| --- | --- | --- |
| iroh | `/iroh/<endpoint-id>` | `/iroh/0123…abcdef/ma/inbox/0.0.1` |

Consumers iterate the transport list and use the first entry whose transport
and protocol they support.

## 7. Designing New Services

When adding a new service to the ma ecosystem:

1. **Choose a versioned protocol ID** following the `/ma/<name>/<semver>` pattern.
   The name should be descriptive and stable. Once published in DID documents,
   changing it requires a coordinated migration.

2. **Implement the service contract** — declare the protocol ID.

3. **Register on the router** — the endpoint router dispatches by protocol ID.

4. **Advertise in DID documents** — add the transport string to `ma.services`
   so peers can discover the service.

5. **Define a content type** if the service handles a specific payload format.
   Follow the `application/x-ma-<name>` convention. Document encryption
   requirements per content type (see
   [messaging-format.md](../messaging-format.md) §2).

6. **Respect the one-way model** — services receive messages. They do not send
   responses over the same connection. If bidirectional communication is needed,
   both parties register services and send to each other's inboxes.

## References

- [did:ma Method Specification](../did-method-spec.md)
- [did:ma DID Document Format](../did-document-format.md) — assertion method,
  proof scheme, verification
- [Messaging Format](../messaging-format.md) — message structure, content
  types, signing, encryption
- [Pub/Sub Transport](pubsub.md) — gossip pub/sub transport, topic primitive,
  broadcast delivery
