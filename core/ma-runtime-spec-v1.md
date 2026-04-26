# MA Runtime Specification v1

**Version:** 1  
**Status:** Draft  
**Authors:** Lars Bahner

## Abstract

This document specifies the runtime behaviour of the `did:ma` actor system. It
defines entity lifecycle, message intake and delivery, the Extism plugin interface,
state persistence, and administrative operations. Because v1 requires Wasm
modules executed through Extism, Extism's execution model constrains the host
interface and runtime semantics defined by this specification.

### Scope Boundary

This document covers runtime-level behaviour only. The `did:ma` DID method, DID
document format, and wire-level messaging format are out of scope and are specified
in the parent specification at <https://github.com/bahner/ma-spec>.

---

## Conformance

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
RECOMMENDED, MAY, and OPTIONAL in this document are to be interpreted as described
in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

---

## Overview

This system implements a **message-driven runtime** based on the Actor Model, as
defined by the `did:ma` method specified at <https://github.com/bahner/ma-spec>.

The runtime MUST be driven exclusively by message passing as seen from the
entities. The runtime MUST NOT implement arbitrary functions outside of defined
kinds.

Each runtime is identified by a `<did>`, which is the root identity of the
runtime. The identity is backed by two local files: a **secret bundle** containing
the key material needed to sign, encrypt, and decrypt messages together with the
canonical DID document metadata for that identity, and a **YAML configuration
file** containing host-specific settings such as listen addresses, bootstrap
peers, and a startup hint for the last known runtime-root CID. The secret bundle
MUST preserve the original `created_at` value across restarts and migrations
between machines. The YAML configuration file is not secret and MUST NOT contain
key material.

It MUST be possible to send messages to the `<identity>` even when it is not a
URL. This is handled by the reserved `#root` fragment. Messages addressed to the
bare identity (i.e. `did:ma:<identity>` without a fragment) MUST be routed to
`#root`.

All inbound messages arrive via the `/ma/inbox/0.0.1` service. The `#root`
entity handles administrative operations; see the Kind Model section for its
method signatures.

### Actor Model Semantics

This runtime follows the Hewitt Actor Model. Messages MUST NOT require a reply.
An entity MAY send a reply, but no sender may assume or depend on one being
produced. Any protocol that needs a response MUST handle the absence of a reply
explicitly.

---

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
MUST be routed to the `#root` entity.

### `<ma-msg>`

A `<ma-msg>` is a full wire-format message as specified in the `did:ma` messaging
format. It is a signed, optionally encrypted CBOR structure with camelCase field
names, carrying a typed payload between actors identified by `<did-ma-url>`s.

The runtime is solely responsible for all `<ma-msg>` protocol concerns: envelope
decryption, signature verification, replay detection, and DID resolution. Entities
MUST NOT be expected to handle any of these.

### `<runtime-msg>`

A `<runtime-msg>` is a `<ma-msg>` from which the runtime has removed all
protocol-layer fields before delivery to an entity. It is not a separate format;
it is a projection of `<ma-msg>` into the local delivery context. Entities operate
at content level only.

The runtime MUST preserve the following fields:

| Field          | Source field in `<ma-msg>` | Description                                 |
| -------------- | -------------------------- | ------------------------------------------- |
| `id`           | `id`                       | Message identifier for correlation          |
| `from`         | `from`                     | Sender `<did-ma-url>`                       |
| `to`           | `to`                       | Recipient `<did-ma-url>`                    |
| `created_at`   | `createdAt`                | Nanosecond epoch (UTC)                      |
| `content_type` | `contentType`              | MIME-like content type                      |
| `reply_to`     | `replyTo`                  | Optional ID of the message being replied to |
| `content`      | `content`                  | Decrypted payload bytes                     |

The runtime MUST strip the following fields before delivery:

| Field                | Reason                                              |
| -------------------- | --------------------------------------------------- |
| `signature`          | Verified by runtime; meaningless to entity          |
| `type`               | Protocol version marker; irrelevant to entity logic |
| `ttl`                | Validated by runtime before delivery                |
| `contentHash`        | Verified by runtime before delivery                 |
| `ephemeralKey`       | Envelope field; decrypted by runtime                |
| `encryptedContent`   | Envelope field; decrypted by runtime                |
| `encryptedHeaders`   | Envelope field; decrypted by runtime                |

Field names in `<runtime-msg>` use snake_case. This is a deliberate local
convention; it does not affect the `<ma-msg>` wire format, which uses camelCase
as specified by the parent. The runtime MUST translate field names between
camelCase (`<ma-msg>`) and snake_case (`<runtime-msg>`) in both directions.
Entities MUST NOT be exposed to camelCase field names, and the wire format MUST
NOT contain snake_case field names.

`<runtime-msg>`:

```yaml
id: <nanoid>
from: <did-ma-url>
to: <did-ma-url>
created_at: <nano-epoch>
reply_to: <id> | null
content_type: <mimetype>
content: <bytes>
```

`<context>`:

```yaml
self: <did-ma-url>
now: <nano-epoch>
created_at: <nano-epoch>
expires_at: <nano-epoch>
runtime: /ma/runtime/0.0.1
```

`expires_at` is derived from `created_at + ttl` of the original `<ma-msg>`.

Messages are delivered to entities as `handle_message(runtime_msg, context)`.

#### Local Delivery

Messages exchanged between entities within the same runtime MUST NOT be wrapped
in a `<ma-msg>` envelope. The runtime constructs a `<runtime-msg>` directly and
routes it without encryption, signing, or DID resolution overhead.

Local delivery is identified by a recipient whose `<did-ma-url>` identity
component matches the runtime's own `<identity>`, or by a bare fragment address
(e.g. `#fortune`).

---

## IPFS Storage Model

All runtime state MUST be stored in IPFS as IPLD dag-cbor nodes. The local
filesystem MUST NOT be used as a persistence layer for runtime or entity state.
The only data read from the local filesystem at startup are the secret bundle and
the YAML configuration file.

### Local Files

| File | Format | Contents |
| --- | --- | --- |
| Secret bundle | binary | IPNS private key; Ed25519 signing key; X25519 key-agreement key; canonical DID document metadata including the immutable `created_at` timestamp |
| Configuration file | YAML | Host-specific settings: listen addresses, bootstrap peers, log level, and the last known runtime root CID as a startup hint (`last_cid`) |

The secret bundle MUST be treated as a secret at rest. The configuration file is
not secret and MAY be readable by operators.

### IPLD Tree Structure

The runtime maintains a single canonical IPLD tree rooted at a dag-cbor node
called the **runtime-root**. This root and all nodes beneath it MUST be stored in
IPFS. The runtime-root CID is the authoritative reference for the full runtime
state.

```txt
runtime-root (dag-cbor)
├── protocol:  "/ma/runtime/0.0.1"
├── identity:  "did:ma:<ipnskey>"
└── entities:  { <fragment> → <entity-CID>, … }

entity (dag-cbor)
├── id:        "<did-ma-url>"
├── owner:     "<did-ma-url>"
├── kind:      "<kind-identifier>"
├── acl:       { … }
├── behavior:  <CID>   ← Wasm module
└── state:     <CID>   ← encrypted /ma/state/0.0.1 envelope
```

The `entities` map keys are bare fragment strings (e.g. `"root"`, `"fortune"`).
The `state` CID references an already-encrypted envelope (see State section), and
it is therefore safe to include it in the otherwise open IPLD tree.

Removing an entity MUST be performed by writing a new runtime-root that omits the
entity's fragment from the `entities` map. No tombstone record is created. The
state CID previously referenced by that entity is then unreferenced and subject to
IPFS garbage collection.

### `ma.runtime` DID Document Field

The runtime-root CID MUST be published in the DID document under `ma.runtime`.
This field is defined in the parent specification (`core/ma-did-ma-fields.md`) and
reproduced here for reference:

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

| Field | Type | Requirement | Description |
| --- | --- | --- | --- |
| `cid` | CIDv1 string | REQUIRED | Current runtime-root CID in base32 encoding |
| `publish_interval` | duration string | RECOMMENDED | How often the runtime publishes an updated `cid`; default `"15m"` |
| `ipns_ttl` | duration string | RECOMMENDED | How long resolvers may cache the IPNS record; MUST be ≥ 2 × `publish_interval`; default `"24h"` |
| `allowed_kinds` | array of strings | OPTIONAL | Whitelist of kind identifiers this runtime accepts for entity creation; absent or empty means all registered kinds are allowed |

Duration strings use Go duration syntax: `"5m"`, `"15m"`, `"1h"`, `"24h"`.

### DID Document Publish Policy

Publishing a new DID document is required whenever `ma.runtime.cid` or any other
`ma` field changes. The runtime MUST follow this policy:

| Trigger | Rule |
| --- | --- |
| Manual save operation | MUST publish immediately |
| Graceful shutdown | MUST publish immediately |
| Automatic (state change) | MUST NOT publish more often than once every 5 minutes |
| Automatic (periodic) | SHOULD publish at the configured `publish_interval`; default 15 minutes |

To prevent IPNS record expiry between automatic publishes, `ipns_ttl` MUST be set
to a value at least twice `publish_interval`. With the defaults (15 min interval,
24 h TTL) this constraint is satisfied with substantial margin.

The runtime MUST update `ma.runtime.cid` in the DID document whenever the
runtime-root CID changes. The runtime MUST increment `updated_at` on every
publish. The runtime MUST NOT reset `created_at`.

---

## Protocol Identifiers

The following protocol identifiers are defined by this specification. All
identifiers follow the IPFS path convention with a leading slash.

| Identifier | Purpose |
| --- | --- |
| `/ma/runtime/0.0.1` | Runtime protocol identifier, exposed in message context |
| `/ma/inbox/0.0.1` | Inbound message service; defined in the parent specification |
| `/ma/state/0.0.1` | Encrypted state envelope format |
| `/ma/kind/<kind>/<version>` | Kind identifier pattern |

---

## Startup

On startup the runtime MUST perform the following steps in order:

1. **Load local files.** Read the YAML configuration file for host-specific
   settings (listen addresses, bootstrap peers, log level, `last_cid` hint) and
   load the secret bundle (IPNS private key, Ed25519 signing key, X25519
   key-agreement key, canonical DID document metadata including the original
   `created_at` timestamp). The runtime MUST abort if any required key material
   or the preserved `created_at` value is missing or unreadable.

2. **Resolve or publish DID document.** The runtime MUST attempt to resolve its
   own `<identity>` via IPNS to obtain the current DID document as a startup
   consistency check. If resolution succeeds, the runtime MUST verify the proof
   on the document and compare the published keys and required metadata against
   the loaded identity bundle. If resolution fails, proof verification fails, or
   any required field does not match, the runtime MUST publish a corrected DID
   document derived from the loaded identity bundle. When republishing, the
   runtime MUST preserve the original `created_at` value from the local bundle
   and refresh only `updated_at` and any fields that no longer match the
   expected document state. The runtime MUST abort only if it cannot publish the
   corrected DID document.

3. **Load runtime-root from IPFS.** Read `ma.runtime.cid` from the resolved DID
   document. If the field is absent or the CID is unreachable, fall back to the
   `last_cid` hint from the configuration file. If neither source yields a
   retrievable CID, treat the runtime as newly initialised with an empty entity
   set. The runtime MUST abort if a CID is available but the node cannot be
   fetched or its `identity` field does not match the loaded `<identity>`.

4. **Load kind registry.** Populate the kind registry with all built-in kinds.
   The runtime MUST abort if a required kind manifest cannot be fetched or
   verified.

5. **Initialise root entity.** Ensure the `#root` entity exists in the loaded
   entity set. If it does not, the runtime MUST create it with
   `kind: /ma/kind/root/0.0.1` and an empty state, write the resulting entity
   node to IPFS, and produce a new runtime-root node that includes the `#root`
   entry. If it exists, load its state CID from the entity node and decrypt the
   `/ma/state/0.0.1` envelope from IPFS.

6. **Begin accepting messages.** Start the `/ma/inbox/0.0.1` service and begin
   the message intake loop.

---

## Message Intake

The runtime MUST process every inbound `<ma-msg>` through the following pipeline
before delivery.

### External Messages

External messages arrive as serialised CBOR over a transport channel.

```txt
receive <ma-msg> bytes
→ deserialise CBOR
→ verify `type` field is known (e.g. "/ma/0.0.1"); reject if not
→ validate replay guard (see Replay Guard below)
→ if encrypted: decrypt envelope (X25519 ECDH + BLAKE3 KDF + XChaCha20-Poly1305)
→ verify signature (Ed25519 over BLAKE3(CBOR(headers)))
→ verify `contentHash` matches BLAKE3(content)
→ resolve target entity
→ strip protocol-layer fields → produce `<runtime-msg>`
→ deliver `<runtime-msg>` to entity
```

The runtime MUST reject any message that fails at any step and SHOULD send an
error reply to the sender if the sender identity is resolvable.

### Local Messages

Messages sent by an entity within the runtime to another entity in the same
runtime bypass the `<ma-msg>` pipeline entirely.

```txt
entity invokes send(target, content, content_type, encrypt=false)
→ validate target is a local <did-ma-url>
→ capability-check sender
→ construct <runtime-msg> directly
→ deliver to target entity
```

Local messages MUST NOT be encrypted or signed by the runtime. The runtime
guarantees integrity by construction.

### Replay Guard

The runtime MUST maintain a replay guard consistent with the `did:ma` messaging
specification:

| Parameter            | Value                         |
| -------------------- | ----------------------------- |
| Retention window     | 120 seconds                   |
| Clock skew tolerance | 30 seconds                    |
| Default TTL          | 3 600 000 000 000 nanoseconds |

The runtime MUST reject a message if:

- `createdAt > now + skew`, or
- `ttl != 0` and `now > createdAt + ttl + skew`, or
- the message `id` has been seen within the retention window.

Expired entries MUST be pruned periodically.

---

## Host Interface

The host interface is divided into two parts: **PDK functions** and the
**Effects API**.

**PDK functions** are Wasm exports that the runtime calls on the plugin. They are
the entry points through which the runtime delivers messages and state.

**Effects** are calls the plugin makes back into the runtime during execution.
They are collected by the runtime and applied atomically after the plugin returns.
Entities MUST NOT assume that effects are applied during execution.

### PDK Functions

The runtime MUST invoke the following exported Wasm functions:

```txt
init(state, state_format=<format|"json">)
handle_message(runtime_msg, context)
```

`init` is called once per entity instantiation and passes the current state to
the plugin. `handle_message` is called on each message delivery.

### Effects API

All entities MAY invoke the following host effects during execution. Outgoing
messages MUST only be sent via these host functions; entities MUST NOT construct
or dispatch `<ma-msg>` directly.

```txt
send(target, content, content_type=<mimetype|"text/plain">, encrypt=<bool>)
reply(content, content_type=<mimetype|"text/plain">, encrypt=<bool>)
state_get(key) -> value
state_set(key, value)
state_delete(key)
```

Rules:

- All effects MUST be capability-checked against the entity's kind before
  application.
- The runtime MUST construct, sign, and route outgoing messages produced by
  `send` and `reply`.
- `reply` MUST address the response to the `from` field of the current
  `<runtime-msg>` and set `replyTo` to its `id`.
- Calls to effects not declared for the entity's kind MUST be rejected.
- An entity invoking `send` or `reply` MUST NOT assume the recipient will
  respond.

---

## Entity Model

Entities resemble Erlang processes. Each entity has an inbox identified by its
`#fragment`. Unlike Erlang processes, entities are implemented as
[Extism](https://extism.org) WebAssembly plugins and can be authored in any
language.

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
| `mailbox`  | Optional message store for long-lived messages            |

### Entity Rules

- Entities MUST reference kinds by name only.
- The runtime MUST resolve kind names to implementations.
- The runtime MUST reject unknown kinds.
- Users MUST NOT supply arbitrary kind plugins.
- Users MAY provide arbitrary behavior.
- All incoming messages MUST be passed to the target entity as a `<runtime-msg>`.
- The runtime MUST NOT infer persistence behavior from `content_type` alone,
  except where explicitly required by a runtime extension.
- An entity MAY append a `<runtime-msg>` to a mailbox, handle it immediately,
  forward it, reply to it, or discard it.
- A mailbox is an entity-controlled message store and is not the primary
  delivery mechanism.

### Behavior

`behavior` is the program executed by the entity.

- MUST be compatible with the entity's `kind`.
- SHOULD be stored and referenced as a CID.
- Defines how the entity reacts to messages.

---

## Kind Model

A `kind` defines **how an entity executes**. Kinds are evaluated by the runtime
and abstract over execution implementations. They can be thought of as prototyped
objects in an OOP sense; there is no inheritance.

The runtime MUST maintain a registry of known kinds. Unknown kinds MUST be
rejected.

### Kind Protocol

Kind identifiers follow this structure:

```txt
/ma/kind/<kind-name>/<version>
```

The kind identifier does not encode the evaluator. In v1, all kinds MUST be
implemented as Wasm modules executed through Extism.

### Minimal Kind Structure

```yaml
kind: <protocol>
manifest: <cid>
implements:
  - init
  - handle_message
  - get_state
  - set_state
```

### `<manifest>`

The manifest is a Wasm manifest serialised as dag-cbor and stored as IPLD.
Because the plugin MUST be fetched by content-addressed CID, a separate checksum
field is not required.

### Kind Resolution

When the runtime loads a kind it MUST:

1. Look up the kind identifier in the registry.
2. Fetch the manifest by its CID from IPFS using `dag get`.
3. Deserialise the dag-cbor manifest.
4. Verify that the manifest's declared `implements` list includes all
   capabilities required by the entity.
5. Load the Wasm module referenced by the manifest.

The runtime MUST abort kind loading if the CID cannot be resolved, the manifest
fails deserialisation, or the Wasm module cannot be loaded.

### Required Kinds

#### `generic`

The base kind. Implements `init`, `handle_message`, `get_state`, and `set_state`.

```yaml
kind: /ma/kind/generic/0.0.1
manifest: <cid>
implements:
  - init
  - handle_message
  - get_state
  - set_state
```

#### `mailbox`

Provides persistent, ordered message storage. Messages with `content_type:
application/x-ma-message` are stored with `created_at` and an optional `ttl`.
If `ttl` is `0` or absent, messages are retained indefinitely. Otherwise,
`prune()` MUST delete messages where `created_at + ttl < now()`.

```yaml
kind: /ma/kind/mailbox/0.0.1
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
append(runtime_msg)
peek() -> runtime_msg | null
pop() -> runtime_msg | null
list(limit, cursor) -> [runtime_msg]
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

```yaml
kind: /ma/kind/root/0.0.1
manifest: <cid>
implements:
  - init
  - get_state
  - set_state
  - create
  - destroy
  - upsert
```

Method signatures:

```txt
create(nanoid, kind) -> <did-ma-url>
destroy(fragment)
upsert(fragment, fields)
```

Rules:

- `create` MUST use the caller-supplied nanoid as the entity fragment. The
  caller is responsible for generating a unique nanoid. The runtime MUST reject
  a `create` request if an entity with that fragment already exists.
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

The runtime identifies the state of an entity by its CID. This CID is stored as the `state` link in the entity node in the IPLD tree.

### State Rules

- MUST be isolated per entity.
- MUST persist across executions.
- MUST only be modified via runtime APIs.
- MUST be stored in IPFS as an IPLD dag-cbor node.

### Persistent Storage Format

Before storage, the runtime MUST serialise the state and prefix the resulting
bytes with the appropriate multicodec identifying the plaintext format.

State stored outside the entity MUST be encrypted. The stored value MUST be an
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

```txt
state
  → serialise using <plaintext-codec>
  → prefix with multicodec(<plaintext-codec>)
  → use as AEAD plaintext input
```

Upon decryption:

```txt
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

All implementations MUST produce identical byte sequences for identical input
data.

---

## Runtime Responsibilities

### Context Exposure

Evaluators MUST have access to the following host-provided context functions:

```txt
self() -> <did-ma-url>
sender() -> <did-ma-url> | null
message_id() -> <nanoid> | null
has_capability(name) -> bool
```

### Capability Model

Capabilities are declared per kind and enforced by the runtime.

The runtime MUST:

- Enforce capability declarations at call time.
- Expose `has_capability()` to evaluators.
- Reject calls to capabilities not declared for the entity's kind.

### Execution

The runtime MUST execute the following sequence on each message delivery:

```txt
resolve kind
→ load evaluator implementation
→ load behavior
→ load state
→ call init(state)
→ deliver <runtime-msg> via handle_message(runtime_msg, context)
→ collect effects
→ apply effects
→ persist updated state
```

---

## Lifecycle

The lifecycle mode is declared per kind.

| Mode       | Description                                         |
| ---------- | --------------------------------------------------- |
| ephemeral  | New plugin instance per message; no retained memory |
| persistent | Plugin instance may be reused; state persists       |

The runtime MAY reuse evaluator instances for performance but MUST NOT rely on
instance memory for persistence. All persistence MUST go through the state API.

---

## Administrative Model

All administration MUST occur via messages, not direct CLI or API calls outside
the message protocol.

### Content Types: `application/x-ma-rpc` and `application/x-ma-rpc-reply`

`application/x-ma-rpc` is a runtime-layer content type used for RPC calls
addressed to any entity. `application/x-ma-rpc-reply` is the corresponding reply
type. Both are runtime-layer extensions to the `did:ma` content type set.

| Property   | `application/x-ma-rpc`         | `application/x-ma-rpc-reply`   |
| ---------- | ------------------------------ | ------------------------------ |
| Encryption | REQUIRED for external messages | REQUIRED for external messages |
| Target     | Any `<did-ma-url>`             | Sender of the originating RPC  |

Consistent with the actor model, a reply MUST NOT be assumed. The caller MAY
set `reply_to` on the RPC message to indicate it expects a result, but the
recipient is not obliged to reply.

The RPC payload uses Elixir-style terms: either a bare atom or a tagged tuple
whose first element is an atom. Tuple arity is not constrained by this
specification; the receiving entity defines which signatures it accepts.

When serialised to CBOR for transport:

- Atoms are encoded as UTF-8 strings.
- Tuples are encoded as CBOR arrays where the first element is the atom string.

Examples of valid RPC payloads:

```elixir
:ping
{:create, "did:ma:<identity>#fortune", "/ma/kind/generic/0.0.1", "<cid>", "did:ma:<identity>#root"}
{:destroy, "did:ma:<identity>#fortune"}
{:upsert, "did:ma:<identity>#fortune", "<cid>"}
{:emote, "wiggles its tail"}
```

For lifecycle operations on `#root`, the nanoid fragment in a `:create` tuple
MUST be caller-supplied. The runtime MUST NOT generate the fragment on behalf of
the caller.

### Root Entity

The well-known root entity for any runtime is:

```txt
did:ma:<identity>#root
```

It handles entity lifecycle operations as described under the `root` kind above.

### Create Entity

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-rpc
content: {:create, "did:ma:<identity>#fortune", "/ma/kind/generic/0.0.1", "<cid>", "did:ma:<identity>#root"}
```

### Update Entity

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-rpc
content: {:upsert, "did:ma:<identity>#fortune", "<cid>"}
```

### Delete Entity

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-rpc
content: {:destroy, "did:ma:<identity>#fortune"}
```

### Authorisation

The runtime MUST:

- Verify the sender's identity against the message signature.
- Verify that the sender is the `owner` of the target entity or holds admin
  rights.
- Reject unauthorised operations with an error reply.

---

## Error Handling

All runtime errors MUST produce a structured error reply addressed to the sender.
Error replies use `content_type: application/x-ma-error` and the following
payload structure:

```yaml
code: <string>
message: <string>
msg_id: <nanoid> | null
```

Where `msg_id` is the `id` of the message that caused the error, if known.

### Error Codes

| Code                | Trigger condition                                         |
| ------------------- | --------------------------------------------------------- |
| `invalid_message`   | Malformed CBOR, unknown `type`, or missing required field |
| `signature_invalid` | Message signature verification failed                     |
| `replay_detected`   | Message `id` seen within replay guard window              |
| `message_expired`   | Message TTL exceeded                                      |
| `entity_not_found`  | Target `<did-ma-url>` does not exist                      |
| `entity_exists`     | `create` called with a fragment that is already in use    |
| `kind_unknown`      | Entity references an unregistered kind                    |
| `capability_denied` | Entity invoked an effect not declared by its kind         |
| `unauthorised`      | Sender is not authorised to perform the operation         |
| `execution_failed`  | Wasm plugin returned an error or panicked                 |
| `state_error`       | State encryption, decryption, or persistence failed       |

The runtime SHOULD NOT send error replies for messages whose sender identity
cannot be resolved.

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
kind: /ma/kind/generic/0.0.1
behavior: /ipfs/bafy...fortune-script
state: /ipfs/bafy...state
```

On receiving a message, the fortune entity picks a fortune and replies using the
`reply()` host effect. The sender MUST NOT assume a reply will be produced.

---

## References

- [MA Spec — DID Method Specification](https://github.com/bahner/ma-spec/blob/main/did-method-spec.md)
- [MA Spec — DID Document Format](https://github.com/bahner/ma-spec/blob/main/did-document-format.md)
- [MA Spec — Messaging Format](https://github.com/bahner/ma-spec/blob/main/messaging-format.md)
- [Extism](https://extism.org) — WebAssembly plugin system
- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) — Key words for use in RFCs
- [IPFS Documentation](https://docs.ipfs.tech/)
- [IPNS Specification](https://specs.ipfs.tech/ipns/ipns-record/)
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
- [Ed25519 (RFC 8032)](https://www.rfc-editor.org/rfc/rfc8032)
- [X25519 (RFC 7748)](https://www.rfc-editor.org/rfc/rfc7748)
- [BLAKE3](https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf)
- [XChaCha20-Poly1305](https://www.rfc-editor.org/rfc/rfc8439)
- [nanoid](https://github.com/ai/nanoid)
