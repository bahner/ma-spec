# MA Runtime Specification v1

Status: draft

This document is the primary source for the MA runtime specification, written in
prose to support a subsequent formal specification pass.

---

## Overview

This system implements a **message-driven runtime** based on the Actor Model,
as defined by the `did:ma` method specified at <https://github.com/bahner/ma-spec>.

The runtime MUST be driven exclusively by message passing as seen from the entities.
The runtime MUST NOT implement arbitrary functions outside of defined kinds.

Each runtime is identified by a `<did>`, which is the root identity of the runtime.
The identity is backed by a bundle of secret keys that allow the runtime to sign,
encrypt, and decrypt messages.

It MUST be possible to send messages to the `<identity>` even when it is not a URL.
This is handled by the reserved `#root` fragment. Messages addressed to the bare
identity (i.e. `did:ma:<identity>` without a fragment) MUST be routed to `@root`.

Messages to `/ma/inbox/0.0.1` are handled by the <root> entity

## Core Concepts

### `<identity>`

An identity is the runtime itself, qualified by its DID: `did:ma:<ipnskey>`.
The IPNS key is the runtime identifier; the runtime MUST possess the corresponding
secret keys at startup.

The identity is used to verify and decrypt messages sent to and from the runtime's
`<did-ma-url>`s, as well as to sign and encrypt outgoing messages.

### `<did-ma-url>`

A `<did-ma-url>` is either a fully qualified `did:ma:<identity>#<nanoid>` or a
bare fragment `#<nanoid>`. A bare fragment can only be used for local delivery
within the runtime; in this case the runtime MAY skip full DID document lookup
and assume message integrity, since the message originates locally.

The bare identity `did:ma:<identity>` (without a fragment) is a special case that
MUST be routed to the `<root>` entity.

### `<msg>`

Messages delivered to entities are stripped of their outer `did:ma` envelope.
The host handles signing, encryption, and routing transparently.

The runtime MUST filter messages based on `created_at` and `ttl` before delivery.

msg:

```yaml
id: <nanoid>
to: <did-ma-url>
from: <did-ma-url>
created_at: <nano-timestamp>
ttl: <nanoseconds>
reply_to: <id>|null
content: {:atom, data}/?
content_type: <mimetype>
```

context:

```yaml
self: <did-ma-url>
now: <nano-epoch>
kind: /ma/<kind>/<semver>
msg: <msg>
```

The messages are appended to the inbox as erlang style: {<content>, ctx=<context>} to the <id>.
NB! The state is not passed, as it is partially handled by the runtime for persistency.

The :atom is extracted from the content. It can typically be: :fortune, :say, :emote or such

---

## Host Functions

Host functions are provided by the host to all plugin instances. They present a simplified interface that hides encryption, signing, and DID resolution.

```txt
send(<did-ma-url>, <msg>)
reply(<msg>)
get_state() -> <json>
set_state(state)
nanoid() -> <nanoid>
```

### send()

send() sends a message to the <url>, if the <did-ma-url> is a fully qualified url the message MUST be encrypted. If the url
is a local #<id> then message is sent directly to the <id> entity.

---

## Entity Model

Entities resemble Erlang processes. Each entity has an inbox identified by its
`#fragment`. Unlike Erlang processes, entities are implemented as
[Extism](https://extism.org) WebAssembly plugins and can be authored in any language.

### Structure

```yaml
id: <did-ma-url>
owner: <did-ma-url>
kind: <kind>
behavior: <cid>
state: <state>
acl: <acl>
```

### Field Definitions

| Field      | Description                                               |
| ---------- | --------------------------------------------------------- |
| `id`       | Unique DID-MA URL used for routing                        |
| `owner`    | Entity authorised to administer this entity               |
| `kind`     | Symbolic execution profile, resolved by the runtime       |
| `acl`      | Access control list governing who may send to this entity |
| `behavior` | Optional executable logic, referenced as a CID            |
| `state`    | Optional mutable persistent state                         |

### Rules

- Entities MUST reference kinds by name only.
- The runtime MUST resolve kind names to implementations.
- The runtime MUST reject unknown kinds.
- Users MUST NOT supply arbitrary kind plugins.
- Users MAY provide arbitrary behavior.
- All incoming messages MUST be passed to the target entity as a `<msg>`.
- The runtime MUST NOT infer persistence behavior from `content_type` alone,
  except where explicitly required by a runtime extension.
- An entity MAY append a `<msg>` to a mailbox, handle it immediately, forward it,
  reply to it, or discard it.
- A mailbox is an entity-controlled message store and is not the primary delivery
  mechanism.

### Behavior

`behavior` is the program executed by the entity.

- MUST be compatible with the entity's `kind`.
- SHOULD be stored and referenced as a CID.
- Defines how the entity reacts to messages.

---

## Kind Model

A `kind` defines **how an entity executes**. Kinds are evaluated by the runtime
and abstract over Extism plugins. They can be thought of as prototyped objects in
an OOP sense; there is no inheritance.

The runtime MUST maintain a registry of known kinds. Unknown kinds MUST be rejected.

### Kind Protocol

Kind identifiers follow this structure:

```
/ma/extism/<kind-name>/<version>
```

As of this specification, only `extism` is supported as the evaluator.

### Minimal Kind Structure

```yaml
kind: <protocol>
manifest: <cid>
implements:
  - init
  - send
  - reply
  - get_state
  - set_state
```

### `<manifest>`

The manifest is a Wasm manifest serialised as dag-cbor and stored as IPLD.
Because the plugin MUST be fetched by content-addressed CID, a separate checksum
field is not required.

### Required Kinds

#### `generic`

The base kind. Implements `init`, `send`, `reply`, `get_state`, and `set_state`.

```yaml
kind: /ma/extism/generic/0.0.1
manifest: <cid>
implements:
  - init
  - send
  - reply
  - get_state
  - set_state
  - receive
  - flush
```

#### `mailbox`

Protocol: /ma/mailbox/0.0.1

Provides persistent, ordered message storage. Messages with `content_type:
application/x-ma-message` are stored with `created_at` and an optional `ttl`.
If `ttl` is `0` or absent, messages are retained indefinitely. Otherwise,
`prune()` MUST delete messages where `created_at + ttl < now()`.

```yaml
protocol: /ma/mailbox/0.0.1
manifest: <cid>
implements:
  - init
  - get_state
  - set_state
  - append
  - peek
  - pop
  - list
  - delete
  - prune
  - ack
  - nack
```

Method signatures:

```txt
init(state, state_format="json")
get_state() -> state
set_state(state, state_format="json")
append(msg)
peek() -> msg | null
pop() -> msg | null
list(limit, cursor) -> [msg]
delete(msg_id)
prune(before_time)
ack(msg_id)
nack(msg_id)
```

Rules:

- `prune` MUST NOT delete messages with `ttl = 0` or absent `ttl`.
- `ack` and `nack` are advisory and do not affect storage unless the entity
  logic acts on them.
- `list` MUST support cursor-based pagination.

#### `root`

The `root` kind is the administrative entry point for the runtime. It is
instantiated at the well-known fragment `#root` and handles entity lifecycle
operations.

It doesn't require a persistent state

```yaml
kind: /ma/extism/root/0.0.1
manifest: <cid>
implements:
  - create
  - destroy
  - upsert
```

Method signatures:

```txt
create(<id>, kind) -> <did-ma-url>
destroy(<did-ma-url>)
upsert(<id>, fields)
```

Rules:

- `create` MUST generate a nanoid if none is provided.
- `destroy` MUST delete the entity and its associated state.
- `upsert` MUST create the entity if it does not exist, or update the provided
  fields if it does.
- Only the entity designated as `owner` of the runtime identity, or the root
  entity itself, MAY invoke root operations.

---

## State

This specification defines the state protocol as `/ma/state/0.0.1`.

`state` is **persistent, mutable storage** isolated per entity. It is stored and
protected by the runtime.

When an entity is created it MUST be initialised with a valid JSON `<state>`.
If no state is provided the runtime MUST substitute an empty JSON object (`{}`).

The runtime identifies the state of an entity by its CID.

### Rules

- MUST be isolated per entity.
- MUST persist across executions.
- MUST only be modified via runtime APIs.

### Persistent Storage Format

Before storage, the runtime MUST serialise the state and prefix the resulting bytes
with the appropriate multicodec identifying the plaintext format.

State stored outside the entity MUST be encrypted. The stored value SHOULD be an
IPLD dag-cbor envelope of the following form:

```cbor
{
  "protocol": "/ma/state/0.0.1",
  "alg": "aes-gcm-256",
  "nonce": <bytes>,
  "ciphertext": <bytes>,
  "tag": <bytes>,
  "recipient_public_key": "<publicKeyMultibase>",
  "entity": "<did-url>"
}
```

Where:

- `ciphertext` is the AEAD-encrypted multicodec-prefixed plaintext.
- `nonce` is unique per encryption operation.
- `tag` is the AEAD authentication tag.

### Additional Authenticated Data (`aad`)

The AEAD Additional Authenticated Data MUST be derived from envelope metadata
and MUST NOT be stored explicitly; it MUST be reconstructed identically during
decryption. Any mismatch MUST cause decryption to fail.

The AAD MUST be the canonical dag-cbor encoding of:

```cbor
{
  "entity": "<did-url>",
  "protocol": "<protocol>",
  "recipient_public_key": "<publicKeyMultibase>"
}
```

Where:

- `entity` is the fully qualified `did-url` including the runtime identity.
- `protocol` is the envelope protocol identifier, e.g. `/ma/state/0.0.1`.
- `recipient_public_key` is the multibase-encoded public key the content is
  encrypted for, typically the public key of the `<identity>`.

Including `recipient_public_key` in the AAD is RECOMMENDED.

### Multicodec-Prefixed Plaintext

Before encryption, state MUST be prepared as follows:

```
state
  → serialise using <plaintext-codec>
  → prefix with multicodec(<plaintext-codec>)
  → use as AEAD plaintext input
```

Upon decryption:

```
AEAD decrypt → <multicodec-prefixed-bytes>
  → read multicodec prefix
  → decode payload using indicated codec
  → return state as JSON
```

### Nonce

The nonce MUST be unique per encryption operation for a given key. For
`aes-gcm-256` the nonce MUST be 12 bytes. Reusing a nonce with the same key MUST
be treated as a fatal error.

### Canonical dag-cbor

When constructing AAD or serialising envelopes, dag-cbor MUST be encoded in
canonical form:

- Map keys sorted in bytewise lexicographic order.
- Deterministic encoding of all values.
- No duplicate keys.

All implementations MUST produce identical byte sequences for identical input data.

---

## Runtime Responsibilities

### Message Handling

- Receive MA message.
- Validate envelope (signature, TTL, sender identity).
- Resolve target entity.
- Deliver `content` to the evaluator via host functions.

### Execution

The runtime MUST execute the following sequence on each message delivery:

```
resolve kind
→ load evaluator implementation
→ load behavior
→ load state
→ call init(state)
→ deliver message
→ collect effects
→ apply effects
→ persist updated state
```

### Context Exposure

Evaluators MUST have access to the following host-provided context:

```txt
self() -> <did-ma-url>
sender() -> <did-ma-url> | null
message_id() -> <nanoid> | null
has_capability(name) -> bool
```

### Effects API

Evaluators MAY invoke the following effects:

```txt
send(target, content, content_type, encrypt)
reply(content, content_type, encrypt)
state_get(key) -> value
state_set(key, value)
state_delete(key)
```

Rules:

- All effects MUST be capability-checked before execution.
- The runtime MUST enforce capability restrictions.
- The runtime MUST construct, sign, and route outgoing messages.
- Calls to capabilities not declared for the entity's kind MUST be rejected.

### Capability Model

Capabilities are declared per kind and enforced by the runtime.

The runtime MUST:

- Enforce capability declarations at call time.
- Expose `has_capability()` to evaluators.
- Reject calls to capabilities not declared for the entity's kind.

---

## Administrative Model

All administration MUST occur via messages, not direct CLI or API calls outside the message protocol.

### Root Entity

The well-known root entity for any runtime is:

```txt
did:ma:<identity>|#root
```

Local entities send administrative requests to #root outside
actors send to the <identity>

It handles entity lifecycle operations as described under the `root` kind above.

### Create Entity

```yaml
to: <did>
content_type: application/x-ma-rpc
content:
  op: create
  id: <did-ma-url>
  kind: <kind>
  behavior: <cid>
  owner: <did-ma-url>
```

The requestor must provide the #id which is why all entities needs access to a nanoid() function to generate valid <id>s

### Update Entity

Updateing the id should is a suposedly commonly used rpc,
when owners update the behaviour of an entity the runtime
save the current state and reinitialises the entity.

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-command
content:
  op: upsert
  id: did:ma:<identity>#<id>
  behavior: <cid>
```

### Delete Entity

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-command
content:
  op: destroy
  id: did:ma:<identity>#fortune
```

### Authorization

The runtime MUST:

- Verify the sender's identity against the message signature.
- Verify that the sender is the `owner` of the target entity or holds admin rights.
- Reject unauthorized operations with an error reply.

---

## Design Principles

### No Built-in Application Types

The runtime MUST NOT define rooms, users, avatars, or any other application-level
concept. These are implemented as kinds and behaviors by users of the runtime.

### Strict Layer Separation

| Layer    | Responsibility                               |
| -------- | -------------------------------------------- |
| Runtime  | Message routing, state management, execution |
| Kind     | Execution profile and capability declaration |
| Behavior | Entity-specific logic                        |
| State    | Mutable persistent storage per entity        |

### Deterministic Core

The runtime SHOULD aim for deterministic execution, reproducibility, and
debuggability. Non-determinism MUST be confined to explicit side effects declared
by kind capabilities.

---

## Example: Fortune Entity

```yaml
id: did:ma:services#fortune
owner: did:ma:services#root
kind: /ma/extism/generic/0.0.1
behavior: /ipfs/bafy...fortune-script
state: /ipfs/bafy...state
```

On receiving a message, the fortune entity reads the content, picks a fortune, and
replies using `reply()`. It declares no `send` capability and therefore MUST NOT
initiate outbound messages.
