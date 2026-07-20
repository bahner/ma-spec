# CRUD Service Protocol

**Version:** 1.0.0
**Status:** Candidate Recommendation

## Abstract

This document defines the `/ma/crud/0.0.1` service protocol: its message
types, payload grammar, and reply conventions for create/read/update/delete
operations over iroh QUIC transport.

**Applicable to:** 間 runtime hosts. A runtime registers this service to
expose its manifest tree (config, entities, kinds, ACLs, groups) for
management by authorised clients. Non-runtime actors do not need to
implement this service.

---

## 1. Service Protocol

`/ma/crud/0.0.1` is the service protocol for structured data management.
It uses exactly two message types: `application/vnd.ma.crud.request` for requests
and `application/vnd.ma.crud.reply` for replies.

Messages with any other message type arriving on `/ma/crud/0.0.1` MUST be
rejected with `[":error", "wrong-message-type"]`.

The service MAY be disabled by the host (e.g. `crud_service: false` in
config). When disabled, the protocol is not registered with the transport
layer and callers receive no reply. Callers MUST NOT infer whether the
runtime exists from the absence of a reply.

**Edit operations are not part of this protocol.** Fetching existing values
for human editing is achieved by a plain GET (`[path]`) followed by
client-side resolution of the returned `/ipfs/` or `/ipns/` reference.
Writing back an edited value is a separate SET or IPFS-store + SET
sequence (see §3.3).

---

## 2. Message Types

All CRUD messages use multicodec-prefixed payloads per
[ma-messaging-format-v1.md §1.1](../core/ma-messaging-format-v1.md). Codec `0x51`
(cbor) MUST be used.

| Direction | Message type | Payload |
|---|---|---|
| Request | `application/vnd.ma.crud.request` | CBOR 1- or 2-element array (see §3) |
| Reply | `application/vnd.ma.crud.reply` | CBOR term (see §4) |

All reply messages MUST set `replyTo` to the `id` of the originating
request message.

---

## 3. Request Payload Grammar

Every CRUD request carries a **CBOR 1- or 2-element array** that encodes
the operation and target path in a single value. There is no separate
operation-name atom (no `:get` / `:delete` prefix) — the array length and
the second element's value together determine the operation.

### 3.1 Path atoms

A **path atom** is a CBOR text string beginning with `/` that identifies
the target resource.

```
path     = "/" ns ["/" segment {"/" segment}]
ns       = "config" | "entities" | "kinds" | "acl" | "acls" | "grp" | segment
segment  = 1*char
char     = any printable UTF-8 code point except "/"
```

Examples: `/config`, `/config/i18n`, `/entities/ping`, `/kinds`,
`/grp/owners`

### 3.2 GET — read a value

```
[path]
```

A single-element array. `path` is a path atom (§3.1).

Path resolution: a path that refers to a non-existent node MUST return an
error reply.

### 3.3 SET — write a value

```
[path, value]
```

`path` is a path atom (§3.1). `value` is a non-empty CBOR scalar (an empty
text string instead signals DELETE — see §3.4).

#### Scalar values

For config leaves and simple string fields, `value` is a CBOR text string,
integer, boolean, or float.

#### IPFS / IPNS reference values

For structured values (entity nodes, ACL maps, kind references), `value`
MUST be a text string with an explicit `/ipfs/<CIDv1>` or `/ipns/<key>`
prefix. Bare CID strings (no prefix) MUST be treated as plain text and are
NEVER auto-detected as a reference — the explicit prefix is required.

`<CIDv1>` MUST be base32-lowercase (multibase prefix `b`). CIDv0 strings
(base58btc, starting with `Qm`) MUST be rejected with
`[":error", "cidv1-required"]`.

The runtime:

1. Resolves `/ipns/<key>` to its currently-published CIDv1 (an `/ipfs/`
   value's CID is used as-is).
2. Stores the resolved CIDv1 as an IPLD link `{ "/": "<CIDv1>" }` in the
   manifest. The `/ipfs/` or `/ipns/` prefix is a wire-format convenience
   for the caller only — it is never itself persisted; only the resolved
   bare CIDv1 is stored.

CIDv1 is self-describing via its embedded multicodec field:

| Codec | Hex | Meaning |
|---|---|---|
| raw | `0x55` | Opaque binary blob |
| dag-cbor | `0x71` | Structured IPLD object (DAG-CBOR) |
| libp2p-key | `0x72` | IPNS public key (libp2p identity) |

**Callers MUST upload binary content (DAG-CBOR, raw bytes) to IPFS via
`/ma/ipfs/0.0.1` first, then SET the returned CID as `/ipfs/<CIDv1>`.**
The CRUD service NEVER accepts raw bytes as a value.

A SET path that refers to a non-existent leaf MAY create the node if the
path is within a writable namespace.

#### Delete-via-SET

Setting a value to the empty string (`""`) on a path that supports it
deletes the entry (this is in fact how DELETE, §3.4, is distinguished from
SET on the wire — both use a 2-element array). Prefer DELETE where
applicable for clarity.

### 3.4 DELETE — remove a value

```
[path, ""]
```

A 2-element array whose second element is the empty text string. `path`
is a path atom (§3.1).

A DELETE on a non-existent node MUST return an error reply.

---

## 4. Reply Conventions

Reply payloads use message type `application/vnd.ma.crud.reply` and are
single CBOR-encoded terms:

| Term | Meaning |
|---|---|
| `":ok"` | Success, no return value |
| `[":ok", value]` | Success with return value |
| `[":ok", root_cid]` | Structural mutation succeeded; `root_cid` is the new manifest root CIDv1 |
| `[":error", reason]` | Failure; `reason` SHOULD be a text string |

- **Structural mutations** (entity or ACL registration/removal) MUST reply
  with `[":ok", root_cid]` where
  `root_cid` is the new manifest root CIDv1 after the update.
- **Field-level SET** (config values, blob fields) MUST reply with
  `":ok"`. The caller already holds the content CIDv1 from the prior
  `/ma/ipfs/0.0.1` upload step; the manifest root is an internal
  implementation detail and MUST NOT be surfaced.
- Read operations (GET) MUST reply with `[":ok", value]`.
- Operations with no meaningful return value reply with `":ok"`.
- **GET replies whose value is a stored reference** (an entity ACL field,
  a named ACL, a group, or any other IPLD-linked field) MUST use the same
  `/ipfs/<CIDv1>` or `/ipns/<key>` prefix required for SET values (§3.3) —
  never a bare CID string. This makes link detection symmetric and
  value-driven on both sides of the protocol: any value beginning with
  `/ipfs/`, `/ipns/`, or `/ipld/` is a reference to be fetched and
  resolved by the client; every other value is inline data. Bare CID
  strings MUST NOT appear in GET replies and MUST NOT be treated as
  references if they do.
- When clients are expected to make control-flow decisions from an error,
  `reason` MUST be a stable, non-localised error code string. Human-readable
  or localised error text belongs in client UI, logs, or an extension field
  in a future structured error format; it MUST NOT replace a machine-readable
  `reason` code in the two-element `[":error", reason]` form.
- A GET or DELETE whose path refers to a non-existent resource MUST reply
  with a `reason` code of exactly `"not-found"` or a namespace-specific code
  ending in `"-not-found"`, such as `"kind-not-found"`,
  `"entity-not-found"`, `"config-not-found"`, `"acl-not-found"`, or
  `"group-not-found"`. Clients MAY classify both `"not-found"` and any
  `"*-not-found"` reason as a missing-resource result, independent of
  display language.

---

## 5. Access Control

CRUD requests MUST be checked against the runtime's ACL before dispatch.
The required capability is implementation-defined per namespace:

| Namespace | Suggested capability |
|---|---|
| `/config/*` | `"crud"` or `"config"` |
| `/entities/*` | `"crud"` or `"entities"` |
| `/kinds/*` | `"crud"` |
| `/acl`, `/acls/*` | `"crud"` or `"acl"` |
| `/grp/*` | `"crud"` or `"acl"` |


See [ma-acl-v1.md](../core/ma-acl-v1.md) for the ACL model.

---

## 6. Protocol Mismatch

If an `application/vnd.ma.crud.request` message arrives on any protocol other than
`/ma/crud/0.0.1`, the runtime MUST drop it and send no reply.

If a message with a message type other than `application/vnd.ma.crud.request`
arrives on `/ma/crud/0.0.1`, the runtime MUST reject it and reply with
`[":error", "wrong-message-type"]`.

---

## References

- [ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md)
- [ma-ipfs-service-v1.md](../core/ma-ipfs-service-v1.md)
- [ma-acl-v1.md](../core/ma-acl-v1.md)
- [ma-runtime-v1.md](ma-runtime-v1.md)
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
