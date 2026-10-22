/**
 * Crée la section "Project budget" et les questions-colonnes des deux tableaux budget sur UNE Funding
 * Opportunity de test, pour tester le rendu de applicationFormBudgetTable.
 *
 * Les versions restent en Draft (IsActive = false) : une question dont la version a été activée ne peut plus
 * être supprimée par la plateforme (voir ApplicationFormLifecycleService.purgeOrphanedDraftQuestions). Le
 * script deleteBudgetTableQuestions.apex supprime tout ce que celui-ci crée.
 *
 * Une colonne = une AssessmentQuestion Dynamic, non EOI, dont ObjectAPIName__c / FieldAPIName__c indiquent
 * où la valeur est enregistrée. Un tableau commence à sa colonne BudgetCategory.Name ; le Name de cette
 * question est la clé du tableau, configurée dans ApplicationFormBudgetService.CONFIG_BY_TABLE_KEY.
 *
 * La section "Project budget" existante de la Funding Opportunity est réutilisée (elle porte déjà les questions
 * Fixed du budget total et du montant demandé) : les colonnes sont ajoutées après ses questions. Elle n'est
 * créée que si elle n'existe pas.
 *
 * Relançable : s'arrête si les colonnes existent déjà sur la Funding Opportunity.
 */

final Id FUNDING_OPPORTUNITY_ID = '119KK0000000110YAA';
final String SECTION_NAME = 'Project budget';
final Boolean DRY_RUN = false;

// name, questionText (EN), questionText (FR), dataType, objectApiName, fieldApiName[, responseValues, responseValues FR]
final List<String[]> COLUMNS = new List<String[]>{
  // Tableau 1 : dépenses (clé "Budget Item Name" : totaux, sans pourcentage)
  new String[]{ 'Budget Item Name', 'Item Name', 'Poste de dépense', 'Text', 'BudgetCategory', 'Name' },
  new String[]{ 'Budget Item Year 1', 'Year 1', 'Année 1', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Item Year 2', 'Year 2', 'Année 2', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Item Year 3', 'Year 3', 'Année 3', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Item Year 4', 'Year 4', 'Année 4', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Item Year 5', 'Year 5', 'Année 5', 'Currency', 'BudgetCategoryValue', 'Amount' },
  // Tableau 2 : budget demandé à la Fondation AXA (clé "Budget Requested Name" : totaux, sans pourcentage)
  new String[]{ 'Budget Requested Name', 'Cost item', 'Poste de coût', 'Text', 'BudgetCategory', 'Name' },
  new String[]{ 'Budget Requested Year 1', 'Year 1', 'Année 1', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Requested Year 2', 'Year 2', 'Année 2', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Requested Year 3', 'Year 3', 'Année 3', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Requested Year 4', 'Year 4', 'Année 4', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Requested Year 5', 'Year 5', 'Année 5', 'Currency', 'BudgetCategoryValue', 'Amount' },
  // Tableau 3 : financeurs (clé "Budget Funder Name" : totaux et pourcentages). Les ResponseValues, obligatoires
  // sur une version Select, reprennent les valeurs des global value sets BudgetFundingStatus et BudgetFundingType.
  new String[]{ 'Budget Funder Name', 'Name', 'Nom', 'Text', 'BudgetCategory', 'Name' },
  new String[]{ 'Budget Funder Status', 'Secured or planned', 'Sécurisé ou prévu', 'Select', 'BudgetCategoryValue', 'FundingStatus__c',
    'Secured\nPlanned', 'Sécurisé\nPrévu' },
  new String[]{ 'Budget Funder Type', 'Public or private', 'Public ou privé', 'Select', 'BudgetCategoryValue', 'FundingType__c',
    'Public\nPrivate', 'Public\nPrivé' },
  new String[]{ 'Budget Funder Year 1', 'Year 1', 'Année 1', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Funder Year 2', 'Year 2', 'Année 2', 'Currency', 'BudgetCategoryValue', 'Amount' },
  new String[]{ 'Budget Funder Year 3', 'Year 3', 'Année 3', 'Currency', 'BudgetCategoryValue', 'Amount' }
};

// ---- 0) Contrôles ----
final FundingOpportunity fundingOpportunity = [
  SELECT Id, Name, Status
  FROM FundingOpportunity
  WHERE Id = :FUNDING_OPPORTUNITY_ID
  LIMIT 1
];
final Set<String> columnNames = new Set<String>();
for (String[] column : COLUMNS) {
  columnNames.add(column[0]);
}
final Integer existingColumnCount = [
  SELECT COUNT()
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = :FUNDING_OPPORTUNITY_ID
  AND AssessmentQuestion.Name IN :columnNames
];
if (existingColumnCount > 0) {
  System.debug('Les colonnes budget existent déjà sur ' + fundingOpportunity.Name + ' : rien à faire.');
  return;
}

// Section existante de la Funding Opportunity, et la dernière position de ses questions.
Id existingSectionId;
Decimal lastQuestionSequence = 0;
for (AssessmentQuestionAssignment assignment : [
  SELECT AssessmentQuestionSetId, AssessmentQuestion.Sequence__c
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = :FUNDING_OPPORTUNITY_ID
  AND AssessmentQuestionSet.Name = :SECTION_NAME
  AND EOI__c = false
]) {
  existingSectionId = assignment.AssessmentQuestionSetId;
  final Decimal questionSequence = assignment.AssessmentQuestion.Sequence__c;
  if (questionSequence != null && questionSequence > lastQuestionSequence) {
    lastQuestionSequence = questionSequence;
  }
}

final Id dynamicRecordTypeId = [
  SELECT Id
  FROM RecordType
  WHERE SObjectType = 'AssessmentQuestion' AND DeveloperName = 'Dynamic'
  LIMIT 1
].Id;
String questionCategory;
for (Schema.PicklistEntry entry : AssessmentQuestion.QuestionCategory.getDescribe().getPicklistValues()) {
  if (entry.isActive()) {
    questionCategory = entry.getValue();
    break;
  }
}

AggregateResult highestSequence = [
  SELECT MAX(AssessmentQuestionSet.Sequence__c) maxSequence
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = :FUNDING_OPPORTUNITY_ID AND EOI__c = false
];
final Decimal maxSequence = (Decimal) highestSequence.get('maxSequence');

System.debug('Funding Opportunity : ' + fundingOpportunity.Name + ' (' + fundingOpportunity.Status + ')');
System.debug(
  COLUMNS.size() + ' colonnes à créer dans la section "' + SECTION_NAME + '" '
  + (existingSectionId == null ? '(nouvelle)' : '(existante ' + existingSectionId + ', après la position '
  + lastQuestionSequence + ')') + '.'
);
if (DRY_RUN) {
  System.debug('DRY_RUN : rien n\'est créé. Passer DRY_RUN à false pour créer.');
  return;
}

// ---- 1) Section : l'existante, sinon une nouvelle ----
final String uniqueSuffix = String.valueOf(Datetime.now().getTime());
Id sectionId = existingSectionId;
if (sectionId == null) {
  final AssessmentQuestionSet section = new AssessmentQuestionSet(
    Name = SECTION_NAME,
    DeveloperName = 'ProjectBudget_' + uniqueSuffix,
    Sequence__c = (maxSequence == null ? 0 : maxSequence) + 1
  );
  insert section;
  sectionId = section.Id;
}

// ---- 2) Questions ----
final List<AssessmentQuestion> questions = new List<AssessmentQuestion>();
for (Integer index = 0; index < COLUMNS.size(); index++) {
  final String[] column = COLUMNS[index];
  questions.add(
    new AssessmentQuestion(
      Name = column[0],
      DeveloperName = column[0].replaceAll('[^a-zA-Z0-9]', '') + '_' + uniqueSuffix,
      DataType = column[3],
      QuestionCategory = questionCategory,
      RecordTypeId = dynamicRecordTypeId,
      ObjectAPIName__c = column[4],
      FieldAPIName__c = column[5],
      // Required by a validation rule on the Text questions: the length of BudgetCategory.Name.
      MaximumCharacters__c = column[3] == 'Text' ? 80 : null,
      Sequence__c = lastQuestionSequence + index + 1
    )
  );
}
insert questions;

// ---- 3) Versions en Draft ----
final List<AssessmentQuestionVersion> versions = new List<AssessmentQuestionVersion>();
for (Integer index = 0; index < COLUMNS.size(); index++) {
  final String[] column = COLUMNS[index];
  versions.add(
    new AssessmentQuestionVersion(
      Name = COLUMNS[index][0],
      AssessmentQuestionId = questions[index].Id,
      QuestionText = COLUMNS[index][1],
      QuestionTextFR__c = COLUMNS[index][2],
      ResponseValues = column.size() > 6 ? column[6] : null,
      ResponseValuesFR__c = column.size() > 7 ? column[7] : null,
      IsActive = false
    )
  );
}
insert versions;

// ---- 4) Assignments sur la Funding Opportunity ----
final List<AssessmentQuestionAssignment> assignments = new List<AssessmentQuestionAssignment>();
for (AssessmentQuestion question : questions) {
  assignments.add(
    new AssessmentQuestionAssignment(
      AssessmentQuestionId = question.Id,
      AssessmentQuestionSetId = sectionId,
      FundingOpportunity__c = FUNDING_OPPORTUNITY_ID,
      EOI__c = false
    )
  );
}
insert assignments;

for (AssessmentQuestionVersion version : [
  SELECT Name, Status, IsActive, ResponseValues
  FROM AssessmentQuestionVersion
  WHERE Id IN :versions
]) {
  System.debug(version.Name + ' : ' + version.Status
    + (version.ResponseValues == null ? '' : ' [' + version.ResponseValues.replace('\n', ', ') + ']'));
}
System.debug(questions.size() + ' questions créées dans la section ' + sectionId + '.');
