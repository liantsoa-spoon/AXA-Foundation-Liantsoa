Id dynamicRtId = [
    SELECT Id
    FROM RecordType
    WHERE SobjectType = 'AssessmentQuestion'
    AND DeveloperName = 'Dynamic'
    LIMIT 1
].Id;

List<AssessmentQuestion> localQuestions = [
    SELECT Id, Name, RecordType.DeveloperName
    FROM AssessmentQuestion
    WHERE RecordType.DeveloperName = 'Local'
];

for (AssessmentQuestion question : localQuestions) {
    question.RecordTypeId = dynamicRtId;
}

update localQuestions;

System.debug('Updated ' + localQuestions.size() + ' AssessmentQuestion(s) from Local to Dynamic.');
for (AssessmentQuestion question : localQuestions) {
    System.debug(question.Id + ' | ' + question.Name);
}
