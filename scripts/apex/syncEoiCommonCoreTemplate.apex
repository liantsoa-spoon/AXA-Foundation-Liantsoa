// Syncs the Common Core / EOI template pool (Sections + Questions + Versions + Assignments) to
// TARGET_ROWS below. Idempotent and safe to re-run: reuses existing Sections/Questions by name,
// updates them in place, inserts what's missing, and removes anything no longer listed here
// (including its AssessmentQuestionResponse/Version/Question and any Section left empty by the
// cleanup). Only ever touches the template pool (FundingOpportunity__c = null, Program__c = null,
// EOI__c = true) — Funding-Opportunity-level clones are never read or written by this script.

Id fixedRecordTypeId = [
    SELECT Id FROM RecordType
    WHERE SObjectType = 'AssessmentQuestion' AND DeveloperName = 'Fixed' LIMIT 1
].Id;
Id dynamicRecordTypeId = [
    SELECT Id FROM RecordType
    WHERE SObjectType = 'AssessmentQuestion' AND DeveloperName = 'Dynamic' LIMIT 1
].Id;

String RESEARCH_FIELD_VALUES =
    'Risk to People and Well-Being, France\n' +
    'Risk to People and Well-Being, Outside France\n' +
    'Risk to the Planet\n' +
    'Risk to Societies';
String CIVILITY_VALUES = 'Mr.\nMs.\nMrs.\nN/A';
String AFFILIATION_VALUES =
    'Legal Representative\n' +
    'Administrative or Operational Representative\n' +
    'Finance Contact\n' +
    'Legal Contact\n' +
    'Communications Contact\n' +
    'Officer / Board Member\n' +
    'Evaluator\n' +
    'AXA Internal\n' +
    'Other (please specify)\n' +
    'Project applicant lead\n' +
    'Project partner lead\n' +
    'Supplier';
String NON_ACADEMIC_SECTOR_VALUES =
    'Public authority\n' +
    'Civil society/NGO\n' +
    'Public Hospital\n' +
    'Professional association\n' +
    'Other';

// sectionName, questionName, questionText, dataType, objectApiName, fieldApiName,
// maximumCharacters, responseValues
// Row order IS display order: Sequence__c is reassigned 1..N in this order, and the catalog
// derives section order from the question order (see ApplicationFormCatalogueQueryService).
// responseValues is only set to deliberately narrow a Fixed Select's options; left null, the
// player shows every active value straight from the CRM field's own schema picklist.
// maximumCharacters mirrors the CRM field's length, except where the spec caps it shorter
// (Project title 200, Project description 3000).
List<Object[]> TARGET_ROWS = new List<Object[]>{
    new Object[]{ 'General', 'Research Field', 'Research Field', 'Select',
        'ApplicationForm', 'ProjectTheme__c', null, RESEARCH_FIELD_VALUES },

    new Object[]{ 'Candidate Information', 'Civility', 'Civility', 'Select',
        'Contact', 'Salutation', null, CIVILITY_VALUES },
    new Object[]{ 'Candidate Information', 'Last name', 'Last name', 'Text',
        'Contact', 'LastName', 80, null },
    new Object[]{ 'Candidate Information', 'First name', 'First name', 'Text',
        'Contact', 'FirstName', 40, null },
    new Object[]{ 'Candidate Information', 'Candidate email', 'Candidate email', 'Email',
        'Contact', 'Email', null, null },
    new Object[]{ 'Candidate Information', 'Candidate nationality', 'Candidate nationality', 'Text',
        'Contact', 'Nationality__c', 100, null },
    new Object[]{ 'Candidate Information', 'Birth year', 'Birth year', 'Date',
        'Contact', 'BirthDate', null, null },
    new Object[]{ 'Candidate Information', 'PhD. Date', 'PhD. Date', 'Date',
        'Contact', 'PhdAwardDate__c', null, null },
    // Roles__c is a multi-select picklist, rendered as Select per business request.
    new Object[]{ 'Candidate Information', 'Current affiliation', 'Current affiliation', 'Select',
        'Contact', 'Roles__c', null, AFFILIATION_VALUES },

    new Object[]{ 'Project', 'Project title', 'Project title', 'Text',
        'ApplicationForm', 'Title', 200, null },
    new Object[]{ 'Project', 'Project description', 'Project description', 'TextArea',
        'ApplicationForm', 'ApplicationSummary', 3000, null },
    new Object[]{ 'Project', 'Disciplines involved',
        'Disciplines involved, besides main research field', 'Text',
        'ApplicationForm', 'DisciplinesInvolved__c', 255, null },
    new Object[]{ 'Project', 'Non-academic sectors involved', 'Non-academic sectors involved', 'Select',
        'ApplicationForm', 'NonAcademicSector__c', null, NON_ACADEMIC_SECTOR_VALUES },
    new Object[]{ 'Project', 'Non-academic partner(s)', 'Non-academic partner(s)', 'TextArea',
        'ApplicationForm', 'NonAcademicPartners__c', 32768, null },
    // Files attach via ContentDocumentLink, never mapped to a CRM field: this question is
    // Dynamic. The uploaded file itself is renamed after this label.
    new Object[]{ 'Project', 'CV', 'CV', 'File', null, null, null, null }
};

String KEY_SEPARATOR = '|';
Map<String, Object[]> rowByKey = new Map<String, Object[]>();
Set<String> targetSectionNames = new Set<String>();
for (Object[] row : TARGET_ROWS) {
    String sectionName = (String) row[0];
    String questionName = (String) row[1];
    String key = sectionName + KEY_SEPARATOR + questionName;
    if (rowByKey.containsKey(key)) {
        throw new IllegalArgumentException(
            'Duplicate row in TARGET_ROWS: "' + sectionName + '" / "' + questionName + '".'
        );
    }
    rowByKey.put(key, row);
    targetSectionNames.add(sectionName);
}

// ---- 1) Sections: reuse an existing template Section with the same Name ----
Map<String, Id> sectionIdByName = new Map<String, Id>();
for (AssessmentQuestionSet existingSection : [
    SELECT Id, Name FROM AssessmentQuestionSet
    WHERE Name IN :targetSectionNames AND FundingOpportunity__c = null
    ORDER BY CreatedDate ASC
]) {
    if (!sectionIdByName.containsKey(existingSection.Name)) {
        sectionIdByName.put(existingSection.Name, existingSection.Id);
    }
}
List<AssessmentQuestionSet> sectionsToCreate = new List<AssessmentQuestionSet>();
for (String sectionName : targetSectionNames) {
    if (!sectionIdByName.containsKey(sectionName)) {
        sectionsToCreate.add(new AssessmentQuestionSet(
            Name = sectionName,
            DeveloperName = sectionName.replaceAll('[^a-zA-Z0-9]+', '_').replaceAll('^_+|_+$', '')
        ));
    }
}
if (!sectionsToCreate.isEmpty()) {
    insert sectionsToCreate;
    for (AssessmentQuestionSet createdSection : sectionsToCreate) {
        sectionIdByName.put(createdSection.Name, createdSection.Id);
    }
}

// ---- 2) Inventory the existing EOI template pool, deduped on section|question ----
List<AssessmentQuestionAssignment> currentAssignments = [
    SELECT Id, AssessmentQuestionId, AssessmentQuestionSetId, AssessmentQuestionSet.Name,
        AssessmentQuestion.Name, IsMandatory__c
    FROM AssessmentQuestionAssignment
    WHERE FundingOpportunity__c = null AND Program__c = null AND EOI__c = true
    ORDER BY CreatedDate ASC
];

Map<String, AssessmentQuestionAssignment> assignmentByKey = new Map<String, AssessmentQuestionAssignment>();
List<AssessmentQuestionAssignment> assignmentsToDelete = new List<AssessmentQuestionAssignment>();
for (AssessmentQuestionAssignment assignment : currentAssignments) {
    String assignmentKey = assignment.AssessmentQuestionSet.Name + KEY_SEPARATOR + assignment.AssessmentQuestion.Name;
    if (!rowByKey.containsKey(assignmentKey) || assignmentByKey.containsKey(assignmentKey)) {
        assignmentsToDelete.add(assignment);
        continue;
    }
    assignmentByKey.put(assignmentKey, assignment);
}

// ---- 3) Remove from the pool anything not in TARGET_ROWS (out of spec or a duplicate) ----
Set<Id> obsoleteQuestionIds = new Set<Id>();
for (AssessmentQuestionAssignment assignment : assignmentsToDelete) {
    obsoleteQuestionIds.add(assignment.AssessmentQuestionId);
}
if (!assignmentsToDelete.isEmpty()) {
    delete assignmentsToDelete;
    System.debug('Deleted ' + assignmentsToDelete.size() + ' out-of-spec or duplicate EOI assignment(s).');
}

// A question is only purged once no assignment references it at all: a Funding-Opportunity
// clone points at its own independent question and must never be touched here.
if (!obsoleteQuestionIds.isEmpty()) {
    for (AggregateResult stillAssigned : [
        SELECT AssessmentQuestionId questionId
        FROM AssessmentQuestionAssignment
        WHERE AssessmentQuestionId IN :obsoleteQuestionIds
        GROUP BY AssessmentQuestionId
    ]) {
        obsoleteQuestionIds.remove((Id) stillAssigned.get('questionId'));
    }
}
if (!obsoleteQuestionIds.isEmpty()) {
    // AssessmentQuestionResponse.AssessmentQuestionId points at the *version*, not the question:
    // any test response left on these questions would otherwise block deleting their version.
    Set<Id> obsoleteVersionIds = new Set<Id>();
    for (AssessmentQuestionVersion version : [
        SELECT Id FROM AssessmentQuestionVersion WHERE AssessmentQuestionId IN :obsoleteQuestionIds
    ]) {
        obsoleteVersionIds.add(version.Id);
    }
    if (!obsoleteVersionIds.isEmpty()) {
        List<AssessmentQuestionResponse> obsoleteResponses = [
            SELECT Id FROM AssessmentQuestionResponse WHERE AssessmentQuestionId IN :obsoleteVersionIds
        ];
        if (!obsoleteResponses.isEmpty()) {
            delete obsoleteResponses;
            System.debug('Deleted ' + obsoleteResponses.size() + ' response(s) attached to removed question(s).');
        }
        delete [SELECT Id FROM AssessmentQuestionVersion WHERE Id IN :obsoleteVersionIds];
    }
    delete [SELECT Id FROM AssessmentQuestion WHERE Id IN :obsoleteQuestionIds];
    System.debug('Purged ' + obsoleteQuestionIds.size() + ' question(s) left orphaned.');
}

// ---- 4) Update the questions already present, create the ones that are missing ----
Map<Id, AssessmentQuestion> questionById = new Map<Id, AssessmentQuestion>();
if (!assignmentByKey.isEmpty()) {
    Set<Id> keptQuestionIds = new Set<Id>();
    for (AssessmentQuestionAssignment assignment : assignmentByKey.values()) {
        keptQuestionIds.add(assignment.AssessmentQuestionId);
    }
    questionById = new Map<Id, AssessmentQuestion>([
        SELECT Id, Name, DataType, RecordTypeId, ObjectAPIName__c, FieldAPIName__c,
            MaximumCharacters__c, Sequence__c, isTable__c
        FROM AssessmentQuestion WHERE Id IN :keptQuestionIds
    ]);
}

Long uniqueSuffix = Datetime.now().getTime();
List<AssessmentQuestion> questionsToUpdate = new List<AssessmentQuestion>();
List<AssessmentQuestion> questionsToCreate = new List<AssessmentQuestion>();
List<Object[]> rowsForNewQuestions = new List<Object[]>();

for (Integer index = 0; index < TARGET_ROWS.size(); index++) {
    Object[] row = TARGET_ROWS[index];
    String rowKey = (String) row[0] + KEY_SEPARATOR + (String) row[1];
    // Normalize the DataType exactly as Salesforce expects it, regardless of how it was typed
    // into TARGET_ROWS (e.g. "Multiselect" vs the picklist's actual "MultiSelect" value).
    String targetDataType = (String) row[3];
    if (targetDataType == 'Multiselect') {
        targetDataType = 'MultiSelect';
    }
    Boolean isFixed = row[4] != null;
    Decimal sequence = index + 1;

    AssessmentQuestionAssignment assignment = assignmentByKey.get(rowKey);
    if (assignment == null) {
        questionsToCreate.add(new AssessmentQuestion(
            Name = (String) row[1],
            DeveloperName = ((String) row[1]).replaceAll('[^a-zA-Z0-9]+', '_')
                .replaceAll('^_+|_+$', '').left(60) + 'X' + String.valueOf(uniqueSuffix + index),
            DataType = targetDataType,
            QuestionCategory = 'Demographic',
            isTable__c = false,
            RecordTypeId = isFixed ? fixedRecordTypeId : dynamicRecordTypeId,
            ObjectAPIName__c = (String) row[4],
            FieldAPIName__c = (String) row[5],
            MaximumCharacters__c = (Decimal) row[6],
            Sequence__c = sequence
        ));
        rowsForNewQuestions.add(row);
        continue;
    }

    AssessmentQuestion question = questionById.get(assignment.AssessmentQuestionId);
    question.DataType = targetDataType;
    question.RecordTypeId = isFixed ? fixedRecordTypeId : dynamicRecordTypeId;
    question.ObjectAPIName__c = (String) row[4];
    question.FieldAPIName__c = (String) row[5];
    question.MaximumCharacters__c = (Decimal) row[6];
    question.isTable__c = false;
    question.Sequence__c = sequence;
    questionsToUpdate.add(question);
}

if (!questionsToUpdate.isEmpty()) {
    update questionsToUpdate;
}
if (!questionsToCreate.isEmpty()) {
    insert questionsToCreate;
}

// ---- 5) Versions: the displayed label lives on the version, not the question ----
Map<Id, Object[]> rowByQuestionId = new Map<Id, Object[]>();
for (Integer index = 0; index < questionsToCreate.size(); index++) {
    rowByQuestionId.put(questionsToCreate[index].Id, rowsForNewQuestions[index]);
}
List<AssessmentQuestionVersion> versionsToCreate = new List<AssessmentQuestionVersion>();
for (Id questionId : rowByQuestionId.keySet()) {
    Object[] row = rowByQuestionId.get(questionId);
    versionsToCreate.add(new AssessmentQuestionVersion(
        Name = (String) row[1],
        AssessmentQuestionId = questionId,
        QuestionText = (String) row[2],
        ResponseValues = (String) row[7],
        IsActive = true
    ));
}
if (!versionsToCreate.isEmpty()) {
    insert versionsToCreate;
}

Map<Id, Object[]> rowByExistingQuestionId = new Map<Id, Object[]>();
for (String rowKey : assignmentByKey.keySet()) {
    rowByExistingQuestionId.put(assignmentByKey.get(rowKey).AssessmentQuestionId, rowByKey.get(rowKey));
}
List<AssessmentQuestionVersion> versionsToUpdate = new List<AssessmentQuestionVersion>();
for (AssessmentQuestionVersion version : [
    SELECT Id, AssessmentQuestionId, Name, QuestionText, ResponseValues
    FROM AssessmentQuestionVersion
    WHERE AssessmentQuestionId IN :rowByExistingQuestionId.keySet()
]) {
    Object[] row = rowByExistingQuestionId.get(version.AssessmentQuestionId);
    version.Name = (String) row[1];
    version.QuestionText = (String) row[2];
    version.ResponseValues = (String) row[7];
    versionsToUpdate.add(version);
}
if (!versionsToUpdate.isEmpty()) {
    update versionsToUpdate;
}

// ---- 6) Assignments: attach each question to its target section ----
List<AssessmentQuestionAssignment> assignmentsToCreate = new List<AssessmentQuestionAssignment>();
for (Id questionId : rowByQuestionId.keySet()) {
    Object[] row = rowByQuestionId.get(questionId);
    assignmentsToCreate.add(new AssessmentQuestionAssignment(
        AssessmentQuestionId = questionId,
        AssessmentQuestionSetId = sectionIdByName.get((String) row[0]),
        FundingOpportunity__c = null,
        Program__c = null,
        EOI__c = true,
        // Preconfigured questions default to mandatory (US-030); none of these rows are
        // "If Applicable".
        IsMandatory__c = true
    ));
}
if (!assignmentsToCreate.isEmpty()) {
    insert assignmentsToCreate;
}

List<AssessmentQuestionAssignment> assignmentsToUpdate = new List<AssessmentQuestionAssignment>();
for (String rowKey : assignmentByKey.keySet()) {
    Object[] row = rowByKey.get(rowKey);
    AssessmentQuestionAssignment assignment = assignmentByKey.get(rowKey);
    Id targetSectionId = sectionIdByName.get((String) row[0]);
    if (assignment.AssessmentQuestionSetId != targetSectionId || assignment.IsMandatory__c != true) {
        assignment.AssessmentQuestionSetId = targetSectionId;
        assignment.IsMandatory__c = true;
        assignmentsToUpdate.add(assignment);
    }
}
if (!assignmentsToUpdate.isEmpty()) {
    update assignmentsToUpdate;
}

// ---- 7) Delete template Sections left empty by the cleanup above ----
Set<Id> emptySectionIds = new Set<Id>();
for (AssessmentQuestionSet section : [
    SELECT Id FROM AssessmentQuestionSet WHERE FundingOpportunity__c = null
]) {
    emptySectionIds.add(section.Id);
}
for (AggregateResult usedSection : [
    SELECT AssessmentQuestionSetId sectionId
    FROM AssessmentQuestionAssignment
    WHERE AssessmentQuestionSetId IN :emptySectionIds
    GROUP BY AssessmentQuestionSetId
]) {
    emptySectionIds.remove((Id) usedSection.get('sectionId'));
}
if (!emptySectionIds.isEmpty()) {
    delete [SELECT Id FROM AssessmentQuestionSet WHERE Id IN :emptySectionIds];
    System.debug('Deleted ' + emptySectionIds.size() + ' template section(s) left empty by the cleanup.');
}

System.debug('EOI Common Core template synced: ' + questionsToCreate.size() + ' created, '
    + questionsToUpdate.size() + ' updated, ' + TARGET_ROWS.size() + ' total.');
