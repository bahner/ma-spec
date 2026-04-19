# 間 Root Meta Protocol
**Status:** Experimental (Non-normative)  
**Version:** 0.2.1  
**Author:** Lars Bahner <lars.bahner@gmail.com>

## 1. Purpose

Defines how `@root` manages ids and system tree.

---

## 2. Core rule

Messages sent to:

did:ma:<identity>

are handled by `@root`.

---

## 3. System coupling

Root operations MUST modify `system.ids`.

---

## 4. Operations

- create  
- destroy  
- list  
- inspect  
- capabilities  

---

## 5. Create

Must result in:

system.ids.<id>

Must include:

- acl  
- owner  
- allowed_effects  

May include:

- public_cid  
- state_cid  

---

## 6. Opaque CID handling

CID-backed content is treated as opaque.

Root MUST NOT:

- parse code  
- validate content semantics  
- enforce language rules  

---

## 7. Sandbox model

Execution of CID content is outside root scope.

If executed, runtime MUST enforce:

- sandboxing  
- effect restrictions  
- ACL  

---

## 8. Responsibility boundaries

Root ensures:

- ids exist  
- metadata exists  
- policy hooks exist  

Root does NOT ensure:

- correctness of code  
- safety of code  
- meaning of content  

---

## 9. Destroy

Removes entry from system.ids.

No tombstones.

---

## 10. Inspect

Returns data derived from system.ids.<id>

---

## 11. Conformance

Implementation MUST:

- route identity messages to root  
- update system.ids on create/destroy  
- treat CID as opaque  
- enforce sandbox externally