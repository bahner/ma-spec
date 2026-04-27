# MA Runtime Function Reference

**Version:** 1  
**Status:** Draft  
**Authors:** Lars Bahner

## Abstract

This document is the normative reference for all functions defined by the
`did:ma` runtime host interface. For architecture, lifecycle, and message
semantics, see the runtime specification (`core/ma-runtime-spec-v1.md`).

These functions are internal runtime entry points for plugin/entity code. They
are not directly callable by end users or external clients. User-visible
operations are expressed as messages (notably `application/x-ma-rpc` and
`application/x-ma-rpc-reply`) and are then handled by entities, which may
invoke host functions as part of handling.

Functions are grouped by role:

- [PDK Functions](#pdk-functions) — Wasm exports the runtime calls on the plugin
- [Host Effects API](#host-effects-api) — Host calls that produce runtime effects
- [Runtime Utility API](#runtime-utility-api) — Host calls that return values
- [Mailbox Extensions](#mailbox-extensions) — Additional functions for the `mailbox` kind
- [Root Extensions](#root-extensions) — Additional functions for the `root` kind

---

## Availability by Kind

The runtime host interface is split by availability:

| Scope | Category | Functions |
| --- | --- | --- |
| All kinds | PDK | `init`, `handle_message` |
| All kinds | Host effects | `send`, `reply`, `get_state`, `set_state`, `receive` |
| All kinds | Runtime utility | `now`, `nanoid`, `random` |
| `mailbox` kind | Kind-specific | `append`, `peek`, `pop`, `list`, `delete` |
| `root` kind | Kind-specific | `create_entity`, `destroy_entity`, `upsert_entity` |

The runtime MUST reject any call not declared by the entity's kind.

---

## PDK Functions

PDK functions are exported by the plugin. The runtime calls them to deliver
state and messages.

---

### `init(state)`

Called once per entity instantiation, before any message is delivered.

| Parameter | Type | Description |
| --- | --- | --- |
| `state` | JSON object | The entity's current persisted state, or `{}` if no state exists |

The plugin MUST store or process `state` as needed for subsequent
`handle_message` calls. The runtime MUST call `init` before calling
`handle_message` on a newly loaded plugin instance.

---

### `handle_message(runtime_msg)`

Called on every inbound message delivery. This is the sole delivery entry
point; the runtime MUST NOT invoke separate handlers per content type.

| Parameter | Type | Description |
| --- | --- | --- |
| `runtime_msg` | `<runtime-msg>` | The stripped, decoded message |

The entity's own identity (`self`) is injected at instantiation time and is
not passed as an argument.

`<runtime-msg>` fields:

| Field | Type | Description |
| --- | --- | --- |
| `id` | nanoid | Message identifier |
| `from` | `<did-ma-url>` | Sender |
| `to` | `<did-ma-url>` | Recipient |
| `created_at` | nanosecond epoch | Message creation time (UTC) |
| `reply_to` | nanoid \| null | ID of the message being replied to |
| `content_type` | string | MIME-like content type |
| `content` | bytes | Decrypted payload |

---

## Host Effects API

Effects are host functions the plugin calls into the runtime during execution.
Each call executes immediately and returns an error if it fails. The plugin
receives the error synchronously and is responsible for handling it.

All effects are capability-checked against the entity's kind before application.

---

### `send(target, content, content_type, encrypt)`

Sends a message to another entity.

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `target` | `<did-ma-url>` | — | Recipient |
| `content` | bytes | — | Message payload |
| `content_type` | string | `"application/x-ma-rpc"` | MIME-like content type |
| `encrypt` | bool | — | Whether to encrypt the message |

The runtime constructs, signs, and routes the outgoing message. The sender
MUST NOT assume the recipient will respond.

This default reflects the standard inter-entity RPC message flow. Other content
types remain valid when explicitly provided.

---

### `reply(content, content_type, encrypt)`

Sends a reply to the sender of the current `<runtime-msg>`.

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `content` | bytes | — | Reply payload |
| `content_type` | string | `"application/x-ma-rpc-reply"` | MIME-like content type |
| `encrypt` | bool | — | Whether to encrypt the reply |

The runtime addresses the reply to `runtime_msg.from` and sets `replyTo` to
`runtime_msg.id`. The caller MUST NOT assume the recipient will respond.

This default reflects the standard RPC reply flow. Other content types remain
valid when explicitly provided.

---

### `get_state() -> state`

Returns the entity's current state as a JSON object.

The runtime MUST NOT expose key-level accessors. State is always read and
written as a complete blob.

---

### `set_state(state)`

Replaces the entity's state with the supplied JSON object.

| Parameter | Type | Description |
| --- | --- | --- |
| `state` | JSON object | New state to persist |

The runtime persists this updated state as part of normal message processing.

---

### `receive(patterns, timeout) -> runtime_msg | :timeout`

Selectively reads the next message from the entity's inbox that matches one
of the supplied `patterns`.

| Parameter | Type | Description |
| --- | --- | --- |
| `patterns` | list of terms | Elixir-inspired match patterns (see RPC Term Syntax in the runtime spec) |
| `timeout` | nanoseconds | Maximum wait time |

Returns the first matching `<runtime-msg>`, or `:timeout` if no match arrives
before `timeout` nanoseconds elapses. Messages that do not match any pattern
remain in the inbox.

The host maintains the inbox as a TTL queue and evicts expired messages
automatically. The entity is not responsible for pruning.

---

## Runtime Utility API

Runtime utility calls are host functions available to all entities. They return
values and do not themselves produce externally visible side effects.

---

### `now() -> <nano-epoch>`

Returns the current wall-clock time as a nanosecond UTC epoch. Entities MUST
use this instead of any platform clock to ensure the runtime controls time.

---

### `nanoid() -> <nanoid>`

Returns a new, unique nanoid generated by the host. Entities that need to
create identifiers (e.g. for `create` calls on `#root`) MUST use this
function rather than generating identifiers themselves.

---

### `random(n) -> integer`

Returns a cryptographically random integer in the range `[0, n)` — i.e. from 0
up to but not including `n`.

| Parameter | Type | Description |
| --- | --- | --- |
| `n` | integer | Upper bound (exclusive) |

---

## Mailbox Extensions

The following functions are available to entities of kind `/ma/mailbox/0.0.1`
in addition to the universal contract.

---

### `append(runtime_msg)`

Appends a message to the mailbox.

| Parameter | Type | Description |
| --- | --- | --- |
| `runtime_msg` | `<runtime-msg>` | Message to store |

---

### `peek() -> runtime_msg | null`

Returns the oldest message in the mailbox without removing it. Returns `null`
if the mailbox is empty.

---

### `pop() -> runtime_msg | null`

Removes and returns the oldest message in the mailbox. Returns `null` if the
mailbox is empty.

---

### `list(limit, cursor) -> [runtime_msg]`

Returns a page of messages from the mailbox.

| Parameter | Type | Description |
| --- | --- | --- |
| `limit` | integer | Maximum number of messages to return |
| `cursor` | opaque | Pagination cursor; omit or pass `null` for the first page |

Returns messages in chronological order. Supports cursor-based pagination.

---

### `delete(msg_id)`

Permanently removes a message from the mailbox.

| Parameter | Type | Description |
| --- | --- | --- |
| `msg_id` | nanoid | ID of the message to delete |

---

## Root Extensions

The following functions are available to entities of kind `/ma/root/0.0.1`
in addition to the universal contract. Only the entity designated as `owner`
of the runtime identity, or the root entity itself, MAY invoke these.

`#root` typically receives lifecycle requests as `application/x-ma-rpc` tuples
and then calls these host functions. RPC tuple format and host-call argument
shape are intentionally separate layers.

---

### `create_entity(fragment, fields)`

Creates a new entity.

| Parameter | Type | Description |
| --- | --- | --- |
| `fragment` | string | Fragment for the new entity; must be caller-supplied and unique |
| `fields` | object | Initial entity attributes |

The runtime MUST reject the call if an entity with that fragment already
exists.

Supported keys in `fields`:

| Key | Required | Description |
| --- | --- | --- |
| `kind` | yes | Kind identifier |
| `owner` | no | Entity owner `<did-ma-url>` |
| `acl` | no | Access control policy |
| `behavior` | no | Behavior CID |
| `state` | no | Initial JSON state |

`id` is derived by the runtime from `<identity>#<fragment>` and MUST NOT be
supplied in `fields`.

---

### `destroy_entity(fragment)`

Deletes an entity and its associated state.

| Parameter | Type | Description |
| --- | --- | --- |
| `fragment` | string | Fragment of the entity to delete |

No tombstone is created. The state CID previously referenced by the entity
becomes unreferenced and is subject to IPFS garbage collection.

---

### `upsert_entity(fragment, fields)`

Creates the entity if it does not exist, or updates the supplied fields if it
does.

| Parameter | Type | Description |
| --- | --- | --- |
| `fragment` | string | Fragment of the entity |
| `fields` | object | Fields to set or update |

`fields` uses the same keys as `create`: `kind`, `owner`, `acl`, `behavior`,
and `state`.

---

## References

- [MA Runtime Specification](core/ma-runtime-spec-v1.md)
- [Extism PDK](https://extism.org/docs/concepts/pdk)
