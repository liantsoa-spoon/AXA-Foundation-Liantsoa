Id fixedRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'AssessmentQuestion' AND DeveloperName = 'Fixed' LIMIT 1].Id;
Id dynamicRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'AssessmentQuestion' AND DeveloperName = 'Dynamic' LIMIT 1].Id;

String SALUTATION_VALUES = 'Mr.\nMs.\nMrs.\nN/A';
String GENDER_VALUES = 'Male\nFemale\nNon-binary\nPrefer not to say';
String COUNTRY_VALUES = 'France\nOutside France\nNon applicable';
String FISCAL_DOMAIN_VALUES = 'Humanitaire\nActions sociales\nScientifique\nNature\nCulture';
String BENEFICIARY_VALUES = 'Legal Person\nNatural Person';

List<Object[]> TARGET_ROWS = new List<Object[]>{
    new Object[]{ 'Host organization', 'Prior AXA support', 'Has this researcher already been supported by AXA?', 'TextArea', null, null, 300, null },
    new Object[]{ 'Applicant identity', 'Salutation', 'Salutation', 'Select', 'Contact', 'Salutation', null, SALUTATION_VALUES },
    new Object[]{ 'Applicant identity', 'First name', 'First name', 'Text', 'Contact', 'FirstName', 40, null },
    new Object[]{ 'Applicant identity', 'Last name', 'Last name', 'Text', 'Contact', 'LastName', 80, null },
    new Object[]{ 'Applicant identity', 'Title', 'Position / Title', 'Text', 'Contact', 'Title', 128, null },
    new Object[]{ 'Applicant identity', 'Birth name', 'Birth name (if applicable)', 'Text', 'Contact', 'BirthName__c', 255, null },
    new Object[]{ 'Applicant identity', 'Birth date', 'Date of birth', 'Date', 'Contact', 'Birthdate', null, null },
    new Object[]{ 'Applicant identity', 'Email', 'Email', 'Email', 'Contact', 'Email', null, null },
    new Object[]{ 'Applicant identity', 'Gender identity', 'Gender', 'Select', 'Contact', 'GenderIdentity', null, GENDER_VALUES },
    new Object[]{ 'Applicant identity', 'PhD award date', 'PhD date', 'Date', 'Contact', 'PhdAwardDate__c', null, null },
    new Object[]{ 'Applicant identity', 'Nationality', 'Citizenship', 'Text', 'Contact', 'Nationality__c', 100, null },
    new Object[]{ 'Project overview', 'Project name', 'Project name:', 'Text', 'ApplicationForm', 'Title', 255, null },
    new Object[]{ 'Project overview', 'Project start date', 'Project start date:', 'Date', 'ApplicationForm', 'ProjectStartDate__c', null, null },
    new Object[]{ 'Project overview', 'Project duration', 'Project duration:', 'Text', 'ApplicationForm', 'ProjectDuration__c', 100, null },
    new Object[]{ 'Project overview', 'Where does your project take place?', 'Where does your project take place?', 'MultiSelect', 'ApplicationForm', 'ProjectCountry__c', null, COUNTRY_VALUES },
    new Object[]{ 'Project overview', 'Which fiscal domain does your project contribute to ?', 'Which fiscal domain does your project contribute to ?', 'Radio', 'ApplicationForm', 'FiscalDomain__c', null, FISCAL_DOMAIN_VALUES },
    new Object[]{ 'Project overview', 'What are the objectives of the project?', 'What are the objectives of the project?', 'TextArea', null, null, 1500, null },
    new Object[]{ 'Project overview', 'Concise, plain-language summary of the project', 'Concise, plain-language summary of the project:', 'TextArea', 'ApplicationForm', 'ApplicationSummary', 500, null },
    new Object[]{ 'Project overview', 'Detailed description of the project', 'Detailed description of the project:', 'TextArea', null, null, 3500, null },
    new Object[]{ 'Project overview', 'Project originality and innovation', 'What is the originality and/or innovative nature of your project?', 'TextArea', null, null, 1000, null },
    new Object[]{ 'Project overview', 'Complementarity with existing initiatives', 'To your knowledge, what other existing initiatives / programs address this topic?', 'TextArea', null, null, 1000, null },
    new Object[]{ 'Project overview', 'Obstacles and solutions', 'What potential obstacles to the project\'s deployment have you identified?', 'TextArea', null, null, 1500, null },
    new Object[]{ 'Project overview', 'Main operational partners', 'Who are the main operational partners of the project? (if any):', 'TextArea', 'ApplicationForm', 'MainOperationalPartners__c', 500, null },
    new Object[]{ 'Project overview', 'Collaboration with other actors', 'Is this project developed in collaboration with other public, private or nonprofit actors?', 'TextArea', 'ApplicationForm', 'PartnerOrganisations__c', 500, null },
    new Object[]{ 'Project overview', 'Expected project impacts', 'What impacts are expected from the project?', 'TextArea', null, null, 1500, null },
    new Object[]{ 'Project overview', 'Leverage effect of AXA support', 'How does AXA\'s support act as a lever to strengthen or accelerate this impact?', 'TextArea', null, null, 500, null },
    new Object[]{ 'Project overview', 'Project sustainability', 'If supported, how do you envisage the project\'s sustainability beyond the AXA Foundation\'s funding?', 'TextArea', null, null, 1000, null },
    new Object[]{ 'Project overview', 'Beneficiary type', 'Is the beneficiary of the agreement a Legal person or a Natural person?', 'Radio', 'ApplicationForm', 'BeneficiaryType__c', null, BENEFICIARY_VALUES },
    new Object[]{ 'Project overview', 'Redistribution of funds', 'Do you intent to redistribute the allocated funds?', 'TextArea', 'ApplicationForm', 'SubsidiaryRedistribution__c', 1500, null },
    new Object[]{ 'Project overview', 'Conflict of interest declaration', 'Do you know of any conflict of interest?', 'TextArea', 'ApplicationForm', 'PotentialConflictOfInterest__c', 1000, null },
    new Object[]{ 'Project overview', 'AXA initiator and rationale', 'Please indicate the full name and position of the person who proposed the initiative', 'Text', 'ApplicationForm', 'AXAInitiatorAndRationale__c', 255, null },
    new Object[]{ 'Project budget', 'Total project budget (in euros)', 'Total project budget (in euros):', 'Currency', 'Budget', 'Amount', null, null },
    new Object[]{ 'Project budget', 'Budget requested', 'Budget requested from the AXA Foundation:', 'Currency', 'ApplicationForm', 'RequestedAmount', null, null },
    new Object[]{ 'Monitoring and evaluation', 'Monitoring and evaluation plan', 'How do you plan to monitor and evaluate the project\'s implementation?', 'TextArea', null, null, 1000, null },
    new Object[]{ 'Communication', 'Communication plan', 'What communication actions are planned around the project?', 'TextArea', null, null, 1500, null },
    new Object[]{ 'Supporting documents', 'Founding document of the organization', 'Founding document of the organization', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Prefecture declaration', 'Prefecture declaration', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Latest activity reports', 'Last 2 activity reports', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Latest financial reports', 'Last 2 financial reports', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Bank details (Bank details / RIB / IBAN)', 'Bank details', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Copy of top executive payslips', 'Copy of top executive payslips', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Minutes of General Assemblies/Board', 'Minutes of the latest General Assemblies', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Tax ruling', 'Tax ruling', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Tax scheme eligibility certificate', 'Certificate or any other official document', 'File', null, null, null, null },
    new Object[]{ 'Supporting documents', 'Your Upload the picture of the project holder', 'Your Upload the picture of the project holder', 'File', null, null, null, null },
    new Object[]{ 'Form submission', 'Deontology chart alignment', 'Do you align with AXA\'s Foundation deontology chart ?', 'Checkbox', null, null, null, null }
};

String KEY_SEPARATOR = '|';
Map<String, Object[]> rowByKey = new Map<String, Object[]>();
Set<String> targetSectionNames = new Set<String>();
for (Object[] row : TARGET_ROWS) {
    rowByKey.put((String) row[0] + KEY_SEPARATOR + (String) row[1], row);
    targetSectionNames.add((String) row[0]);
}

Map<String, Id> sectionIdByName = new Map<String, Id>();
for (AssessmentQuestionSet existingSection : [SELECT Id, Name FROM AssessmentQuestionSet WHERE Name IN :targetSectionNames AND FundingOpportunity__c = null]) {
    sectionIdByName.put(existingSection.Name, existingSection.Id);
}

List<AssessmentQuestionSet> sectionsToCreate = new List<AssessmentQuestionSet>();
for (String sectionName : targetSectionNames) {
    if (!sectionIdByName.containsKey(sectionName)) {
        sectionsToCreate.add(new AssessmentQuestionSet(Name = sectionName, DeveloperName = sectionName.replaceAll('[^a-zA-Z0-9]+', '_').replaceAll('^_+|_+$', '')));
    }
}
if (!sectionsToCreate.isEmpty()) {
    insert sectionsToCreate;
    for (AssessmentQuestionSet createdSection : sectionsToCreate) sectionIdByName.put(createdSection.Name, createdSection.Id);
}

List<AssessmentQuestionAssignment> currentAssignments = [
    SELECT Id, AssessmentQuestionId, AssessmentQuestionSetId, AssessmentQuestionSet.Name, AssessmentQuestion.Name, IsMandatory__c 
    FROM AssessmentQuestionAssignment WHERE FundingOpportunity__c = null AND Program__c = null AND EOI__c = false
];

Map<String, AssessmentQuestionAssignment> assignmentByKey = new Map<String, AssessmentQuestionAssignment>();
List<AssessmentQuestionAssignment> assignmentsToDelete = new List<AssessmentQuestionAssignment>();
for (AssessmentQuestionAssignment assignment : currentAssignments) {
    String assignmentKey = assignment.AssessmentQuestionSet.Name + KEY_SEPARATOR + assignment.AssessmentQuestion.Name;
    if (!rowByKey.containsKey(assignmentKey) || assignmentByKey.containsKey(assignmentKey)) assignmentsToDelete.add(assignment);
    else assignmentByKey.put(assignmentKey, assignment);
}

Set<Id> obsoleteQuestionIds = new Set<Id>();
for (AssessmentQuestionAssignment assignment : assignmentsToDelete) obsoleteQuestionIds.add(assignment.AssessmentQuestionId);
if (!assignmentsToDelete.isEmpty()) delete assignmentsToDelete;

if (!obsoleteQuestionIds.isEmpty()) {
    for (AggregateResult stillAssigned : [SELECT AssessmentQuestionId questionId FROM AssessmentQuestionAssignment WHERE AssessmentQuestionId IN :obsoleteQuestionIds GROUP BY AssessmentQuestionId]) {
        obsoleteQuestionIds.remove((Id) stillAssigned.get('questionId'));
    }
}
if (!obsoleteQuestionIds.isEmpty()) {
    Set<Id> obsoleteVersionIds = new Set<Id>();
    for (AssessmentQuestionVersion version : [SELECT Id FROM AssessmentQuestionVersion WHERE AssessmentQuestionId IN :obsoleteQuestionIds]) obsoleteVersionIds.add(version.Id);
    if (!obsoleteVersionIds.isEmpty()) {
        delete [SELECT Id FROM AssessmentQuestionResponse WHERE AssessmentQuestionId IN :obsoleteVersionIds];
        delete [SELECT Id FROM AssessmentQuestionVersion WHERE Id IN :obsoleteVersionIds];
    }
    delete [SELECT Id FROM AssessmentQuestion WHERE Id IN :obsoleteQuestionIds];
}

Map<Id, AssessmentQuestion> questionById = new Map<Id, AssessmentQuestion>();
if (!assignmentByKey.isEmpty()) {
    Set<Id> keptQuestionIds = new Set<Id>();
    for (AssessmentQuestionAssignment assignment : assignmentByKey.values()) keptQuestionIds.add(assignment.AssessmentQuestionId);
    questionById = new Map<Id, AssessmentQuestion>([SELECT Id, Name, DataType, RecordTypeId, ObjectAPIName__c, FieldAPIName__c, MaximumCharacters__c, Sequence__c, isTable__c FROM AssessmentQuestion WHERE Id IN :keptQuestionIds]);
}

Long uniqueSuffix = Datetime.now().getTime();
List<AssessmentQuestion> questionsToUpdate = new List<AssessmentQuestion>();
List<AssessmentQuestion> questionsToCreate = new List<AssessmentQuestion>();
List<Object[]> rowsForNewQuestions = new List<Object[]>();

for (Integer index = 0; index < TARGET_ROWS.size(); index++) {
    Object[] row = TARGET_ROWS[index];
    String rowKey = (String) row[0] + KEY_SEPARATOR + (String) row[1];
    Boolean isFixed = row[4] != null;
    Decimal sequence = index + 1;
    AssessmentQuestionAssignment assignment = assignmentByKey.get(rowKey);
    
    // Normalize Data Type exactly as Salesforce expects it
    String targetDataType = (String) row[3];
    if (targetDataType == 'Multiselect') targetDataType = 'MultiSelect';

    if (assignment == null) {
        questionsToCreate.add(new AssessmentQuestion(
            Name = (String) row[1],
            DeveloperName = ((String) row[1]).replaceAll('[^a-zA-Z0-9]+', '_').replaceAll('^_+|_+$', '').left(60) + 'X' + String.valueOf(uniqueSuffix + index),
            DataType = targetDataType,
            QuestionCategory = 'Custom AXA',
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

// 1. DML: Process Questions
if (!questionsToUpdate.isEmpty()) update questionsToUpdate;
if (!questionsToCreate.isEmpty()) insert questionsToCreate;

Map<Id, Object[]> rowByQuestionId = new Map<Id, Object[]>();
for (Integer index = 0; index < questionsToCreate.size(); index++) {
    rowByQuestionId.put(questionsToCreate[index].Id, rowsForNewQuestions[index]);
}

// 2. DML: Prepare Versions with strict AGGRESSIVE FAILS-SAFE logic for OmniStudio
List<AssessmentQuestionVersion> versionsToCreate = new List<AssessmentQuestionVersion>();
for (Id questionId : rowByQuestionId.keySet()) {
    Object[] row = rowByQuestionId.get(questionId);
    String dt = (String) row[3];
    String rv = (String) row[7];
    
    // THE FAILSAFE: If it is any Picklist type and it evaluates to null, aggressively force a value
    if ((dt == 'Select' || dt == 'Radio' || dt == 'MultiSelect' || dt == 'Multiselect') && String.isBlank(rv)) {
        rv = 'N/A\nOther';
    }

    versionsToCreate.add(new AssessmentQuestionVersion(
        Name = (String) row[1], 
        AssessmentQuestionId = questionId, 
        QuestionText = (String) row[2], 
        ResponseValues = rv, 
        IsActive = false
    ));
}
if (!versionsToCreate.isEmpty()) insert versionsToCreate;

// 3. DML: Update existing versions with same strict logic
Map<Id, Object[]> rowByExistingQuestionId = new Map<Id, Object[]>();
for (String rowKey : assignmentByKey.keySet()) rowByExistingQuestionId.put(assignmentByKey.get(rowKey).AssessmentQuestionId, rowByKey.get(rowKey));

List<AssessmentQuestionVersion> versionsToUpdate = new List<AssessmentQuestionVersion>();
for (AssessmentQuestionVersion version : [SELECT Id, AssessmentQuestionId, Name, QuestionText, ResponseValues FROM AssessmentQuestionVersion WHERE AssessmentQuestionId IN :rowByExistingQuestionId.keySet()]) {
    Object[] row = rowByExistingQuestionId.get(version.AssessmentQuestionId);
    String dt = (String) row[3];
    String rv = (String) row[7];
    
    // THE FAILSAFE
    if ((dt == 'Select' || dt == 'Radio' || dt == 'MultiSelect' || dt == 'Multiselect') && String.isBlank(rv)) {
        rv = 'N/A\nOther';
    }

    version.Name = (String) row[1];
    version.QuestionText = (String) row[2];
    version.ResponseValues = rv;
    versionsToUpdate.add(version);
}
if (!versionsToUpdate.isEmpty()) update versionsToUpdate;

// 4. DML: Attach Assignments
List<AssessmentQuestionAssignment> assignmentsToCreate = new List<AssessmentQuestionAssignment>();
for (Id questionId : rowByQuestionId.keySet()) {
    Object[] row = rowByQuestionId.get(questionId);
    assignmentsToCreate.add(new AssessmentQuestionAssignment(
        AssessmentQuestionId = questionId, AssessmentQuestionSetId = sectionIdByName.get((String) row[0]),
        FundingOpportunity__c = null, Program__c = null, EOI__c = false, IsMandatory__c = true
    ));
}
if (!assignmentsToCreate.isEmpty()) insert assignmentsToCreate;

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
if (!assignmentsToUpdate.isEmpty()) update assignmentsToUpdate;

Set<Id> emptySectionIds = new Set<Id>();
for (AssessmentQuestionSet section : [SELECT Id FROM AssessmentQuestionSet WHERE FundingOpportunity__c = null]) emptySectionIds.add(section.Id);
for (AggregateResult usedSection : [SELECT AssessmentQuestionSetId sectionId FROM AssessmentQuestionAssignment WHERE AssessmentQuestionSetId IN :emptySectionIds GROUP BY AssessmentQuestionSetId]) emptySectionIds.remove((Id) usedSection.get('sectionId'));
if (!emptySectionIds.isEmpty()) delete [SELECT Id FROM AssessmentQuestionSet WHERE Id IN :emptySectionIds];