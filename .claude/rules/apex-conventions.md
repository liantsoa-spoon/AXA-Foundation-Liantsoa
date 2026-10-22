# Apex classes

## Naming

Name classes in PascalCase after their responsibility.

Use the established suffix that identifies the role of a class, such as Batch, Queueable,
Job, Service, Controller, Wrapper, WS, EmailService, or TriggerHandler.

## Declarations

Declare every variable that receives only one assignment as final.

Declare every method that neither reads nor modifies instance state as static, unless a
required signature makes it an instance method.

Declare every picklist API value referenced in code in the PicklistValues class, never in the
class that uses it. Reuse the constant instead of repeating the literal value.

Group values in an inner class named after the object and field, or after the global value set if
the field uses one. Expose each group as a public static final instance on the top-level class,
and declare its values as public final String instance fields.

## Layout

### General

Indent with two spaces.

Limit lines to 120 characters, including indentation. Wrap longer lines at the outermost
syntactic boundary that keeps each line within the limit, such as an argument list, ternary
expression, or method chain. Indent continuations one level.

Always use braces for control statement bodies, even when they contain a single statement.

Align operators in consecutive assignments and SOQL conditions when their left-hand sides have
similar lengths, without excessively padding shorter ones.

When a parenthesized expression or argument list spans multiple lines, put the closing
parenthesis on its own line, aligned with the start of the construct.

### SOQL

Place each SOQL clause keyword on its own line. Put its content on the following lines, indented
one level, so the query reads as a hierarchy rather than a sentence. Use this format without
exception, regardless of the query length.

```apex
return [
  SELECT
    Id,
    Name,
    Industry
  FROM
    Account
  WHERE
    BillingCountry = :country
    AND Industry   = :industry
  WITH
    USER_MODE
  ORDER BY
    Name ASC
  LIMIT
    100
];
```

## Tests

Give every non-test Apex class a corresponding test class named <ClassName>_TEST.

Name test methods <unit>_<scenario>_<expectedResult>, starting with the method or unit under
test, for example methodName_givenCondition_expectedOutcome.

Test every behavior through its positive, negative, and boundary cases. Target 100% code
coverage.

Use the same file header for the test class, with @description set to
Test class for <ClassName>.
