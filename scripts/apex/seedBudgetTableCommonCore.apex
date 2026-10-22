/**
 * Ajoute les questions-colonnes des trois tableaux budget et du tableau des contreparties au Common Core du dossier complet : des templates
 * (FundingOpportunity__c = null, Program__c = null, EOI__c = false), copiés dans chaque nouvelle Funding
 * Opportunity par ApplicationFormLifecycleService.cloneTemplateQuestionCataloguesToFundingOpportunities.
 * Les Funding Opportunities existantes ne sont pas modifiées.
 *
 * Les colonnes vont dans la section template "Project budget" (créée si elle n'existe pas), après ses questions.
 * Un tableau commence à sa colonne BudgetCategory.Name ; le Name de cette question est la clé du tableau,
 * configurée dans ApplicationFormBudgetService.CONFIG_BY_TABLE_KEY.
 *
 * Obligatoire (IsMandatory__c de l'assignment, copié au clonage) :
 * - sur la colonne nom de ligne : le tableau doit avoir au moins une ligne à la soumission ;
 * - sur une autre colonne : la cellule est obligatoire sur chaque ligne remplie.
 *
 * Relançable : s'arrête si une des colonnes existe déjà dans le Common Core.
 */

final String SECTION_NAME = 'Project budget';
final Boolean ACTIVATE_VERSIONS = true;
final Boolean DRY_RUN = true;

// name, questionText (EN), questionText (FR), dataType, objectApiName, fieldApiName, isMandatory
// [, responseValues, responseValues FR]
final List<String[]> COLUMNS = new List<String[]>{
  // Tableau 1 : budget total du projet (clé "Budget Item Name")
  new String[]{ 'Budget Item Name', 'Item Name', 'Poste de dépense', 'Text', 'BudgetCategory', 'Name', 'true' },
  new String[]{ 'Budget Item Year 1', 'Year 1', 'Année 1', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Item Year 2', 'Year 2', 'Année 2', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Item Year 3', 'Year 3', 'Année 3', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Item Year 4', 'Year 4', 'Année 4', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Item Year 5', 'Year 5', 'Année 5', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  // Tableau 2 : budget demandé à la Fondation AXA (clé "Budget Requested Name")
  new String[]{ 'Budget Requested Name', 'Cost item', 'Poste de coût', 'Text', 'BudgetCategory', 'Name', 'true' },
  new String[]{ 'Budget Requested Year 1', 'Year 1', 'Année 1', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Requested Year 2', 'Year 2', 'Année 2', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Requested Year 3', 'Year 3', 'Année 3', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Requested Year 4', 'Year 4', 'Année 4', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Requested Year 5', 'Year 5', 'Année 5', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  // Tableau 3 : financeurs (clé "Budget Funder Name"). Les ResponseValues, obligatoires sur une version Select,
  // reprennent les global value sets BudgetFundingStatus et BudgetFundingType.
  new String[]{ 'Budget Funder Name', 'Name', 'Nom', 'Text', 'BudgetCategory', 'Name', 'true' },
  new String[]{ 'Budget Funder Status', 'Secured or planned', 'Sécurisé ou prévu', 'Select', 'BudgetCategoryValue',
    'FundingStatus__c', 'true', 'Secured\nPlanned', 'Sécurisé\nPrévu' },
  new String[]{ 'Budget Funder Type', 'Public or private', 'Public ou privé', 'Select', 'BudgetCategoryValue',
    'FundingType__c', 'true', 'Public\nPrivate', 'Public\nPrivé' },
  new String[]{ 'Budget Funder Year 1', 'Year 1', 'Année 1', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Funder Year 2', 'Year 2', 'Année 2', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  new String[]{ 'Budget Funder Year 3', 'Year 3', 'Année 3', 'Currency', 'BudgetCategoryValue', 'Amount', 'false' },
  // Tableau 4 : contreparties (clé "Benefit Counterpart Title") : un Benefit standard par ligne, rattaché au
  // projet (Benefit.Project__c) et au Benefit Type "AXA Foundation Counterpart". Type__c suit le global value
  // set Benefit_Type.
  new String[]{ 'Benefit Counterpart Title', 'Title', 'Intitulé', 'Text', 'Benefit', 'Name', 'true' },
  new String[]{ 'Benefit Counterpart Amount', 'Amount', 'Montant', 'Currency', 'Benefit', 'MaxBenefitAmount', 'false' },
  new String[]{ 'Benefit Counterpart Availability', 'Availability', 'Disponibilité', 'Date', 'Benefit',
    'ValidFrom__c', 'false' },
  new String[]{ 'Benefit Counterpart Type', 'Type of counterpart', 'Type de contrepartie', 'Select', 'Benefit',
    'Type__c', 'true', 'Venue\nMuseum and Culture\nCatering\nMixed\nOther',
    'Lieu\nMusée et culture\nRestauration\nMixte\nAutre' },
  new String[]{ 'Benefit Counterpart Description', 'Description', 'Description', 'TextArea', 'Benefit',
    'Description', 'false' }
};

// ---- 0) Contrôles ----
final Set<String> columnNames = new Set<String>();
for (String[] column : COLUMNS) {
  columnNames.add(column[0]);
}
final Integer existingColumnCount = [
  SELECT COUNT()
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = null
  AND Program__c = null
  AND AssessmentQuestion.Name IN :columnNames
];
if (existingColumnCount > 0) {
  System.debug('Les colonnes budget existent déjà dans le Common Core : rien à faire.');
  return;
}

// Section template existante et dernière position de ses questions.
Id existingSectionId;
Decimal lastQuestionSequence = 0;
for (AssessmentQuestionAssignment assignment : [
  SELECT AssessmentQuestionSetId, AssessmentQuestion.Sequence__c
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = null
  AND Program__c = null
  AND EOI__c = false
  AND AssessmentQuestionSet.Name = :SECTION_NAME
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
final AggregateResult highestSequence = [
  SELECT MAX(AssessmentQuestionSet.Sequence__c) maxSequence
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = null AND Program__c = null AND EOI__c = false
];
final Decimal maxSectionSequence = (Decimal) highestSequence.get('maxSequence');

System.debug(
  COLUMNS.size() + ' colonnes à créer dans la section template "' + SECTION_NAME + '" '
  + (existingSectionId == null ? '(nouvelle)' : '(existante ' + existingSectionId + ', après la position '
  + lastQuestionSequence + ')') + ', versions ' + (ACTIVATE_VERSIONS ? 'actives' : 'Draft') + '.'
);
if (DRY_RUN) {
  System.debug('DRY_RUN : rien n\'est créé. Passer DRY_RUN à false pour créer.');
  return;
}

// ---- 1) Section ----
final String uniqueSuffix = String.valueOf(Datetime.now().getTime());
Id sectionId = existingSectionId;
if (sectionId == null) {
  final AssessmentQuestionSet section = new AssessmentQuestionSet(
    Name = SECTION_NAME,
    DeveloperName = 'ProjectBudget_' + uniqueSuffix,
    Sequence__c = (maxSectionSequence == null ? 0 : maxSectionSequence) + 1
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
      // Required by a validation rule on the Text and Text Area questions: the length of the target field.
      MaximumCharacters__c = column[3] == 'Text' ? 80 : (column[3] == 'TextArea' ? 1000 : null),
      Sequence__c = lastQuestionSequence + index + 1
    )
  );
}
insert questions;

// ---- 3) Versions ----
final List<AssessmentQuestionVersion> versions = new List<AssessmentQuestionVersion>();
for (Integer index = 0; index < COLUMNS.size(); index++) {
  final String[] column = COLUMNS[index];
  versions.add(
    new AssessmentQuestionVersion(
      Name = column[0],
      AssessmentQuestionId = questions[index].Id,
      QuestionText = column[1],
      QuestionTextFR__c = column[2],
      ResponseValues = column.size() > 7 ? column[7] : null,
      ResponseValuesFR__c = column.size() > 8 ? column[8] : null,
      IsActive = ACTIVATE_VERSIONS
    )
  );
}
insert versions;

// ---- 4) Assignments template (Common Core, dossier complet) ----
final List<AssessmentQuestionAssignment> assignments = new List<AssessmentQuestionAssignment>();
for (Integer index = 0; index < COLUMNS.size(); index++) {
  assignments.add(
    new AssessmentQuestionAssignment(
      AssessmentQuestionId = questions[index].Id,
      AssessmentQuestionSetId = sectionId,
      FundingOpportunity__c = null,
      Program__c = null,
      EOI__c = false,
      IsMandatory__c = Boolean.valueOf(COLUMNS[index][6])
    )
  );
}
insert assignments;

System.debug(questions.size() + ' questions template créées dans la section ' + sectionId + '.');
