# did:ma Extension Namespace — `ma`

**Version:** 0.0.3
**Status:** Draft

## Abstract

A `did:ma` DID document provides everything needed to send signed, encrypted
messages to a subject. Any extensions beyond that core messaging purpose MUST
be placed in the `ma` key of the document, stored in IPLD dag-cbor.

Concrete field definitions are specified by implementation profiles.

## 1. The `ma` Key

1. All `did:ma` method-specific extensions MUST be placed inside the top-level
   `ma` key in the DID document.
1. `ma` MUST be a CBOR map when present.
1. The `ma` map is part of the dag-cbor DID document stored in IPFS. Values
   within `ma` MAY contain IPLD links, making them natively traversable
   (e.g. `ipfs dag get <did-ipns>/ma/...`).
1. No `did:ma`-specific extensions are permitted outside the `ma` namespace.
1. Unknown fields within `ma` SHOULD be ignored.
1. The `ma` key is OPTIONAL. A valid `did:ma` document MAY omit it entirely.

## 2. Example

DAG-JSON for readability. Canonical format is dag-cbor.

```json
{
  "@context": ["https://www.w3.org/ns/did/v1"],
  "id": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr",
  "controller": ["did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr"],
  "verificationMethod": [],
  "assertionMethod": [],
  "keyAgreement": [],
  "proof": {},
  "ma": {}
}
```

## 3. Relationship to Base Document

The base DID document format (`did-document-format.md`) defines identity,
keys, proof, and serialization. The `ma` key extends the document with
method-specific metadata without modifying base document semantics.

## 4. Implementation Profiles

Concrete field schemas are specified in separate profile documents. Each
profile:

1. MUST document which fields it defines within `ma`.
1. MUST NOT place method-specific fields outside the `ma` key.
