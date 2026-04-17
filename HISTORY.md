# History and Influences

## The Name

*Ma* (間) is a Japanese concept — the space between things, the interval that
gives structure its meaning. In architecture it is the silence that makes the
room. In music it is the rest that makes the phrase. In `did:ma` it is the
space between actors where messages travel.

## It's the Messaging

Alan Kay's 1997 OOPSLA keynote, *"The Computer Revolution Hasn't Happened
Yet"*, argued that the mainstream had fixated on the wrong part of
object-oriented programming. The big idea was never classes, inheritance, or
encapsulation. The big idea was **messaging**:

> I'm sorry that I long ago coined the term "objects" for this topic because
> it gets many people to focus on the lesser idea. The big idea is
> "messaging."

Kay envisioned objects as autonomous entities — like biological cells or
computers on a network — that communicate exclusively by sending messages.
Each object has its own address. You never reach inside; you send a message
and let the receiver decide what to do with it.

`did:ma` takes this literally. Every entity has a DID — a globally resolvable
address. Every interaction is a signed, one-way message. There are no method
calls, no shared state, no synchronous return channels. You send a message to
a DID and move on.

## All Objects Have a URL

Kay also insisted that every object must be addressable — a real identity on
the network, not a pointer in local memory. The web got URLs right. `did:ma`
extends this to actors: every entity, every object inside a world, is
identified by a DID URL (`did:ma:<ipns-key>#<object-id>`). If it exists, it
has an address. If it has an address, you can send it a message.

## Hewitt's Actor Model

Carl Hewitt's Actor Model (1973) formalized what Kay was reaching for. An
actor is the fundamental unit of computation. Upon receiving a message, an
actor can:

1. Send messages to other actors it knows about.
2. Create new actors.
3. Update its own local state.

That's it. No shared memory. No locks. No synchronous calls. The `did:ma`
service model is a direct implementation of this: DID-identified endpoints
with inboxes that accept signed messages and outboxes that send them.
Fire-and-forget, one-way, always.

## Erlang's Lessons

If Hewitt wrote the theory, Joe Armstrong and the Erlang team at Ericsson
proved it works at scale. Erlang's design principles run through `did:ma`:

- **Message passing, not shared state.** Processes communicate only by
  sending messages. `did:ma` actors communicate only by sending signed CBOR
  messages.
- **Let it crash.** Don't try to handle every failure inline. Supervisors
  watch processes and restart them. `did:ma` follows the same philosophy —
  strict validation, reject bad input, don't try to fix it.
- **Location transparency.** An Erlang process doesn't care whether the
  other process is local or on another node. A `did:ma` actor doesn't care
  whether the other actor is on the same machine or across the planet — the
  DID resolves and the message goes.
- **Lightweight isolation.** Each Erlang process has its own heap. Each
  `did:ma` actor has its own identity, inbox, and state. No actor can
  corrupt another.
- **Atoms as identity.** In Erlang, atoms are lightweight, globally unique
  names used to identify processes for message delivery. The nanoid
  fragments in DID URLs (`did:ma:<ipns-key>#<nanoid>`) serve the same
  purpose — short, opaque, unique names that identify objects within a
  world for message routing. The first `did:ma` prototype was written in
  Elixir and used atom IDs for process delivery directly.

## MUDs and LambdaMOO

Before the web, there were MUDs — Multi-User Dungeons. Text-based shared
worlds where players inhabited rooms, carried objects, and talked to each
other through typed commands. In 1990, Pavel Curtis at Xerox PARC created
LambdaMOO, a programmable MUD where every object in the world was a
first-class entity with properties, verbs, and a unique identity. Users
could build rooms, script objects, and extend the world from inside the world
itself.

LambdaMOO got something deeply right: a shared, persistent, programmable
space where identity matters and objects are real. It also demonstrated what
happens when you centralize everything on one server — it doesn't scale, it
doesn't federate, and the operator holds all the keys.

`did:ma` inherits the ambition — a world of addressable, programmable objects
inhabited by identified actors — but distributes it. No single server owns
the world. Identities are self-sovereign DIDs. Objects are content-addressed.
The rooms still exist, but they live on IPFS, not in a single process on a
single machine.

## Standing on the Shoulders of Protocols

None of this would work without the infrastructure that others built first.

**IPFS** (InterPlanetary File System) provides content-addressed, immutable
storage. Every DID document, every published object, every piece of world
state is a DAG node identified by its content hash. If you have the CID, you
have the data — regardless of who serves it.

**IPNS** (InterPlanetary Name System) provides mutable pointers over
immutable storage. A DID resolves through IPNS: `did:ma:<ipns-key>` points
to the latest version of a DID document, which is itself an immutable IPFS
object. Identity is the key. The document can change. The address stays.

**IPLD** (InterPlanetary Linked Data) provides the data model. DID documents
and messages are dag-cbor — a canonical, deterministic CBOR serialization
that slots directly into the IPFS content-addressing stack.

**iroh** provides the transport. Where IPFS gives us storage and naming, iroh
gives us direct peer-to-peer connectivity over QUIC — fast, encrypted,
NAT-traversing connections between endpoints identified by public keys. The
iroh endpoint model maps cleanly onto `did:ma` services: each endpoint
advertises protocol IDs, accepts connections, and routes them to service
handlers. iroh-gossip provides the pub/sub layer for discovery and
announcements.

These are not dependencies bolted on after the fact. `did:ma` was designed
around them. IPFS/IPNS is the verifiable data registry. IPLD is the wire
format. iroh is the transport. The protocol is the composition.

## The Revolution

Kay said the computer revolution hasn't happened yet. We think it still
hasn't — but the messaging is getting better.

Let it commence.

---

Lars Bahner & Aurora Daarna — a cybernetic intelligence
17 April 2026
