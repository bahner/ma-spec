# IPFS Service Protocol (Core)

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines the `/ma/ipfs/0.0.1` service protocol: its single
message type `application/x-ma-ipfs-request`, the unified payload format
with `kind` discriminator, and the semantics for each operation kind.

## 1. Service Protocol

`/ma/ipfs/0.0.1` is the service protocol for delegated IPFS operations. It
is bound to a single message type:

| Message type | Direction |
| --- | --- |
| `application/x-ma-ipfs-request` | Request (client → publisher) |
| `application/x-ma-rpc-reply` | Reply (publisher → client), on `/ma/rpc/0.0.1` |

Messages with any other message type arriving on `/ma/ipfs/0.0.1` MUST be
rejected.

Replies are always returned on the **sender's `/ma/rpc/0.0.1` service**, not
on `/ma/ipfs/0.0.1`. The reply MUST set `replyTo` to the `id` of the
originating request message.

## 2. Message Type

### 2.1 `application/x-ma-ipfs-request`

| Property | Value |
| --- | --- |
| Encryption | Required |
| Service | `/ma/ipfs/0.0.1` |

A request to perform a delegated IPFS operation. The payload is a CBOR map
whose `kind` field (text string) selects the operation. All operations share
the same message type; the `kind` field is the discriminator.

#### 2.1.1 Payload envelope

The top-level CBOR object always contains at least:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `kind` | string | Yes | Operation kind. See §2.1.2. |

Additional fields depend on `kind`. Unknown `kind` values MUST be rejected
with `[:error, "unknown kind: <value>"]`.

#### 2.1.2 Operation kinds

##### kind: `did-document-publish`

Delegate publishing of a signed DID document to IPFS/IPNS. The sender
transmits their IPNS secret key and signed document; the publisher calls Kubo
on their behalf.

**Security warning:** This operation transmits an IPNS private key. The sender
is delegating full publishing authority over their DID to the receiver. Only
send this to endpoints you trust completely. A compromised or malicious
receiver can publish arbitrary DID documents under the sender's identity.
Senders SHOULD prefer direct IPFS publishing when possible and treat this as a
last-resort mechanism for environments without Kubo access (e.g. browsers).

Additional payload fields:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `document` | bytes | Yes | IPLD dag-cbor encoded signed DID document. |
| `ipns_secret_key` | bytes | Yes | Raw 32-byte Ed25519 IPNS seed. MUST be zeroized by the receiver immediately after use. |

The receiving endpoint MUST:

1. Decode and validate the DID document (structure, required fields).
2. Verify the DID document's own proof signature.
3. Verify the message sender's IPNS identity matches the document's DID.
4. Verify the outer message signature against the sender's DID document.
5. Publish the document to IPFS via `ipfs dag put` (dag-cbor), recording the
   CID.
6. Publish a new IPNS record pointing to the CID using the provided key.
7. Zeroize `ipns_secret_key` immediately after the Kubo call completes
   (success or failure).
8. Reply with `[:ok, "<cid>"]` on success or `[:error, "<reason>"]` on
   failure, on the sender's `/ma/rpc/0.0.1`.

   Replay protection MUST be applied before any key material is used.

##### kind: `store`

Store arbitrary content on IPFS and obtain the resulting CID. No key material
is transmitted.

Additional payload fields:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `content` | bytes | Yes | Raw bytes to store. |
| `content_type` | string | Yes | MIME type of `content` (e.g. `text/plain`, `text/markdown`). |

The receiving endpoint MUST:

1. Accept the content bytes.
2. Call `ipfs add` on the raw bytes and obtain a CID.
3. Reply with `[:ok, "<cid>"]` on success or `[:error, "<reason>"]` on
   failure, on the sender's `/ma/rpc/0.0.1`.

## 3. Reply Format

Replies use `application/x-ma-rpc-reply` (see `ma-rpc-service-v1.md`) and
are delivered to the sender's `/ma/rpc/0.0.1` service.

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
rejected before any key material or payload is processed.

### 4.2 ACL

Receivers SHOULD enforce an access control list (ACL) on the sender DID. Deny
rules MUST override allow rules. An identity-level deny blocks all DID-URLs
under that identity.

### 4.3 IPNS key handling

The IPNS secret key in a `did-document-publish` request is the sender's full
publishing authority over their DID. Receivers MUST NOT log, persist, or
forward the key. The key bytes MUST be zeroized from memory as soon as the
Kubo call completes.

### 4.4 Transport security

All `/ma/ipfs/0.0.1` messages MUST be encrypted (`application/x-ma-ipfs-request`
requires encryption). The iroh QUIC transport provides an additional encrypted
channel. Unencrypted messages on this service MUST be rejected.
