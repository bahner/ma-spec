# ma-lambda-ma-v1 - Lambda-ma World Profile

**Status:** Draft
**Version:** 0.4.0
**Date:** 7 August 2026

## Abstract

Lambda-ma is an optional world profile for bare `did:ma:` identities, rooms,
exits, containers, and movable actors. It defines no identity actors. The bare
DID in `msg.from` is the only authenticated identity fact.

The profile defines three distinct ctx records:

- **runtime ctx**: root-published service configuration;
- **DID ctx**: room-authoritative bare-DID presence and placement;
- **entity ctx**: generic actor state keyed by a full actor DID-URL.

Ctx and revisions do not authenticate a message. Every authority decision MUST
be based on `msg.from`.

## 1. Scope

This profile standardises direct DID room entry, focused routing, runtime ctx,
DID presence, actor ctx publication, and parent/child actor exchange. It is a
world-layer profile over the ma RPC service and is not required for base runtime
conformance.

Actor references crossing a client, runtime, or actor boundary MUST be complete
DIDs or DID-URLs. Runtime-local fragments such as `#root`, `#house`, and
`#scheduler` are documentation metanames only; they are never wire values or
persisted ctx values.

## 2. Runtime Ctx

Each runtime has one local root DID-URL, conventionally
`did:ma:<runtime>#root`. Root is the local trust anchor.

`:ctx?` replies with a root-issued map containing at least:

```text
{
  runtime: "did:ma:<runtime>",
  root: "did:ma:<runtime>#root",
  house: "did:ma:<runtime>#house",
  scheduler: "did:ma:<runtime>#scheduler",
  rev: 1
}
```

Every service reference MUST be a full DID-URL. Receivers validate a service
message by comparing `msg.from` to the exact configured reference. `rev` is
root-issued and monotone; it orders snapshots but provides no authority.

Root accepts `:register <actor-did-url>` from a local actor and distributes the
current runtime ctx to registered actors. Root does not enter rooms, move an
identity, or forward identity commands.

## 3. Entry

A client enters a known room by sending `:enter` directly to its full room
DID-URL. `msg.from` MUST be a bare `did:ma:` DID. An optional claim may propose
`name`, `nick`, and `description`; it conveys no authority.

The room commits a DID presence record keyed by that bare DID. The record is
room state, contains the full parent room DID-URL and presentation fields, and
has a monotone `rev`. The room replies:

```text
[:ok, { parent, name, nick, description, rev }]
```

After committing, the room sends `:did-ctx <did> <ctx>` to the exact full
DID-URL in `ctx.house`. The ctx `parent` MUST equal the sending room's full
DID-URL.

A client accepts an entry reply only when `reply_to` matches its newest active
entry request and `msg.from` is the requested room. A timeout does not discard
an already accepted DID ctx. Repeating a committed entry is idempotent.

## 4. Focus and Traversal

A focused client routes both ordinary shorthand and colon-prefixed methods to
the confirmed focused actor DID-URL. A leading colon selects a direct method; it
MUST NOT select a proxy actor. A client MUST NOT adopt an unsolicited ctx
message as a focus update.

A DID requests exit traversal with transient `{ did, parent }`. An exit replies
with `{ did, parent, text, exit, direction }`. The DID enters the returned
parent room directly with `:enter`.

## 5. House Registries and Handoffs

House is runtime-agnostic policy and transition coordination. It maintains:

- `did-ctxs`, keyed by bare DID;
- `entity-ctxs`, keyed by full actor DID-URL.

On `:did-ctx <did> <ctx>`, house verifies that `msg.from` equals `ctx.parent`.
If the existing DID ctx has a different parent, house sends `:leave <did>` to
that old full parent DID-URL before storing the new ctx. `:did-ctx? <did>`
returns the stored DID ctx; the lookup is open until world ACL policy restricts
it.

An actor publishes `:entity-ctx <ctx>` to house. House derives the registry key
from full `msg.from`, never from a caller-supplied key.
`:entity-ctx? <actor-did-url>` returns the stored entity ctx.

House MUST NOT impersonate an identity or forward identity commands. A room
accepts a targeted `:leave <did>` only when `msg.from` equals its exact
`ctx.house` DID-URL.

## 6. Actor Parentage

`/ma/node/0.0.1` remains the only actor tree. Every actor may have children,
and the single `children` map is keyed by full actor DID-URLs. DID presence is
room state, never a node child and never a parallel actor tree.

Actor transfer remains parent-authoritative. The child requests `:parent <ctx>`
from the candidate parent; the parent confirms with `:child <ctx>`; the child
commits the new parent and informs its former parent. Valid retries are
idempotent. House may coordinate old-parent cleanup for forward movement, but
it does not change the node tree protocol.

## 7. Authority and Revisions

`msg.from` is the sole authenticated message fact. A room authorises DID
presence only when `msg.from` equals the bare DID key. Actor parent/child flows
authorise the exact full actor DID-URL specified by their ctx.

Each authoritative DID ctx and entity ctx has a monotone revision. A lower
revision from an otherwise authorised sender is stale and MUST NOT roll state
back. Revisions order authoritative snapshots and retries only; they never
substitute for sender authentication.

## 8. Replies and World Events

Lambda-ma has two separate message layers.

The technical layer uses RPC replies. Queries, structured state, configuration,
validation, and errors MUST use `:ok`, `[:ok, value]`, or `[:error, reason]`.
Examples include `:enter`, `:look`, `:who?`, `:exits?`, `:contents?`, `:did?`,
and `:owner?`.

The world-event layer uses unsolicited `[:print, text]` messages. Arrival,
departure, speech, emotes, movement, transfer, and world-building outcomes are
events. A room emits their narrative text after its authoritative local state
change. Clients display these events and MUST NOT derive or invent an alternate
narrative from an RPC acknowledgement.

An action MAY return a bare `:ok` as a technical completion acknowledgement.
That acknowledgement is not a user-visible description. Its narrative outcome,
when any, is sent only as `:print`.
