/**
 * Seeds the Common Core / EOI template pool with the "Candidate Information" and "Project"
 * sections shown in the spec screenshot. All rows are templates (FundingOpportunity__c = null,
 * Program__c = null => Common Core, valid for every Pillar) flagged EOI__c = true so they show up
 * in the short Expression of Interest form (lwc02ApplicationFormPlayer with eoi = true).
 *
 * Safe to re-run: it skips any Section/Question whose Name already exists as a template.
 */

Id fixedRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'AssessmentQuestion' AND DeveloperName = 'Fixed' LIMIT 1].Id;
Id dynamicRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'AssessmentQuestion' AND DeveloperName = 'Dynamic' LIMIT 1].Id;

// name, dataType, objectApiName, fieldApiName, questionText, sectionName, isFixed, responseValues
// responseValues is only set for a Fixed picklist question whose form options must be a
// deliberately narrowed subset of the CRM field's own schema picklist (see
// AP02_ApplicationFormPlayerController.getFormDefinition: a static Response Values list always
// wins over the field's full schema picklist). Left null, a Select/Multiselect/RadioGroup Fixed
// question instead shows every active value straight from the CRM field's schema.
// Section display order for the EOI player (see the reordering step at the bottom of this
// script): General always comes first, ahead of Candidate Information and Project.
List<String> SECTION_ORDER = new List<String>{ 'General', 'Candidate Information', 'Project' };

List<Object[]> rows = new List<Object[]>{
    // Salutation is a standard Contact picklist; rendered as Select, its full active value set is
    // pulled dynamically from the schema (responseValues = null), same mechanism as Roles__c below.
    new Object[]{ 'Civility', 'Select', 'Contact', 'Salutation', 'Civility', 'Candidate Information', true, null },
    new Object[]{ 'Last name', 'Text', 'Contact', 'LastName', 'Last name', 'Candidate Information', true, null },
    new Object[]{ 'First name', 'Text', 'Contact', 'FirstName', 'First name', 'Candidate Information', true, null },
    new Object[]{ 'Candidate email', 'Email', 'Contact', 'Email', 'Candidate email', 'Candidate Information', true, null },
    new Object[]{ 'Candidate nationality', 'Text', 'Contact', 'Nationality__c', 'Candidate nationality', 'Candidate Information', true, null },
    new Object[]{ 'Birth year', 'Date', 'Contact', 'BirthDate', 'Birth year', 'Candidate Information', true, null },
    new Object[]{ 'PhD. Date', 'Date', 'Contact', 'PhdAwardDate__c', 'PhD. Date', 'Candidate Information', true, null },
    // Roles__c is a MultiselectPicklist (Contact_Role value set); rendered as Select per business
    // request, its full active value set is pulled dynamically from the schema (responseValues = null).
    new Object[]{ 'Current affiliation', 'Select', 'Contact', 'Roles__c', 'Current affiliation', 'Candidate Information', true, null },
    new Object[]{ 'Project title', 'Text', 'ApplicationForm', 'Title', 'Project title (200 characters max)', 'Project', true, null },
    new Object[]{ 'Project description', 'TextArea', 'ApplicationForm', 'ApplicationSummary', 'Project description (3000 characters max)', 'Project', true, null },
    new Object[]{ 'Non-academic partner(s)', 'TextArea', 'ApplicationForm', 'NonAcademicPartners__c', 'Non-academic partner(s)', 'Project', true, null },
    // File uploads attach directly via ContentDocumentLink (see AP02_ApplicationFormPlayerController's
    // populateExistingFiles) — never mapped to a CRM field, so this one is Dynamic, not Fixed.
    // Named "CV" (not "Add CV") since the uploaded file itself is auto-renamed from this label.
    new Object[]{ 'CV', 'File', null, null, 'CV', 'Project', false, null },
    // ProjectTheme__c's restricted picklist (Project_Theme value set) has ~20 values; only these 4
    // are offered here, so the static Response Values list below is required (see comment above).
    new Object[]{
        'Research Field', 'Select', 'ApplicationForm', 'ProjectTheme__c', 'Research Field', 'General', true,
        'Risk to People and Well-Being, France\nRisk to People and Well-Being, Outside France\nRisk to the Planet\nRisk to Societies'
    }
};

// ---- 0) Rename "Add CV" to "CV" if it was already seeded under the old name, BEFORE the
// existing-question-name check below (otherwise it wouldn't recognize the "CV" row as already
// seeded and would insert a duplicate question) ----
List<AssessmentQuestion> addCvQuestions = [
    SELECT Id, Name
    FROM AssessmentQuestion
    WHERE Name = 'Add CV'
    AND Id IN (
        SELECT AssessmentQuestionId FROM AssessmentQuestionAssignment
        WHERE FundingOpportunity__c = null AND Program__c = null AND EOI__c = true
    )
];
if (!addCvQuestions.isEmpty()) {
    Set<Id> addCvQuestionIds = new Set<Id>();
    for (AssessmentQuestion q : addCvQuestions) {
        q.Name = 'CV';
        addCvQuestionIds.add(q.Id);
    }
    update addCvQuestions;
    List<AssessmentQuestionVersion> addCvVersions = [
        SELECT Id, Name, QuestionText
        FROM AssessmentQuestionVersion
        WHERE AssessmentQuestionId IN :addCvQuestionIds
    ];
    for (AssessmentQuestionVersion v : addCvVersions) {
        v.Name = 'CV';
        v.QuestionText = 'CV';
    }
    update addCvVersions;
    System.debug('Renamed ' + addCvQuestions.size() + ' "Add CV" question(s) to "CV".');
}

// ---- 1) Sections (reuse if a template section with the same Name already exists) ----
Set<String> sectionNames = new Set<String>();
for (Object[] row : rows) {
    sectionNames.add((String) row[5]);
}
Map<String, Id> sectionIdByName = new Map<String, Id>();
for (AssessmentQuestionSet existing : [
    SELECT Id, Name FROM AssessmentQuestionSet
    WHERE Name IN :sectionNames AND FundingOpportunity__c = null
]) {
    sectionIdByName.put(existing.Name, existing.Id);
}
List<AssessmentQuestionSet> newSections = new List<AssessmentQuestionSet>();
for (String sectionName : sectionNames) {
    if (!sectionIdByName.containsKey(sectionName)) {
        newSections.add(new AssessmentQuestionSet(
            Name = sectionName,
            DeveloperName = sectionName.replaceAll('[^a-zA-Z0-9]+', '_').replaceAll('^_+|_+$', '')
        ));
    }
}
if (!newSections.isEmpty()) {
    insert newSections;
    for (AssessmentQuestionSet s : newSections) {
        sectionIdByName.put(s.Name, s.Id);
    }
}

// ---- 2) Questions + Versions + Assignments (skip a row if that Question name already exists as a template) ----
Set<String> questionNames = new Set<String>();
for (Object[] row : rows) {
    questionNames.add((String) row[0]);
}
Set<String> existingQuestionNames = new Set<String>();
for (AssessmentQuestionAssignment aqa : [
    SELECT AssessmentQuestion.Name
    FROM AssessmentQuestionAssignment
    WHERE FundingOpportunity__c = null AND Program__c = null AND AssessmentQuestion.Name IN :questionNames
]) {
    existingQuestionNames.add(aqa.AssessmentQuestion.Name);
}

List<Object[]> rowsToInsert = new List<Object[]>();
for (Object[] row : rows) {
    if (!existingQuestionNames.contains((String) row[0])) {
        rowsToInsert.add(row);
    }
}

if (rowsToInsert.isEmpty()) {
    System.debug('Nothing to insert: every question already exists as a Common Core/EOI template.');
} else {
    // Continue numbering after whatever's already in the pool, so re-running this script to add
    // a new row appends it at the end instead of resetting everything back to Sequence__c = 1.
    Decimal maxExistingSequence = 0;
    for (AggregateResult ar : [
        SELECT MAX(Sequence__c) maxSeq
        FROM AssessmentQuestion
        WHERE Id IN (
            SELECT AssessmentQuestionId FROM AssessmentQuestionAssignment
            WHERE FundingOpportunity__c = null AND Program__c = null AND EOI__c = true
        )
    ]) {
        Object maxSeq = ar.get('maxSeq');
        if (maxSeq != null) {
            maxExistingSequence = (Decimal) maxSeq;
        }
    }

    List<AssessmentQuestion> newQuestions = new List<AssessmentQuestion>();
    for (Integer i = 0; i < rowsToInsert.size(); i++) {
        Object[] row = rowsToInsert[i];
        Boolean isFixed = (Boolean) row[6];
        newQuestions.add(new AssessmentQuestion(
            Name = (String) row[0],
            DeveloperName = ((String) row[0]).replaceAll('[^a-zA-Z0-9]+', '_').replaceAll('^_+|_+$', ''),
            DataType = (String) row[1],
            QuestionCategory = 'Demographic',
            isTable__c = false,
            RecordTypeId = isFixed ? fixedRecordTypeId : dynamicRecordTypeId,
            ObjectAPIName__c = (String) row[2],
            FieldAPIName__c = (String) row[3],
            Sequence__c = maxExistingSequence + i + 1
        ));
    }
    insert newQuestions;

    List<AssessmentQuestionVersion> newVersions = new List<AssessmentQuestionVersion>();
    for (Integer i = 0; i < rowsToInsert.size(); i++) {
        Object[] row = rowsToInsert[i];
        newVersions.add(new AssessmentQuestionVersion(
            Name = (String) row[0],
            AssessmentQuestionId = newQuestions[i].Id,
            QuestionText = (String) row[4],
            ResponseValues = (String) row[7],
            IsActive = false
        ));
    }
    insert newVersions;

    List<AssessmentQuestionAssignment> newAssignments = new List<AssessmentQuestionAssignment>();
    for (Integer i = 0; i < rowsToInsert.size(); i++) {
        Object[] row = rowsToInsert[i];
        newAssignments.add(new AssessmentQuestionAssignment(
            AssessmentQuestionId = newQuestions[i].Id,
            AssessmentQuestionSetId = sectionIdByName.get((String) row[5]),
            FundingOpportunity__c = null,
            Program__c = null,
            EOI__c = true,
            // Pre-configured questions (mapped to a Salesforce field, or not) are mandatory by
            // default per US-030; none of this seed's rows are tagged "If Applicable".
            IsMandatory__c = true
        ));
    }
    insert newAssignments;

    System.debug('Inserted ' + newQuestions.size() + ' EOI/Common Core template questions.');
}

// ---- 3) Fix up questions already seeded as Text before they were switched to Select (dynamic
// schema picklist values) — currently Civility (Salutation) and Current affiliation (Roles__c) ----
Set<String> selectQuestionNames = new Set<String>{ 'Civility', 'Current affiliation' };
List<AssessmentQuestion> questionsToSwitchToSelect = [
    SELECT Id, DataType
    FROM AssessmentQuestion
    WHERE Name IN :selectQuestionNames AND DataType != 'Select'
    AND Id IN (
        SELECT AssessmentQuestionId FROM AssessmentQuestionAssignment
        WHERE FundingOpportunity__c = null AND Program__c = null AND EOI__c = true
    )
];
if (!questionsToSwitchToSelect.isEmpty()) {
    for (AssessmentQuestion q : questionsToSwitchToSelect) {
        q.DataType = 'Select';
    }
    update questionsToSwitchToSelect;
    System.debug('Switched ' + questionsToSwitchToSelect.size() + ' question(s) to Select.');
}

// ---- 4) Reorder sections so the player always shows them in SECTION_ORDER, regardless of when
// each section's questions were seeded (section order is driven purely by the ordering of
// AssessmentQuestion.Sequence__c across all sections — see AP01_CatalogQueryService). Renumbers
// every EOI Common Core question, grouping by section in SECTION_ORDER while preserving each
// section's existing relative question order. ----
List<AssessmentQuestionAssignment> allEoiAssignments = [
    SELECT AssessmentQuestionId, AssessmentQuestionSet.Name, AssessmentQuestion.Sequence__c
    FROM AssessmentQuestionAssignment
    WHERE FundingOpportunity__c = null AND Program__c = null AND EOI__c = true
];
Map<String, List<AssessmentQuestionAssignment>> assignmentsBySectionName = new Map<String, List<AssessmentQuestionAssignment>>();
for (AssessmentQuestionAssignment aqa : allEoiAssignments) {
    String sectionName = aqa.AssessmentQuestionSet.Name;
    if (!assignmentsBySectionName.containsKey(sectionName)) {
        assignmentsBySectionName.put(sectionName, new List<AssessmentQuestionAssignment>());
    }
    assignmentsBySectionName.get(sectionName).add(aqa);
}
List<String> orderedSectionNames = new List<String>(SECTION_ORDER);
for (String sectionName : assignmentsBySectionName.keySet()) {
    if (!orderedSectionNames.contains(sectionName)) {
        orderedSectionNames.add(sectionName);
    }
}

List<AssessmentQuestion> questionsToRenumber = new List<AssessmentQuestion>();
Decimal nextSequence = 1;
for (String sectionName : orderedSectionNames) {
    List<AssessmentQuestionAssignment> sectionAssignments = assignmentsBySectionName.get(sectionName);
    if (sectionAssignments == null) {
        continue;
    }
    // Small lists (a handful of questions per section): plain insertion sort by the question's
    // current Sequence__c, ascending, avoiding any ambiguity around List.sort()'s default
    // ordering for sObjects.
    for (Integer i = 1; i < sectionAssignments.size(); i++) {
        AssessmentQuestionAssignment current = sectionAssignments[i];
        Integer j = i - 1;
        while (j >= 0 && sectionAssignments[j].AssessmentQuestion.Sequence__c > current.AssessmentQuestion.Sequence__c) {
            sectionAssignments[j + 1] = sectionAssignments[j];
            j--;
        }
        sectionAssignments[j + 1] = current;
    }
    for (AssessmentQuestionAssignment aqa : sectionAssignments) {
        questionsToRenumber.add(new AssessmentQuestion(Id = aqa.AssessmentQuestionId, Sequence__c = nextSequence));
        nextSequence += 1;
    }
}
if (!questionsToRenumber.isEmpty()) {
    update questionsToRenumber;
    System.debug('Reordered ' + questionsToRenumber.size() + ' EOI Common Core questions per SECTION_ORDER.');
}
