# CRUD Service Protocol

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines the `/ma/crud/0.0.1` service protocol: its content
types, dot-path grammar, and reply conventions for create/read/update/delete
operations over iroh QUIC transport.

**Applicable to:** 間 runtime hosts. A runtime registers this service to
expose its manifest tree (config, entities, kinds, ACLs, namespaces) for
management by authorised clients. Non-runtime actors do not need to
implement this service.

---

## 1. Service Protocol

`/ma/crud/0.0.1` is the service protocol for structured data management.
It is bound exclusively to the eight CRUD content types defined in §2.

Messages with any other content type arriving on `/ma/crud/0.0.1` MUST be
rejected.

The service MAY be disabled by the host (e.g. `crud_service: false` in
config). When disabled, the protocol is not registered with the transport
layer and callers receive no reply. Callers MUST NOT infer whether the
runtime exists from the absence of a reply.

---

## 2. Content Types

All CRUD content types use multicodec-prefixed payloads per
[ma-messaging-format-v1.md §1.1](ma-messaging-format-v1.md). Codec `0x51`
(cbor) SHOULD be used for all CRUD messages.

### 2.1 Request types

| Content type | Operation | Payload |
|---|---|---|
| `application/x-ma-crud-get` | Read a value | Path atom (CBOR text, see §3) |
| `application/x-ma-crud-edit` | Read for editing | Path atom (CBOR text, see §3) |
| `application/x-ma-crud-set` | Write a value | CBOR array `[path, value]` (see §3.3) |
| `application/x-ma-crud-delete` | Delete a value | Path atom (CBOR text, see §3) |

### 2.2 Reply types

| Content type | In reply to | Payload |
|---|---|---|
| `application/x-ma-crud-get-reply` | `crud-get` | Value (any CBOR) or error term |
| `application/x-ma-crud-edit-reply` | `crud-edit` | Human-editable value (see §2.3) or error term |
| `application/x-ma-crud-set-reply` | `crud-set` | `:ok`, `[":ok", cid]`, or error term |
| `application/x-ma-crud-delete-reply` | `crud-delete` | `:ok` or error term |

All reply messages MUST set `replyTo` to the `id` of the originating
request message. The `contentType` header field of every CRUD reply MUST be
`application/x-ma-term` (see [ma-messaging-format-v1.md §2.3](ma-messaging-format-v1.md)).

### 2.3 Edit replies

`application/x-ma-crud-edit-reply` returns a human-editable representation
of the value, which MAY differ from the raw value returned by
`application/x-ma-crud-get-reply`. Implementations SHOULD return:

- YAML text (CBOR text string) for structured values such as entity nodes
  and ACL maps, so clients can open an editor directly.
- Plain string values for scalar fields such as `config.i18n`.

The implementation MAY refuse an edit request (e.g. based on a separate
write capability check) by returning an error term. Callers MUST NOT
assume that a successful `crud-get` implies a successful `crud-edit`.

---

## 3. Dot-Path Grammar

### 3.1 Path atoms

Every CRUD request carries a **path atom** as its primary payload: a CBOR
text string beginning with `:` that identifies the target resource.

```
path     = ":" ns ["." segment {"." segment}]
ns       = "config" | "entities" | "kinds" | "acl" | "acls" | segment
segment  = 1*char
char     = any printable UTF-8 code point except "." and ":"
```

Examples: `:config`, `:config.i18n`, `:entities.ping`, `:kinds`

### 3.2 Path resolution

Path atoms are resolved against the runtime manifest tree. A path that
refers to a non-existent node:

- For `crud-get`: MUST return an error reply.
- For `crud-edit`: MUST return an error reply or a sensible default (e.g.
  the active language for `:config.i18n` when not yet persisted).
- For `crud-set`: MAY create the node if the path is within a writable
  namespace.
- For `crud-delete`: MUST return an error reply if the node does not exist.

### 3.3 Set payload

A `crud-set` request carries a CBOR array `[path, value]`:

```
set-payload = [path-atom, value]
value       = any CBOR value
```

For structured values (entity nodes, ACL maps), the value is DAG-CBOR
bytes (codec `0x71`).

---

## 4. Reply Conventions

CRUD reply payloads are single CBOR-encoded terms. The following terms are
used:

| Term | Meaning |
|---|---|
| `:ok` | Success, no return value |
| `[":ok", value]` | Success with return value |
| `[":ok", cid]` | Mutation succeeded; `cid` is the new IPFS CID of the updated manifest |
| `[":error", reason]` | Failure; `reason` SHOULD be a text string |

Upsert and field-set operations that mutate the IPFS manifest MUST reply
with `[":ok", cid]` where `cid` is the new root CID. Delete operations
MUST reply with `:ok` on success. Read operations MUST reply with
`[":ok", value]` or the value directly.

---

## 5. Access Control

CRUD requests MUST be checked against the runtime's ACL before dispatch.
The required capability is implementation-defined per namespace:

| Namespace | Suggested capability |
|---|---|
| `:config.*` | `"crud"` or `"config"` |
| `:entities.*` | `"crud"` or `"entities"` |
| `:kinds.*` | `"crud"` |
| `:acl` / `:acls.*` | `"crud"` |

Edit requests (`crud-edit`) MAY require the same capability as set
requests rather than read requests, at the implementation's discretion.

See [ma-acl-v1.md](ma-acl-v1.md) for the ACL model.

---

## 6. Protocol Mismatch

If a `crud-*` message arrives on any protocol other than
`/ma/crud/0.0.1`, the runtime MUST drop it and send no reply.

If a non-`crud-*` message arrives on `/ma/crud/0.0.1`, the runtime MUST
reject it and reply with `[":error", "wrong-protocol"]`.

---

## References

- [ma-messaging-format-v1.md](ma-messaging-format-v1.md)
- [ma-acl-v1.md](ma-acl-v1.md)
- [ma-runtime-v1.md](ma-runtime-v1.md)
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
