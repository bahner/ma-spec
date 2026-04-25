# DID Document Format: did:ma

**Version:** 0.0.3
**Status:** Draft

## Abstract

This document specifies the DID document format produced and consumed by the
`did:ma` method. It defines the document structure, verification method types,
proof format, and serialization.

## 1. Context

All `did:ma` DID documents MUST include the following `@context` value:

```json
["https://www.w3.org/ns/did/v1.1"]
```

## 2. Document Structure

A `did:ma` DID document has the following properties:

| Property | Required | Description |
| --- | --- | --- |
| `@context` | Yes | JSON-LD context. Always `["https://www.w3.org/ns/did/v1.1"]`. |
| `id` | Yes | The DID. A string conforming to `did:ma:<method-specific-id>`. |
| `controller` | Yes | DID string or array of DID strings that control this document. All listed controllers may request or perform updates in any setting where they have access to the IPNS private key. |
| `verificationMethod` | Yes | Array of verification method objects. |
| `assertionMethod` | Yes | Array of DID URL strings referencing signing verification methods. |
| `keyAgreement` | Yes | Array of DID URL strings referencing encryption verification methods. |
| `proof` | Yes | Proof object containing the document signature. |
| `createdAt` | Yes | RFC 3339 UTC timestamp of initial document creation with nanosecond granularity (e.g. `"2025-04-17T12:00:00.000000000Z"`). Set once and never changed. |
| `updatedAt` | Yes | RFC 3339 UTC timestamp of the most recent document update with nanosecond granularity. Updated on every new publication. |
| `identity` | No | CID string referencing a content object in IPFS that describes the subject (e.g. profile, avatar, or service description). This is a top-level field, not placed under `ma`, because it describes the DID subject itself rather than method-specific metadata. |
| `ma` | No | Method-specific extension namespace. See `core/did-ma-fields.md`. |

## 3. Verification Methods

Each verification method in a `did:ma` document uses the `Multikey` type with
`publicKeyMultibase` encoding.

### 3.1 Verification Method Structure

```json
{
  "id": "did:ma:<ipns>#<fragment>",
  "type": "Multikey",
  "controller": "did:ma:<ipns>",
  "publicKeyMultibase": "<multibase-encoded key>"
}
```

| Property | Required | Description |
| --- | --- | --- |
| `id` | Yes | DID URL identifying this verification method, including a fragment. |
| `type` | Yes | Always `"Multikey"`. |
| `controller` | Yes | DID string identifying the controller of this key (per W3C DID Core §5.2). |
| `publicKeyMultibase` | Yes | Multibase-encoded public key (see section 3.2). |

### 3.2 Public Key Encoding

Public keys are encoded using the multicodec + multibase pipeline:

1. **Multicodec prefix:** Prepend the unsigned varint-encoded codec identifier
   to the raw public key bytes.

1. **Multibase encoding:** Encode the result using Base58Btc (multibase prefix
   `z`).

   The resulting string has the form `z<base58btc-encoded-data>`.

#### Codec Values

| Algorithm | Multicodec | Hex | Usage |
| --- | --- | --- | --- |
| Ed25519 public key | `ed25519-pub` | `0xed` | Assertion method (signing/verification) |
| X25519 public key | `x25519-pub` | `0xec` | Key agreement (encryption) |
| EdDSA signature | `eddsa` | `0xd0ed` | Document proof signature |

### 3.3 Assertion Method

The assertion method is an Ed25519 verification method used for:

- Signing DID documents (proofs).
- Signing messages.
- Verifying the authenticity of statements made by the DID subject.

The `assertionMethod` property in the document is an array of DID URL strings
referencing verification methods by their `id`.

### 3.4 Key Agreement

The key agreement method is an X25519 verification method used for:

- Elliptic-curve Diffie-Hellman (ECDH) key exchange.
- Deriving shared secrets for encrypted messaging.

The `keyAgreement` property in the document is an array of DID URL strings
referencing verification methods by their `id`.

### 3.5 Omitted Verification Relationships

The `did:ma` method does not use the W3C DID Core `authentication`,
`capabilityInvocation`, or `capabilityDelegation` verification relationships.
Authentication in `did:ma` is implicit: any party that can produce a valid
Ed25519 signature verifiable against the document's `assertionMethod` key is
authenticated. Capability relationships are not used because `did:ma` does not
define a capability delegation model at the DID layer.

## 4. Proof Format

### 4.1 Proof Type: MultiformatSignature2023

`MultiformatSignature2023` is a proof type defined by `did:ma`. It is not
registered with any external standards body. The name reflects the multiformat
encoding pipeline (multibase + multicodec) used for both key material and
signature values, combined with the 2023 design vintage of the format.

The name is backdated — the type was first defined in 2025 — so it may
theoretically collide with other formats created independently under the same
name. Within `did:ma`, the implementation in this section is the authoritative
definition.

#### 4.1.1 Definition

MultiformatSignature2023 is an Ed25519 document signature scheme with the
following characteristics:

1. **Signature algorithm:** Ed25519 (RFC 8032).
1. **Payload:** dag-cbor serialization of the document with the `proof` field
   cleared (set to default/empty `proofValue`).
1. **Hash function:** BLAKE3, producing a 32-byte digest of the dag-cbor payload.
1. **Input to sign/verify:** The 32-byte BLAKE3 digest (not the raw dag-cbor bytes).
1. **Signature encoding:** The raw Ed25519 signature bytes (64 bytes) are
   prefixed with the `eddsa` multicodec varint (`0xd0ed`), then the
   prefixed bytes are encoded using multibase Base58Btc (prefix `z`).
1. **Key encoding:** Public keys in `verificationMethod` entries use the
   multicodec + multibase pipeline described in section 3.2 (multicodec varint
   prefix + Base58Btc).
1. **Proof purpose:** Always `assertionMethod`. The referenced verification
   method MUST be an Ed25519 key listed in the document's `verificationMethod`
   array.

   This differs from W3C Data Integrity proof suites in that it uses dag-cbor
   (not JSON-LD canonicalization) as the serialization format and BLAKE3 (not
   SHA-256) as the hash function. It uses multicodec prefixes on both keys and signatures,
   making all encoded values self-describing.

### 4.2 Proof Structure

```json
{
  "type": "MultiformatSignature2023",
  "verificationMethod": "did:ma:<ipns>#<fragment>",
  "proofPurpose": "assertionMethod",
  "proofValue": "<multibase-encoded signature>"
}
```

| Property | Required | Description |
| --- | --- | --- |
| `type` | Yes | Always `"MultiformatSignature2023"`. |
| `verificationMethod` | Yes | DID URL referencing the verification method used to create the proof. |
| `proofPurpose` | Yes | Always `"assertionMethod"`. |
| `proofValue` | Yes | Multibase Base58Btc-encoded Ed25519 signature with `eddsa` (`0xd0ed`) multicodec prefix. |

### 4.3 Signing Algorithm

1. **Prepare the payload document:** Clone the document and set the `proof`
   field to an empty proof (empty `proofValue`).

1. **Serialize to dag-cbor:** Encode the payload document as dag-cbor
   (RFC 8949, deterministic encoding with lexicographically sorted map keys).
1. **Hash:** Compute the BLAKE3 hash of the dag-cbor bytes, producing a
   32-byte digest.

1. **Sign:** Sign the 32-byte digest with the Ed25519 private key corresponding
   to the assertion method.

1. **Encode:** Prefix the signature bytes with the `eddsa` multicodec varint
   (`0xd0ed`), then encode using multibase Base58Btc (prefix `z`).

1. **Attach:** Set the `proofValue` field to the encoded signature string.

### 4.4 Verification Algorithm

1. **Extract the proof** from the document.
1. **Locate the verification method** referenced by `proof.verificationMethod`
   in the document's `verificationMethod` array.

1. **Decode the public key** from `publicKeyMultibase`: strip the multibase
   prefix, decode Base58Btc, strip the multicodec varint prefix (`0xed`),
   yielding the raw Ed25519 public key bytes.

1. **Prepare the payload document:** Clone the document and set the `proof`
   field to an empty proof.

1. **Serialize** the payload to dag-cbor (sorted keys).
1. **Hash** the dag-cbor bytes with BLAKE3.
1. **Decode the signature** from `proof.proofValue`: strip the multibase prefix
   and decode Base58Btc, then strip and verify the `eddsa` multicodec varint
   prefix (`0xd0ed`), yielding the raw Ed25519 signature bytes.

1. **Verify** the Ed25519 signature against the hash and the decoded public key.

## 5. Serialization

### 5.1 dag-cbor (Storage and Wire Format)

DID documents MUST be stored in IPFS using the dag-cbor codec via `dag put`.
This enables IPLD path traversal through the document structure and allows
fields containing IPLD links (objects of the form `{"/": "<cid>"}`) to be
resolved as native DAG links by Kubo.

The dag-cbor representation uses the same property names as the JSON
representation (camelCase).

### 5.2 JSON (Display and Interchange)

For display, debugging, and interchange with systems that do not support
dag-cbor, DID documents MAY be represented as JSON with the media type
`application/did+json`.

JSON serialization uses camelCase property names as defined in the document
structure tables above:

- `@context`, `verificationMethod`, `assertionMethod`, `keyAgreement`,
  `publicKeyMultibase`, `proofPurpose`, `proofValue`.

### 5.3 Canonical Serialization (Signing)

For signing, hashing, and proof computation, DID documents are serialized to
dag-cbor. Map keys MUST be sorted lexicographically (dag-cbor deterministic
encoding) to ensure all implementations produce identical bytes for the same
logical structure. dag-cbor is the canonical format for computing document
hashes and proof signatures.

Note: Messages use plain CBOR (RFC 8949) with sorted keys for signing — not
dag-cbor — because messages are not stored in IPFS and do not contain IPLD
links. See [messaging-format.md](messaging-format.md) §3 for message signing.

The CBOR representation uses the same property names as the JSON representation.

## 6. Method-Specific Extensions Namespace

All method-specific extensions MUST be placed under the top-level `ma` key in
the DID document. No `did:ma`-specific fields are permitted outside this
namespace, with one exception: the `identity` field (§2) is top-level because
it describes the DID subject itself, not method-specific metadata.

The concrete `ma` field schema is specified in `core/did-ma-fields.md`.

## 7. Example DID Document (Core)

```json
{
  "@context": ["https://www.w3.org/ns/did/v1.1"],
  "id": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr",
  "controller": [
    "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr"
  ],
  "verificationMethod": [
    {
      "id": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#signing",
      "type": "Multikey",
      "controller": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr",
      "publicKeyMultibase": "z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
    },
    {
      "id": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#encryption",
      "type": "Multikey",
      "controller": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr",
      "publicKeyMultibase": "z6LSbysY2xFMRpGMhb7tFTLMpeuPRaqaWM1yECx2AtzE3KCc"
    }
  ],
  "assertionMethod": [
    "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#signing"
  ],
  "keyAgreement": [
    "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#encryption"
  ],
  "proof": {
    "type": "MultiformatSignature2023",
    "verificationMethod": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#signing",
    "proofPurpose": "assertionMethod",
    "proofValue": "z5vJGBFmMGCzfw2gMwZMGuQDUnh3S5M4GZEEMqVPSBZPzBNks1VpmPSjc12QYfqMz4k1PJLerRJNiKJsLCi7h2aSR"
  },
  "identity": "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"
}
```
