# Messaging Format: did:ma

**Version:** 1.0.0
**Status:** Candidate Recommendation

## Abstract

This document specifies the wire message format for the `did:ma` method.
Messages are signed CBOR structures carrying typed, optionally encrypted
payloads between DID-identified actors.

## 1. Message Structure

### 1.1 Fields

| Field | Key | Type | Req | Description |
|---|---|---|---|---|
| Identifier | `id` | string | Yes | Unique message ID (nanoid: `[A-Za-z0-9_-]`). |
| Protocol | `protocol` | string | Yes | Always `"/ma/0.0.1"`. |
| Type | `type` | string | Yes | Message category. See §2. |
| Sender | `from` | string | Yes | DID or DID URL of the sender. |
| Recipient | `to` | string | No | DID or DID URL of the recipient. MAY be omitted for broadcasts. |
| Created at | `createdAt` | integer | Yes | Unix epoch seconds (UTC). |
| Expiry | `exp` | integer | No | Expiry as Unix epoch seconds. `0` = never expires. Default `now + 3600`. |
| Content type | `contentType` | string | Yes | MIME type of the decoded payload (e.g. `text/plain`). |
| Reply to | `replyTo` | string | No | `id` of the message being replied to. Absence means this is not a reply. |
| Content | `content` | bytes | Yes | Multicodec-prefixed payload. First bytes are a varint codec identifier; `0x00` (identity) means the payload follows verbatim. |
| Signature | `signature` | bytes | Yes | Raw 64-byte Ed25519 signature over the unsigned headers. |

Receivers MUST reject messages with an unrecognised `protocol` value.

`contentType` describes the semantic type of the **decoded** payload.
It MUST NOT be replaced by a codec label.

### 1.2 Headers

`Headers` is the signed subset of a message. It contains all message fields
except `content`, which is replaced by its BLAKE3 hash.

| Field | Key | Type | Description |
|---|---|---|---|
| Identifier | `id` | string | As in message. |
| Protocol | `protocol` | string | As in message. |
| Type | `type` | string | As in message. |
| Sender | `from` | string | As in message. |
| Recipient | `to` | string | As in message. |
| Created at | `createdAt` | integer | As in message. |
| Expiry | `exp` | integer | As in message. |
| Content type | `contentType` | string | As in message. |
| Reply to | `replyTo` | string | As in message. |
| Content hash | `contentHash` | bytes (32) | BLAKE3 hash of `content`. |
| Signature | `signature` | bytes | Raw 64-byte Ed25519 signature; empty in unsigned headers. |

### 1.3 Correlation

Every message carries a unique `id`. A reply MUST set `replyTo` to the
originating message `id`. No additional correlation identifier is defined.

## 2. Message Types

The `type` field determines routing and delivery semantics.

### 2.1 Base Types

| Type | Encryption | Description |
|---|---|---|
| `application/vnd.ma.message` | Required | Generic point-to-point envelope. Delivered via `/ma/inbox/0.0.1`. |
| `application/vnd.ma.broadcast` | Forbidden | Signed broadcast without a specific recipient. Delivered via `/ma/inbox/0.0.1`. |

Rules:

1. `application/vnd.ma.message` MUST be transmitted as an encrypted envelope (§4). Receivers MUST reject unencrypted instances.
1. `application/vnd.ma.broadcast` MUST NOT be encrypted. Receivers MUST reject encrypted instances. The `to` field SHOULD be empty.
1. Senders MUST use the most specific applicable type. `application/vnd.ma.message` is the fallback of last resort.

### 2.2 Extension Types

Extension services define additional `application/vnd.ma.*` types in separate
documents. All protocol-owned message types use the `application/vnd.ma.*`
media type tree.

| Type | Service | Specification |
|---|---|---|
| `application/vnd.ma.chat` | `/ma/inbox/0.0.1` | [ma-chat-messages-v1.md](ma-chat-messages-v1.md) |
| `application/vnd.ma.emote` | `/ma/inbox/0.0.1` | [ma-emote-messages-v1.md](ma-emote-messages-v1.md) |
| `application/vnd.ma.identity.publish.request` | `/ma/ipfs/0.0.1` | [ma-ipfs-service-v1.md](ma-ipfs-service-v1.md) |
| `application/vnd.ma.ipfs.request` | `/ma/ipfs/0.0.1` | [ma-ipfs-service-v1.md](ma-ipfs-service-v1.md) |
| `application/vnd.ma.rpc.request` | `/ma/rpc/0.0.1` | [ma-rpc-service-v1.md](ma-rpc-service-v1.md) |
| `application/vnd.ma.rpc.reply` | `/ma/rpc/0.0.1` | [ma-rpc-service-v1.md](ma-rpc-service-v1.md) |
| `application/vnd.ma.crud.request` | `/ma/crud/0.0.1` | [ma-crud-service-v1.md](../runtime/ma-crud-service-v1.md) |
| `application/vnd.ma.crud.reply` | `/ma/crud/0.0.1` | [ma-crud-service-v1.md](../runtime/ma-crud-service-v1.md) |

Profile-specific types MAY be defined outside this specification.
Their semantics are non-normative for the base format.

### 2.3 Standard Content-Type Values

`contentType` is distinct from the `type` routing field. The following values
are defined across 間 protocols:

| `contentType` | Used by | Decoded payload |
|---|---|---|
| `application/cbor` | Any | Arbitrary CBOR value. |
| `text/plain` | Inbox, chat, emote | UTF-8 text. |
| `application/vnd.ma.term` | RPC, CRUD | CBOR term — either a bare atom (e.g. `:ok`, `:pong`) or a tuple (CBOR array whose first element is a dispatchable atom, e.g. `[:ok, data]`, `[:error, reason]`). See the RPC and CRUD service specs for the defined atoms. |
| `application/vnd.ipld.dag-cbor` | Documents, entity nodes | IPLD DAG-CBOR. |

`contentType` carries semantic meaning; it MUST NOT be substituted with a
codec label. Receivers MUST use `contentType` to interpret the decoded payload.

## 3. Signing

Messages are signed with the sender's Ed25519 assertion method key
(see [did:ma DID Document Format](../did-ma-spec-v1.md) §3–4).

### 3.1 Signing

1. Copy all message fields into a `Headers` structure.
1. Set `contentHash` to the BLAKE3 hash of `content`.
1. Set `signature` to an empty byte array.
1. Serialize `Headers` to CBOR (RFC 8949).
1. Sign the serialized unsigned header bytes with the sender's Ed25519 private key.
1. Set `signature` on both `Headers` and `Message` to the raw 64-byte signature.

### 3.2 Verification

1. Resolve the sender's DID document from `from`.
1. Extract the assertion method public key.
1. Copy the message headers and clear `signature`.
1. Serialize the unsigned headers to CBOR.
1. Verify the raw 64-byte Ed25519 signature against those serialized header
   bytes and the public key.
1. Verify that `contentHash` equals the BLAKE3 hash of `content`.
1. Verify that `createdAt` is within the acceptable clock window (see §5).

## 4. Encryption

Message types that require encryption MUST be enclosed in an `Envelope`
before transmission. The envelope provides end-to-end confidentiality for
both headers and content.

### 4.1 Envelope Fields

| Field | Key | Type | Description |
|---|---|---|---|
| Ephemeral key | `ephemeralKey` | bytes (32) | Sender's ephemeral X25519 public key. |
| Encrypted content | `encryptedContent` | bytes | 24-byte nonce followed by XChaCha20-Poly1305 ciphertext of `content`. |
| Encrypted headers | `encryptedHeaders` | bytes | 24-byte nonce followed by XChaCha20-Poly1305 ciphertext of the serialized `Headers`. |

### 4.2 Encryption

1. Generate an ephemeral X25519 key pair.
1. Perform X25519 DH with the recipient's `keyAgreement` public key → 32-byte shared secret.
1. Derive two 32-byte symmetric keys via BLAKE3 key derivation:
   - Content key: context `"/ma/0.0.1"`
   - Headers key: context `"ma"`
1. For each of `content` and serialized `Headers`: generate a random 24-byte nonce, encrypt with XChaCha20-Poly1305, store as `nonce || ciphertext`.
1. Serialize the envelope to CBOR.

Context labels are version-bound. Changing them in a future protocol version
will break decryption of messages encrypted under prior labels. This is
intentional.

### 4.3 Decryption

1. Deserialize the envelope from CBOR.
1. Perform X25519 DH with the envelope's `ephemeralKey` → shared secret.
1. Derive the same two symmetric keys using the same context labels.
1. Split each ciphertext into nonce (first 24 bytes) and ciphertext.
1. Decrypt headers and content with XChaCha20-Poly1305.
1. Verify the decrypted message as in §3.2.

## 5. Replay Protection

Receivers SHOULD maintain a sliding-window replay guard.

| Parameter | Default | Description |
|---|---|---|
| Retention window | 120 s | How long message IDs are remembered. |
| Clock skew | 30 s | Maximum permitted sender/receiver clock difference. |
| Default exp | `now + 3 600 s` | Applied when `exp` is absent. |

Algorithm:

1. Reject if `createdAt > now + skew`.
1. If `exp != 0`, reject if `now > exp + skew`.
1. Reject if `id` was seen within the retention window.
1. Otherwise accept and record `id`.

## 6. Wire Format

All messages and envelopes are CBOR-encoded (RFC 8949) for transport.

## References

- [did:ma DID Document Format](../did-ma-spec-v1.md)
- [Inbox Service v1](ma-inbox-service-v1.md)
- [RPC Service v1](ma-rpc-service-v1.md)
- [IPFS Service v1](ma-ipfs-service-v1.md)
- [CRUD Service v1](../runtime/ma-crud-service-v1.md)
- [ACL Model v1](ma-acl-v1.md)
- [RFC 8949 — CBOR](https://www.rfc-editor.org/rfc/rfc8949)
- [RFC 8032 — Ed25519](https://www.rfc-editor.org/rfc/rfc8032)
- [RFC 7748 — X25519](https://www.rfc-editor.org/rfc/rfc7748)
- [RFC 8439 — ChaCha20-Poly1305](https://www.rfc-editor.org/rfc/rfc8439)
- [BLAKE3](https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf)
- [Multicodec table](https://github.com/multiformats/multicodec/blob/master/table.csv)
- [nanoid](https://github.com/ai/nanoid)
