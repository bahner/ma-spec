# did:ma Field Extensions Format (Core)

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document is the normative definition of `did:ma` method-specific fields
under the `ma` key.

It combines:

1. Namespace and structural rules for `ma`.
2. Core runtime field requirements for `ma.services` and `ma.iroh`.

## 1. The `ma` Key

1. All `did:ma` method-specific extensions MUST be placed inside top-level
   `ma`.
2. `ma` MUST be a dag-cbor map when present.
3. No `did:ma`-specific extensions are permitted outside `ma`.
4. Unknown fields within `ma` SHOULD be ignored.
5. `ma` is OPTIONAL. A document without `ma` is valid but unreachable for
   messaging.

## 2. Required Reachability Field

### 2.1 `ma.services`

- Type: array of strings and/or objects.
- Requirement: REQUIRED for reachability.

Each service entry combines transport address and protocol id:

    <transport-address>/<protocol-id>

Example:

    /iroh/<endpoint-id>/ma/inbox/0.0.1

A document without usable `ma.services` entries is valid but unreachable.

### 2.2 Service protocol id format

Service protocol ids use:

    /ma/<name>/<semver>

Required for reachable endpoints:

- `/ma/inbox/0.0.1` MUST be advertised.

Optional:

- `/ma/ipfs/0.0.1` MAY be advertised.

## 3. iroh Field Requirements

### 3.1 `ma.iroh`

If any `ma.services` entry advertises iroh transport, the DID document MUST
include `ma.iroh`.

Required shape:

```json
{
  "ma": {
    "iroh": {
      "endpoint_id": "7f5be139...",
      "relay_url": "https://relay.n0.computer"
    }
  }
}
```

Required fields in `ma.iroh`:

| Field | Type | Requirement |
| --- | --- | --- |
| `endpoint_id` | string | REQUIRED. MUST be the live iroh endpoint ID for the running node instance. |
| `relay_url` | string | REQUIRED. MUST be a valid relay URL currently used by the running node instance. |

## 4. Normalization Rules

Implementations MUST normalize values before comparing persisted and live node
metadata.

1. `endpoint_id`: case-insensitive hex compare.
2. `relay_url`: trim whitespace, normalize trailing `/`, then compare.

## 5. Startup Reconciliation and Re-publish

On iroh service start/restart:

1. Read live iroh metadata (`endpoint_id`, `relay_url`).
2. Read existing `ma.iroh`.
3. Normalize both sides per Section 4.
4. If `ma.iroh` is missing/incomplete/mismatched, replace with live values.
5. Re-sign and publish DID document.

This process MUST be idempotent: if normalized values match, no publish is
required.

## 6. Runtime Field Requirements

### 6.1 `ma.runtime`

A `did:ma` runtime SHOULD publish its current state reference and operational
policy under `ma.runtime`.

Required shape:

```json
{
  "ma": {
    "runtime": {
      "cid":              "<base32-CIDv1>",
      "publish_interval": "15m",
      "ipns_ttl":         "24h",
      "allowed_kinds": [
        "/ma/kind/generic/0.0.1",
        "/ma/kind/mailbox/0.0.1",
        "/ma/kind/root/0.0.1"
      ]
    }
  }
}
```

Fields in `ma.runtime`:

| Field | Type | Requirement | Description |
| --- | --- | --- | --- |
| `cid` | CIDv1 string | REQUIRED | Base32-encoded CID of the current runtime-root IPLD node |
| `publish_interval` | duration string | RECOMMENDED | How often the runtime republishes an updated `cid`; default `"15m"` |
| `ipns_ttl` | duration string | RECOMMENDED | How long resolvers may cache the IPNS record; MUST be ≥ 2 × `publish_interval`; default `"24h"` |
| `allowed_kinds` | array of strings | OPTIONAL | Whitelist of kind identifiers accepted for entity creation; absent or empty means all registered kinds are allowed |

Duration strings use Go duration syntax (e.g. `"5m"`, `"15m"`, `"1h"`, `"24h"`).

The `cid` field allows any party that can reach IPFS to reconstruct the full
runtime state (entity set, behavior CIDs, and encrypted state envelopes) from
nothing more than the DID document. The secret bundle is required to decrypt
entity state.

### 6.2 `ma.runtime` Update Rules

The runtime MUST update `ma.runtime.cid` whenever the runtime-root IPLD node
changes. The runtime MUST NOT publish a new DID document solely for `cid`
changes more often than once every 5 minutes. On graceful shutdown and on
operator-requested saves the runtime MUST publish immediately regardless of the
interval constraint.

---

## 7. Runtime Connect Resolution (Normative)

When connecting to a remote iroh service for protocol `P`, implementations
MUST resolve routing data in this order:

1. Resolve remote endpoint id from `ma.services` for protocol `P`.
2. Read `ma.iroh.relay_url` for remote routing hints.
3. Build remote address using resolved endpoint id plus available
  `ma.iroh` hints.

If `ma.iroh` is absent, malformed, or incomplete at runtime, implementations
MAY fall back to endpoint-id-only dialing from `ma.services`.

This fallback preserves reachability while documents converge through startup
reconciliation (Section 5).

## 8. Runtime Caching (Non-normative)

Implementations may cache:

1. Resolved DID documents.
2. Warm per-service transport paths (for example keyed by `(did, protocol)`).

Cache TTL, capacity, and eviction policy are implementation-defined and not
part of protocol conformance.

## 9. Conformance Summary

A conforming runtime implementation MUST:

1. Publish `ma.services` for reachability.
2. Publish `ma.iroh` when iroh transport is advertised.
3. Reconcile and republish `ma.iroh` at startup when live metadata changes.
4. Resolve runtime iroh connect routing per Section 6.

## 10. Example Minimum Reachable Document

```json
{
  "ma": {
    "services": [
      "/iroh/<endpoint-id>/ma/inbox/0.0.1"
    ]
  }
}
```

## References

- [DID Document Format](../did-document-format.md)
- [Pub/Sub Transport](pubsub.md)
