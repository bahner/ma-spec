# did:ma Field Extensions Format (Core)

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document is the normative definition of `did:ma` method-specific fields
under the `ma` key.

It combines:

1. Namespace and structural rules for `ma`.
2. Core field requirements for `ma.services` and `ma.kind`.
3. Transport profile linkage rules.

## 1. The `ma` Key

1. All `did:ma` method-specific extensions MUST be placed inside top-level
   `ma`.
2. `ma` MUST be a dag-cbor map when present.
3. No `did:ma`-specific extensions are permitted outside `ma`.
4. Unknown fields within `ma` SHOULD be ignored.
5. If `ma` is present, `ma.kind` SHOULD be present.
6. `ma.kind` is a free-form hint string. Its value is opaque to the core
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

A reachable endpoint MUST advertise at least one of:

- `/ma/inbox/0.0.1` — general-purpose message delivery. Accepts any content
  type. Intended as a mailbox; senders have no guarantee the receiving entity
  reads incoming messages.
- `/ma/rpc/0.0.1` — discrete function calls. Exclusively accepts
  `application/x-ma-rpc` (request) and `application/x-ma-rpc-reply` (reply).
  Messages with any other content type MUST be rejected. See §2.3 for the
  term format.

Both MAY be advertised simultaneously.

Optional:

- `/ma/ipfs/0.0.1` MAY be advertised.

### 2.3 RPC Term Format

The `application/x-ma-rpc` and `application/x-ma-rpc-reply` content types
carry a single CBOR-encoded term as their payload. A term is either an
**atom** or a **tuple**.

**Atom**

An atom is a CBOR text string whose value begins with `:` followed by one or
more characters. Valid characters are all printable UTF-8 code points,
excluding:

- Whitespace: U+0009 (tab), U+000A (LF), U+000D (CR), U+0020 (space)
- C0 control characters: U+0000–U+001F
- DEL: U+007F
- C1 control characters: U+0080–U+009F

Examples: `:fortune`, `:ping`, `:ok`

**Tuple**

A tuple is a CBOR array (major type 4) whose first element is an atom and
whose remaining elements are positional arguments. Arguments MAY be any valid
CBOR value, including byte strings, integers, text strings, arrays, and maps.
CBOR arrays are ordered sequences (RFC 8949 §3.1); the atom is always the
first element and argument positions are significant.

Elixir-style notation `{:emote, "wiggles its tail."}` is used in prose and
examples for readability. The wire encoding is always a CBOR array.

Examples:

    [":emote", "wiggles its tail."]
    [":transfer", h'<bytes>', 42]

**Reply conventions**

For `application/x-ma-rpc-reply`, the following terms are RECOMMENDED:

| Term | Meaning |
| --- | --- |
| `:ok` | Success, no return value |
| `[":ok", <value>]` | Success with return value |
| `[":error", <reason>]` | Failure; `<reason>` SHOULD be an atom or text string |

Individual call semantics and argument profiles are application-defined and
out of scope for this specification.

### 2.4 Protocol Mismatch

If a message is addressed to a protocol not advertised by the target entity,
the runtime MUST drop the message silently and send no reply.

A runtime MAY send a generic error response under local policy. If it does,
the response MUST NOT distinguish between "entity does not exist" and "protocol
not supported" — both cases MUST produce the same opaque response. This
prevents capability scanning of a runtime.

## 3. Kind Hint (Non-normative)

### 3.1 `ma.kind`

`ma.kind` is an opaque hint string. It signals to consumers what keys and
structures they can expect to find under `ma`. The core protocol imposes no
format on its value and no normative rules about what keys must accompany it.

| Field | Type | Requirement | Description |
| --- | --- | --- | --- |
| `kind` | string | SHOULD (when `ma` exists) | Free-form hint about the contents of `ma` |

The value MAY follow any convention the implementation chooses: a simple label
(`runtime`), a compound string (`runtime+mud`), a MIME-style type
(`application/x-ma-runtime+mud`), or any other scheme. Consumers that do not
recognise the value SHOULD ignore it and MAY fall back to inspecting known
keys directly.

---

## 4. Transport Profiles

Transport-specific requirements are defined in separate transport profile
documents.

At present, iroh is the only standardized and supported transport profile for
`did:ma` core. Any implementation that advertises iroh transport in
`ma.services` MUST conform to:

- [iroh Transport Profile (Core)](iroh-transport.md)

## 5. Conformance Summary

A conforming implementation MUST:

1. Publish `ma.services` for reachability.
2. Include `ma.kind` whenever `ma` is present.
3. Advertise at least one of `/ma/inbox/0.0.1` or `/ma/rpc/0.0.1` in
   `ma.services`.
4. Reject messages to `/ma/rpc/0.0.1` whose content type is not
   `application/x-ma-rpc` or `application/x-ma-rpc-reply`.
5. Drop silently any message addressed to a protocol not advertised by the
   target entity (§2.4).
6. If advertising iroh transport, conform to the iroh transport profile
   ([iroh Transport Profile (Core)](iroh-transport.md)).

An identity that currently advertises only `/ma/inbox/0.0.1` satisfies
requirement 3 and remains conformant. New entities MAY advertise only
`/ma/rpc/0.0.1`.

## 6. Example Minimum Reachable Documents

Inbox-only (general-purpose mailbox):

```json
{
  "ma": {
    "kind": "runtime",
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
    "kind": "runtime",
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
    "kind": "runtime",
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
    "kind": "runtime+mud",
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

- [DID Document Format](../did-document-format.md)
- [Pub/Sub Transport](pubsub.md)
- [iroh Transport Profile (Core)](iroh-transport.md)
