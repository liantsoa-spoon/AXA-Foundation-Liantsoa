# General code conventions

These rules apply to Apex classes and Lightning web components.

## File header

Start every Apex class file and every JavaScript file in a Lightning web component bundle with
this block, with the tags aligned as shown. Do not add @group.

```apex
/**
 * @description       : <one short sentence describing what this file does>
 * @author            : <full name>
 * @last modified on  : <DD-MM-YYYY>
 * @last modified by  : <full name>
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   DD-MM-YYYY   <TRI>    Initial version
 **/
```

Use full names in @author and @last modified by, and three-letter identifiers in the
modifications log. Ask for either when unknown; do not derive the identifier from the name.

When creating a file, use the same person for @author and @last modified by, set
@last modified on to the creation date, and add version 1.0 to the log with the description
Initial version.

For each subsequent logical change, preserve @author, update @last modified on and
@last modified by, and append one log entry with an English description.

Use DD-MM-YYYY for all dates.

Increment the minor version for changes within the file's existing purpose. When its purpose
changes, increment the major version and reset the minor version to zero.

Align log columns using the longest value in each column, including its heading, followed by
three spaces. Do not pad the final column.

## Naming

Preserve the spelling and capitalization of every established abbreviation wherever it appears
in an identifier.

Start every method name with an action verb, followed by what it acts on, unless a framework or
a more specific rule determines the name.

Name non-constant variables and parameters in camelCase.

Start Boolean names with is or has.

Name constants in SCREAMING_SNAKE_CASE.

Use plural names for collections.

Name Maps as <values>By<Key>. For nested Maps, append one By<Key> segment for each key level,
ordered from the outermost Map to the innermost one.
