# did:ma Method Specification

**Method Name:** `ma`
**Version:** 1.0.0
**Status:** Candidate Recommendation
**Authors:** Lars Bahner

## Abstract

The `did:ma` method is a decentralized identifier method that uses IPFS
content-addressed storage and IPNS name resolution as its verifiable data
registry. Each DID is bound to an IPNS key, and the corresponding DID document
is published as a dag-cbor object to IPFS and resolved via the IPNS name system.

The method name `ma` (間) refers to the Japanese concept of negative space — the
interval between things.

This document covers the full `did:ma` specification: identifier syntax, DID
document format, verification method types, proof format, serialisation, the
CRUD operation lifecycle, and security and privacy considerations.

### Design Philosophy

Decentralized messaging over IPFS/IPNS carries inherent latency: DHT lookups,
content propagation, and peer discovery all add delay. Reducing latency wherever
possible has therefore been an explicit design principle throughout the
development of `did:ma`. Concretely, this means preferring dag-cbor over JSON
for encoding (faster to serialise and parse), BLAKE3 over SHA-256 for hashing
(faster with equivalent or better security), and keeping the document structure
flat and minimal to reduce processing overhead at every step.

This approach breaks with JSON-LD. `did:ma` documents carry a `@context` field
for compatibility with DID Core tooling, but the method does not depend on
JSON-LD processing, RDF canonicalization, or linked-data graph semantics.
Dropping JSON-LD is a deliberate trade-off: it sacrifices semantic
interoperability with the broader linked-data ecosystem in exchange for a
simpler, faster, self-contained implementation stack.

### Scope Boundary

This document defines the `did:ma` DID method itself: identifier syntax,
DID document structure and cryptography, resolution/update lifecycle, registry
assumptions, and security/privacy considerations.

Implementation/runtime behaviour (for example world simulation protocols,
service transport layouts, or client command semantics) is out of scope for
this document and should be specified in separate implementation documents.

## Conformance

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

A conformant `did:ma` implementation is one that implements all MUST and
MUST NOT requirements defined in this specification.

## 1. Method Syntax

### 1.1 Method Name

The method name is `ma`.

### 1.2 Method-Specific Identifier

The `did:ma` method-specific identifier is an IPNS Name as defined in
[IPNS Spec §3.1](https://specs.ipfs.tech/ipns/ipns-record/#ipns-name).
An IPNS Name is a CIDv1-encoded Ed25519 public key using the `libp2p-key`
codec (`0x72`), encoded per the
[CID specification](https://github.com/multiformats/cid).
The canonical string form is base36lower (multibase prefix `k`).

`did:ma` implementations MUST accept any valid IPNS Name string. The method-specific
identifier is case-sensitive.

The ABNF definition for the `did:ma` identifier is:

```abnf
did-ma            = "did:ma:" method-specific-id
method-specific-id = ipns-name
ipns-name         = <CIDv1 string as defined by the IPNS specification>
```

### 1.3 DID URL Syntax

`did:ma` DID URLs consist of a DID and an optional fragment. The method
intentionally does NOT support the path or query components of the DID URL
syntax defined in DID Core §3.2. This is a deliberate design decision: `did:ma`
does not impose or imply any hierarchical structure, taxonomy, or routing
convention on identifiers. Resources are named flatly by fragment only.

A `did:ma` DID URL MUST NOT contain a path component (i.e. a `/`-separated
string following the method-specific identifier) or a query component (i.e. a
`?`-prefixed string). Resolvers MUST return an `invalidDid` error if a path or
query component is present.

Fragments identify resources within the DID subject's namespace, such as actor
inboxes, verification method identifiers, or named endpoints.

Fragment values MUST conform to the nanoid character set: ASCII letters, digits,
underscores, and hyphens. While fragments MAY carry any semantically meaningful
label, the use of nanoid-generated identifiers is RECOMMENDED for uniqueness and
collision avoidance. All fragment values MUST match the pattern
`^[a-zA-Z0-9_-]+$`.

```abnf
did-ma-url  = did-ma [ "#" fragment ]
fragment    = 1*fchar
fchar       = ALPHA / DIGIT / "_" / "-"
```

### 1.4 Examples

Root DID (identifies the IPNS namespace):

```text
did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr
```

DID URL with fragment (identifies a named actor within the namespace):

```text
did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#bahner
```

## 2. DID Document

### 2.1 Context

All `did:ma` DID documents MUST include the following `@context` value:

```json
["https://www.w3.org/ns/did/v1.1"]
```

### 2.2 Document Structure

A `did:ma` DID document has the following properties:

| Property             | Required | Description                                                                                                             |
| -------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------- |
| `@context`           | Yes      | JSON-LD context. Always `["https://www.w3.org/ns/did/v1.1"]`.                                                          |
| `id`                 | Yes      | The DID string, conforming to `did:ma:<method-specific-id>`.                                                            |
| `controller`         | Yes      | DID string or array of DID strings that control this document. Controllers must have access to the IPNS private key.    |
| `verificationMethod` | Yes      | Array of verification method objects.                                                                                   |
| `assertionMethod`    | Yes      | Array of DID URL strings referencing signing verification methods.                                                      |
| `keyAgreement`       | Yes      | Array of DID URL strings referencing encryption verification methods.                                                   |
| `proof`              | Yes      | Proof object containing the document signature.                                                                         |
| `createdAt`          | Yes      | RFC 3339 UTC timestamp of initial document creation, with whole-second precision. Set once and never changed.           |
| `updatedAt`          | Yes      | RFC 3339 UTC timestamp of the most recent update, with whole-second precision. Updated on every new publication.        |
| `ma`                 | No       | Method-specific extension namespace. See `core/ma-did-ma-fields-v1.md`.                                                   |

### 2.3 Verification Methods

Each verification method in a `did:ma` document uses the `Multikey` type with
`publicKeyMultibase` encoding.

#### 2.3.1 Verification Method Structure

```json
{
  "id": "did:ma:<ipns>#<fragment>",
  "type": "Multikey",
  "controller": "did:ma:<ipns>",
  "publicKeyMultibase": "<multibase-encoded key>"
}
```

| Property             | Required | Description                                                            |
| -------------------- | -------- | ---------------------------------------------------------------------- |
| `id`                 | Yes      | DID URL identifying this verification method, including a fragment.    |
| `type`               | Yes      | Always `"Multikey"`.                                                   |
| `controller`         | Yes      | DID string identifying the controller of this key (per DID Core §5.2).|
| `publicKeyMultibase` | Yes      | Multibase-encoded public key (see section 2.3.2).                      |

#### 2.3.2 Public Key Encoding

Public keys are encoded using the multicodec + multibase pipeline:

1. **Multicodec prefix:** Prepend the unsigned varint-encoded codec identifier
   to the raw public key bytes.

1. **Multibase encoding:** Encode the result using Base58Btc (multibase prefix
   `z`).

   The resulting string has the form `z<base58btc-encoded-data>`.

##### Codec Values

| Algorithm          | Multicodec    | Hex     | Usage                                   |
| ------------------ | ------------- | ------- | --------------------------------------- |
| Ed25519 public key | `ed25519-pub` | `0xed`  | Assertion method (signing/verification) |
| X25519 public key  | `x25519-pub`  | `0xec`  | Key agreement (encryption)              |
| EdDSA signature    | `eddsa`       | `0xd0ed`| Document proof signature                |

#### 2.3.3 Assertion Method

The assertion method is an Ed25519 verification method used for:

- Signing DID documents (proofs).
- Signing messages.
- Verifying the authenticity of statements made by the DID subject.

The `assertionMethod` property in the document is an array of DID URL strings
referencing verification methods by their `id`.

#### 2.3.4 Key Agreement

The key agreement method is an X25519 verification method used for:

- Elliptic-curve Diffie-Hellman (ECDH) key exchange.
- Deriving shared secrets for encrypted messaging.

The `keyAgreement` property in the document is an array of DID URL strings
referencing verification methods by their `id`.

#### 2.3.5 Omitted Verification Relationships

The `did:ma` method does not use the W3C DID Core `authentication`,
`capabilityInvocation`, or `capabilityDelegation` verification relationships.
Authentication in `did:ma` is implicit: any party that can produce a valid
Ed25519 signature verifiable against the document's `assertionMethod` key is
authenticated. Capability relationships are not used because `did:ma` does not
define a capability delegation model at the DID layer.

### 2.4 Proof Format

#### 2.4.1 Proof Type: MultiformatSignature2023

`MultiformatSignature2023` is a proof type defined by and normative within
`did:ma`. Implementations MUST use this proof type for all `did:ma` DID
document proofs. It is not registered with any external standards body.

`did:ma` uses dag-cbor as its canonical serialisation format and BLAKE3 as
its hash function. dag-cbor is faster to encode and decode than JSON-LD, and
BLAKE3 is significantly faster than SHA-256 while providing equivalent or
better security. This keeps the entire signing and verification path within
the IPLD/multiformat ecosystem and avoids the overhead of JSON-LD
canonicalization (URDNA2015/RDFC-1.0).

The name reflects the multiformat encoding pipeline (multibase + multicodec)
used for both key material and signature values, combined with the 2023 design
vintage of the format. The name is backdated — the type was first defined in
2024 — and may theoretically collide with other formats created independently
under the same name. Within `did:ma`, the definition in this section is
authoritative.

##### Definition

MultiformatSignature2023 is an Ed25519 document signature scheme with the
following characteristics:

1. **Signature algorithm:** Ed25519 (RFC 8032).
1. **Payload:** dag-cbor serialisation of the document with the `proof` field
   cleared (set to default/empty `proofValue`).
1. **Hash function:** BLAKE3, producing a 32-byte digest of the dag-cbor payload.
1. **Input to sign/verify:** The 32-byte BLAKE3 digest (not the raw dag-cbor bytes).
1. **Signature encoding:** The raw Ed25519 signature bytes (64 bytes) are
   prefixed with the `eddsa` multicodec varint (`0xd0ed`), then the
   prefixed bytes are encoded using multibase Base58Btc (prefix `z`).
1. **Key encoding:** Public keys in `verificationMethod` entries use the
   multicodec + multibase pipeline described in section 2.3.2 (multicodec varint
   prefix + Base58Btc).
1. **Proof purpose:** Always `assertionMethod`. The referenced verification
   method MUST be an Ed25519 key listed in the document's `verificationMethod`
   array.

   This differs from W3C Data Integrity proof suites in that it uses dag-cbor
   (not JSON-LD canonicalization) as the serialisation format and BLAKE3 (not
   SHA-256) as the hash function. It uses multicodec prefixes on both keys and
   signatures, making all encoded values self-describing.

#### 2.4.2 Proof Structure

```json
{
  "type": "MultiformatSignature2023",
  "verificationMethod": "did:ma:<ipns>#<fragment>",
  "proofPurpose": "assertionMethod",
  "proofValue": "<multibase-encoded signature>"
}
```

| Property             | Required | Description                                                                 |
| -------------------- | -------- | --------------------------------------------------------------------------- |
| `type`               | Yes      | Always `"MultiformatSignature2023"`.                                         |
| `verificationMethod` | Yes      | DID URL referencing the verification method used to create the proof.       |
| `proofPurpose`       | Yes      | Always `"assertionMethod"`.                                                  |
| `proofValue`         | Yes      | Multibase Base58Btc-encoded Ed25519 signature with `eddsa` (`0xd0ed`) prefix.|

#### 2.4.3 Signing Algorithm

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

#### 2.4.4 Verification Algorithm

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

### 2.5 Serialisation

#### 2.5.1 dag-cbor (Storage and Wire Format)

DID documents MUST be stored in IPFS using the dag-cbor codec via `dag put`.
This enables IPLD path traversal through the document structure and allows
fields containing IPLD links (objects of the form `{"/": "<cid>"}`) to be
resolved as native DAG links by Kubo.

The dag-cbor representation uses the same property names as the JSON
representation (camelCase).

#### 2.5.2 JSON (Display and Interchange)

For display, debugging, and interchange with systems that do not support
dag-cbor, DID documents MAY be represented as JSON with the media type
`application/did+json`.

JSON serialisation uses camelCase property names as defined in the document
structure tables above:

- `@context`, `verificationMethod`, `assertionMethod`, `keyAgreement`,
  `publicKeyMultibase`, `proofPurpose`, `proofValue`.

#### 2.5.3 Canonical Serialisation (Signing)

For signing, hashing, and proof computation, DID documents are serialised to
dag-cbor. Map keys MUST be sorted lexicographically (dag-cbor deterministic
encoding) to ensure all implementations produce identical bytes for the same
logical structure. dag-cbor is the canonical format for computing document
hashes and proof signatures.

Note: Messages use plain CBOR (RFC 8949) for signing — not dag-cbor —
because messages are not stored in IPFS and do not contain IPLD links. See
[ma-messaging-format-v1.md](core/ma-messaging-format-v1.md) §3 for message signing.

The CBOR representation uses the same property names as the JSON representation.

### 2.6 Method-Specific Extensions Namespace

All method-specific extensions MUST be placed under the top-level `ma` key in
the DID document. No `did:ma`-specific fields are permitted outside this
namespace.

The concrete `ma` field schema is specified in `core/ma-did-ma-fields-v1.md`.

### 2.7 Example DID Document

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
  }
}
```

## 3. Method Operations

### 3.1 Create

To create a `did:ma` identifier and its associated DID document:

1. **Generate an IPNS key pair.** Use an IPFS node to generate a new key,
   or import an existing Ed25519 key. The resulting IPNS key identifier (a CIDv1
   string) becomes the method-specific identifier.

   Kubo is the de facto standard IPFS implementation. Generating keys directly
   through the IPFS node (rather than importing externally created keys)
   is RECOMMENDED, as it ensures the key material never exists outside the
   node's keystore. Either approach is acceptable.

1. **Generate cryptographic key material:**
   - Generate an Ed25519 signing key pair for assertion.
   - Generate an X25519 key pair for key agreement (encryption).

1. **Construct the DID document.** Build a conforming DID document containing:
   - The DID as the `id` field.
   - At least one verification method of type `Multikey` with a
     `publicKeyMultibase`-encoded Ed25519 public key (multicodec `0xed`).

   - At least one key agreement method of type `Multikey` with a
     `publicKeyMultibase`-encoded X25519 public key (multicodec `0xec`).

   - An `assertionMethod` reference to the signing verification method.
   - A `keyAgreement` reference to the encryption verification method.

1. **Sign the document.** Create a proof of type `MultiformatSignature2023`:
   - Serialize the document without the proof field to dag-cbor (sorted keys).
   - Compute the BLAKE3 hash of the dag-cbor payload.
   - Sign the hash with the Ed25519 signing key.
   - Prefix the signature with the `eddsa` multicodec varint (`0xd0ed`) and
     encode as a multibase Base58Btc string.
   - Attach the proof to the document.

1. **Publish to IPFS/IPNS:**
   - Store the signed document to IPFS as dag-cbor using `dag put`, obtaining
     a content identifier (CID).
   - Publish the CID as an IPNS record under the key from step 1.

   The DID is now resolvable via IPNS.

### 3.2 Read (Resolve)

To resolve a `did:ma` identifier to a DID document:

1. **Parse the DID** to extract the method-specific identifier (IPNS key).
1. **Resolve the IPNS name** to obtain the current CID of the DID document.
1. **Fetch the document** from IPFS using `dag get` with the resolved CID.
1. **Deserialise** the dag-cbor payload into a DID document.
1. **Verify the proof:**
   - Locate the verification method referenced by the proof's
     `verificationMethod` field.

   - Serialize the document without the proof to dag-cbor (sorted keys).
   - Compute the BLAKE3 hash of the dag-cbor payload.
   - Decode the multibase-encoded `proofValue` and verify the `eddsa`
     multicodec prefix (`0xd0ed`).
   - Verify the Ed25519 signature against the assertion method's public key.
1. **Return** the verified DID document.

If the IPNS name cannot be resolved, return a `notFound` error. If the proof
verification fails, return an `invalidDidDocument` error.

### 3.3 Update

To update a `did:ma` DID document:

1. **Resolve** the current DID document as described in section 3.2.
1. **Modify** the document fields as needed (e.g., add/remove verification
   methods, update services, change controller).

1. **Re-sign** the document by repeating the signing process from section 3.1,
   step 4.

1. **Republish** the updated document to IPFS via `dag put` and update the
   IPNS record.

   Authorisation: Any controller listed in the document may request or perform
   updates, provided they have access to the IPNS private key. The IPNS key is
   required to update the name record; the Ed25519 signing key is required to
   produce a valid proof.

### 3.4 Deactivate

To deactivate a `did:ma` identifier:

1. **Stop publishing** the IPNS record. The IPNS name will eventually expire and
  become unresolvable. Resolvers MUST return `notFound` once the IPNS name no
  longer resolves to a DID document.

1. Alternatively, **publish a final deactivated document** before destroying the
  IPNS key. A deactivated document MUST still be a conforming signed DID
  document, but SHOULD contain no service endpoints and no active verification
  relationships beyond the keys required to verify the final proof. Resolvers
  that understand `did:ma` deactivation metadata SHOULD treat such a document as
  deactivated and MUST NOT use it as an active service or verification document.

   Deactivation is effectively irreversible if the IPNS key is destroyed.

## 4. Verifiable Data Registry

The `did:ma` method uses the InterPlanetary File System (IPFS) and
InterPlanetary Name System (IPNS) as its verifiable data registry.

- **IPFS** provides content-addressed, immutable storage for DID documents. Each
  version of a document is identified by its content hash (CID).

- **IPNS** provides mutable name resolution. An IPNS name is bound to a
  cryptographic key pair and can be updated to point to new CIDs over time.

  The combination ensures that:

- Document integrity is guaranteed by content addressing.
- Document authenticity is guaranteed by IPNS record signatures.
- Document freshness is guaranteed by IPNS record expiration and re-publication.

No blockchain, distributed ledger, or centralized registry is required. Any IPFS
node running an IPNS resolver can resolve `did:ma` identifiers.

## 5. Security Considerations

### 5.1 Cryptographic Algorithms

- **Ed25519** (EdDSA over Curve25519) is used for all signing operations,
  including DID document proofs and message signatures. Ed25519 provides 128-bit
  security.

- **X25519** (ECDH over Curve25519) is used for key agreement in encrypted
  messaging.

- **BLAKE3** is used as the hash function for document payloads, message content
  hashing, and key derivation. BLAKE3 provides 256-bit security with performance
  advantages over SHA-256.

- **XChaCha20-Poly1305** is used for authenticated encryption of message content
  in envelopes.

### 5.2 Key Management

- Private signing keys and encryption keys MUST be kept secret.
- The IPNS key pair is separate from the DID document's verification method
  keys. Both are required for document updates.

- Key rotation is performed by updating the DID document with new verification
  methods and re-signing.

- Compromised keys SHOULD be rotated immediately by publishing an updated
  document.

### 5.3 Document Integrity

- DID documents are self-signed using the `MultiformatSignature2023` proof type.
- The proof covers the entire document (excluding the proof itself) via dag-cbor
  serialisation and BLAKE3 hashing.

- IPFS content addressing provides an additional integrity check — the CID of
  the document is a hash of its content.

- IPNS records include their own signature, providing transport-level
  authenticity.

### 5.4 Replay Protection

- Messages in the `did:ma` protocol include a unique identifier (nanoid), a
  timestamp, and a content hash.

- Receivers maintain a replay guard that tracks seen message IDs within a
  configurable time window (default: 120 seconds).

- Clock skew tolerance of 30 seconds is permitted.

### 5.5 Transport Authentication

- The `did:ma` method is transport-agnostic. Any transport that provides
  authenticated, encrypted channels MAY be used (e.g., direct peer-to-peer,
  WebRTC, relay-based).

- IPNS resolution depends on the security of the IPFS network and the DHT.
  Resolvers should verify IPNS record signatures.

### 5.6 Residual Risks

- If the IPNS private key is compromised, an attacker can publish a fraudulent
  DID document. Mitigation: destroy the key and inform relying parties out of
  band.

- IPNS resolution depends on DHT availability. A partitioned or degraded IPFS
  network may prevent resolution.

- There is no built-in revocation list. Deactivation depends on IPNS record
  expiration.

## 6. Privacy Considerations

### 6.1 Personal Data

DID documents produced by this method SHOULD NOT contain personal data. The
document contains only cryptographic keys, method-specific metadata, and
optional operational hints (e.g., language preference, transport capabilities).

### 6.2 Correlation

- A `did:ma` identifier is a persistent, globally unique identifier. It can be
  used to correlate activity across contexts.

- The use of DID URL fragments enables sub-identifiers (e.g., `#alice`,
  `#lobby`) that are linked to the root DID, enabling correlation within the
  namespace.

- To mitigate correlation, subjects MAY use separate IPNS keys (and thus
  separate DIDs) for different contexts.

### 6.3 Surveillance

- DID documents are published to IPFS, a public network. Any party with the DID
  can fetch the document and observe its contents and update history.

- IPNS resolution queries are visible to DHT participants.
- Message content between actors can be encrypted end-to-end using the key
  agreement verification method, preventing content surveillance.

### 6.4 Stored Data Compromise

- Private keys stored on the local file system are vulnerable to compromise if
  the host is breached.

- Implementations SHOULD use passphrase-based encryption (e.g., Argon2id +
  XChaCha20-Poly1305) for local key storage, providing defense in depth.

### 6.5 Identifier Persistence

- `did:ma` identifiers are persistent as long as the IPNS record is maintained.
- Subjects can deactivate identifiers by ceasing IPNS publication or destroying
  the IPNS key.

- There is no mechanism to transfer ownership of an IPNS key; deactivation and
  re-creation under a new key is the prescribed approach.

## Further Reading

The `did:ma` method is the identity layer for the 間 actor framework.
Messaging, service protocols, runtime behaviour, and access control are
specified in the companion documents in this repository — see
[ma-messaging-format-v1.md](core/ma-messaging-format-v1.md) to start, or browse the `ma-*`
files alongside this one.

## Reference Implementation

- [rust-ma-core](https://github.com/bahner/rust-ma-core) — Rust implementation of the `did:ma` method, DID document handling, message format, and transport layer.

## References

- [W3C Decentralized Identifiers (DIDs) v1.1](https://www.w3.org/TR/did-1.1/)
- [W3C DID Specification Registries](https://www.w3.org/TR/did-spec-registries/)
- [IPFS Documentation](https://docs.ipfs.tech/)
- [IPNS Specification](https://specs.ipfs.tech/ipns/ipns-record/)
- [Multibase Specification](https://github.com/multiformats/multibase)
- [Multicodec Table](https://github.com/multiformats/multicodec/blob/master/table.csv)
- [Ed25519 (RFC 8032)](https://www.rfc-editor.org/rfc/rfc8032)
- [X25519 (RFC 7748)](https://www.rfc-editor.org/rfc/rfc7748)
- [BLAKE3](https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf)
- [XChaCha20-Poly1305](https://www.rfc-editor.org/rfc/rfc8439)
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
