# CRUD Service Protocol

**Version:** 0.2.0
**Status:** Draft

## Abstract

This document defines the `/ma/crud/0.0.1` service protocol: its content
types, payload grammar, and reply conventions for create/read/update/delete
operations over iroh QUIC transport.

**Applicable to:** 間 runtime hosts. A runtime registers this service to
expose its manifest tree (config, entities, kinds, ACLs) for
management by authorised clients. Non-runtime actors do not need to
implement this service.

---

## 1. Service Protocol

`/ma/crud/0.0.1` is the service protocol for structured data management.
It uses exactly two content types: `application/x-ma-crud` for requests
and `application/x-ma-crud-reply` for replies.

Messages with any other content type arriving on `/ma/crud/0.0.1` MUST be
rejected with `[":error", "wrong-content-type"]`.

The service MAY be disabled by the host (e.g. `crud_service: false` in
config). When disabled, the protocol is not registered with the transport
layer and callers receive no reply. Callers MUST NOT infer whether the
runtime exists from the absence of a reply.

**Edit operations are not part of this protocol.** Fetching existing values
for human editing is achieved by a plain GET (`[":get", path]`) followed by
client-side resolution of the returned IPFS CID. Writing back an edited
value is a separate SET or IPFS-store + SET sequence (see §3.3).

---

## 2. Content Types

All CRUD messages use multicodec-prefixed payloads per
[ma-messaging-format-v1.md §1.1](../core/ma-messaging-format-v1.md). Codec `0x51`
(cbor) MUST be used.

| Direction | Content type | Payload |
|---|---|---|
| Request | `application/x-ma-crud` | CBOR 2-element array (see §3) |
| Reply | `application/x-ma-crud-reply` | CBOR term (see §4) |

All reply messages MUST set `replyTo` to the `id` of the originating
request message.

---

## 3. Request Payload Grammar

Every CRUD request carries a **CBOR 2-element array** that encodes the
operation and target path in a single value.

### 3.1 Path atoms

A **path atom** is a CBOR text string beginning with `:` that identifies
the target resource.

```
path     = ":" ns ["." segment {"." segment}]
ns       = "config" | "entities" | "kinds" | "acl" | segment
segment  = 1*char
char     = any printable UTF-8 code point except "." and ":"
```

Examples: `:config`, `:config.i18n`, `:entities.ping`, `:kinds`

### 3.2 GET — read a value

```
[":get", path]
```

`":get"` is a CBOR text string. `path` is a path atom (§3.1).

Path resolution: a path that refers to a non-existent node MUST return an
error reply.

### 3.3 SET — write a value

```
[path, value]
```

`path` is a path atom (§3.1). `value` is a CBOR scalar.

#### Scalar values

For config leaves and simple string fields, `value` is a CBOR text string,
integer, boolean, or float.

#### CIDv1 values

For structured values (entity nodes, ACL maps, kind references), `value` MUST be a bare **CIDv1** string in base32 lowercase
(multibase prefix `b`). CIDv0 strings (base58btc, starting with `Qm`)
MUST be rejected with `[":error", "cidv1-required"]`.

CIDv1 is self-describing via its embedded multicodec field:

| Codec | Hex | Meaning |
|---|---|---|
| raw | `0x55` | Opaque binary blob |
| dag-cbor | `0x71` | Structured IPLD object (DAG-CBOR) |
| libp2p-key | `0x72` | IPNS public key (libp2p identity) |

The runtime stores the CIDv1 as an IPLD link `{ "/": "<CIDv1>" }`.
No path prefix is part of the CRUD wire format.

**Callers MUST upload binary content (DAG-CBOR, raw bytes) to IPFS via
`/ma/ipfs/0.0.1` first, then SET the returned CIDv1.**
The CRUD service NEVER accepts raw bytes as a value.

Clients resolving a CIDv1 value MUST determine the access method from the
codec:

| Codec | Access method |
|---|---|
| `0x55` / `0x71` | Fetch from IPFS gateway: `/ipfs/<CIDv1>` |
| `0x72` | Resolve IPNS record: `/ipns/<CIDv1>` |

A SET path that refers to a non-existent leaf MAY create the node if the
path is within a writable namespace.

#### Delete-via-SET

Setting a value to the empty string (`""`) on a path that supports it
deletes the entry. Prefer DELETE (§3.4) where applicable.

### 3.4 DELETE — remove a value

```
[":delete", path]
```

`":delete"` is a CBOR text string. `path` is a path atom (§3.1).

A DELETE on a non-existent node MUST return an error reply.

---

## 4. Reply Conventions

Reply payloads use content type `application/x-ma-crud-reply` and are
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

---

## 5. Access Control

CRUD requests MUST be checked against the runtime's ACL before dispatch.
The required capability is implementation-defined per namespace:

| Namespace | Suggested capability |
|---|---|
| `:config.*` | `"crud"` or `"config"` |
| `:entities.*` | `"crud"` or `"entities"` |
| `:kinds.*` | `"crud"` |


See [ma-acl-v1.md](../core/ma-acl-v1.md) for the ACL model.

---

## 6. Protocol Mismatch

If an `application/x-ma-crud` message arrives on any protocol other than
`/ma/crud/0.0.1`, the runtime MUST drop it and send no reply.

If a message with a content type other than `application/x-ma-crud`
arrives on `/ma/crud/0.0.1`, the runtime MUST reject it and reply with
`[":error", "wrong-content-type"]`.

---

## References

- [ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md)
- [ma-ipfs-service-v1.md](../core/ma-ipfs-service-v1.md)
- [ma-acl-v1.md](../core/ma-acl-v1.md)
- [ma-runtime-v1.md](ma-runtime-v1.md)
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
