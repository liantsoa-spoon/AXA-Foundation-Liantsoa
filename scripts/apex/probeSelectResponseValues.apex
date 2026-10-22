// Probe jetable : la validation plateforme "Response Values is required for Select" s'applique-t-elle
// à l'update, ou seulement à l'insert ? Tout est annulé par le rollback final.
Savepoint savepoint = Database.setSavepoint();

Id dynamicRecordTypeId = [
    SELECT Id FROM RecordType
    WHERE SObjectType = 'AssessmentQuestion' AND DeveloperName = 'Fixed' LIMIT 1
].Id;

AssessmentQuestion question = new AssessmentQuestion(
    Name = 'Probe Industry',
    DeveloperName = 'ProbeIndustry' + String.valueOf(Datetime.now().getTime()),
    DataType = 'Select',
    QuestionCategory = 'Demographic',
    RecordTypeId = dynamicRecordTypeId,
    ObjectAPIName__c = 'Account',
    FieldAPIName__c = 'Industry'
);
insert question;

// 1) Insert direct avec ResponseValues null
try {
    insert new AssessmentQuestionVersion(
        Name = 'Probe Industry',
        AssessmentQuestionId = question.Id,
        QuestionText = 'Which industry?',
        ResponseValues = null,
        IsActive = false
    );
    System.debug('PROBE insert-null: OK');
} catch (Exception e) {
    System.debug('PROBE insert-null: BLOQUE -> ' + e.getMessage());
}

// 2) Insert avec valeurs, puis update vers null
AssessmentQuestionVersion version = new AssessmentQuestionVersion(
    Name = 'Probe Industry 2',
    AssessmentQuestionId = question.Id,
    QuestionText = 'Which industry?',
    ResponseValues = 'Placeholder',
    IsActive = false
);
insert version;
try {
    update new AssessmentQuestionVersion(Id = version.Id, ResponseValues = null);
    System.debug('PROBE update-to-null: OK');
} catch (Exception e) {
    System.debug('PROBE update-to-null: BLOQUE -> ' + e.getMessage());
}

Database.rollback(savepoint);
