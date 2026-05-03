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
in the parent specification at <https://github.com/bahner/ma-spec> (間-spec).

---

## Conformance

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
RECOMMENDED, MAY, and OPTIONAL in this document are to be interpreted as described
in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

---

## Overview

This system implements a **message-driven runtime** based on the Actor Model, as
defined by the `did:ma` method specified at <https://github.com/bahner/ma-spec> (間-spec).

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

### Debt to Erlang and Elixir

This runtime draws heavily on the Erlang/OTP runtime and the Elixir ecosystem.
Erlang has operated reliably as a distributed, fault-tolerant actor system for
decades in production environments of the highest demands. Where this
specification borrows concepts — message passing, selective receive, term syntax,
process isolation, and the principle that state is always explicit — it does so
deliberately. There is significant value in reusing a proven mental model and
familiar syntax: implementors and users who know Erlang or Elixir will find the
semantics immediately recognisable, and the runtime inherits the clarity that
comes from a design that has been tested at scale over a long time.

Where the `did:ma` runtime diverges from Erlang/Elixir — most notably in its use
of WebAssembly plugins, content-addressed state, and a decentralised identity
layer — those divergences are intentional and are specified explicitly. Everything
else should feel familiar.

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

Messages are delivered to entities as `handle_message(runtime_msg)`. The entity's own identity (`self`) is set at instantiation time and does not need to be passed with each message.

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
The only data read from the local filesystem at startup are the secret bundle
and the YAML configuration file. Publication of that IPFS/IPLD state through
IPNS and DID metadata is an eventually consistent, best-effort background
process used for recovery, later loading, and public inspection. The runtime's
correctness MUST NOT depend on immediate IPFS/IPNS freshness or on every
publication attempt succeeding on the first try. A temporary IPFS/Kubo outage
MUST be handled gracefully where possible. Delayed or failed publication of new
state to IPFS/IPNS MUST NOT by itself prevent continued message delivery,
entity execution, or iroh-based transport. IPFS availability remains a hard
dependency for required reads: the runtime MUST fail when it must load,
resolve, or decrypt a CID-backed object that is required for the requested
operation and that read cannot be completed.

### Local Files

| File | Format | Contents |
| --- | --- | --- |
| Secret bundle | binary | Identity IPNS private key; tree IPNS private key; Ed25519 signing key; X25519 key-agreement key; canonical DID document metadata including the immutable `created_at` timestamp |
| Configuration file | YAML | Host-specific settings: listen addresses, bootstrap peers, log level, and the last known ipld-root CID as a startup hint (`cid`) |

The secret bundle MUST be treated as a secret at rest. The configuration file is
not secret and MAY be readable by operators.

### IPLD Tree Structure

The **ipld-root** is a dag-cbor node published under a dedicated tree IPNS key
that is internal to the runtime. The ipld-root is itself the runtime node: all
runtime data sits directly at the root, with no intermediate wrapper key.

The tree IPNS key is an implementation detail. It is stored in the secret bundle
and its public key is recorded in `config`. It MUST NOT be exposed to users or
referenced in external documentation. Runtime data is always accessed via the
identity and the `ma.runtime` link in the DID document (see below).

All nodes MUST be stored in IPFS as dag-cbor.

```txt
ipld-root (dag-cbor)          ← resolved via ma.runtime in the DID document
├── protocol:  "/ma/runtime/0.0.1"
├── identity:  "did:ma:<ipnskey>"
├── config:    <config-CID>
├── kinds:     { <kind-identifier> → <manifest-CID>, … }
└── entities:  { #<fragment> → <entity-CID>, … }

config (dag-cbor)
├── owner:                       "<did-ma-url>"
├── locale:                      "<locale-string>"
├── publish_identity_on_startup: <bool>
├── publish_interval:            <seconds>
├── publish_ttl:                 <seconds>
└── cid:                         "<base32-CIDv1>"

entity (dag-cbor)
├── id:        "<did-ma-url>"
├── owner:     "<did-ma-url>"
├── kind:      "<kind-identifier>"
├── acl:       { … }
├── behavior:  <CID>   ← Wasm module
├── attrs:     { … }   ← runtime projection of state.attrs (eventually consistent in IPLD)
└── state:     <CID>   ← encrypted /ma/state/0.0.1 envelope
```

The `entities` map keys are `#`-prefixed fragment strings (e.g. `"#root"`, `"#fortune"`).
The `kinds` map keys are kind identifier strings (e.g. `"/ma/generic/0.0.1"`);
values are CIDs pointing to the kind's Wasm manifest. A kind MUST be present in
`kinds` before any entity may use it. The `state` CID references an
already-encrypted envelope (see State section) and is therefore safe to include
in the otherwise open IPLD tree.

The `config` node holds operative settings that govern runtime behaviour. The
runtime MUST support at least the following keys:

| Key | Type | Description |
| --- | --- | --- |
| `owner` | `<did-ma-url>` | The owning entity of this runtime |
| `locale` | string | Locale hint, e.g. `"nb_NO"` |
| `tree_key` | multibase public key | Public key of the tree IPNS key used to publish the ipld-root (`ma.runtime` resolves here); the corresponding secret MUST be in the local secret bundle |
| `publish_identity_on_startup` | bool | Whether to publish the DID document immediately on startup |
| `publish_interval` | integer (seconds) | How often the runtime republishes the tree IPNS record; default `900` (15 min) |
| `publish_ttl` | integer (seconds) | IPNS record TTL for the tree key seen by resolvers; MUST be ≥ 2 × `publish_interval`; default `3600` (1 hour) |
| `cid` | CIDv1 string | Current `runtime` node CID; used as a startup hint |

Secrets (e.g. private keys, key material) MUST NOT appear in `config`.

Adding a kind requires writing a new ipld-root that includes the kind's
identifier and manifest CID in `kinds`. Removing a kind requires writing a new
ipld-root that omits it. The runtime MUST reject entity creation requests that
reference a kind not present in `kinds`.

Removing an entity MUST be performed by writing a new ipld-root that omits the
entity's fragment from `entities`. No tombstone record is created. The state CID
previously referenced by that entity is then unreferenced and subject to IPFS
garbage collection.

### `ma.runtime` DID Document Field

The DID document MUST contain an IPLD link under `ma.runtime` pointing to the
ipld-root. This field is defined in the parent specification
(`ma-did-ma-fields.md`) and reproduced here for reference:

```json
{
  "ma": {
    "runtime": { "/": "/ipns/<tree_key>" }
  }
}
```

```txt
/ipns/<identity>/ma/runtime           →  ipld-root
/ipns/<identity>/ma/runtime/config    →  config node
/ipns/<identity>/ma/runtime/kinds     →  kinds map
/ipns/<identity>/ma/runtime/entities  →  entities map
```

All operative detail — kinds, entities, config — is reachable via the identity.
There are no additional fields in the DID document for runtime state.

### Publish Policies

There are two independent publish cycles with different triggers and frequencies.

#### Tree Key Publish Policy

The tree IPNS key is published asynchronously as a best-effort background task
whenever the desired ipld-root CID changes. This happens on state mutations
(entity created, updated, or removed; kinds changed; config changed), but the
runtime MUST continue operating from local state even when publication is
delayed or temporarily fails.

| Trigger | Rule |
| --- | --- |
| Any state change | MUST mark the tree publication dirty and schedule background publication |
| Graceful shutdown | SHOULD attempt a final flush of dirty entities and trigger an immediate background publish attempt without blocking shutdown indefinitely |
| Automatic (periodic) | SHOULD retry at `config.publish_interval`; default 900 s |

`config.publish_ttl` MUST be ≥ 2 × `config.publish_interval`.
With the defaults (900 s interval, 3600 s TTL) remote resolvers can observe
stale data for extended periods; this affects inspectability and recovery
quality, not core runtime correctness.

#### Identity Key / DID Document Publish Policy

The identity IPNS key and DID document are updated only when identity-level
information changes. Because `ma.runtime` is a permanent IPNS link, runtime
state changes do NOT require a DID document republish. The runtime MUST treat
identity publication as an asynchronous background task: when the desired DID
document state changes, the runtime marks the identity document dirty and
retries publication lazily until a publish succeeds.

| Trigger | Rule |
| --- | --- |
| `ma.*` field change (excluding `ma.runtime`) | MUST mark the DID document dirty and schedule background publication |
| Graceful shutdown | SHOULD trigger an immediate background publish attempt without blocking shutdown indefinitely |
| `publish_identity_on_startup: true` | MUST schedule a startup background publish |
| Automatic (periodic) | SHOULD NOT publish more often than once every 24 hours |

The runtime MUST increment `updated_at` on every DID document publish. The
runtime MUST NOT reset `created_at`.

---

## Protocol Identifiers

The following protocol identifiers are defined by this specification. All
identifiers follow the IPFS path convention with a leading slash.

| Identifier | Purpose |
| --- | --- |
| `/ma/runtime/0.0.1` | Runtime protocol identifier, exposed in message context |
| `/ma/inbox/0.0.1` | Inbound message service; defined in the parent specification |
| `/ma/state/0.0.1` | Encrypted state envelope format |
| `/ma/<kind>/<version>` | Kind identifier pattern |

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
  any required field does not match, the runtime MUST derive a corrected DID
  document from the loaded identity bundle, preserve the original `created_at`
  value from the local bundle, refresh only `updated_at` and any fields that no
  longer match the expected document state, and mark that corrected document
  for background publication. The runtime MAY attempt publication immediately,
  but it MUST NOT block startup on IPFS/IPNS publication and MUST NOT abort
  solely because the corrected DID document cannot be published yet. Startup
  MUST continue from the local expected document state while publication
  remains pending.

3. **Load runtime-root from IPFS.** Read `ma.runtime.cid` from the resolved DID
  document when resolution produced a valid document; otherwise read it from
  the locally corrected document state prepared in step 2. If the field is
  absent or the CID is unreachable, fall back to the `last_cid` hint from the
  configuration file. If neither source yields a retrievable CID, treat the
  runtime as newly initialised with an empty entity set. If a CID is available
  but the node cannot be fetched, the runtime MUST fail startup for that
  existing state load. The runtime MUST abort only if a fetched node's
  `identity` field does not match the loaded `<identity>`.

4. **Load kind registry.** Populate the kind registry with all built-in kinds.
  Built-in kinds MAY be bundled with the runtime and therefore need not depend
  on IPFS availability at startup. The runtime MUST abort only if a required
  kind cannot be resolved from either bundled artifacts or the referenced CID,
  or if the resolved manifest fails verification.

5. **Initialise root entity.** Ensure the `#root` entity exists in the loaded
   entity set. If it does not, the runtime MUST create it with
   `kind: /ma/root/0.0.1` and an empty state, write the resulting entity
   node to IPFS, and produce a new runtime-root node that includes the `#root`
   entry. If it exists, load its state CID from the entity node and decrypt the
  `/ma/state/0.0.1` envelope from IPFS. If that CID cannot be read or
  decrypted, the runtime MUST fail startup for that entity load.

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

**Effects** are host functions the plugin calls into the runtime during
execution. Each call executes immediately and MUST return an error if it fails.
The plugin receives the error synchronously and is responsible for handling it.

This host interface is internal to plugin execution and is not directly
available to end users or network clients. User-visible interaction happens via
messages (`<ma-msg>` / `<runtime-msg>`), including `application/x-ma-rpc` where
applicable.

### Universal Entity Contract

Every entity, regardless of kind, MUST have access to the following PDK functions
and host APIs. This includes universal effects and utility functions. This is
the minimum contract that all ma-core-runtime
implementations MUST honour.

### PDK Functions

The runtime MUST invoke the following exported Wasm functions on every entity:

```txt
init(state)
handle_message(runtime_msg)
```

`init` is called once per entity instantiation and passes the current persisted
state to the plugin. `handle_message` is called on every message delivery.
`handle_message` is the **sole delivery entry point**; the runtime MUST NOT
invoke separate handlers per content type.

### Effects API

All entities MUST have access to the following host effects during execution.
Outgoing messages MUST only be sent via these host functions; entities MUST NOT
construct or dispatch `<ma-msg>` directly.

```txt
send(target, content, content_type=<mimetype|"application/x-ma-rpc">, encrypt=<bool|"auto">)
reply(content, content_type=<mimetype|"application/x-ma-rpc-reply">, encrypt=<bool|"auto">)
get_state() -> state
set_state(state)
receive(patterns, timeout) -> runtime_msg | :timeout
```

For inter-entity messaging, `send` SHOULD default to `application/x-ma-rpc`
and `reply` SHOULD default to `application/x-ma-rpc-reply`. Entities MAY use
other content types when required by application behavior.

`encrypt` MUST default to `auto` when omitted. In `auto` mode, the runtime MUST
set encryption to `false` for local delivery and `true` for non-local delivery.
If a target is fully-qualified but resolves to the local identity, the runtime
SHOULD normalise it to a local fragment address before delivery.

`get_state` and `set_state` operate on the entity's entire state blob.
The runtime MUST NOT expose key-level state accessors as part of the universal
contract.

`receive` selectively reads the next message from the entity's inbox that matches
one of the supplied `patterns`. If no matching message arrives before `timeout`
nanoseconds elapses, the host MUST return `:timeout`. Patterns follow the same
Elixir-inspired term form used in `application/x-ma-rpc` payloads (see
[RPC Content Type](#rpc-content-type)). Messages that do not match any pattern
MUST remain in the inbox.

The host MUST maintain each entity's inbox as a TTL queue. A message MUST be
evicted automatically when `now() > created_at + ttl`. Messages with `ttl = 0`
or absent `ttl` are retained until consumed. The entity MUST NOT be responsible
for pruning its own inbox.

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

### Runtime Utility API

All entities MUST also have access to runtime utility functions. These return
values to the entity and do not themselves produce externally visible side
effects.

```txt
now() -> <nano-epoch>
nanoid() -> <nanoid>
random(n) -> <integer>
```

### Kind-Specific Host APIs

In addition to the universal contract above:

- `mailbox` kind entities MAY call mailbox functions: `append`, `peek`, `pop`,
  `list`, `delete`.
- `root` kind entities MAY call root host functions: `create_entity`,
  `destroy_entity`, `patch_entity`, `create_kind`, `destroy_kind`,
  `patch_kind`.

The runtime MUST reject calls to kind-specific functions when invoked by an
entity whose kind does not declare them.

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
attrs: <attrs>
state: <state>
acl: <acl>
```

### Field Definitions

| Field      | Description                                    |
| ---------- | ---------------------------------------------- |
| `id`       | Unique DID-MA URL used for routing             |
| `owner`    | Entity authorised to administer this entity    |
| `kind`     | Symbolic execution profile resolved by runtime |
| `acl`      | Access control policy for inbound messages     |
| `behavior` | Optional executable logic referenced as CID    |
| `attrs`    | Public projection of `state.attrs` in IPLD     |
| `state`    | Optional mutable persistent state              |
| `mailbox`  | Optional long-lived message store              |

### Entity Rules

- Entities MUST reference kinds by name only.
- The runtime MUST resolve kind names to registered implementations.
- The runtime MUST reject unknown kinds.
- Users MAY define and register custom kinds by adding a manifest CID to the
  `kinds` map in the runtime-root.
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

A `kind` is simultaneously an **interface contract** and an **implementation**.
As an interface, it declares which functions an entity exposes — both the
universal host contract and any kind-specific extensions. As an implementation,
it is a concrete Wasm module referenced by a manifest CID.

Kinds define how entities execute. They abstract over execution strategy, host
function requirements, and lifecycle semantics. There is no inheritance between
kinds.

Kinds are fully extensible. Anyone may define a new kind by creating a Wasm
module that satisfies the universal entity contract and publishing its manifest to
IPFS. For example, `/ma/js/0.0.1` could define a JavaScript-oriented actor kind
with its own execution conventions, as long as it implements the universal
host functions. The built-in kinds — `generic`, `mailbox`, and `root` — are
normative defaults, not an exhaustive list.

Because a kind is identified by a CID-backed manifest, swapping an implementation
is a first-class operation: an administrator may replace the `#root` plugin, or
any other kind, by registering a new manifest CID under the same or a new kind
identifier in the runtime-root `kinds` map. No special out-of-band mechanism is
required; the change takes effect when the new runtime-root is published.

A kind MUST be explicitly registered in the `kinds` map of the IPLD runtime-root
before any entity may use it. This ensures that every kind present in a runtime
has a verifiable, content-addressed implementation. The runtime MUST reject
entity creation or update requests that reference an unregistered kind.

### Kind Protocol

Kind identifiers SHOULD follow the pattern `/ma/<kind-name>/<version>`. This is
a convention, not a requirement. Names SHOULD be short; longer names are
acceptable only when necessary for clarity or namespacing.

The kind identifier does not encode the evaluator. In v1, all kinds MUST be
implemented as Wasm modules executed through Extism.

### Minimal Kind Structure

All kinds MUST implement at least the following. This reflects the universal
entity contract defined in the Host Interface section.

```yaml
kind: <protocol>
manifest: <cid>
implements:
  - init
  - handle_message
  - get_state
  - set_state
  - send
  - reply
  - receive
```

### `<manifest>`

The manifest is a Wasm manifest serialised as dag-cbor and stored as IPLD.
Because the plugin MUST be fetched by content-addressed CID, a separate checksum
field is not required.

### Kind Resolution

When the runtime loads a kind it MUST:

1. Look up the kind identifier in the registry.
2. Resolve the manifest from a bundled artifact or fetch it by CID from IPFS
  using `dag get`.
3. Deserialise the dag-cbor manifest.
4. Verify that the manifest's declared `implements` list includes all
   capabilities required by the entity.
5. Load the Wasm module referenced by the manifest.

The runtime MUST fail that kind load if the manifest cannot be resolved, the
manifest fails deserialisation, or the Wasm module cannot be loaded. A failure
to load a new or uncached kind MUST NOT by itself interrupt unrelated entities
that are already running with previously loaded behavior, but the operation
that required that kind load MUST fail.

### Required Kinds

#### `generic`

The base kind for general-purpose entities. Implements the full universal entity
contract: message delivery, state persistence, outgoing messages, and inbox
access.

```yaml
kind: /ma/generic/0.0.1
manifest: <cid>
implements:
  - init
  - handle_message
  - get_state
  - set_state
  - send
  - reply
  - receive
```

Method signatures:

```txt
init(state)
handle_message(runtime_msg)
get_state() -> state
set_state(state)
send(target, content, content_type, encrypt)
reply(content, content_type, encrypt)
receive(patterns, timeout) -> runtime_msg | :timeout
```

#### `mailbox`

Provides persistent, ordered message storage. Messages with `content_type:
application/x-ma-message` are stored with `created_at` and an optional `ttl`.
Messages with `ttl = 0` or absent `ttl` are retained indefinitely.

```yaml
kind: /ma/mailbox/0.0.1
manifest: <cid>
implements:
  - init
  - handle_message
  - get_state
  - set_state
  - send
  - reply
  - receive
  - append
  - peek
  - pop
  - list
  - delete
```

Method signatures:

```txt
init(state)
handle_message(runtime_msg)
get_state() -> state
set_state(state)
send(target, content, content_type, encrypt)
reply(content, content_type, encrypt)
receive(patterns, timeout) -> runtime_msg | :timeout
append(runtime_msg)
peek() -> runtime_msg | null
pop() -> runtime_msg | null
list(limit, cursor) -> [runtime_msg]
delete(msg_id)
```

Rules:

- `list` MUST support cursor-based pagination.

#### `root`

The `root` kind is the administrative entry point for the runtime. It is
instantiated at the well-known fragment `#root` and handles entity lifecycle
operations.

```yaml
kind: /ma/root/0.0.1
manifest: <cid>
implements:
  - init
  - handle_message
  - get_state
  - set_state
  - send
  - reply
  - receive
  - create_entity
  - destroy_entity
  - patch_entity
  - create_kind
  - destroy_kind
  - patch_kind
```

Method signatures:

```txt
init(state)
handle_message(runtime_msg)
get_state() -> state
set_state(state)
send(target, content, content_type, encrypt)
reply(content, content_type, encrypt)
receive(patterns, timeout) -> runtime_msg | :timeout
create_entity(fragment, fields)
destroy_entity(fragment)
patch_entity(fragment, fields)
create_kind(kind_id, manifest_cid)
destroy_kind(kind_id)
patch_kind(kind_id, manifest_cid)
```

Rules:

- `create` MUST use the caller-supplied fragment. The fragment MUST be `#`-prefixed
  (e.g. `"#fortune"`). The caller is responsible for generating a unique fragment;
  use `nanoid()` and prepend `#`. The runtime MUST reject a `create` request if
  an entity with that fragment already exists.
- `destroy` MUST delete the entity and its associated state.
- `patch` MUST update only the supplied fields on an existing entity. The
  runtime MUST reject the call if that entity does not exist.
- `create_kind` MUST register the supplied kind identifier and manifest CID in
  the runtime-root `kinds` map. The runtime MUST reject the call if that kind
  identifier already exists.
- `destroy_kind` MUST remove the supplied kind identifier from the runtime-root
  `kinds` map. The runtime MUST reject the call if any existing entity still
  references that kind.
- `patch_kind` MUST replace the manifest CID for an existing kind identifier.
  The runtime MUST reject the call if that kind identifier does not exist.
- Only the entity designated as `owner` of the runtime identity, or the root
  entity itself, MAY invoke root operations.

For `create_entity(fragment, fields)` and `patch_entity(fragment, fields)`,
`fields` MUST be an object containing only the following entity attributes:

| Attribute | Required on `create` | Allowed on `patch` | Description |
| --- | --- | --- | --- |
| `kind` | yes | yes | Kind identifier |
| `owner` | yes | yes | Entity owner `<did-ma-url>` |
| `acl` | yes | yes | Access control policy |
| `behavior` | no | yes | Behavior CID |
| `state` | no | yes | Initial or replacement JSON state |

`id` is derived from `<identity><fragment>` by the runtime (since `<fragment>` already
carries the `#` separator) and MUST NOT be supplied in `fields`. `attrs` is derived
from `state.attrs` and MUST NOT be supplied in `fields`.

For `create_kind(kind_id, manifest_cid)` and `patch_kind(kind_id, manifest_cid)`:

| Parameter | Description |
| --- | --- |
| `kind_id` | Kind identifier string, typically `/ma/<kind-name>/<version>` |
| `manifest_cid` | CID of the dag-cbor Wasm manifest for that kind |

`kind_id` MUST be treated as an opaque string by the runtime except for any
optional validation of the recommended identifier pattern. `manifest_cid` MUST
resolve to a valid kind manifest before the runtime publishes the updated
runtime-root.

---

## State

This specification defines the state protocol as `/ma/state/0.0.1`.

`state` is **persistent, mutable storage** isolated per entity. It is stored and
protected by the runtime.

When an entity is created it MUST be initialised with a valid JSON `<state>`.
If no state is provided the runtime MUST substitute an empty JSON object (`{}`).

The runtime identifies the state of an entity by its CID. This CID is stored as the `state` link in the entity node in the IPLD tree.

### Entity Attributes Projection (`entity.attrs`)

`entity.attrs` is a runtime-maintained public projection of `state.attrs` for
IPLD traversal.

- `entity.attrs` MUST be derived from `state.attrs`.
- `entity.attrs` MUST be managed by the runtime and MUST NOT be written directly
  by entities.
- `set_state()` MUST NOT block waiting for IPLD publication of `entity.attrs`.
- The runtime MUST make updated `entity.attrs` available immediately for local
  runtime access after `set_state()` succeeds.
- After `set_state()` succeeds locally, the runtime MUST mark that entity state
  dirty in runtime-local bookkeeping until persistence of the accepted state
  completes.
- Repeated successful `set_state()` calls MAY be coalesced so that only the
  latest accepted state is written to IPFS/IPLD.
- Publication of `entity.attrs` into IPLD MAY be lazy and eventually
  consistent.
- If `state.attrs` is absent, the runtime MUST treat it as `{}` when deriving
  `entity.attrs`.
- Dirty-tracking bookkeeping for entity state MUST remain runtime-local and
  MUST NOT be persisted to IPFS/IPLD.
- Dirty-tracking bookkeeping MUST NOT be exposed through entity data, IPLD
  data, or DID data.

`state` remains encrypted at rest; `entity.attrs` is the explicit public
projection.

### State Rules

- MUST be isolated per entity.
- MUST persist across executions.
- MUST only be modified via runtime APIs.
- MUST be stored in IPFS as an IPLD dag-cbor node.
- State persistence writes MUST remain best-effort background work after local
  acceptance of `set_state()`.
- Operations that require reading CID-backed state from IPFS MUST fail when
  that read cannot be completed, even if the missing state reflects a pending
  background persistence attempt.

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

### Entity Identity

The entity's own `<did-ma-url>` (`self`) MUST be injected by the runtime at
instantiation time, before any message is delivered. How this is done is
implementation-defined; in Extism, the plugin config is a natural vehicle.

### Runtime Utility Functions

Runtime utility functions are defined in the Host Interface section
(`Runtime Utility API`) and are available to all entities.

### Capability Model

Capabilities are declared per kind and enforced by the runtime.

The runtime MUST:

- Enforce capability declarations at call time.
- Reject calls to capabilities not declared for the entity's kind.

### Execution

The runtime MUST execute the following sequence on each message delivery:

```txt
resolve kind
→ load evaluator implementation
→ load behavior
→ load state
→ call init(state)
→ deliver <runtime-msg> via handle_message(runtime_msg)
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

### RPC Content Type

`application/x-ma-rpc` is the primary runtime-layer content type for inter-entity
calls. It is the normative mechanism through which entities invoke operations on
one another. `application/x-ma-rpc-reply` is the corresponding reply type. Both
are runtime-layer extensions to the `did:ma` content type set.

| Property   | `application/x-ma-rpc`         | `application/x-ma-rpc-reply`   |
| ---------- | ------------------------------ | ------------------------------ |
| Encryption | REQUIRED for external messages | REQUIRED for external messages |
| Target     | Any `<did-ma-url>`             | Sender of the originating RPC  |

Any entity MAY receive `application/x-ma-rpc` messages. The runtime MUST deliver
them via `handle_message` like all other messages. The receiving entity is
responsible for dispatching on the RPC payload using `receive` pattern matching.

When entities use host functions without explicit `content_type`, `send` MUST
default to `application/x-ma-rpc` and `reply` MUST default to
`application/x-ma-rpc-reply`.

When entities use host functions without explicit `encrypt`, the runtime MUST
apply locality-aware defaults: local delivery (`#fragment` or same identity)
MUST default to unencrypted transport, while non-local delivery MUST default to
encrypted transport.

`application/x-ma-rpc` is the user-facing and inter-entity message layer.
Host functions (`send`, `set_state`, `create_entity`, etc.) are internal runtime
entry points callable only from entity/plugin code after message delivery.

Consistent with the actor model, a reply MUST NOT be assumed. The caller MAY
set `reply_to` on the RPC message to indicate it expects a result, but the
recipient is not obliged to reply.

#### Mandatory Health RPC (`:ping` -> `:pong`)

All entities MUST implement a minimal RPC health check:

- On receiving RPC content `:ping`, the entity MUST send a reply to the sender
  with RPC content `:pong`.
- The reply MUST use `application/x-ma-rpc-reply` unless explicitly overridden
  by runtime policy.
- The reply MUST target the original sender and set `replyTo` to the incoming
  message `id`.

This requirement provides a fast liveness probe to confirm that a runtime is
up and that the addressed entity is responsive, even when other message flows
are delayed or lost.

Example liveness flow:

```yaml
# Request
id: "m1"
from: "did:ma:alice#probe"
to: "did:ma:bob#worker"
content_type: application/x-ma-rpc
content: :ping

# Reply
id: "m2"
from: "did:ma:bob#worker"
to: "did:ma:alice#probe"
reply_to: "m1"
content_type: application/x-ma-rpc-reply
content: :pong
```

#### RPC Term Syntax

The term syntax for RPC is borrowed directly from Elixir/Erlang. This is a
conscious choice: the syntax is compact, unambiguous, and already familiar to a
large community of practitioners. Reusing it avoids the need to invent a new
format for a problem that Erlang solved well.

The `content` of an RPC message MUST be an Elixir-inspired term in one of two
forms:

- A bare atom: `:name`
- A tagged tuple: `{:name, ...fields}`

For root lifecycle RPC calls that mutate entities (`:create`, `:patch`), the
`fields` term in the tuple MUST be a list of tagged tuples, not a map. Example:

`{:create, "#fortune", [{:kind, "/ma/generic/0.0.1"}, {:owner, "did:ma:<identity>#root"}, {:acl, []}, {:behavior, "<cid>"}]}`

The `#root` plugin is responsible for decoding this tuple-list format and
calling the root host functions (`create_entity`, `patch_entity`) with a
runtime-native `fields` object. Kind lifecycle RPC calls MAY use direct tuple
arguments because the underlying `kinds` map stores only `kind_id ->
manifest_cid` pairs.

Tuple arity is not constrained by this specification; the receiving entity
defines which signatures it accepts. This format is chosen deliberately so that
entities can use `receive` pattern matching directly on RPC content without
additional parsing.

Non-RPC content types (e.g. `application/x-ma-message`) carry application-defined
payloads. The runtime MUST NOT impose structure on their `content` field.

#### CBOR Serialisation of RPC Terms

When serialised to CBOR for transport:

- Atoms are encoded as UTF-8 strings.
- Tuples are encoded as CBOR arrays where the first element is the atom string.

Examples of valid RPC payloads:

```elixir
:ping
:pong
{:create, "#fortune", [{:kind, "/ma/generic/0.0.1"}, {:owner, "did:ma:<identity>#root"}, {:acl, []}, {:behavior, "<cid>"}]}
{:destroy, "#fortune"}
{:patch, "#fortune", [{:behavior, "<cid>"}]}
{:create_kind, "/ma/js/0.0.1", "<cid>"}
{:destroy_kind, "/ma/js/0.0.1"}
{:patch_kind, "/ma/js/0.0.1", "<cid>"}
{:emote, "wiggles its tail"}
```

For lifecycle operations on `#root`, the fragment in a `:create` tuple MUST be
caller-supplied. The runtime MUST NOT generate the fragment on behalf of the
caller.

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
content: {:create, "#fortune", [{:kind, "/ma/generic/0.0.1"}, {:owner, "did:ma:<identity>#root"}, {:acl, []}, {:behavior, "<cid>"}]}
```

### Update Entity

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-rpc
content: {:patch, "#fortune", [{:behavior, "<cid>"}]}
```

### Delete Entity

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-rpc
content: {:destroy, "#fortune"}
```

### Create Kind

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-rpc
content: {:create_kind, "/ma/js/0.0.1", "<cid>"}
```

### Update Kind

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-rpc
content: {:patch_kind, "/ma/js/0.0.1", "<cid>"}
```

### Delete Kind

```yaml
to: did:ma:<identity>#root
content_type: application/x-ma-rpc
content: {:destroy_kind, "/ma/js/0.0.1"}
```

### Authorisation

The runtime MUST:

- Verify the sender's identity against the message signature.
- Verify that the sender is authorised for the requested root operation,
  including entity lifecycle changes and kind registry changes.
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
| `kind_exists`       | `create_kind` called with an existing kind identifier     |
| `kind_in_use`       | `destroy_kind` called for a kind still in use             |
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
kind: /ma/generic/0.0.1
behavior: /ipfs/bafy...fortune-script
state: /ipfs/bafy...state
```

On receiving a message, the fortune entity picks a fortune and replies using the
`reply()` host effect. The sender MUST NOT assume a reply will be produced.

---

## References

- [MA Runtime Function Reference](ma-runtime-functions.md)
- [間-spec — DID Method Specification](https://github.com/bahner/ma-spec/blob/main/did-method-spec.md)
- [間-spec — DID Document Format](https://github.com/bahner/ma-spec/blob/main/did-document-format.md)
- [間-spec — Messaging Format](https://github.com/bahner/ma-spec/blob/main/messaging-format.md)
- [Extism](https://extism.org) — WebAssembly plugin system
- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) — Key words for use in RFCs
- [IPFS Documentation](https://docs.ipfs.tech/)
- [IPLD Specification](https://ipld.io/specs/)
- [IPNS Specification](https://specs.ipfs.tech/ipns/ipns-record/)
- [CBOR (RFC 8949)](https://www.rfc-editor.org/rfc/rfc8949)
- [Ed25519 (RFC 8032)](https://www.rfc-editor.org/rfc/rfc8032)
- [X25519 (RFC 7748)](https://www.rfc-editor.org/rfc/rfc7748)
- [BLAKE3](https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf)
- [XChaCha20-Poly1305](https://www.rfc-editor.org/rfc/rfc8439)
- [nanoid](https://github.com/ai/nanoid)
