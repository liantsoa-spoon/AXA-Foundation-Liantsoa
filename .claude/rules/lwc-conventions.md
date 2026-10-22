# Lightning web components

## Design

Before writing code, analyze the need and propose the component's placement, presentation, and
interface. When any of these is unspecified, choose what provides the best possible UI and UX.
Present the proposed design as a Markdown mockup and explain the UX decisions behind it.

Build with the standard components and design patterns provided by SLDS 2. Add custom markup or
styling only when the design system does not cover the need.

When the design is complex or requires custom work, research established patterns before
creating one. Consult the official SLDS and Salesforce developer documentation first, followed
by Salesforce Help and Trailhead. Use community resources only when the official sources do not
cover the need.

## File header

Start every HTML template with the same header tags as JavaScript files, using an HTML comment.

```html
<!--
  @description       : <one short sentence describing what the template renders>
  @author            : <full name>
  @last modified on  : <DD-MM-YYYY>
  @last modified by  : <full name>

  Modifications Log
  Ver   Date         Author   Modification
  1.0   DD-MM-YYYY   <TRI>    Initial version
-->
```

## Naming

Name component bundles in camelCase after their responsibility. Use the bundle name as the
base name of every file in the bundle.

Name JavaScript classes in PascalCase after their component.

Name properties in camelCase.

Name getters after the value they expose, such as itemCount or isActionDisabled.

Name event handlers handle<Event>.

Preserve the exported name of an import. When an alias is necessary, name it according to what
it represents.

## Labels and text

Declare every user-facing string in a single LABELS constant at the top of the file. Keep
standalone strings at the top level, and group related strings into nested objects named after
the part of the UI they serve.

```javascript
const LABELS = {
  title: "Liste des éléments",
  filter: "Filtre",
  clearSelection: "Annuler la sélection",

  selection: {
    separator: "sur",
    suffix: "sélectionnés"
  },

  columnHeaders: {
    name: "Nom",
    category: "Catégorie",
    description: "Description",
    status: "Statut"
  },

  feedback: {
    loading: "Chargement",
    emptyState: "Aucun élément à afficher.",
    errorTitle: "Une erreur est survenue"
  }
};
```

## Formatting

Treat the configured ESLint and Prettier rules as the formatting authority for this folder. Do not
introduce or preserve formatting that conflicts with their output.
