# did:ma Extension Namespace — `ma`

**Version:** 0.0.5
**Status:** Draft

## Abstract

A `did:ma` DID document provides everything needed to send signed, encrypted
messages to a subject. Any extensions beyond that core messaging purpose MUST
be placed in the `ma` key of the document, stored in IPLD dag-cbor.

Concrete field definitions are specified by implementation profiles.

## 1. The `ma` Key

1. All `did:ma` method-specific extensions MUST be placed inside the top-level
   `ma` key in the DID document.
1. `ma` MUST be a dag-cbor map when present. Since the DID document is stored
   in IPFS as dag-cbor, the `ma` map is natively part of the IPLD DAG. This
   means values within `ma` MAY contain IPLD links (CID references), and the
   entire `ma` subtree is traversable via IPLD paths
   (e.g. `ipfs dag get <did-ipns>/ma/services`).
1. No `did:ma`-specific extensions are permitted outside the `ma` namespace.
1. Unknown fields within `ma` SHOULD be ignored.
1. The `ma` key is OPTIONAL. A valid `did:ma` document MAY omit it entirely.
   However, a document without `ma` (or without `ma.services`) is valid but
   **unreachable** — the DID can be resolved and verified, but no transport
   endpoint is advertised. To be contactable, a document MUST include at
   least the `services` field (§1.1).

### 1.1 Reserved Field Names

The following field names within `ma` are reserved by the core specification:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `services` | array of strings | Yes (for reachability) | Multiaddr transport advertisement strings (see [core/services.md](core/services.md) §6). |

All other fields within `ma` are application-defined. Implementation profiles
(§4) MAY reserve additional field names for their own use.

### 1.2 Minimum Reachable Document

A document that only provides identity (keys + proof) is valid but unreachable.
To be contactable, a document MUST include `ma.services` with at least one
transport entry:

```json
"ma": {
  "services": [
    "/iroh/<node-id>/ma/inbox/0.0.1"
  ]
}
```

The multiaddr format is `/<transport>/<endpoint-id>/<protocol-id>`. See
[core/services.md](core/services.md) §6 for the full transport advertisement
specification.

## 2. Example

DAG-JSON for readability. Canonical format is dag-cbor.

```json
{
  "@context": ["https://www.w3.org/ns/did/v1.1"],
  "id": "did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr",
  "controller": ["did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr"],
  "verificationMethod": ["..."],
  "assertionMethod": ["did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#signing"],
  "keyAgreement": ["did:ma:k51qzi5uqu5dj9807pbuod1pplf0vxh8m4lfy3ewl9qbm2s8dsf9ugdf9gedhr#encryption"],
  "proof": {"...": "..."},
  "createdAt": "2025-04-17T12:00:00.000Z",
  "updatedAt": "2025-04-17T12:00:00.000Z",
  "ma": {
    "services": [
      "/iroh/41cfc1cc04e011a11c23f7e7bf1abee182fa64e2d313a3ab3c74438070f59306/ma/inbox/0.0.1",
      "/iroh/41cfc1cc04e011a11c23f7e7bf1abee182fa64e2d313a3ab3c74438070f59306/ma/presence/0.0.1"
    ]
  }
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

The reserved fields in §1.1 constitute the core profile. Additional profiles
MAY define further fields within `ma` for domain-specific use.
