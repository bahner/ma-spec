# Messaging Format: did:ma

**Version:** 0.0.2
**Status:** Draft

## Abstract

This document specifies the messaging format used by the `did:ma` method.
Messages are signed CBOR structures that carry typed payloads between actors
identified by DIDs. The format supports DID document notifications,
encrypted point-to-point envelopes, and replay protection.

This document defines the protocol-level message format only. Runtime-specific
usage (for example world simulation commands, service protocol layouts, and
client UX conventions) is out of scope for this specification.

## 1. Message Structure

A message is a signed, typed container for content exchanged between actors.

### 1.1 Fields

| Field | Key | Type | Required | Description |
| --- | --- | --- | --- | --- |
| Identifier | `id` | string | Yes | Unique message identifier (nanoid: alphanumeric + `_` + `-`). |
| Type | `type` | string | Yes | Protocol version. Always `"/ma/0.0.1"`. |
| Sender | `from` | string | Yes | DID or DID URL of the sender. |
| Recipient | `to` | string | No | DID or DID URL of the recipient. MAY be empty for content types that do not require a specific recipient (e.g. broadcast). |
| Created at | `createdAt` | float | Yes | Unix timestamp in fractional seconds (nano-epoch, UTC). Nanosecond granularity is required. |
| TTL | `ttl` | integer | Yes | Message time-to-live in nanoseconds. Default `3_600_000_000_000`. Value `0` disables age-based expiration. |
| Content type | `contentType` | string | Yes | MIME-like content type identifier (see section 2). |
| Reply to | `replyTo` | string | No | Optional message ID this message replies to. |
| Content | `content` | bytes | Yes | Arbitrary payload bytes. |
| Signature | `signature` | bytes | Yes | Ed25519 signature over the message headers, prefixed with the `eddsa` multicodec varint (`0xd0ed`). |

The `type` field identifies the version of the `did:ma` messaging specification
used to construct the message. It is not a service protocol ID. A receiver that
does not recognise the `type` value MUST reject the message. There is currently
no version negotiation mechanism; version migration is handled by updating all
participants. The field exists to allow future revisions of this specification
to be distinguished from the current one.

Note: The `type` value `"/ma/0.0.1"`, service protocol IDs
(e.g. `/ma/inbox/0.0.1`), topic strings (e.g. `/ma/broadcast/0.0.1`), and the
BLAKE3 key derivation context `"/ma/0.0.1"` all use a leading slash, following
the IPFS protocol path convention. The headers key context `"ma"` is the sole
exception — it is a bare label. The difference is intentional.

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
| Created at | `createdAt` | float | Same as message `createdAt`. |
| TTL | `ttl` | integer | Same as message `ttl`. |
| Content type | `contentType` | string | Same as message `contentType`. |
| Reply to | `replyTo` | string | Optional message ID this message replies to. |
| Content hash | `contentHash` | bytes (32) | BLAKE3 hash of the message `content`. |
| Signature | `signature` | bytes | Ed25519 signature with `eddsa` multicodec prefix (`0xd0ed`); empty in unsigned headers. |

## 2. Content Types

Messages are classified by content type. Each content type identifies the
purpose and handling semantics of the payload.

### 2.1 Foundational Content Types

| Content Type | Value | Encryption | Description |
| --- | --- | --- | --- |
| Broadcast | `application/x-ma-broadcast` | Forbidden | Signed message without a specific recipient. MUST NOT be encrypted. Delivered via gossip or point-to-point via `/ma/inbox/0.0.1`. |
| Message | `application/x-ma-message` | Required | Generic point-to-point envelope. Content MAY be any payload (text, binary, JPEG, etc.). Delivered via `/ma/inbox/0.0.1`. |

Rules:

1. `application/x-ma-message` MUST always be transmitted as an encrypted
   envelope. Receivers MUST reject unencrypted `application/x-ma-message`
   payloads. Its `content` field is unconstrained and MAY carry any payload.
   Senders MUST NOT use `application/x-ma-message` when a more specific
   protocol applies (e.g. use `/ma/rpc/0.0.1` for function calls).
1. `application/x-ma-broadcast` MUST NOT be encrypted. It has no specific
   recipient and is signed only. The `to` field MAY be empty. Receivers MUST
   reject encrypted `application/x-ma-broadcast` payloads.

### 2.2 Core Extension Content Types

#### 2.2.1 `application/x-ma-ipfs-request`

| Property | Value |
| --- | --- |
| Encryption | Required |
| Service | `/ma/ipfs/0.0.1` |

Request to publish a DID document to IPFS/IPNS on behalf of a client that lacks
direct Kubo access. Contains secret key material and MUST only be sent over
encrypted channels to a trusted endpoint.

**Security warning:** This content type transmits an IPNS private key. The
sender is delegating full publishing authority over their DID to the receiver.
Only send this to endpoints you trust completely. A compromised or malicious
receiver can publish arbitrary DID documents under the sender's identity.
Senders SHOULD treat this as a last-resort mechanism and prefer direct IPFS
publishing when possible.

Payload is a CBOR object with the following fields:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `did_document` | bytes | Yes | IPLD dag-cbor encoded DID document to publish. |
| `ipns_private_key` | bytes | Yes | IPNS private key for publishing, as a raw CBOR byte string. |

The receiving endpoint MUST:

1. Validate the DID document.
2. Verify that the message sender's IPNS identity matches the document's DID.
3. Import the private key (raw bytes) under a deterministic name derived from
   the DID identity (e.g. BLAKE3 hash of the IPNS id).
4. Publish the document to IPFS/IPNS via the imported key.

### 2.3 Profile-Defined Content Types

Additional `application/x-ma-*` content types MAY be defined by implementation
profiles. Such profile-specific semantics are not normative for the base
`did:ma` format.

Implementations MUST use an explicit content type for every message.
`application/x-ma-message` serves as the generic fallback but MUST NOT be
used where a more specific protocol exists.

## 3. Signing

### 3.1 Signing Algorithm

Messages are signed using the sender's Ed25519 assertion method key as defined
in the [did:ma DID Document Format](did-document-format.md) (§3 Assertion
Method, §4 Proof). The same `MultiformatSignature2023` proof scheme applies:
Ed25519 over a BLAKE3 digest, with multicodec-prefixed keys and signatures.

The signature covers the headers (not the content directly), which include a
content hash for integrity binding.

1. **Construct unsigned headers:**
   - Copy all message fields into a `Headers` structure.
   - Compute the BLAKE3 hash of the `content` bytes and set `contentHash`.
   - Set `signature` to an empty byte array.
1. **Serialize headers to CBOR** (RFC 8949). Map keys MUST be sorted
   lexicographically to ensure all implementations produce identical bytes
   for the same logical structure.
1. **Hash** the CBOR bytes using BLAKE3, producing a 32-byte digest.
1. **Sign** the digest with the sender's Ed25519 private key.
1. **Encode:** Prefix the raw signature bytes with the `eddsa` multicodec
   varint (`0xd0ed`).
1. **Set** the `signature` field on both the headers and the message to the
   prefixed signature bytes.

### 3.2 Verification Algorithm

1. **Resolve the sender's DID document** using the `from` field.
1. **Extract the assertion method** verification key from the sender's document.
1. **Reconstruct unsigned headers:** Copy the message headers and clear the
   `signature` field.

1. **Serialize** the unsigned headers to CBOR (sorted keys).
1. **Hash** the CBOR bytes with BLAKE3.
1. **Decode** the signature: strip and verify the `eddsa` multicodec varint
   prefix (`0xd0ed`), yielding the raw Ed25519 signature bytes.
1. **Verify** the Ed25519 signature against the hash and the sender's
   public key.

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
| Encrypted content | `encryptedContent` | bytes | Nonce (24 bytes) followed by XChaCha20-Poly1305 ciphertext of the message content. |
| Encrypted headers | `encryptedHeaders` | bytes | Nonce (24 bytes) followed by XChaCha20-Poly1305 ciphertext of the serialized message headers. |

### 4.2 Encryption Algorithm

1. **Generate an ephemeral X25519 key pair.**
1. **Perform ECDH** between the ephemeral private key and the recipient's
   `keyAgreement` public key (from their DID document), producing a 32-byte
   shared secret.

1. **Derive symmetric keys** using BLAKE3 key derivation from the shared
   secret with fixed context labels:
   - Content encryption key: `blake3::derive_key("/ma/0.0.1", shared_secret)`
   - Headers encryption key: `blake3::derive_key("ma", shared_secret)`

   Both derived keys are 32 bytes (256 bits).

1. **Encrypt:**
   - Generate a random 24-byte nonce for each encryption operation.
   - Encrypt the message `content` with XChaCha20-Poly1305 using the content
     key and a random nonce.
   - Encrypt the serialized `Headers` (CBOR) with XChaCha20-Poly1305 using the
     headers key and a separate random nonce.
   - Prepend each nonce to its corresponding ciphertext. The stored format is
     `nonce || ciphertext` (24 bytes + ciphertext).

1. **Construct the envelope** with the ephemeral public key and both
   nonce-prefixed ciphertexts.

1. **Serialize the envelope** to CBOR for transport.

The context labels are version-bound. If a future protocol version changes
these labels, messages encrypted under the old labels will fail to decrypt.
This is intentional — version migration requires re-encryption, not silent
fallback.

### 4.3 Decryption Algorithm

1. **Deserialize** the envelope from CBOR.
1. **Perform ECDH** between the recipient's `keyAgreement` private key and the
   envelope's `ephemeralKey`, producing the shared secret.

1. **Derive symmetric keys** using the same BLAKE3 context labels
   (`"/ma/0.0.1"` for content, `"ma"` for headers).
1. **Split** each ciphertext field into nonce (first 24 bytes) and ciphertext
   (remainder).
1. **Decrypt** the headers and content using XChaCha20-Poly1305 with the
   corresponding key and nonce.
1. **Verify** the decrypted message signature as in section 3.2.

## 5. Replay Protection

### 5.1 Replay Guard

Receivers SHOULD maintain a replay guard to detect and reject duplicate or
replayed messages.

| Parameter | Default | Description |
| --- | --- | --- |
| Time window | 120 seconds | Duration for which message IDs are retained. |
| Clock skew tolerance | 30 seconds | Maximum permitted difference between sender and receiver clocks. |
| Message TTL | 3_600_000_000_000 nanoseconds | Default max age per message (`ttl=0` disables age-based expiration). |

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

## 7. Transport

The `did:ma` messaging protocol is transport-agnostic. Any transport providing
authenticated, encrypted, bidirectional channels MAY be used — including direct
peer-to-peer, WebRTC, or relay-based transports.

Transport-specific connection details are out of scope for the base `did:ma`
format.

## References

- [did:ma DID Document Format](did-document-format.md) — assertion method,
  proof scheme, verification
- [RPC Service Protocol (Core)](core/ma-rpc-service-v1.md) — `/ma/rpc/0.0.1`, term format, protocol mismatch
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
- [Ed25519 (RFC 8032)](https://www.rfc-editor.org/rfc/rfc8032)
- [X25519 (RFC 7748)](https://www.rfc-editor.org/rfc/rfc7748)
- [XChaCha20-Poly1305](https://www.rfc-editor.org/rfc/rfc8439)
- [BLAKE3](https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf)
- [Multibase](https://github.com/multiformats/multibase)
- [Multicodec](https://github.com/multiformats/multicodec)
- [nanoid](https://github.com/ai/nanoid)
