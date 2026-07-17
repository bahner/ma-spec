# runtime — the ma-runtime actor framework

> **Work in progress.** These documents are incomplete and unstable.
> Do not use them as a basis for implementation yet.

These documents specify **ma-runtime**: a full implementation of an actor
framework built on `did:ma`, geared towards multi-user text-based virtual
reality (think MUD). A runtime hosts *entities* — sandboxed Wasm plugin
actors addressed as `did:ma:<runtime>#<name>` — and provides them with
persistence, scheduling, placement, and identity services.

## How this relates to the other layers

`did:ma` itself ([../did-ma-spec-v1.md](../did-ma-spec-v1.md)) is a generic
DID and DIDComm model that can be used by many, for many things. ma-runtime
is *one* framework built on top of it. Everything in this directory is
**required for a conforming runtime**, but **irrelevant if you only want
DIDs and messaging** — and it presumes the whole
[core](../core/README.md) conventions layer, with considerable extensions
to the basic message vocabulary.

## Documents

| Document | Defines |
|---|---|
| [ma-runtime-v1.md](ma-runtime-v1.md) | The normative runtime spec: manifest (IPLD DAG-CBOR), entity/kind plugin model, services, fragment routing, config, reserved names. |
| [ma-runtime-guide-v1.md](ma-runtime-guide-v1.md) | Prose companion for operators and plugin developers. Start here. |
| [ma-crud-service-v1.md](ma-crud-service-v1.md) | `/ma/crud/0.0.1` — slash-path grammar (`/entities`, `/kinds`, `/config`, `/acl`) for managing a runtime remotely. |
| [ma-standard-actors-v1.md](ma-standard-actors-v1.md) | The built-in actors: `#root` (entity lifecycle), `#scheduler`. |
| [ma-schedules-v1.md](ma-schedules-v1.md) | Schedule registration: cron, interval, at, random. |
| [ma-avatar-v1.md](ma-avatar-v1.md) | `#avatar` — pseudonymous identity mapping for agents in the world. |
| [ma-house-v1.md](ma-house-v1.md) | `#house` — placement authority: containment tree and ticket-based entry. |
| [ma-scheme-v1.md](ma-scheme-v1.md) | ma-scheme — the minimal, sandboxed scripting dialect that runs *inside* entity plugins, letting non-developers define entity behaviour without writing/compiling Wasm. Not to be confused with zscheme (client-side, see [zscheme-v1.md](../zscheme/zscheme-v1.md)). |

## Intended audience

- **Runtime developers** implementing or extending a runtime. The
  reference implementation is written in Rust and builds on the
  [ma-core](https://crates.io/crates/ma-core) crate, which provides DID
  handling, the message envelope, transport, ACL, and config — so a new
  runtime does not have to start from the wire format.
- **Plugin developers** writing entity kinds (Wasm/Extism, e.g. via the
  Python actor libraries): read the guide, the standard actors, and the
  schedules spec.
- **Client developers** only need the [core](../core/README.md) layer plus
  the CRUD grammar in this directory if they manage runtimes.
