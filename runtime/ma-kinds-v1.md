# ma-kinds-v1 — the node kinds

**Status:** Recommendation
**Version:** 1.1.0
**Date:** 7 November 2026

---

## Abstract

A 間 world is built from six node kinds, each extending the base
`/ma/node/0.0.1` protocol ([ma-node-v1.md](ma-node-v1.md)):

| Kind | What it is |
| --- | --- |
| `/ma/thing/0.0.1` | a movable object |
| `/ma/container/0.0.1` | a movable object that holds other objects |
| `/ma/agent/0.0.1` | a movable object that can move itself |
| `/ma/passage/0.0.1` | a passage from one room to another |
| `/ma/room/0.0.1` | a place where people and objects gather |
| `/ma/trigger/0.0.1` | a sensor that counts and reacts |

This document specifies the verbs each kind MUST answer, above the base node
surface. A MUST verb is the minimum a foreign actor needs in order to interact
with that kind, without knowing its implementation. A kind MAY answer many
more; these are the only ones required.

---

## Table of contents

1. [Notational conventions](#1-notational-conventions)
2. [Movable objects](#2-movable-objects)
3. [`/ma/thing/0.0.1`](#3-mathing0001)
4. [`/ma/container/0.0.1`](#4-macontainer0001)
5. [`/ma/agent/0.0.1`](#5-maagent0001)
6. [`/ma/passage/0.0.1`](#6-maexit0001)
7. [`/ma/room/0.0.1`](#7-maroom0001)
8. [`/ma/trigger/0.0.1`](#8-matrigger0001)

---

## 1. Notational conventions

Verbs and replies follow [ma-node-v1.md](ma-node-v1.md) and
[ma-messaging-format-v1.md §2.4](../core/ma-messaging-format-v1.md). A verb
listed here MUST reply `:ok` or `[:ok, <value>]` on success and
`[:error, <reason>]` on failure, unless stated otherwise. Where a verb
carries meaning that is already fully specified elsewhere, that document is
named instead of repeating it.

---

## 2. Movable objects

`thing`, `container`, and `agent` are movable objects. In addition to the base
node surface, they MUST answer:

| Verb | Effect |
| --- | --- |
| `:where?` | reply with the current parent DID-URL, or `"(none)"` |
| `:set-parent <target>` | propose relocation to `<target>` |
| `:hold` | be held by the caller (relocate to the caller) |
| `:recycle` | end the object |

Ownership (`:owner`, `:owner?`, `:claim`, `:set-recovery-secret`) and the full
`:parent`/`:child` handshake are specified in
[ma-lambda-ma-v1.md](ma-lambda-ma-v1.md) and are not repeated here.

---

## 3. `/ma/thing/0.0.1`

A thing is the plain movable object. It has no additional required verbs
beyond the base node surface and the movable-object verbs in §2.

---

## 4. `/ma/container/0.0.1`

A container is a movable object that holds other objects. In addition to §2,
it MUST answer:

| Verb | Effect |
| --- | --- |
| `:contents?` | reply with the list of contained child ctx's |
| `:locked?` | reply `"true"` or `"false"` |
| `:lock [secret]` | lock, optionally storing a `secret` for `:unlock` |
| `:unlock [secret]` | unlock (owner, or holder of the secret) |

---

## 5. `/ma/agent/0.0.1`

An agent is a movable object that can move itself. In addition to §2, it MUST
answer:

| Verb | Effect |
| --- | --- |
| `:move <direction>` | move through the named exit of its current room |
| `:wander [direction]` | move through the named exit, or let the room choose one |
| `:exits?` | reply with the exits from the room ctx cached in its last `:child` ack |

`:move <direction>` and `:wander [direction]` are the movement entry points for
an agent — a rubber duck, or an h00man presence driven by a client or a
scheduler. Both initiate the ordinary traversal by sending a `:move` ctx to the
agent's current room; omitting `direction` in `:wander` lets the room choose an
available exit. They are not client convenience wrappers and MUST NOT be
removed or reshaped. An agent is always its own traveller: it mints the
`traverseId` and completes the returned `:move` answer with its own `:enter` at
the established exit ([ma-lambda-ma-v1.md](ma-lambda-ma-v1.md) §4.2).

---

## 6. `/ma/passage/0.0.1`

A passage is one two-ended node with ends `entrance` (the room a traveller
comes from) and `exit` (the room they go to). It has no parent, and each room
references it in its own `exits` map under a cosmetic local name. One passage is
one object, so it has one lock. It MUST answer:

| Verb | Effect |
| --- | --- |
| `:move <move-ctx>` | route a movement: when the sender is the current destination, relay its answer to `entrance`; otherwise verify `entrance` is an end, set `exit`, and ask the far end |
| `:to?` | the far end relative to the caller, or `"(none)"` |
| `:locked?` | reply `"true"` or `"false"` |
| `:lock [secret]` | lock (owner or `entrance` room), optionally storing a secret |
| `:unlock [secret]` | unlock (owner or `entrance` room, or holder of the secret) |
| `:message <slot> <text>` | set a narration proposal by short slot (`leave`, `oleave`, `arrive`, `oarrive`, `nogo`, `onogo`) |

The passage never moves anyone; the traveller completes the move with `:enter`
at the established `exit` room. See [ma-lambda-ma-v1.md](ma-lambda-ma-v1.md) §4.

---

## 7. `/ma/room/0.0.1`

A room is where people and objects gather. It MUST answer:

| Verb | Effect |
| --- | --- |
| `:enter <move-ctx>` | commit presence when `msg.from` equals `ctx.did`; reply with the DID ctx |
| `:move <move-ctx>` | resolve the passage and forward the ctx, or admit when `exit` names this room |
| `:dig <ctx>` | owner-only: create a passage, and a room when `dst` is absent |
| `:exit <name> <exit-did-url>` | owner-only: register an existing exit locally |
| `:look` | reply with the room presentation ctx |
| `:exits?` | reply with the room's exits |
| `:who?` | reply with the people present |
| `:occupants?` | reply with the occupants present |
| `:things?` | reply with the known things |
| `:say <text>` | broadcast an in-world speech event |
| `:emote <text>` | broadcast an in-world action event |
| `:leave` | stop being shown in the room |

Building (`:fill`), ownership (`:claim`, `:owner`), and the movement pre-check
(`:drop`) are specified in [ma-lambda-ma-v1.md](ma-lambda-ma-v1.md).

---

## 8. `/ma/trigger/0.0.1`

A trigger is a sensor that keeps per-identity counters and reacts to them with
rules. It MUST answer:

| Verb | Effect |
| --- | --- |
| `:count <did> <name> <delta>` | add `delta` to `counters[did][name]` |
| `:set <did> <name> <value>` | set an absolute counter value (owner) |
| `:reset <did> <name>` | delete / zero a counter |
| `:value? <did> <name>` | reply with the current counter integer |
| `:counters? <did> ` | reply with the current counters for the <did> |
| `:trigger <id> …` | add, replace, or remove a rule (owner) |
| `:triggers` | reply with the rule list (owner) |

The complete trigger behaviour is documented in the lambda-ma
`actors/trigger.md`.
