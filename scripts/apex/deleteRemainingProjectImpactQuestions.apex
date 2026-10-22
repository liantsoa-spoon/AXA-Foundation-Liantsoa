/**
 * Purge the two remaining Draft Fixed clones of "Project Impact & Scope" still attached
 * to Funding Opportunity 119KN00000000HrYAI.
 */
Set<Id> questionIds = new Set<Id>{
    '0U4KN0000008Rdu0AE',
    '0U4KN0000008Rdz0AE'
};

List<AssessmentQuestionAssignment> assignments = [
    SELECT Id, AssessmentQuestionSetId, AssessmentQuestionId
    FROM AssessmentQuestionAssignment
    WHERE AssessmentQuestionId IN :questionIds
];
Set<Id> sectionIds = new Set<Id>();
for (AssessmentQuestionAssignment aqa : assignments) {
    sectionIds.add(aqa.AssessmentQuestionSetId);
}

List<AssessmentQuestionVersion> versions = [
    SELECT Id, AssessmentQuestionId, Status
    FROM AssessmentQuestionVersion
    WHERE AssessmentQuestionId IN :questionIds
];
Set<Id> versionIds = new Set<Id>();
Set<Id> activatedQuestionIds = new Set<Id>();
for (AssessmentQuestionVersion version : versions) {
    versionIds.add(version.Id);
    if (version.Status != 'Draft') {
        activatedQuestionIds.add(version.AssessmentQuestionId);
    }
}

List<AssessmentQuestionResponse> responses = [
    SELECT Id FROM AssessmentQuestionResponse WHERE AssessmentQuestionId IN :versionIds
];

System.debug('Assignments=' + assignments.size() + ' versions=' + versions.size()
    + ' responses=' + responses.size() + ' activated=' + activatedQuestionIds.size());

if (!responses.isEmpty()) {
    delete responses;
}
if (!assignments.isEmpty()) {
    delete assignments;
}

List<AssessmentQuestionVersion> versionsToDelete = new List<AssessmentQuestionVersion>();
for (AssessmentQuestionVersion version : versions) {
    if (!activatedQuestionIds.contains(version.AssessmentQuestionId)) {
        versionsToDelete.add(version);
    }
}
if (!versionsToDelete.isEmpty()) {
    delete versionsToDelete;
}

List<AssessmentQuestion> questionsToDelete = new List<AssessmentQuestion>();
for (Id questionId : questionIds) {
    if (!activatedQuestionIds.contains(questionId)) {
        questionsToDelete.add(new AssessmentQuestion(Id = questionId));
    }
}
if (!questionsToDelete.isEmpty()) {
    delete questionsToDelete;
}

Set<Id> stillUsedSectionIds = new Set<Id>();
if (!sectionIds.isEmpty()) {
    for (AssessmentQuestionAssignment aqa : [
        SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment
        WHERE AssessmentQuestionSetId IN :sectionIds
    ]) {
        stillUsedSectionIds.add(aqa.AssessmentQuestionSetId);
    }
}
List<AssessmentQuestionSet> sectionsToDelete = new List<AssessmentQuestionSet>();
for (Id sectionId : sectionIds) {
    if (!stillUsedSectionIds.contains(sectionId)) {
        sectionsToDelete.add(new AssessmentQuestionSet(Id = sectionId));
    }
}
if (!sectionsToDelete.isEmpty()) {
    delete sectionsToDelete;
}

System.debug('Purged questions=' + questionsToDelete.size() + ' sections=' + sectionsToDelete.size());
