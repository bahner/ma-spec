# ma-runtime Generator Checklist v1

**Status:** Draft
**Scope:** Validation and generation of `/ma/runtime/0.0.1` runtime manifests
across implementation languages (including Elixir).

## 1. Input requirements

A generator MUST accept:
- A DID document with a `ma.runtime` field
- The runtime manifest (root)
- All referenced kind and entity nodes

The generator MUST fail early if a required node cannot be fetched or parsed.

## 2. DID runtime link

Rules:
- `ma.runtime` MUST be an IPLD link map with key `/`.
- The value MUST be a CID (runtime manifest root).
- The value MUST NOT be a string such as `/ipns/...`.

Example (YAML):
```yaml
ma:
  runtime:
    "/": bafy...runtime_root
```

## 3. RuntimeManifest (root)

Required fields:
- `owner` (string, DID)
- `kinds` (map)
- `entities` (map)

Optional fields:
- `lang` (map)
- `config` (map)
- `kinds_index` (list)
- `kinds_tree` (map)

Example (YAML):
```yaml
owner: did:ma:<owner_ipns>
kinds:
  stateless:
    "/": bafy...kind_stateless
entities:
  fortune:
    "/": bafy...entity_fortune
lang: {}
config: {}
```

Rules:
- Every value in `kinds`, `entities`, `lang` MUST be an IPLD link map
  (`{"/": "..."}`).
- `kinds` and `entities` MUST NOT be empty when the runtime is expected to be
  operational.
- If `kinds_index` is present, each entry SHOULD contain `protocol` + `link`
  for traversal without slash keys.
- If `kinds_tree` is present, it SHOULD follow the segmentation of
  `/ma/<name>/<version>`.

## 4. KindNode

Required fields:
- `protocol` (string)
- `api` (list of strings)
- `host_functions` (list of strings)

Optional fields:
- `wasi` (bool)

Example (YAML):
```yaml
protocol: /ma/runtime/call/0.0.1
api:
  - init
  - handle_call
  - get_state
host_functions:
  - ma_send
  - ma_reply
  - ma_set_state
wasi: false
```

Rules:
- `api` MUST contain all plugin exports the runtime requires for this kind.
- `host_functions` MUST be set explicitly.
- The runtime MUST NOT expose host functions beyond those in `host_functions`.

## 5. EntityNode

Required fields:
- `name` (string)
- `kind` (string)
- `behavior` (IPLD link map)
- `owner` (string, DID)
- `acl` (list)

Optional fields:
- `state` (IPLD link map)
- `wasi` (bool)

Example (YAML):
```yaml
name: counter
kind: stateful
behavior:
  "/": bafy...wasm_counter
state:
  "/": bafy...state_counter
owner: did:ma:<owner_ipns>
acl:
  - "*"
wasi: false
```

Rules:
- `kind` MUST reference an existing kind in `RuntimeManifest.kinds`.
- `behavior` MUST point to a loadable plugin artefact.
- If `state` is present, it MUST be a valid IPLD link map.

## 6. Cross-validation

The generator MUST validate:
- All kind links can be resolved.
- All entity links can be resolved.
- All entities point to a valid kind.
- Each plugin implements all exports listed in its kind's `api`.
- `wasi` requirements are consistent between kind and entity.

The generator SHOULD validate:
- `protocol` follows `/ma/<name>/<semver>`.
- `owner` DID is syntactically valid `did:ma`.

## 7. Generation contract (output)

When validation passes, the generator MUST produce an internal runtime setup
where:
- entities are mapped to plugin artefacts
- kind policy governs available host functions
- stateful entities receive a state lifecycle

Minimum output contract:
- a loadable plugin per entity
- host functions restricted per kind
- deterministic reference to the runtime root via IPNS
- deterministic reference to the runtime root via CID link in the DID document

## 8. RPC dot-path dispatcher

The generator MUST implement a dispatcher for unfragmented RPC messages.

Rules:
- Root namespaces `:entities`, `:kinds`, `:config`, and `:ping` MUST be
  supported.
- Unknown root namespaces MUST be rejected with
  `[:error, "unknown operation: <term>"]`.
- Unknown verbs under a known namespace MUST be rejected with
  `[:error, "unknown <namespace>.<name> operation: <term>"]`.
- Fragmented messages (`did:ma:<ipns>#<name>`) are routed to the named entity
  plugin — NOT to the dot-path dispatcher.

Required verb support for `:entities`:

| Term | Requirement |
|------|-------------|
| `:entities` | MUST return list of entity names |
| `:entities.<name>` | MUST return EntityNode as CBOR bytes, or error if not found |
| `:entities.<name>:` | MUST delete entity and unregister plugin |
| `[":entities.<name>:", <cid-text>]` | MUST fetch and validate EntityNode from Kubo, load plugin, return CID |
| `":entities.<name>:edit"` | MUST return current CID as a CBOR text atom |
| `[":entities.<name>:edit", <dag-cbor-bytes>]` | See §9 |

## 9. `:entities.<name>:edit` — write arm

The generator MUST implement receipt of pre-encoded DAG-CBOR bytes from the
client.

Processing requirements:

1. **`dag_put_raw`**: POST bytes to Kubo with `input-codec=dag-cbor,
   store-codec=dag-cbor`. MUST NOT use `input-codec=json`.
2. **Validation**: Fetch EntityNode via `dag_get` with the new CID. MUST
   verify that all required EntityNode fields are present.
3. **Plugin loading**: Load the Wasm plugin from the `behavior` link. MUST
   reject an EntityNode with an invalid or unreachable `behavior`.
4. **Manifest update**: Register the new CID in `manifest.entities[name]`.
5. **Reply**: Return `[:ok, "<new-cid>"]` (CBOR tuple with text atom).

Error responses:

| Condition | Reply |
|-----------|-------|
| Invalid DAG-CBOR | `[:error, "invalid dag-cbor"]` |
| Missing required fields | `[:error, "invalid entity node: <detail>"]` |
| Unreachable behavior link | `[:error, "entity behavior not loadable: <detail>"]` |
| Kubo error | `[:error, "dag_put failed: <detail>"]` |

## 10. Wire format — implementation requirements

The generator MUST follow these data format rules:

1. **CBOR on the wire**: All messages between peers are CBOR. JSON MUST NOT be
   sent between peers.
2. **Text argument = string**: A `CborValue::Text` argument is a plain string
   (CID, DID, config value).
3. **Kubo HTTP is internal**: JSON from the Kubo HTTP API is never visible to
   peers.
4. **IPFS gateway responses**: When the client fetches from a gateway it
   receives DAG-JSON (gateway-converted). Converting to YAML for the editor is
   the client's responsibility.

## 11. Elixir note (non-normative)

In Elixir, these rules can be mapped to:
- schemas + changesets for RuntimeManifest/KindNode/EntityNode
- an explicit validation pipeline for link resolution and cross-references
- a separate step for plugin ABI inspection against `api`
- `dag_put_raw` implemented with `Tesla` or `Req` against Kubo
  `/api/v0/dag/put` with a `multipart/form-data` body and
  `input-codec=dag-cbor, store-codec=dag-cbor`

This document is language-agnostic; Elixir is only one example of a generator
implementation.
