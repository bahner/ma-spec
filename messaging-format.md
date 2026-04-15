# Messaging Format: did:ma

**Version:** 0.0.2
**Status:** Draft

## Abstract

This document specifies the messaging format used by the `did:ma` actor
protocol. Messages are signed CBOR structures that carry typed payloads between
actors identified by DIDs. The format supports DID document notifications,
encrypted point-to-point envelopes, and replay protection.

This document defines the protocol-level message format only. Runtime-specific
usage (for example world simulation commands, ALPN lane layouts, and client UX
conventions) is out of scope for this specification.

## 1. Message Structure

A message is a signed, typed container for content exchanged between actors.

### 1.1 Fields

| Field | Key | Type | Required | Description |
| --- | --- | --- | --- | --- |
| Identifier | `id` | string | Yes | Unique message identifier (nanoid: alphanumeric + `_` + `-`). |
| Type | `type` | string | Yes | Protocol version. Always `"/ma/0.0.1"`. |
| Sender | `from` | string | Yes | DID or DID URL of the sender. |
| Recipient | `to` | string | No | DID or DID URL of the recipient. MAY be empty for content types that do not require a specific recipient (e.g. broadcast). |
| Created at | `createdAt` | integer | Yes | Unix timestamp in seconds (UTC). |
| TTL | `ttl` | integer | Yes | Message time-to-live in seconds. Default `3600`. Value `0` disables age-based expiration. |
| Content type | `contentType` | string | Yes | MIME-like content type identifier (see section 2). |
| Reply to | `replyTo` | string | No | Optional message ID this message replies to. |
| Content | `content` | bytes | Yes | Arbitrary payload bytes. |
| Signature | `signature` | bytes | Yes | Ed25519 signature over the message headers. |

### 1.2 Correlation Semantics

`did:ma` uses existing message fields for correlation:

- Every message has a unique `id`.
- A response MAY set `replyTo` to the `id` of the message it answers.

No additional request/session/transaction identifier is required by this
format. In particular, this specification does not define an AJAX-style request
context spanning multiple transport calls.

### 1.3 Headers

Headers are the subset of message fields used for signing and verification. A
`Headers` structure contains all fields of a `Message` except `content`, and
replaces `content` with a content hash.

| Field | Key | Type | Description |
| --- | --- | --- | --- |
| Identifier | `id` | string | Same as message `id`. |
| Type | `type` | string | Same as message `type`. |
| Sender | `from` | string | Same as message `from`. |
| Recipient | `to` | string | Same as message `to`. |
| Created at | `createdAt` | integer | Same as message `createdAt`. |
| TTL | `ttl` | integer | Same as message `ttl`. |
| Content type | `contentType` | string | Same as message `contentType`. |
| Reply to | `replyTo` | string | Optional message ID this message replies to. |
| Content hash | `contentHash` | bytes (32) | BLAKE3 hash of the message `content`. |
| Signature | `signature` | bytes | Ed25519 signature (empty in unsigned headers). |

## 2. Content Types

Messages are classified by content type. Each content type identifies the
purpose and handling semantics of the payload.

### 2.1 Foundational Content Types

| Content Type | Value | Encryption | Description |
| --- | --- | --- | --- |
| Document | `application/x-ma-doc` | Forbidden | DID document payload. MUST NOT be encrypted; DID documents are public data. |
| Message | `application/x-ma-message` | Required | Point-to-point message. MUST be enclosed in an encrypted envelope (section 4). |

Rules:

1. `application/x-ma-message` MUST always be transmitted as an encrypted
   envelope. Receivers MUST reject unencrypted `application/x-ma-message`
   payloads.
1. `application/x-ma-doc` MUST NOT be encrypted. DID documents are public data
   intended for open consumption. Receivers MUST reject encrypted
   `application/x-ma-doc` payloads.

### 2.2 Profile-Defined Content Types

Additional `application/x-ma-*` content types MAY be defined by implementation
profiles. Such profile-specific semantics are not normative for the base
`did:ma` format.

There is no generic fallback content type. Implementations MUST use an explicit
content type for every message.

## 3. Signing

### 3.1 Signing Algorithm

Messages are signed using the sender's Ed25519 assertion method key. The
signature covers the headers (not the content directly), which include a content
hash for integrity binding.

1. **Construct unsigned headers:**
   - Copy all message fields into a `Headers` structure.
   - Compute the BLAKE3 hash of the `content` bytes and set `contentHash`.
   - Set `signature` to an empty byte array.
1. **Serialize headers to CBOR** (RFC 8949).
1. **Hash** the CBOR bytes using BLAKE3, producing a 32-byte digest.
1. **Sign** the digest with the sender's Ed25519 private key.
1. **Set** the `signature` field on both the headers and the message to the
   resulting signature bytes.

### 3.2 Verification Algorithm

1. **Resolve the sender's DID document** using the `from` field.
1. **Extract the assertion method** verification key from the sender's document.
1. **Reconstruct unsigned headers:** Copy the message headers and clear the
   `signature` field.

1. **Serialize** the unsigned headers to CBOR.
1. **Hash** the CBOR bytes with BLAKE3.
1. **Verify** the Ed25519 signature from the message against the hash and the
   sender's public key.

Additionally:

- Verify that the `contentHash` in the headers matches the BLAKE3 hash of the
  actual `content`.

- Verify that the `createdAt` timestamp is within the acceptable time window
  (see section 5).

## 4. Encryption (Envelopes)

Content types that require encryption (e.g. `application/x-ma-message`) MUST be
enclosed in encrypted envelopes before transmission. The envelope encrypts both
headers and content, providing end-to-end confidentiality.

### 4.1 Envelope Structure

| Field | Key | Type | Description |
| --- | --- | --- | --- |
| Ephemeral key | `ephemeralKey` | bytes (32) | X25519 ephemeral public key. |
| Encrypted content | `encryptedContent` | bytes | XChaCha20-Poly1305 ciphertext of the message content. |
| Encrypted headers | `encryptedHeaders` | bytes | XChaCha20-Poly1305 ciphertext of the message headers. |

### 4.2 Encryption Algorithm

1. **Generate an ephemeral X25519 key pair.**
1. **Perform ECDH** between the ephemeral private key and the recipient's
   `keyAgreement` public key (from their DID document), producing a 32-byte
   shared secret.

1. **Derive symmetric keys** using BLAKE3 key derivation with a context label:
   - Content encryption key: derived from the shared secret with a
     content-specific context.

   - Headers encryption key: derived from the shared secret with a
     headers-specific context.

1. **Encrypt:**
   - Encrypt the message `content` with XChaCha20-Poly1305 using the content
     key.

   - Encrypt the serialized `Headers` (CBOR) with XChaCha20-Poly1305 using the
     headers key.

1. **Construct the envelope** with the ephemeral public key and both
   ciphertexts.

1. **Serialize the envelope** to CBOR for transport.

### 4.3 Decryption Algorithm

1. **Deserialize** the envelope from CBOR.
1. **Perform ECDH** between the recipient's `keyAgreement` private key and the
   envelope's `ephemeralKey`, producing the shared secret.

1. **Derive symmetric keys** using the same BLAKE3 derivation context.
1. **Decrypt** the headers and content using XChaCha20-Poly1305.
1. **Verify** the decrypted message signature as in section 3.2.

## 5. Replay Protection

### 5.1 Replay Guard

Receivers SHOULD maintain a replay guard to detect and reject duplicate or
replayed messages.

| Parameter | Default | Description |
| --- | --- | --- |
| Time window | 120 seconds | Duration for which message IDs are retained. |
| Clock skew tolerance | 30 seconds | Maximum permitted difference between sender and receiver clocks. |
| Message TTL | 3600 seconds | Default max age per message (`ttl=0` disables age-based expiration). |

### 5.2 Algorithm

1. Check that `createdAt <= now + skew`.

1. If `ttl != 0`, check that `now <= createdAt + ttl + skew`.

1. Check that the message `id` has not been seen within the retention window.
1. If both checks pass, record the message `id` with its timestamp.
1. Reject the message if either check fails.

Expired entries (older than the time window) are periodically pruned.

## 6. Wire Format

All messages and envelopes are serialized to CBOR (RFC 8949) for transport over
the wire. CBOR is a compact binary format that preserves the full fidelity of
the message structure including byte arrays.

Serialization methods:

- `Message::to_cbor() / Message::from_cbor()` for plaintext messages.
- `Envelope::to_cbor() / Envelope::from_cbor()` for encrypted envelopes.
- `Headers::to_cbor()` for header serialization during signing.

## 7. Transport

The `did:ma` messaging protocol is transport-agnostic. Any transport providing
authenticated, encrypted, bidirectional channels MAY be used — including direct
peer-to-peer, WebRTC, or relay-based transports.

Implementation-specific transport profiles are documented separately from the
base `did:ma` format.

## References

- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
- [Ed25519 (RFC 8032)](https://www.rfc-editor.org/rfc/rfc8032)
- [X25519 (RFC 7748)](https://www.rfc-editor.org/rfc/rfc7748)
- [XChaCha20-Poly1305](https://www.rfc-editor.org/rfc/rfc8439)
- [BLAKE3](https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf)
- [Multibase](https://github.com/multiformats/multibase)
- [Multicodec](https://github.com/multiformats/multicodec)
- [nanoid](https://github.com/ai/nanoid)
