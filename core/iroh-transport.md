# iroh Transport Profile (Core)

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines the iroh transport profile for `did:ma`.

At the time of writing, iroh is the only standardized and supported transport
profile for `ma.services` in the core specification.

## 1. Scope

This profile specifies transport-specific metadata and behavior for iroh:

1. `ma.iroh` field requirements.
2. Normalization rules for live versus published metadata.
3. Startup reconciliation and re-publish behavior.
4. Connect resolution using `ma.services` and `ma.iroh`.

## 2. `ma.iroh` Field Requirements

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

## 3. Normalization Rules

Implementations MUST normalize values before comparing persisted and live node
metadata.

1. `endpoint_id`: case-insensitive hex compare.
2. `relay_url`: trim whitespace, normalize trailing `/`, then compare.

## 4. Startup Reconciliation and Re-publish

On iroh service start/restart:

1. Read live iroh metadata (`endpoint_id`, `relay_url`).
2. Read existing `ma.iroh`.
3. Normalize both sides per Section 3.
4. If `ma.iroh` is missing/incomplete/mismatched, replace with live values.
5. Re-sign the desired DID document state and queue background publication.

This process MUST be idempotent: if normalized values match, no publish is
required.

## 5. Connect Resolution (Normative)

When connecting to a remote iroh service for protocol `P`, implementations
MUST resolve routing data in this order:

1. Resolve remote endpoint id from `ma.services` for protocol `P`.
2. Read `ma.iroh.relay_url` for remote routing hints.
3. Build remote address using resolved endpoint id plus available
   `ma.iroh` hints.

If `ma.iroh` is absent, malformed, or incomplete at runtime, implementations
MAY fall back to endpoint-id-only dialing from `ma.services`.

This fallback preserves reachability while documents converge through startup
reconciliation (Section 4).

## 6. Caching (Non-normative)

Implementations may cache:

1. Resolved DID documents.
2. Warm per-service transport paths (for example keyed by `(did, protocol)`).

Cache TTL, capacity, and eviction policy are implementation-defined and not
part of protocol conformance.

## 7. Conformance Summary

A conforming iroh transport implementation MUST:

1. Publish `ma.iroh` when iroh transport is advertised.
2. Reconcile and republish `ma.iroh` at startup when live metadata changes.
3. Resolve iroh connect routing per Section 5.

## References

- [DID Document Format](../did-document-format.md)
- [did:ma Field Extensions Format (Core)](ma-did-ma-fields.md)
