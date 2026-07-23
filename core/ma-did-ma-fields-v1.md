# did:ma Field Extensions Format (Core)

**Version:** 1.0.0
**Status:** Candidate Recommendation

## Abstract

This document is the normative definition of `did:ma` method-specific fields
under the `ma` key.

It combines:

1. Namespace and structural rules for `ma`.
2. Core field requirements for `ma.services` and `ma.type`.
3. Reachability and conformance rules.

## 1. The `ma` Key

1. All `did:ma` method-specific extensions MUST be placed inside top-level
   `ma`.
2. `ma` MUST be a dag-cbor map when present.
3. No `did:ma`-specific extensions are permitted outside `ma`.
4. Unknown fields within `ma` SHOULD be ignored.
5. If `ma` is present, `ma.type` SHOULD be present.
6. `ma.type` is a free-form hint string. Its value is opaque to the core
   protocol; consumers use it to determine what other keys and structures
   to expect under `ma`. No specific format is mandated.
7. `ma` is OPTIONAL. A document without `ma` is valid but unreachable for
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

A reachable endpoint MUST advertise at least one service in `ma.services`. A
document without services is valid but unreachable.

- `/ma/inbox/0.0.1` — point-to-point messaging. Accepts only
  `application/vnd.ma.message`, `application/vnd.ma.chat`, `application/vnd.ma.emote`,
  and `application/vnd.ma.broadcast`. Messages with any other message type MUST be
  rejected. Senders have no guarantee the
  receiving entity reads incoming messages.
- `/ma/rpc/0.0.1` — discrete function calls. Exclusively accepts
  `application/vnd.ma.rpc.request` (request) and `application/vnd.ma.rpc.reply` (reply).
  Messages with any other message type MUST be rejected. See §2.3 for the
  term format. Entities that only handle function calls SHOULD advertise only
  this service.
- `/ma/crud/0.0.1` — structured runtime management. Exclusively accepts
  `application/vnd.ma.crud.request` (request) and `application/vnd.ma.crud.reply` (reply).
  Messages with any other message type MUST be rejected. See
  [CRUD Service Protocol](../runtime/ma-crud-service-v1.md).

These services MAY be advertised simultaneously.

Optional:

- `/ma/ipfs/0.0.1` MAY be advertised.

The `/ma/rpc/0.0.1` service, its message types, term format, and protocol
mismatch rules are specified in [RPC Service Protocol (Core)](ma-rpc-service-v1.md).

## 3. Type Hint (Non-normative)

### 3.1 `ma.type`

`ma.type` is an opaque hint string. It signals to consumers what keys and
structures they can expect to find under `ma`. The core protocol imposes no
format on its value and no normative rules about what keys must accompany it.
The reference Rust implementation writes this field through
`MaExtension::kind()`, whose method name is builder terminology rather than
the serialised field name.

| Field | Type | Requirement | Description |
| --- | --- | --- | --- |
| `type` | string | SHOULD (when `ma` exists) | Free-form hint about the contents of `ma` |

The value MAY follow any convention the implementation chooses: a simple label
(`runtime`), a compound string (`runtime+mud`), a MIME-style type
(`application/x-ma-runtime+mud`), or any other scheme. Consumers that do not
recognise the value SHOULD ignore it and MAY fall back to inspecting known
keys directly.

---

## 4. Transport Addresses

`ma.services` carries the transport address needed to reach an advertised
protocol endpoint.

The core specification does not require any additional transport-specific
metadata under `ma`. Implementations MAY define private transport hints, but
unknown fields remain optional extension data and are not part of core
conformance.

At present, iroh is the only standardized and supported transport used by the
core specification examples.

## 5. Conformance Summary

A conforming implementation MUST:

1. Publish `ma.services` for reachability.
2. Include `ma.type` whenever `ma` is present.
3. Advertise at least one service in `ma.services` to be reachable.
4. Reject messages to `/ma/rpc/0.0.1` whose message type is not
   `application/vnd.ma.rpc.request` or `application/vnd.ma.rpc.reply`.
5. Reject messages to `/ma/inbox/0.0.1` whose message type is not
  `application/vnd.ma.message`, `application/vnd.ma.broadcast`,
  `application/vnd.ma.chat`, or `application/vnd.ma.emote`.
6. Drop silently any message addressed to a protocol not advertised by the
   target entity (§2.4).

Any single service satisfies requirement 3. An entity MAY advertise only
`/ma/rpc/0.0.1`, only `/ma/inbox/0.0.1`, only `/ma/crud/0.0.1`, or only
`/ma/ipfs/0.0.1`, and
remain conformant.

## 6. Runtime Field for `/ma/runtime/0.0.1`

For the `/ma/runtime/0.0.1` protocol, the `runtime` field is an IPLD link
to the runtime manifest root CID. See [ma-runtime-v1.md](../runtime/ma-runtime-v1.md)
for the normative runtime definition.

Earlier IPNS-based string variants of the `runtime` field are superseded for
this protocol.

Example:

```json
{
  "ma": {
    "type": "runtime",
    "runtime": { "/": "<base32-CIDv1-runtime-root>" },
    ...
  }
}
```

---

## 7. Example Minimum Reachable Documents

Inbox-only (general-purpose mailbox):

```json
{
  "ma": {
    "type": "runtime",
    "runtime": {
      "/": "<base32-CIDv1>"
    },
    "services": [
      "/iroh/<endpoint-id>/ma/inbox/0.0.1"
    ]
  }
}
```

RPC-only (function-call endpoint, no mailbox):

```json
{
  "ma": {
    "type": "runtime",
    "runtime": {
      "/": "<base32-CIDv1>"
    },
    "services": [
      "/iroh/<endpoint-id>/ma/rpc/0.0.1"
    ]
  }
}
```

Both protocols:

```json
{
  "ma": {
    "type": "runtime",
    "runtime": {
      "/": "<base32-CIDv1>"
    },
    "services": [
      "/iroh/<endpoint-id>/ma/inbox/0.0.1",
      "/iroh/<endpoint-id>/ma/rpc/0.0.1"
    ]
  }
}
```

Multiple kinds in the same document:

```json
{
  "ma": {
    "type": "runtime+mud",
    "runtime": {
      "/": "<base32-CIDv1-runtime>"
    },
    "mud": {
      "/": "<base32-CIDv1-mud>"
    },
    "services": [
      "/iroh/<endpoint-id>/ma/rpc/0.0.1"
    ]
  }
}
```

## References

- [DID Document Format](../did-ma-spec-v1.md)
