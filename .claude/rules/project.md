# Project

Salesforce implementation for the AXA Foundation for Human Progress, part of the AXA group.
It funds projects in science, nature, solidarity, and culture across the countries where the
group operates ([axafoundation.org](https://axafoundation.org)).
The org runs Nonprofit Cloud with Omnistudio, with a focus on Grantmaking.

Use API names in code and the following mapping when interpreting tickets.

| API name                    | Org label        | Business term                         |
| ---------------------------- | ---------------- | ------------------------------------- |
| Account                      | Partner           | Partenaire, Organisation, Institution |
| Contact                      | Contact            | Contact                               |
| Program                      | Pillar             | Pilier                                |
| FundingOpportunity           | Program            | Programme                             |
| ApplicationForm               | Project            | Projet                                |
| Budget                        | Budget             | Budget                                |
| Contract                      | Conventionnement   | Conventionnement                      |
| ApplicationFormEvaluation      | Evaluation         | Évaluation                            |
| Benefit__c                    | Counterpart        | Contrepartie                          |

## Data dictionary

The project's fields and labels are defined in the data dictionary, an internal file kept outside
the repository. Ask for the relevant extract rather than inventing field definitions or labels.

| Column                  | Description                                             |
| ----------------------- | --------------------------------------------------------- |
| CRM?                    | Whether to implement the field in the CRM                 |
| Field Label (French)    | French translation of the field label                     |
| Field Label (English)   | Field label in English                                    |
| API Name                | Field API name                                             |
| Data Type               | Field type                                                 |
| Info.                   | Additional field information, including picklist values    |

Other columns are S/C, Required, Unique, ID ex., Hist., Default value, Help, and Comments.

## Language

Always write API names in English.

Author labels and user-facing text in English and provide French translations for all
Experience Cloud content and standard CRM components, including object, field, related list,
and picklist labels. Use Custom Labels where needed.

For Lightning web components and screen flows, follow this bilingual rule when used in
Experience Cloud; otherwise, write directly in French.
