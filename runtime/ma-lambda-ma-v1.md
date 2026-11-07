# ma-lambda-ma-v1 - Lambda-ma World Profile

**Status:** Recommendation
**Version:** 0.9.0
**Date:** 7 November 2026

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
world-layer profile over the ma inbox service and is not required for base runtime
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

A client enters a known room by sending `:enter` to its full room DID-URL. Every
`:enter` carries a movement ctx (section 3.1); there is no bare or
argument-free form. `msg.from` is the sole authenticated fact (section 8).

### 3.1 The movement ctx

```text
{
  did:        "did:ma:alice",   # the traveller; advisory, msg.from is authoritative
  traverseId: "<opaque>",       # required; minted by the traveller
  name:       "Alice Example",  # user ctx; optional
  nick:       "Alice",          # user ctx; optional
  key:        "<opaque>",       # optional admission credential
  source:     "did:ma:…",       # set by a room; the room the traveller is in
  entrance:   "did:ma:…"        # set by an exit; the proposed destination
}
```

`traverseId` is ephemeral and identifies one intended movement. A traveller MUST
mint a fresh value for each new intent and MUST NOT reuse a value for a
different intent. Retrying the same intent reuses the same value; that reuse is
what makes the exchange idempotent.

`key` is an admission credential. It is opaque to every forwarder: forwarders
MUST carry it unchanged and MUST NOT inspect or transform it. Only the
destination room reads it.

`did`, `traverseId`, and `key` (when present) MUST survive every hop unchanged.
Any other field is advisory, and any forwarder MAY drop or replace it. No field
authenticates anything (section 8).

### 3.2 Sender classification

A room classifies an `:enter` by comparing `msg.from` with `ctx.did`:

| `msg.from` | Meaning | Permitted replies | Presence |
| --- | --- | --- | --- |
| equal to `ctx.did` | the traveller enters itself | `[:ok, <room-ctx>]`, `[:entrance, <target>]`, `[:deny, reason]` | MAY commit |
| not equal to `ctx.did` | delegated, from an exit | `[:ok, { key }]`, `[:entrance, <target>]`, `[:deny, reason]` | MUST NOT commit |

A delegated `:enter` authorises only. It MUST NOT commit presence, and a room
MUST NOT treat a delegated request as the traveller's arrival.

`[:entrance, <target>]` is a redirect (section 4.5). A caller that receives one
retries the same `traverseId` against `target`.

### 3.3 Direct entry and admission

A room admits a traveller when any of the following holds:

- the room is public (`public: true`, the default);
- `key` names one of the room's admission keys;
- `key` matches `pending[<did>].key` for the same `traverseId`;
- `key` equals the runtime's `global_key`.

A DID that already holds committed presence in the room is also admitted,
without a key: this is the idempotent repeat entry, not a new admission, and a
first-entry key such as a traversal grant may already have been consumed. This
is not an owner bypass, because it applies only to a DID the room already lists
as a child.

A room that admits nobody through the first clause is private
(`public: false`). There is no owner bypass: the owner presents a key like
anyone else, so gating is testable.

On commit the room:

1. writes or refreshes the DID presence record keyed by `ctx.did`, containing
   the room's full parent DID-URL, the presentation fields it accepts from the
   ctx, and a monotone `rev`;
2. consumes `pending[ctx.did]`, if any;
3. replies `[:ok, <room-ctx>]`;
4. broadcasts the arrival event (section 4.7).

Repeating a committed entry is idempotent and MUST reply `[:ok, <room-ctx>]`
without a second presence change.

A client accepts an entry reply only when `reply_to` matches its newest active
entry request and `msg.from` is the requested room. A timeout does not discard
an already accepted ctx.

### 3.4 Runtime root as redirector

Root is not a place a traveller can be. It has no `children`, never commits
presence, and answers every `:enter` with `[:entrance, <start-room>]`:

```text
[:entrance, "did:ma:<runtime>#concourse"]
```

A runtime with no configured start room answers `[:deny, reason]` instead. Root
MUST NOT answer `:enter` with `[:ok, …]`.

A client with no known room address therefore enters a runtime by sending
`:enter` to `did:ma:<runtime>#root` and then entering the room named by the
reply, reusing the same `traverseId`. This is the only unqualified-entry
mechanism; there is no separate discovery verb.

### 3.5 Departure and the house handoff

A present DID departs with an argument-free `:leave` sent by itself. A room
accepts a targeted `:leave <did>` only when `msg.from` equals its exact
`ctx.house` DID-URL.

After committing presence the room sends `:did-ctx <did> <ctx>` to the exact
full DID-URL in `ctx.house`. The ctx `parent` MUST equal the sending room's
full DID-URL.

A client SHOULD say goodbye when it moves. A client that has committed presence
in a room SHOULD send that room an argument-free `:leave` when it commits
presence in a different room, rather than relying solely on the house handoff.
The handoff is the coordinated path and remains the room's authoritative
cleanup, but it is not a precondition for the client's own departure: a house
that is unreachable, not yet deployed, or simply slow must not leave a stale
child behind. A client always departs as itself with the argument-free form;
only the house may send the targeted `:leave <did>` form. `:leave` is
idempotent, so both paths running is harmless. A client SHOULD also treat a
room broadcast whose child ctx names a room other than its current room as
another place's story: it must not render or cache that event, and it SHOULD
send that room an argument-free `:leave` so the stale record is repaired.

The `global_key` is the runtime's daemon-local config value, set in the
runtime's `ma.yaml`. It is never exposed or writable over the CRUD service; the
runtime injects it into every actor's config map, where an actor reads it with
`(ma-get-config-key "global_key")`. An absent or empty value disables it. It is
an administrator break-glass gate, not a player-facing secret.

## 4. Passages and Traversal

### 4.1 The passage node

A passage is one top-level `/ma/passage/0.0.1` node with two hardcoded ends,
`entrance` and `exit`, each a full room DID-URL. `entrance` is the room the
traveller comes from; `exit` is the room the traveller goes to. A passage is a
child of neither room and has no parent.

A room references a passage through its own `exits` map (local name → passage
DID-URL), published in the room ctx as `exits`. The local name is purely
cosmetic, and the two endpoint rooms MAY name the same passage differently. One
passage is one object, so it has one lock. A passage is two-way exactly when
both endpoint rooms have registered it.

A move ctx names both ends, so every receiver decides its role by comparison:

| Receiver is | Role |
| --- | --- |
| `entrance` | the room being left: it verifies presence and hands the ctx on |
| `exit` | the room being entered: it authorises and answers |
| the passage | it routes, follows redirects, and relays the answer to `entrance` |

An exit MAY carry per-end presentation flags such as `visible` and `traverse`.
They are local policy and never substitute for the destination's admission
decision (section 3.3).

### 4.2 Movement is `:move`

There is one movement verb for rooms and passages, `:move <move-ctx>`. It is
not the agent's `:move <direction>`, which moves the agent itself. After the
first hop every answer is a new `:move` message carrying `traverseId`, never an
actor reply: a runtime drops a locally-addressed envelope whose `reply_to` is
set, so a reply between two local actors would vanish.

An agent actor can be its own traveller. `:wander [direction]` mints the
`traverseId` and sends the walk ctx to its current room; omitting `direction`
lets the room choose an available exit. On the routed answer the agent
completes the movement with `:enter` at the established exit, presenting the
issued `key`. It keeps one walk in flight, in memory, and ignores a result
whose `traverseId` is not live. Its `:exits?` returns the exits from the room
ctx cached in its last `:child` ack. A free agent MAY be asked to wander by
anyone; an owned agent accepts `:wander` only from its owner or from the
runtime `#scheduler`, which dispatches back to the fragment that registered the
schedule.

```text
traveller → source room    [:move, { traverseId, direction, key? }]
source room → passage      [:move, { did, traverseId, name, nick, key?, entrance }]
passage → destination      [:move, { …m, exit }]
destination → passage      [:move, { traverseId, exit, key }]        # accepted
                           [:move, { traverseId, exit: <other room> }]  # redirect
                           [:move, { traverseId, deny }]             # refused
passage → source room      [:move, { traverseId, exit, key }]        # accepted
                           [:move, { traverseId, deny }]             # refused
source room → traveller    [:move, { traverseId, exit, key }]        # accepted
                           [:move, { traverseId, deny }]             # refused
traveller → exit room      [:enter, { did, traverseId, name, nick, key }]
exit room → traveller      [:ok, <room-ctx>]
```

The source room supplies `name`/`nick` from its own authoritative `children`
record. On the final `:enter` the traveller supplies them, because the
destination has no prior record, and the destination address is the message
target — `entrance` and `exit` are routing fields and do not appear there.

A trail is at most three `:move` redirects. A redirect MUST name a room on the
same runtime as the destination that proposed it; a passage MUST treat anything
else as a refusal. Because redirects cannot cross a runtime boundary, a `key`
proposed to one runtime is never presented to another.

### 4.3 Admission

A destination that receives a delegated `:move` (`msg.from` is the passage)
records one grant and answers without committing presence:

```text
pending[<did>]:
  traverseId: "<opaque>"
  key:        "<opaque>"
  arrive:     "<text>"
  oarrive:    "<text>"
```

The traveller then presents that `key` in its own `:enter`. A room admits when
the room is public, `key` names one of its keys, `key` matches
`pending[did].key` for the same `traverseId`, or `key` equals `global_key`.
There is no owner bypass: the owner presents a key like anyone else. A DID
already present in the destination room is admitted again regardless of `key`
(section 3.3).

`pending[did]` is in memory only, is overwritten by the next movement for that
DID, and is consumed by the matching `:enter`.

### 4.4 Exit locks

A passage MAY be locked. Its owner or its `entrance` room locks it with
`:lock [secret]`; a lock is global and never per-player. A caller holding the
secret, or the runtime's `global_key`, opens it for everyone with
`:unlock <secret>`. A locked passage answers a move with `deny` at once.

A locked passage is a door, not a wall: it stops this route only. Whether a
traveller may reach the room another way is decided by that room's admission
policy.

### 4.5 Narration

Narration has two channels with one principle: a room broadcasts, a passage may
speak to the traveller directly.

**Presence narration.** The passage proposes six texts, already composed for
their audience:

| Field | Audience |
| --- | --- |
| `leave` | the traveller, on departure |
| `oleave` | the others in the `entrance` room |
| `arrive` | the traveller, on arrival |
| `oarrive` | the others in the `exit` room |
| `nogo` | the traveller, on refusal |
| `onogo` | the others in the `entrance` room |

The room fires them as world events to all of its children. Each recipient
renders the traveller-facing text when the subject is itself, otherwise the
others-facing text. The passage's text takes precedence over the room default,
and the room MAY override either. Presence narration is one-way: the passage
proposes, the room fires, and nothing echoes the text back.

**Passage narration.** A passage MAY send free-form narration describing the
journey itself, addressed directly to the traveller, carrying `traverseId`. A
client accepts it only from a passage listed in the `exits` map of the room ctx
it holds, and only when `traverseId` matches its live movement.

### 4.6 Traversal invariants

1. `msg.from` is the sole authenticated fact; ctx never authenticates anything.
2. Every `:enter` carries a movement ctx with `did`, `traverseId`, and the user
   ctx. There is no shorter form.
3. Only `msg.from` equal to `ctx.did` may commit presence. A delegated `:move`
   or `:enter` authorises, never commits.
4. A traveller has at most one live `traverseId`. Every hop ignores a message
   whose `traverseId` does not match its live movement.
5. `did`, `traverseId`, and `key` (when present) survive every hop unchanged.
   `key` is opaque to forwarders and is read only by the destination.
6. A room admits a traveller only as specified in section 4.3.
7. A passage consults one destination at a time. Redirects are bounded and stay
   on the destination's own runtime.
8. Presence narration is a one-way proposal: the passage authors it, the room
   broadcasts it, and nothing is echoed back.
9. Registration (visibility) and admission are separate acts. A room's `exits`
   map decides what it shows; a room's keys decide who enters.

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

This is an explicit data-model rule: a node MUST have exactly one authoritative
collection of child ctx records, namely `children`. Implementations MUST NOT
store parallel child collections split by kind, lifecycle/state, or any other
category. Kind-specific, state-specific, inventory, occupancy, and similar
views MAY be derived by filtering the single `children` collection, but they
MUST NOT become additional sources of truth. Keeping more than one child list
creates divergence between parentage, ctx updates, persistence, and removal;
developers SHOULD treat such designs as an interoperability and consistency
risk.

Exits are the deliberate structural exception. An exit has two hardcoded
endpoints and no parent; it is not a child of either room. Each room keeps a
separate `exits` map (local name → exit DID-URL), published in the room ctx as
`exits`. That map is not a second child collection — an exit is never admitted,
moved, or forgotten as a child, and the local name conveys no authority. An
implementation MUST NOT instead model an exit as a room child.

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

A parent whose own ctx changes (e.g. a room's occupancy) MUST push a fresh
`:child <ctx>` to every current child, not only to the child that triggered
the change, so each child's cached parent-facing ctx never goes stale. This
reuses the same `:parent`/`:child` idempotent-retry rules above; it is not a
separate wire form, and the pushed `ctx` MUST still satisfy the base identity
rules (`actor` names the child, `parent` names the sender). A parent's own
richer self-description (e.g. a room's current occupants) MAY travel as an
additional field on that same `ctx`, conventionally nested under its own key
so it cannot collide with the child's own name/nick/description fields. A
child SHOULD cache the most recent such field it accepts from its parent so
it can introspect its parent's kind and contents without a separate round
trip; this cached data is not authenticated beyond the sender check above and
MAY be incomplete or absent at the parent's discretion.

A child announces its own termination with a ctx whose `parent` is empty; the
parent forgets it. `:parent?` returns an actor's current parent. `:children?`
returns the `children` map and is owner-gated.

Root adopts orphaned thing, agent, and container actors. An owner requests
repair with `:orphan <actor> from <parent>` on root, and `:orphans?` lists the
ctxs of root's live orphaned children.

Ownership is optional per-actor state gating parentage authority; it is a
profile convention, not part of the `/ma/node/0.0.1` handshake itself.
Parentage is placement, not ownership: a successful `:parent`/`:child`
transfer, including one triggered by `:set-parent` or `:hold`, MUST NOT change
an existing actor's owner. An actor with no owner MAY be freely proposed to a
new parent by any caller and remains unowned after that transfer. An owned
actor accepts a transfer request only from `msg.from` equal to its current
parent, its owner, or a holder of its recovery secret (below); an unrelated
caller's request MUST be refused. `:owner?` returns the current owner DID, or
none.

An owner MAY set a recovery secret on their actor. Presenting that secret with
`:claim <secret>` reassigns ownership to the presenting `msg.from` and clears
the secret, without requiring a message from the current owner. An unowned
actor with no stored secret accepts an argument-free `:claim` from any caller.
For an existing actor, `:claim` is the only ownership-changing convention
verb. `:forge` is the creation exception: it initialises a new actor's owner
from `msg.from` as specified in section 7. These are convention verbs; this
profile does not mandate their exact wire form beyond the ctx and authority
rules above.

A convention trigger verb, `:set-parent <target-parent-did-url> [ctx]`, sent
directly to the child actor, is this profile's reference way to make an actor
initiate the `:parent`/`:child` handshake of its own accord. It is not itself
part of the normative handshake in section 6 above and other trigger names
remain conforming, but implementations SHOULD accept `:set-parent` for
interop with this profile's reference actors. `:set-parent` MUST NOT change
ownership.

Two further convention trigger verbs cover the common case of an actor being
held by, or dropped by, a bare-DID caller rather than another parented actor:

- `:hold`, sent to the child actor with no argument at all, initiates the
  same handshake with the target parent taken implicitly from `msg.from` (a
  bare DID, never a DID-URL) — this is what lets a caller who is not itself
  an addressable parent (e.g. an avatar with no actor identity of its own)
  become an actor's parent, which `:set-parent`'s DID-URL-only target cannot
  express. `:hold` is ownership-blind: any caller present alongside the
  object MAY hold it regardless of who owns it, and a successful hold MUST
  NOT itself change ownership.
- `:drop`, sent to a candidate parent (not the object being moved), is an
  advisory capacity pre-check that MAY be refused independently of the
  handshake itself; a caller conventionally sends it before triggering
  `:set-parent`/`:hold` on the object, but it never itself changes parentage.

Both remain outside the normative handshake in section 6, on the same footing
as `:set-parent`.

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

The technical layer uses actor replies. Queries, structured state, configuration,
validation, and errors MUST use `:ok`, `[:ok, value]`, or `[:error, reason]`.
Examples include `:enter`, `:look`, `:who?`, `:exits?`, `:contents?`, `:did?`,
and `:owner?`.

Two world-layer reply terms extend this vocabulary: `[:deny, reason]` is a
policy refusal whose `reason` is free text authored by the refusing actor, and
`[:entrance, target]` asks the caller to retry an entry against another room.

The world-event layer uses unsolicited `[:event, <name>, <args…>]` messages — a
single envelope so a room broadcast never collides with a direct term. Arrival,
departure, speech, emotes, movement, transfer, and world-building outcomes are
events. A room emits their narrative text after its authoritative local state
change. Clients display these events and MUST NOT derive or invent an alternate
narrative from an actor acknowledgement.

An action MAY return a bare `:ok` as a technical completion acknowledgement.
That acknowledgement is not a user-visible description. Its narrative outcome,
when any, is sent only as an `[:event, …]` message. A direct, non-broadcast
notice MAY use `[:print, text]`.
