/**
 * Data fix : renseigne MaximumCharacters__c sur toutes les AssessmentQuestion de type Text ou
 * TextArea qui ne l'ont pas, afin qu'elles cessent de violer la validation rule
 * "Maximum Characters is required when Data Type is Text or Text Area".
 *
 * Trois sources de valeur, par ordre de priorité :
 *   1. une question homonyme déjà renseignée (les clones portés par une Funding Opportunity
 *      héritent ainsi de la limite de leur template — Project description reste à 3000) ;
 *   2. la longueur du champ CRM pour une question Fixed correctement mappée ;
 *   3. un défaut par type de donnée, pour les questions Dynamic sans mapping.
 *
 * Rejouable : ne touche que les enregistrements dont MaximumCharacters__c est null.
 */

Decimal DEFAULT_TEXT_LENGTH = 255;
Decimal DEFAULT_TEXT_AREA_LENGTH = 32768;

List<AssessmentQuestion> questionsToFix = [
    SELECT Id, Name, DataType, ObjectAPIName__c, FieldAPIName__c
    FROM AssessmentQuestion
    WHERE DataType IN ('Text', 'TextArea') AND MaximumCharacters__c = null
];
if (questionsToFix.isEmpty()) {
    System.debug('Rien à corriger : toutes les questions Text/TextArea ont déjà une limite.');
    return;
}

// ---- 1) Limites déjà en place, indexées par nom de question ----
Set<String> questionNames = new Set<String>();
for (AssessmentQuestion question : questionsToFix) {
    questionNames.add(question.Name);
}
Map<String, Decimal> lengthByQuestionName = new Map<String, Decimal>();
for (AssessmentQuestion reference : [
    SELECT Name, MaximumCharacters__c
    FROM AssessmentQuestion
    WHERE Name IN :questionNames AND MaximumCharacters__c != null
    ORDER BY LastModifiedDate DESC
]) {
    // Le tri place la référence la plus récente en tête : on garde la première rencontrée.
    if (!lengthByQuestionName.containsKey(reference.Name)) {
        lengthByQuestionName.put(reference.Name, reference.MaximumCharacters__c);
    }
}

// ---- 2) Longueurs des champs CRM cibles, un seul describe par objet ----
Set<String> objectNames = new Set<String>();
for (AssessmentQuestion question : questionsToFix) {
    if (String.isNotBlank(question.ObjectAPIName__c) && String.isNotBlank(question.FieldAPIName__c)) {
        objectNames.add(question.ObjectAPIName__c);
    }
}
Map<String, Decimal> lengthByObjectAndField = new Map<String, Decimal>();
for (String objectName : objectNames) {
    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
    if (objectType == null) {
        continue;
    }
    for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {
        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
        if (fieldDescribe.getLength() > 0) {
            lengthByObjectAndField.put(
                objectName + '.' + fieldDescribe.getName(), fieldDescribe.getLength());
        }
    }
}

// ---- 3) Appliquer la limite ----
List<AssessmentQuestion> questionsToUpdate = new List<AssessmentQuestion>();
Integer fromTwinCount = 0;
Integer fromCrmFieldCount = 0;
Integer fromDefaultCount = 0;

for (AssessmentQuestion question : questionsToFix) {
    Decimal maximumCharacters = lengthByQuestionName.get(question.Name);
    if (maximumCharacters != null) {
        fromTwinCount++;
    } else if (String.isNotBlank(question.ObjectAPIName__c)
            && String.isNotBlank(question.FieldAPIName__c)) {
        maximumCharacters = lengthByObjectAndField.get(
            question.ObjectAPIName__c + '.' + question.FieldAPIName__c);
        if (maximumCharacters != null) {
            fromCrmFieldCount++;
        }
    }
    if (maximumCharacters == null) {
        maximumCharacters = question.DataType == 'TextArea'
            ? DEFAULT_TEXT_AREA_LENGTH
            : DEFAULT_TEXT_LENGTH;
        fromDefaultCount++;
    }
    questionsToUpdate.add(new AssessmentQuestion(
        Id = question.Id,
        MaximumCharacters__c = maximumCharacters
    ));
}

// Partial success : une question bloquée par une autre règle ne doit pas annuler tout le lot.
List<Database.SaveResult> results = Database.update(questionsToUpdate, false);
Integer successCount = 0;
for (Integer index = 0; index < results.size(); index++) {
    if (results[index].isSuccess()) {
        successCount++;
        continue;
    }
    System.debug(LoggingLevel.ERROR, 'Échec sur ' + questionsToUpdate[index].Id + ' : '
        + results[index].getErrors());
}

System.debug('Corrigé ' + successCount + '/' + questionsToUpdate.size() + ' question(s). '
    + 'Sources : ' + fromTwinCount + ' homonyme(s), ' + fromCrmFieldCount + ' champ(s) CRM, '
    + fromDefaultCount + ' défaut(s).');
