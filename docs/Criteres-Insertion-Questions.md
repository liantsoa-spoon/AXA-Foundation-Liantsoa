# Critères d’insertion des questions

**Objet porteur du scope :** `AssessmentQuestionAssignment`  
**Objets liés :** `AssessmentQuestionSet` (section), `AssessmentQuestion` + `AssessmentQuestionVersion` (définition)

Le scope ne vit **pas** sur la question elle-même. Une question n’est Common Core, Pillar, FO ou EOI que via sa ligne d’assignment.

---

## Matrice des 4 critères

| | `FundingOpportunity__c` | `Program__c` | `EOI__c` | Record Type question |
|---|---|---|---|---|
| **Common Core** | `null` | `null` | `false` (formulaire complet) | Dynamic **ou** Fixed |
| **Pillar only** | `null` | Id du Program (pilier) | `false` | Dynamic **ou** Fixed |
| **Dynamic (FO)** | Id de la Funding Opportunity | non utilisé pour le scope FO | `false` | **Dynamic** |
| **EOI** | `null` (template) | `null` (Common Core) **ou** Id Program (Pillar) | **`true`** | Dynamic **ou** Fixed |

---

## 1. Common Core

Banque de questions proposée à **tous** les Programmes, quel que soit le pilier.

**Insertion template**

- `AssessmentQuestionAssignment.FundingOpportunity__c` = `null`
- `AssessmentQuestionAssignment.Program__c` = `null`
- `AssessmentQuestionAssignment.EOI__c` = `false`
- Section (`AssessmentQuestionSet`) sans FO (template, pas une section locale de Programme)

**Lecture**

Reprise dans le pool template du builder :

```
FundingOpportunity__c = null
AND (Program__c = :fo.ProgramId OR Program__c = null)
```

`Program__c = null` = Common Core.

**Après validation** : clone indépendant sur la FO (`FundingOpportunity__c` = Id FO). L’original template reste `null` / `null`.

---

## 2. Pillar only

Même mécanisme que Common Core, mais limité au pilier du Programme.

**Insertion template**

- `FundingOpportunity__c` = `null`
- `Program__c` = Id du Program (pilier)
- `EOI__c` = `false`

**Lecture** : même requête que ci-dessus ; seules les lignes dont `Program__c` = pilier de la FO (ou Common Core) apparaissent.

Une question Pillar d’un **autre** Program n’est jamais proposée.

---

## 3. Dynamic question

Type de **définition**, pas de scope. Indépendant de Common Core / Pillar / EOI.

**Insertion**

- `AssessmentQuestion.RecordType` = `Dynamic` (pas `Fixed`)
- `ObjectAPIName__c` / `FieldAPIName__c` = `null` (réservés au Fixed)
- Version initiale : `IsActive = false` (Draft)
- Réponse candidat → `AssessmentQuestionResponse` (pas un champ CRM)

**Côté builder FO** (`+` / Ajouter une question)

- Section déjà rattachée à la FO (`AssessmentQuestionSet.FundingOpportunity__c` = Id FO)
- Assignment créé avec `FundingOpportunity__c` = Id FO
- `isFixed = false` (le LWC n’insère jamais de Fixed)
- `EOI__c` non renseigné → `false` (hors mini-formulaire EOI)

**Fixed (hors builder, pour contraste)** : Record Type `Fixed` + Object API Name + Field API Name obligatoires. Section contenant un Fixed = verrouillée (pas d’edit / delete section).

---

## 4. Is EOI Question

Mini-formulaire Expression of Interest. Flag sur l’**assignment** : `EOI__c = true`.

**Insertion template**

- `FundingOpportunity__c` = `null`
- `EOI__c` = `true`
- `Program__c` = `null` → EOI Common Core (tous les piliers)
- `Program__c` = Id Program → EOI Pillar only

**Lecture player EOI** (`eoiOnly = true`)

```
FundingOpportunity__c = null
AND EOI__c = true
AND (Program__c = null OR Program__c = :fo.ProgramId)
```

**Builder Programme** : les questions `isEOI = true` sont **exclues** de la liste. Elles ne se cochent / ne se valident pas dans l’onglet Questions.

**Player formulaire complet** : les questions EOI de la FO sont **ignorées**. EOI et formulaire long sont deux parcours distincts.

---

## Combo utiles

| Intention | FO | Program | EOI | Record Type |
|---|---|---|---|---|
| Socle formulaire long | `null` | `null` | `false` | Dynamic (typique) |
| Pilier formulaire long | `null` | Program Id | `false` | Dynamic (typique) |
| Socle EOI | `null` | `null` | `true` | Dynamic (typique) |
| Pilier EOI | `null` | Program Id | `true` | Dynamic (typique) |
| Question locale d’un Programme | FO Id | — | `false` | Dynamic |
| Question CRM mappée (template) | `null` | `null` ou Program Id | `false` ou `true` | **Fixed** + Object/Field |

**Identité clone** (éviter les doublons à la validation) : couple `Nom de section` + `Nom de question`, identique entre template et copie FO.

**Gel UI après Valider** : dès qu’au moins une question template **non EOI** est clonée sur la FO, le builder fige ajout / edit / delete / reorder. Les templates EOI n’entrent pas dans ce calcul.
