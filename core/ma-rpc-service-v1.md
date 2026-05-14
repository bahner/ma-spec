# RPC Service Protocol (Core)

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines the `/ma/rpc/0.0.1` service protocol: its content
types, term format, and protocol mismatch rules.

## 1. Service Protocol

`/ma/rpc/0.0.1` is the service protocol for discrete function calls. It is
exclusively bound to two content types:

| Content type | Direction |
| --- | --- |
| `application/x-ma-rpc` | Request |
| `application/x-ma-rpc-reply` | Reply |

Messages with any other content type arriving on `/ma/rpc/0.0.1` MUST be
rejected.

## 2. Content Types

### 2.1 `application/x-ma-rpc`

| Property | Value |
| --- | --- |
| Encryption | Required |
| Service | `/ma/rpc/0.0.1` |

A discrete function call. Content is a single CBOR-encoded term (see §3).

This content type is exclusively bound to the `/ma/rpc/0.0.1` service.
Receivers MUST reject `application/x-ma-rpc` messages arriving on any other
service. `/ma/inbox/0.0.1` does not accept RPC content types; if an
`application/x-ma-rpc` message arrives on `/ma/inbox/0.0.1`, the runtime
MUST drop it and SHOULD send a generic error reply indicating the correct
service (e.g. `"use /ma/rpc/0.0.1 for RPC requests"`). The error reply MUST
NOT leak information about whether the target entity exists.

### 2.2 `application/x-ma-rpc-reply`

| Property | Value |
| --- | --- |
| Encryption | Required |
| Service | `/ma/rpc/0.0.1` |

A reply to an `application/x-ma-rpc` message. MUST set `replyTo` to the `id`
of the originating RPC message. Content is a single CBOR-encoded term (see §3).

## 3. RPC Term Format

The content of both `application/x-ma-rpc` and `application/x-ma-rpc-reply`
is a single CBOR-encoded term. A term is either an **atom** or a **tuple**.

### 3.1 Atom

An atom is a CBOR text string whose value begins with `:` followed by one or
more characters. Valid characters are all printable UTF-8 code points,
excluding:

- Whitespace: U+0009 (tab), U+000A (LF), U+000D (CR), U+0020 (space)
- C0 control characters: U+0000–U+001F
- DEL: U+007F
- C1 control characters: U+0080–U+009F

Examples: `:fortune`, `:ping`, `:ok`

### 3.2 Tuple

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

### 3.3 Reply Conventions

For `application/x-ma-rpc-reply`, the following terms are RECOMMENDED:

| Term | Meaning |
| --- | --- |
| `:ok` | Success, no return value |
| `[":ok", <value>]` | Success with return value |
| `[":error", <reason>]` | Failure; `<reason>` SHOULD be an atom or text string |

Individual call semantics and argument profiles are application-defined and
out of scope for this specification.

## 4. Protocol Mismatch

If a message is addressed to a protocol not advertised by the target entity,
the runtime MUST drop the message silently and send no reply.

A runtime MAY send a generic error response under local policy. If it does,
the response MUST NOT distinguish between "entity does not exist" and "protocol
not supported" — both cases MUST produce the same opaque response. This
prevents capability scanning of a runtime.

## References

- [did:ma Field Extensions Format (Core)](ma-did-ma-fields.md)
- [did:ma Messaging Format](../messaging-format.md)
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
