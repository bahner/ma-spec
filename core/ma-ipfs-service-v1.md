# IPFS Service Protocol (Core)

**Version:** 0.2.0
**Status:** Draft

## Abstract

This document defines the `/ma/ipfs/0.0.1` service protocol: its two
independent message types — `application/vnd.ma.identity.publish.request`
(delegated DID-document publishing) and `application/vnd.ma.ipfs.request`
(generic content storage) — and the semantics for each.

Earlier drafts of this specification unified both operations under a single
message type (`application/x-ma-ipfs-request`) discriminated by an internal
`kind` field. That design has been replaced: each operation now has its own
message type and its own ACL capability, since identity-publish transmits
sensitive IPNS key material and warrants a strictly separate access grant
from generic, low-sensitivity content storage.

## 1. Service Protocol

`/ma/ipfs/0.0.1` is the service protocol for delegated IPFS operations. It
is bound to two message types:

| Message type | Direction |
| --- | --- |
| `application/vnd.ma.identity.publish.request` | Request (client → publisher) |
| `application/vnd.ma.ipfs.request` | Request (client → publisher) |
| `application/vnd.ma.rpc.reply` | Reply (publisher → client), on `/ma/rpc/0.0.1` |

Messages with any other message type arriving on `/ma/ipfs/0.0.1` MUST be
rejected.

Replies are always returned on the **sender's `/ma/rpc/0.0.1` service**, not
on `/ma/ipfs/0.0.1`. The reply MUST set `replyTo` to the `id` of the
originating request message.

## 2. Message Types

### 2.1 `application/vnd.ma.identity.publish.request`

| Property | Value |
| --- | --- |
| Encryption | Required |
| Service | `/ma/ipfs/0.0.1` |
| Required capability | `identity-publish` |

Delegate publishing of a signed DID document to IPFS/IPNS. The sender
transmits their IPNS secret key and signed document; the publisher calls Kubo
on their behalf.

**Security warning:** This operation transmits an IPNS private key. The sender
is delegating full publishing authority over their DID to the receiver. Only
send this to endpoints you trust completely. A compromised or malicious
receiver can publish arbitrary DID documents under the sender's identity.
Senders SHOULD prefer direct IPFS publishing when possible and treat this as a
last-resort mechanism for environments without Kubo access (e.g. browsers).
This is precisely why identity-publish uses its own dedicated `identity-publish`
capability rather than sharing the `ipfs` capability used for generic storage
(§2.2) — the two operations have very different blast radii if granted to the
wrong principal.

#### 2.1.1 Payload

The payload is a CBOR map:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `document` | bytes | Yes | IPLD dag-cbor encoded signed DID document. |
| `ipns_secret_key` | bytes | Yes | Raw 32-byte Ed25519 IPNS seed. MUST be zeroized by the receiver immediately after use. |

The receiving endpoint MUST:

1. Reject the message if its type is not `application/vnd.ma.identity.publish.request`.
2. Decode and validate the DID document (structure, required fields).
3. Verify the DID document's own proof signature.
4. Verify the message sender's IPNS identity matches the document's DID.
5. Verify the outer message signature against the sender's DID document.
6. Verify the sender holds the `identity-publish` capability (§4.2).
7. Publish the document to IPFS via `ipfs dag put` (dag-cbor), recording the
   CID.
8. Publish a new IPNS record pointing to the CID using the provided key.
9. Zeroize `ipns_secret_key` immediately after the Kubo call completes
   (success or failure).
10. Reply with `[:ok, "<cid>"]` on success or `[:error, "<reason>"]` on
    failure, on the sender's `/ma/rpc/0.0.1`.

Replay protection MUST be applied before any key material is used.

### 2.2 `application/vnd.ma.ipfs.request`

| Property | Value |
| --- | --- |
| Encryption | Required |
| Service | `/ma/ipfs/0.0.1` |
| Required capability | `ipfs` |

Store arbitrary content on IPFS and obtain the resulting CID. No key material
is transmitted. This is a fire-and-forget, deliberately less sensitive
operation than identity-publish (§2.1), and is gated by the separate `ipfs`
capability.

#### 2.2.1 Payload

The payload is a CBOR map:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `content` | bytes | Yes | Raw bytes to store. |
| `content_type` | string | Yes | MIME type of `content` (e.g. `text/plain`, `text/markdown`). |

The receiving endpoint MUST:

1. Reject the message if its type is not `application/vnd.ma.ipfs.request`.
2. Verify the sender holds the `ipfs` capability (§4.2).
3. Accept the content bytes.
4. Call `ipfs add` on the raw bytes and obtain a CID.
5. Reply with `[:ok, "<cid>"]` on success or `[:error, "<reason>"]` on
   failure, on the sender's `/ma/rpc/0.0.1`.

## 3. Reply Format

Replies use `application/vnd.ma.rpc.reply` (see `ma-rpc-service-v1.md`) and
are delivered to the sender's `/ma/rpc/0.0.1` service, for both message types.

Reply content is a CBOR-encoded two-element array:

| Outcome | CBOR |
| --- | --- |
| Success | `[":ok", "<cid>"]` |
| Failure | `[":error", "<reason>"]` |

The reply MUST set `replyTo` to the `id` of the originating request message.

## 4. Security Considerations

### 4.1 Replay protection

The receiver MUST maintain a replay cache (e.g. sliding time window) keyed on
the message `id`. A request whose `id` has been seen within the window MUST be
rejected before any key material or payload is processed — this applies to
both message types.

### 4.2 ACL

Receivers SHOULD enforce an access control list (ACL) on the sender DID. Deny
rules MUST override allow rules. An identity-level deny blocks all DID-URLs
under that identity.

The two message types are gated by two independent capabilities:

| Message type | Required capability |
| --- | --- |
| `application/vnd.ma.identity.publish.request` | `identity-publish` |
| `application/vnd.ma.ipfs.request` | `ipfs` |

A principal granted `ipfs` does NOT thereby gain `identity-publish`, and vice
versa. Implementations MUST check the capability specific to the message type
received, not a shared or overlapping capability.

### 4.3 IPNS key handling

The IPNS secret key in an identity-publish request (§2.1) is the sender's full
publishing authority over their DID. Receivers MUST NOT log, persist, or
forward the key. The key bytes MUST be zeroized from memory as soon as the
Kubo call completes.

### 4.4 Transport security

All `/ma/ipfs/0.0.1` messages MUST be encrypted (both
`application/vnd.ma.identity.publish.request` and `application/vnd.ma.ipfs.request`
require encryption). The iroh QUIC transport provides an additional encrypted
channel. Unencrypted messages on this service MUST be rejected.
