# ma-lambda-ma-v1 - Lambda-ma World Profile

**Status:** Draft
**Version:** 0.5.0
**Date:** 9 August 2026

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

Root accepts an argument-free `:register` from a local actor. The subscriber is
the full actor DID-URL in `msg.from`. Root records the subscriber, replies
`:ok`, and sends it the current runtime ctx as `:ctx <ctx>`. Root does not
enter rooms, move an identity, or forward identity commands.

## 3. Entry

A client enters a known room by sending `:enter` directly to its full room
DID-URL. `msg.from` MUST be a bare `did:ma:` DID. An optional claim may propose
`name` and `nick` (a bare string argument proposes `nick`); the room issues
`description`. A claim conveys no authority.

The room commits a DID presence record keyed by that bare DID. The record is
room state, contains the full parent room DID-URL and presentation fields, and
has a monotone `rev`. The room replies with the committed DID ctx:

```text
[:ok, { did, parent, name, nick, description, rev }]
```

After committing, the room sends `:did-ctx <did> <ctx>` to the exact full
DID-URL in `ctx.house`. The ctx `parent` MUST equal the sending room's full
DID-URL.

A client accepts an entry reply only when `reply_to` matches its newest active
entry request and `msg.from` is the requested room. A timeout does not discard
an already accepted DID ctx. Repeating a committed entry is idempotent.

A present DID departs with an argument-free `:leave` sent by itself. A room
accepts a targeted `:leave <did>` only when `msg.from` equals its exact
`ctx.house` DID-URL.

## 4. Focus and Traversal

A focused client routes both ordinary shorthand and colon-prefixed methods to
the confirmed focused actor DID-URL. A leading colon selects a direct method; it
MUST NOT select a proxy actor. A client MUST NOT adopt an unsolicited ctx
message as a focus update.

A DID requests exit traversal with transient `{ did, parent }`, where `parent`
MUST equal the exit's current source room. An exit authorises `:traverse` only
for the traveller itself (`msg.from` equal to `ctx.did`) or its source room. It
replies with `{ did, parent, text, exit, direction }`; a locked exit returns
the source room as `parent` with blocking text. Traversal moves nothing by
itself: the DID enters the returned parent room directly with `:enter`.

## 5. House Registries and Handoffs

House is runtime-agnostic policy and transition coordination. It maintains:

- `did-ctxs`, keyed by bare DID;
- `entity-ctxs`, keyed by full actor DID-URL.

On `:did-ctx <did> <ctx>`, house verifies that `msg.from` equals `ctx.parent`.
House stores the new ctx and, when the previously stored ctx named a different
parent, sends `:leave <did>` to that old full parent DID-URL.
`:did-ctx? <did>` returns the stored DID ctx; the lookup is open until world
ACL policy restricts it.

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
commits the new parent and informs its former parent. House may coordinate
old-parent cleanup for forward movement, but it does not change the node tree
protocol.

Valid retries are idempotent and MUST repair lost messages rather than loop:

- A parent that receives a valid repeated `:parent <ctx>` MUST confirm with
  `:child <ctx>` again so a lost confirmation can be repaired.
- A child that receives `:child <ctx>` differing from its committed
  parent-facing ctx MUST commit the confirmation. After committing a changed
  parent it informs its former parent with `:parent <ctx>` naming the new
  parent, and the former parent forgets the child.
- A confirmation exactly matching the committed ctx is a terminal
  acknowledgement: the child replies success without sending another
  `:parent`, preventing a response-to-response loop.
- When a ctx kind defines a monotone `rev`, a confirmation with a lower
  revision than the committed ctx is a successful stale acknowledgement. The
  child MUST NOT roll state back, increment its revision, or send another
  `:parent` in response.

A child announces its own termination with a ctx whose `parent` is empty; the
parent forgets it. `:parent?` returns an actor's current parent. `:children?`
returns the `children` map and is owner-gated.

Root adopts orphaned thing, agent, and container actors. An owner requests
repair with `:orphan <actor> from <parent>` on root, and `:orphans?` lists the
ctxs of root's live orphaned children.

## 7. Entity Creation (`:forge`)

Every `/ma/node/0.0.1` actor accepts `:forge <ctx>` as a direct request to
create a new child entity of itself. There is no avatar-mediated or root-
mediated creation path; `:forge` is sent straight to whichever actor is meant
to become the new entity's parent.

Forge ctx MUST contain:

| Key | Type | Meaning |
| --- | --- | --- |
| `kind` | text | Protocol id of the kind to create, e.g. `/ma/thing/0.0.1`. |
| `name` | text | Name of the new entity. |

Forge ctx MAY contain:

| Key | Type | Meaning |
| --- | --- | --- |
| `behaviour` | text | Optional behaviour CID override for the new entity. |

Forge ctx MUST NOT contain an `owner` field. The new entity's owner is always
the bare DID or actor DID-URL in `msg.from` of the `:forge` request; a
client-supplied owner value would let a caller foist ownership onto a DID that
never agreed to it, so it is never accepted from ctx.

Forge ctx MUST NOT contain caller-supplied initialisation code or text. The
receiving actor is solely responsible for the new entity's initial state.
Accepting caller-supplied init would let a request race or override the
authoritative `name`/`owner`/`parent` assignment; this version deliberately
excludes that surface and MAY define a separate, explicitly gated mechanism for
it in a later revision.

The receiving actor MAY refuse a `:forge` request for any local policy reason
(for example, a room enforcing an occupancy limit) by replying
`[:error, reason]`. On refusal, no entity is created.

On acceptance, the receiving actor:

1. Creates the new entity with `owner` set to `msg.from` and `parent` set to
   its own full DID-URL.
2. Replies `[:ok, <new actor DID-URL>]`.

The new entity's own genesis then proposes itself to that parent through the
ordinary `:parent`/`:child` exchange defined in section 6 — `:forge` does not
duplicate or shortcut that handshake.

## 8. Authority and Revisions

`msg.from` is the sole authenticated message fact. A room authorises DID
presence only when `msg.from` equals the bare DID key. Actor parent/child flows
authorise the exact full actor DID-URL specified by their ctx.

Each authoritative DID ctx and entity ctx has a monotone revision. A lower
revision from an otherwise authorised sender is stale and MUST NOT roll state
back. Revisions order authoritative snapshots and retries only; they never
substitute for sender authentication.

## 9. Replies and World Events

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
