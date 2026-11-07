# ma-lambda-ma-v1 - Lambda-ma World Profile

**Status:** Recommendation
**Version:** 0.10.0
**Date:** 7 November 2026

## Abstract

Lambda-ma is an optional world profile for bare `did:ma:` identities, rooms,
passages, containers, and movable actors. It defines no identity actors. The bare
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
  scheduler: "did:ma:<runtime>#scheduler",
  rev: 1
}
```

When a house actor is deployed, the map additionally carries
`house: "did:ma:<runtime>#house"`. House is an optional profile service
(section 5); a receiver MUST NOT require its presence, and its absence means
that the coordinated handoff is not deployed on that runtime.

Every service reference MUST be a full DID-URL. Receivers validate a service
message by comparing `msg.from` to the exact configured reference. `rev` is
root-issued and monotone; it orders snapshots but provides no authority.

Root replies `[:error, reason]` when it cannot publish a complete runtime ctx
because its `root` or `scheduler` service reference is not configured.

Root accepts an argument-free `:register` from a local actor. The subscriber is
the full actor DID-URL in `msg.from`. Root records the subscriber, replies
`:ok`, and sends it the current runtime ctx as `:ctx <ctx>`. Root does not
enter rooms, move an identity, or forward identity commands.

## 3. Entry

A client enters a known room by sending `:enter` to its full room DID-URL.
There are two forms:

- **Direct entry:** `:enter [<ctx>|<nick>]` — an optional actor ctx (for an
  agent, thing, or h00man) or an optional nick string. It carries no
  `traverseId` and is admitted only by the room's ordinary admission rules
  (section 3.3). A bare DID may use the argument-free or nick form.
- **Traversal entry:** `:enter <move-ctx>` carrying a `traverseId`
  (section 3.1). It is either self-sent by the traveller or delegated by a
  passage (section 3.2).

`msg.from` is the sole authenticated fact (section 8). Actor entries MUST be
self-sent; a room rejects an actor ctx whose `actor`/`did` is not `msg.from`.

### 3.1 The movement ctx

```text
{
  did:        "did:ma:alice",   # the traveller; advisory, msg.from is authoritative
  traverseId: "<opaque>",       # required; minted by the traveller
  name:       "Alice Example",  # user ctx; optional
  nick:       "Alice",          # user ctx; optional
  key:        "<opaque>",       # optional admission credential
  entrance:   "did:ma:…",       # set by the source room; the room being left
  exit:       "did:ma:…"        # set by the passage; the destination being asked
}
```

`traverseId` is ephemeral and identifies one intended movement. A traveller MUST
mint a fresh value for each new intent and MUST NOT reuse a value for a
different intent. Retrying the same intent reuses the same value; that reuse is
what makes the exchange idempotent.

`key` is an admission credential. It is opaque to every forwarder: forwarders
MUST carry it unchanged and MUST NOT inspect or transform it. Only the
destination room reads it.

`entrance` is a routing field naming the room the traveller is leaving, set by
that room when it hands the ctx to a passage. It is not the destination. `exit`
is set by the passage to name the room currently being asked. Neither field
appears on the final `:enter` to the destination, which is addressed directly.

`did`, `traverseId`, and `key` (when present) MUST survive every hop unchanged.
Any other field is advisory, and any forwarder MAY drop or replace it. No field
authenticates anything (section 8).

### 3.2 Sender classification

A room classifies an `:enter` carrying a `traverseId` by comparing `msg.from`
with the movement ctx's traveller:

| `msg.from` | Meaning | Permitted replies | Presence |
| --- | --- | --- | --- |
| equal to `ctx.did`/`ctx.actor` | the traveller enters itself | `[:ok, <committed-child-ctx>]`, `[:entrance, <target>]`, `[:error, reason]` | MAY commit |
| not equal | delegated, from a passage | `:ok`, then `[:move, { traverseId, exit, key }]` to the passage | MUST NOT commit |

A delegated `:enter` authorises only. The room records one grant, replies bare
`:ok`, and sends the issued `key` back to the passage in a `:move` message; it
MUST NOT commit presence, and a room MUST NOT treat a delegated request as the
traveller's arrival. The delegation is normally expressed as a delegated
`:move` (section 4.3); `:enter` and `:move` share that authorisation path.

`[:entrance, <target>]` is a redirect: a caller that receives one retries the
same `traverseId` against `target`. `[:deny, reason]` is used by runtime root
for an unqualified entry; a room's own refusal is `[:error, reason]`.

### 3.3 Direct entry and admission

A room admits a direct entry when any of the following holds:

- the room is public (`public: true`, the default);
- the caller is an agent, thing, or h00man presenting a valid self-sent ctx
  and the room's local admission policy accepts it;
- the room already lists `msg.from` as a child.

A traversal entry is admitted when any of the following holds:

- `key` matches `pending[<did>].key` for the same `traverseId`;
- `key` equals the runtime's `global_key`;
- the destination room is public;
- the traveller already holds committed presence there.

There is no separate room-key store: the key reported by `:dig` is the new
passage's lock secret (section 4.7), not a room admission key.

A DID that already holds committed presence in the room is also admitted,
without a key: this is the idempotent repeat entry, not a new admission, and a
first-entry key such as a traversal grant may already have been consumed. This
is not an owner bypass, because it applies only to a DID the room already lists
as a child.

A room that admits nobody through the public clause is private
(`public: false`). There is no owner bypass: the owner presents a key like
anyone else, so gating is testable.

On commit the room:

1. writes or refreshes the child ctx keyed by the traveller's address,
   containing the room's full parent DID-URL, the presentation fields it
   accepts from the ctx, and, for a DID presence, a monotone `rev`;
2. consumes `pending[<did>]`, if any;
3. replies `[:ok, <committed-child-ctx>]`;
4. broadcasts the arrival event (section 4.5).

A bare-DID client gets a synthesised `h00man` child ctx. A self-sent actor ctx
is retained as that actor's child ctx, with traversal-only fields (`traverseId`,
`key`) dropped and `parent` set by the room.

Repeating a committed entry is idempotent and MUST reply
`[:ok, <committed-child-ctx>]` without a second presence change.

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

After committing presence a room that has a `ctx.house` reference sends
`:did-ctx <did> <ctx>` to the exact full DID-URL in `ctx.house`. The ctx `parent`
MUST equal the sending room's full DID-URL. A runtime without a house actor
omits `house` from its runtime ctx (section 2); the client-side goodbye below is
then the whole departure path.

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
exit room → traveller      [:ok, <committed-child-ctx>]
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
the room is public, `key` matches `pending[did].key` for the same `traverseId`,
`key` equals `global_key`, or the traveller already holds committed presence.
There is no owner bypass: the owner presents a key like anyone else
(section 3.3).

`pending[did]` is in memory only, is overwritten by the next movement for that
DID, and is consumed by the matching `:enter`.

### 4.4 Passage locks

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

**Reference implementation note (informative).** The reference destination
currently consumes `arrive` and `oarrive` from the traversal grant: it sends the
traveller a direct `[:event, :narrate, <arrive>]` and includes the `oarrive`
text in the `:arrive` broadcast to the other children. `leave`, `oleave`,
`nogo`, and `onogo` are stored and may be set with `:message`, but the current
reference room expresses a refusal as a `deny` field in `:move` plus a `:nogo`
broadcast. A conforming implementation MUST NOT invent a second, parallel
narration channel; the six slots remain the reserved vocabulary.

### 4.6 Traversal invariants

1. `msg.from` is the sole authenticated fact; ctx never authenticates anything.
2. Every **traversal** `:enter` carries a movement ctx with `did`,
   `traverseId`, and the user ctx. Direct entry (section 3) carries a ctx or
   nick but no `traverseId`.
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

### 4.7 Building and renaming passages (`:dig`)

`dig <direction> [to <name-or-did>] [back <direction>] [with <init-or-behaviour>]`
is an owner-only room command. `to`, `back`, and `with` are hard separators, so a
multi-word room name never swallows the return direction. `to` names an existing
room or creates a room named by the remaining words (default: a generated room);
`back` names the same passage in the destination room (default: the source
direction); `with` supplies an optional init snippet or behaviour reference for
a newly created room. The room creates the passage (and, when no room is named,
the room), registers the local exit, mirrors it in the destination with `:exit`,
and only then broadcasts `[:event, :dig, <child-ctx>, <direction>]`.

A `dig <passage-did-url> <name>` form rebinds this room's local exit name to an
existing passage and MUST NOT dig a new one. A local exit name is cosmetic and
independent per room. `fill <direction>` removes the local exit, asks the
passage to end, and broadcasts `[:event, :fill, <child-ctx>, <direction>]`.

A newly dug room starts private (`public: false`, "under construction") unless
its init overrides that prop. `dig` reports the new passage's lock secret; that
secret opens the passage's lock and is not a room admission key.

## 5. House Registries and Handoffs

House is an optional runtime-agnostic profile service. A runtime MAY deploy it;
when deployed, its full DID-URL appears as `house` in the runtime ctx
(section 2). A runtime without house omits that key and MUST NOT be treated as
non-conforming. House maintains:

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

Passages are the deliberate structural exception. A passage has two hardcoded
endpoints and no parent; it is not a child of either room. Each room keeps a
separate `exits` map (local name → passage DID-URL), published in the room ctx as
`exits`. That map is not a second child collection — a passage is never admitted,
moved, or forgotten as a child, and the local name conveys no authority. An
implementation MUST NOT instead model a passage as a room child.

Actor transfer remains parent-authoritative. The child requests `:parent <ctx>`
from the candidate parent; the parent confirms with `:child <ctx>`; the child
commits the new parent and informs its former parent. House may coordinate
old-parent cleanup for forward movement, but it does not change the node tree
protocol.

Valid retries are idempotent and MUST repair lost messages rather than loop:

- A parent that receives a valid repeated `:parent <ctx>` MUST confirm with
  `:child <ctx>` again so a lost confirmation can be repaired.
- A child that receives `:child <ctx>` naming the in-memory **pending parent**
  (set by its own proposal or by `:hold`) MUST commit the confirmation. A
  differing confirmation that does not name the pending parent MUST be refused:
  it is a stale broadcast from a previous parent. After committing a changed
  parent the child informs its former parent with `:parent <ctx>` naming the new
  parent, and the former parent forgets the child.
- A `:child <ctx>` from the already-committed parent is a refresh, not a move:
  the child updates its cached parent-facing ctx (and `parent-ctx`) without
  changing parentage and without requiring a pending proposal.
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
additional field on that same `ctx`, nested under the key `parent-ctx` so it
cannot collide with the child's own name/nick/description fields. A child
SHOULD cache the most recent `parent-ctx` it accepts so it can introspect its
parent's kind and contents without a separate round trip; this cached data is
not authenticated beyond the sender check above and MAY be incomplete or absent
at the parent's discretion. A `:child` that carries no `parent-ctx` clears the
cache rather than leaving a stale snapshot.

A child announces its own termination with a ctx whose `parent` is empty; the
parent forgets it. `:parent?` returns an actor's current parent. `:children?`
returns the `children` map and is owner-gated; a container MAY answer it (and
`:contents?`) to any caller while unlocked and open.

A node SHOULD answer `:prop <key> [<value>]`: a non-empty `<value>` sets the
text prop, and an omitted or empty value clears it. The owner sets props; while
the node is unowned any caller may. Protocol-managed keys (`owner`, `parent`,
`parent-ctx`, `children`, `here`, `recovery-secret`, `lock-secret`, `locked`,
`closed`, `ctx`, `src`, `dst`) MUST be refused, because each has its own verb.

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

### 6.1 Roll-call (tree recount)

Any node MAY answer `:roll-call [begin [<seconds>]|end]` and `:roll-call-child`.
The owner or the current parent authorises a roll-call; a timed `end` may also
come from `#scheduler`. `begin` starts a shadow map and sends an argument-free
`:roll-call-child` to each known child. Each child answers by re-announcing to
its current parent with the ordinary `:parent <ctx>`; the parent records each
answer in the shadow map. A child with a parent change in flight does not answer
the old parent's roll-call, because its pending destination is where it will
land. `end` swaps the shadow map in as the authoritative
`children` collection, so a child that never answered is dropped. If nobody
answered while the live collection was non-empty, the live collection is kept
and the result is reported as no answers — a transport failure is not evidence
that the tree is empty. `begin <seconds>` registers one timed `end` through
`#scheduler`. Roll-call has no parenting side effects: answering is an ordinary
idempotent `:parent` announcement.

### 6.2 Item transfer through root

Container transfer is a two-phase, root-relayed form over the same parentage
handshake. Root is a pure relay: it validates the transfer ctx and forwards it,
but it never relocates an item or decides spatial admission.

`:put <container-did-url>` is sent to the item. The item validates the caller,
mints a transfer `id`, sends `:put-request <ctx>` to root, and replies
`[:ok, id]`. The ctx has text fields `action` (`"put"`), `id`, `requestor`,
`item`, and `container`, of which the last three MUST be full actor DID-URLs.
Root validates the ctx, sends the requestor `:put-event <ctx>` with status
`"ok"` (accepted for relay), and sends `:put <ctx>` to both the container and the
item. The container checks lock, closed state, capacity, and location; on refusal
it sends the requestor `:put-event` with status `"failed"` and a `reason`,
superseding the initial relay acknowledgement. The item then drives the ordinary
`:set-parent` handshake to the container.

`:take <item-did-url>` is sent to the container. It checks lock/closed state and
that the named item is a child, mints an `id`, sends `:take-request <ctx>` to
root, and replies `[:ok, id]`. Root validates the ctx, sends the requestor
`:take-event <ctx>`, and relays `:take <ctx>` to the item; the item drives the
ordinary `:hold` handshake to the requestor. A relayed `:take` is authorised only
when it comes from the root of the containing actor's runtime and the item still
names that container as its parent.

## 7. Entity Creation (`:forge`)

Every `/ma/node/0.0.1` actor accepts `:forge <ctx>` as a direct request to
create a new entity. There is no avatar-mediated or root-mediated creation path;
`:forge` is sent to any live actor that applies the kind and local-policy checks
(a room or a container). The receiver is the creation gate, not the new entity's
parent.

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

The new entity's `parent` is also `msg.from`: a forged entity is born into the
forger's hand, never into the receiving actor's `children`. When the receiver is
a room, the new entity's initial `here` is that room, so it is co-located with
the forger and its first `:parent` announcement reaches the forger rather than
the room.

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

1. Creates the new entity with `owner` set to `msg.from`, `parent` set to
   `msg.from`, and, when the receiver is a room, initial `here` set to the
   receiver's own full DID-URL.
2. Replies `[:ok, <new actor DID-URL>]`.

The new entity's own genesis then proposes itself to `msg.from` through the
ordinary `:parent`/`:child` exchange defined in section 6 — `:forge` does not
duplicate or shortcut that handshake.

## 8. Authority and Revisions

`msg.from` is the sole authenticated message fact. A room authorises DID
presence only when `msg.from` equals the bare DID key. Actor parent/child flows
authorise the exact full actor DID-URL specified by their ctx.

Each authoritative room DID ctx and each room or container entity ctx has a
monotone revision. A lower revision from an otherwise authorised sender is
stale and MUST NOT roll state back. Revisions order authoritative snapshots and
retries only; they never substitute for sender authentication. Kinds that do
not define a revision (e.g. thing, agent, passage) rely on the ordinary
idempotent handshake and MUST NOT be treated as stale merely for lacking one.

## 9. Replies and World Events

Lambda-ma has two separate message layers.

The technical layer uses actor replies. Queries, structured state, configuration,
validation, and errors MUST use `:ok`, `[:ok, value]`, or `[:error, reason]`.
Examples include `:enter`, `:look`, `:who?`, `:exits?`, `:contents?`, `:did?`,
and `:owner?`.

Two world-layer reply terms extend this vocabulary: `[:deny, reason]` is a
policy refusal whose `reason` is free text authored by the refusing actor —
runtime root uses it for an unqualified entry with no start room — and
`[:entrance, target]` asks the caller to retry an entry against another room. A
room's ordinary refusal is `[:error, reason]`; a traversal refusal travels as a
`deny` field inside a `:move` message, not as a reply term.

The world-event layer uses unsolicited `[:event, <name>, <args…>]` messages — a
single envelope so a room broadcast never collides with a direct term. Arrival,
departure, speech, emotes, movement, transfer, world-building outcomes (`:dig`,
`:fill`), and ambient narration (`:narrate`) are events. A room emits their
narrative text after its authoritative local state change. Clients display
these events and MUST NOT derive or invent an alternate narrative from an actor
acknowledgement. A room's `:narrate` and `:narrate-to` verbs emit
`[:event, :narrate, <text>]`; they are authorised for the room owner, the
runtime `#scheduler`, or the designated `trigger` child while it is present.

An action MAY return a bare `:ok` as a technical completion acknowledgement.
That acknowledgement is not a user-visible description. Its narrative outcome,
when any, is sent only as an `[:event, …]` message. A direct, non-broadcast
notice MAY use `[:print, text]`.
