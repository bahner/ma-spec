# DID Method Specification: did:ma

**Method Name:** `ma`
**Version:** 0.0.1
**Status:** Draft
**Authors:** Lars Bahner

## Abstract

The `did:ma` method is a decentralized identifier method that uses IPFS
content-addressed storage and IPNS name resolution as its verifiable data
registry. Each DID is bound to an IPNS key, and the corresponding DID document
is published as a JSON object to IPFS and resolved via the IPNS name system.

The method name `ma` (間) refers to the Japanese concept of negative space — the
interval between things.

## 1. Method Syntax

### 1.1 Method Name

The method name is `ma`.

### 1.2 Method-Specific Identifier

The `did:ma` method-specific identifier is a CIDv1-encoded IPNS public key. The
identifier MUST be encoded as either base36lower or base58btc and MUST contain
only ASCII alphanumeric characters.

The ABNF definition for the `did:ma` identifier:

```abnf
did-ma            = "did:ma:" method-specific-id
method-specific-id = 1*idchar
idchar             = ALPHA / DIGIT
```

The method-specific identifier is case-sensitive.

### 1.3 DID URL Syntax

The `did:ma` method supports the standard DID URL fragment component. Fragments
identify sub-resources within the DID subject's domain, such as actor inboxes,
verification method identifiers, or named endpoints.

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

```
did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr
```

DID URL with fragment (identifies a named actor within the namespace):

```
did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#bahner
```

## 2. Method Operations

### 2.1 Create

To create a `did:ma` identifier and its associated DID document:

1. **Generate an IPNS key pair.** Use the Kubo IPFS node to generate a new key,
   or import an existing Ed25519 key. The resulting IPNS key identifier (a CIDv1
   string) becomes the method-specific identifier.

1. **Generate cryptographic key material:**
   - Generate an Ed25519 signing key pair for assertion and authentication.
   - Generate an X25519 key pair for key agreement (encryption).

1. **Construct the DID document.** Build a conforming DID document containing:
   - The DID as the `id` field.
   - At least one verification method of type `MultiKey` with a
     `publicKeyMultibase`-encoded Ed25519 public key (multicodec `0xed`).

   - At least one key agreement method of type `MultiKey` with a
     `publicKeyMultibase`-encoded X25519 public key (multicodec `0xec`).

   - An `assertionMethod` reference to the signing verification method.
   - A `keyAgreement` reference to the encryption verification method.

1. **Sign the document.** Create a proof of type `MultiformatSignature2023`:
   - Serialize the document without the proof field to CBOR.
   - Compute the BLAKE3 hash of the CBOR payload.
   - Sign the hash with the Ed25519 signing key.
   - Encode the signature as a multibase Base58Btc string.
   - Attach the proof to the document.

1. **Publish to IPFS/IPNS:**
   - Serialize the signed document to JSON.
   - Add the JSON to IPFS, obtaining a content identifier (CID).
   - Publish the CID as an IPNS record under the key from step 1.

The DID is now resolvable via IPNS.

### 2.2 Read (Resolve)

To resolve a `did:ma` identifier to a DID document:

1. **Parse the DID** to extract the method-specific identifier (IPNS key).
1. **Resolve the IPNS name** to obtain the current CID of the DID document.
1. **Fetch the document** from IPFS using the resolved CID.
1. **Deserialize** the JSON payload into a DID document.
1. **Verify the proof:**
   - Locate the verification method referenced by the proof's
     `verificationMethod` field.

   - Serialize the document without the proof to CBOR.
   - Compute the BLAKE3 hash of the CBOR payload.
   - Decode the multibase-encoded `proofValue`.
   - Verify the Ed25519 signature against the assertion method's public key.
1. **Return** the verified DID document.

If the IPNS name cannot be resolved, return a `notFound` error. If the proof
verification fails, return an `invalidDidDocument` error.

### 2.3 Update

To update a `did:ma` DID document:

1. **Resolve** the current DID document as described in section 2.2.
1. **Modify** the document fields as needed (e.g., add/remove verification
   methods, update services, change controller).

1. **Re-sign** the document by repeating the signing process from section 2.1,
   step 4.

1. **Republish** the updated document to IPFS and update the IPNS record.

Authorization: Any controller listed in the document may request or perform
updates, provided they have access to the IPNS private key. The IPNS key is
required to update the name record; the Ed25519 signing key is required to
produce a valid proof.

### 2.4 Deactivate

To deactivate a `did:ma` identifier:

1. **Stop publishing** the IPNS record. The IPNS name will eventually expire and
   become unresolvable.

1. Alternatively, **publish a deactivated document** — a minimal document
   containing only the `id` field and no verification methods or proof — to
   signal explicit deactivation.

Deactivation is effectively irreversible if the IPNS key is destroyed.

## 3. Verifiable Data Registry

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

## 4. Security Considerations

### 4.1 Cryptographic Algorithms

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

### 4.2 Key Management

- Private signing keys and encryption keys MUST be kept secret.
- The IPNS key pair is separate from the DID document's verification method
  keys. Both are required for document updates.

- Key rotation is performed by updating the DID document with new verification
  methods and re-signing.

- Compromised keys should be rotated immediately by publishing an updated
  document.

### 4.3 Document Integrity

- DID documents are self-signed using the `MultiformatSignature2023` proof type.
- The proof covers the entire document (excluding the proof itself) via CBOR
  serialization and BLAKE3 hashing.

- IPFS content addressing provides an additional integrity check — the CID of
  the document is a hash of its content.

- IPNS records include their own signature, providing transport-level
  authenticity.

### 4.4 Replay Protection

- Messages in the `did:ma` protocol include a unique identifier (nanoid), a
  timestamp, and a content hash.

- Receivers maintain a replay guard that tracks seen message IDs within a
  configurable time window (default: 120 seconds).

- Clock skew tolerance of 30 seconds is permitted.

### 4.5 Transport Authentication

- The `did:ma` method is transport-agnostic. Any transport that provides
  authenticated, encrypted channels MAY be used (e.g., direct peer-to-peer,
  WebRTC, relay-based). The reference implementation currently uses iroh, whose
  connections are authenticated by the endpoint's cryptographic identity.

- IPNS resolution depends on the security of the IPFS network and the DHT.
  Resolvers should verify IPNS record signatures.

### 4.6 Residual Risks

- If the IPNS private key is compromised, an attacker can publish a fraudulent
  DID document. Mitigation: destroy the key and inform relying parties out of
  band.

- IPNS resolution depends on DHT availability. A partitioned or degraded IPFS
  network may prevent resolution.

- There is no built-in revocation list. Deactivation depends on IPNS record
  expiration.

## 5. Privacy Considerations

### 5.1 Personal Data

DID documents produced by this method SHOULD NOT contain personal data. The
document contains only cryptographic keys, method-specific metadata, and
optional operational hints (e.g., locale preference, transport capabilities).

### 5.2 Correlation

- A `did:ma` identifier is a persistent, globally unique identifier. It can be
  used to correlate activity across contexts.

- The use of DID URL fragments enables sub-identifiers (e.g., `#alice`,
  `#lobby`) that are linked to the root DID, enabling correlation within the
  namespace.

- To mitigate correlation, subjects MAY use separate IPNS keys (and thus
  separate DIDs) for different contexts.

### 5.3 Surveillance

- DID documents are published to IPFS, a public network. Any party with the DID
  can fetch the document and observe its contents and update history.

- IPNS resolution queries are visible to DHT participants.
- Message content between actors can be encrypted end-to-end using the key
  agreement verification method, preventing content surveillance.

### 5.4 Stored Data Compromise

- Private keys stored on the local file system are vulnerable to compromise if
  the host is breached.

- Implementations SHOULD use passphrase-based encryption (e.g., Argon2id +
  XChaCha20-Poly1305) for local key storage, providing defense in depth.

### 5.5 Identifier Persistence

- `did:ma` identifiers are persistent as long as the IPNS record is maintained.
- Subjects can deactivate identifiers by ceasing IPNS publication or destroying
  the IPNS key.

- There is no mechanism to transfer ownership of an IPNS key; deactivation and
  re-creation under a new key is the prescribed approach.

## References

- [W3C Decentralized Identifiers (DIDs) v1.0](https://www.w3.org/TR/did-core/)
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
