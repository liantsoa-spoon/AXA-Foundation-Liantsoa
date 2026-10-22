/**
 * Crée les quatre questions tableau de la section "Project budget" du dossier complet (une question = un tableau) :
 * - dans le Common Core (FUNDING_OPPORTUNITY_ID = null) : des templates copiés dans chaque nouvelle Funding
 *   Opportunity par ApplicationFormLifecycleService ;
 * - ou directement sur une Funding Opportunity (FUNDING_OPPORTUNITY_ID renseigné), pour tester.
 *
 * Une question tableau : record type Dynamic, isTable__c = true, ObjectAPIName__c = Budget ou Benefit,
 * FieldAPIName__c = Name. Sa version porte la configuration lue par ApplicationFormBudgetController :
 * NumberOfYears__c, HasTotal__c, HasPercent__c, HasPicklistSecuredPlanned__c, HasPicklistPublicPrivate__c.
 *
 * Le Name des deux premières questions doit être celui des Custom Labels BudgetTotalProjectBudgetQuestionName et
 * BudgetRequestedAmountQuestionName : leurs totaux alimentent le budget total du projet et ApplicationForm.RequestedAmount.
 *
 * Relançable : s'arrête si une des questions existe déjà sur la cible.
 */

// null : Common Core (templates). Un Id : la Funding Opportunity de test.
final Id FUNDING_OPPORTUNITY_ID = null;
final String SECTION_NAME = 'Project budget';
// false : versions en Draft, supprimables ensuite (test). true : versions actives (Common Core).
final Boolean ACTIVATE_VERSIONS = true;
final Boolean DRY_RUN = true;

// name, questionText EN, questionText FR, helpText, objectApiName, numberOfYears, hasTotal, hasPercent,
// hasPicklistSecuredPlanned, hasPicklistPublicPrivate, isMandatory
final List<Object[]> TABLES = new List<Object[]>{
  new Object[]{
    System.Label.BudgetTotalProjectBudgetQuestionName,
    'Total project budget per year (in euros)',
    'Budget total du projet par année (en euros)',
    null,
    'Budget', 5, true, false, false, false, true
  },
  new Object[]{
    System.Label.BudgetRequestedAmountQuestionName,
    'Budget requested from the AXA Foundation (in euros)',
    'Budget demandé à la Fondation AXA (en euros)',
    null,
    'Budget', 5, true, false, false, false, true
  },
  new Object[]{
    'Main public/private financial partners of the project and donation amounts',
    'Main public/private financial partners of the project and donation amounts',
    'Principaux partenaires financiers publics/privés du projet et montants des dons',
    null,
    'Budget', 3, true, true, true, true, true
  },
  new Object[]{
    'What counterparts would you like to offer to the AXA Foundation?',
    'What counterparts would you like to offer to the AXA Foundation?',
    'Quelles contreparties souhaitez-vous proposer à la Fondation AXA ?',
    'E.g. communication action, provision of a venue, AXA visibility, etc.',
    'Benefit', null, false, false, false, false, false
  }
};

// ---- 0) Contrôles ----
final Set<String> questionNames = new Set<String>();
for (Object[] table : TABLES) {
  questionNames.add((String) table[0]);
}
final Integer existingCount = [
  SELECT COUNT()
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = :FUNDING_OPPORTUNITY_ID
  AND EOI__c = false
  AND AssessmentQuestion.Name IN :questionNames
];
if (existingCount > 0) {
  System.debug('Les questions tableau existent déjà sur la cible : rien à faire.');
  return;
}

// Section existante de la cible (FUNDING_OPPORTUNITY_ID null : Common Core) et dernière position de ses questions.
Id sectionId;
Decimal lastQuestionSequence = 0;
for (AssessmentQuestionAssignment assignment : [
  SELECT AssessmentQuestionSetId, AssessmentQuestion.Sequence__c
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = :FUNDING_OPPORTUNITY_ID
  AND Program__c = null
  AND EOI__c = false
  AND AssessmentQuestionSet.Name = :SECTION_NAME
]) {
  sectionId = assignment.AssessmentQuestionSetId;
  final Decimal questionSequence = assignment.AssessmentQuestion.Sequence__c;
  if (questionSequence != null && questionSequence > lastQuestionSequence) {
    lastQuestionSequence = questionSequence;
  }
}

final Id dynamicRecordTypeId = Schema.SObjectType.AssessmentQuestion.getRecordTypeInfosByDeveloperName()
  .get('Dynamic')
  .getRecordTypeId();
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
  WHERE FundingOpportunity__c = :FUNDING_OPPORTUNITY_ID AND Program__c = null AND EOI__c = false
];
final Decimal maxSectionSequence = (Decimal) highestSequence.get('maxSequence');

System.debug(
  TABLES.size() + ' questions tableau à créer sur ' + (FUNDING_OPPORTUNITY_ID == null ? 'le Common Core' : FUNDING_OPPORTUNITY_ID)
  + ', section "' + SECTION_NAME + '" ' + (sectionId == null ? '(nouvelle)' : '(existante ' + sectionId + ')')
  + ', versions ' + (ACTIVATE_VERSIONS ? 'actives' : 'Draft') + '.'
);
if (DRY_RUN) {
  System.debug('DRY_RUN : rien n\'est créé. Passer DRY_RUN à false pour créer.');
  return;
}

// ---- 1) Section ----
final String uniqueSuffix = String.valueOf(Datetime.now().getTime());
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
for (Integer index = 0; index < TABLES.size(); index++) {
  final Object[] table = TABLES[index];
  final String name = (String) table[0];
  questions.add(
    new AssessmentQuestion(
      Name = name.left(80),
      DeveloperName = name.replaceAll('[^a-zA-Z0-9]', '').left(60) + '_' + uniqueSuffix,
      DataType = 'TextBlock',
      QuestionCategory = questionCategory,
      RecordTypeId = dynamicRecordTypeId,
      isTable__c = true,
      ObjectAPIName__c = (String) table[4],
      FieldAPIName__c = 'Name',
      Sequence__c = lastQuestionSequence + index + 1
    )
  );
}
insert questions;

// ---- 3) Versions : libellés et configuration du tableau ----
final List<AssessmentQuestionVersion> versions = new List<AssessmentQuestionVersion>();
for (Integer index = 0; index < TABLES.size(); index++) {
  final Object[] table = TABLES[index];
  versions.add(
    new AssessmentQuestionVersion(
      Name = ((String) table[0]).left(80),
      AssessmentQuestionId = questions[index].Id,
      QuestionText = (String) table[1],
      QuestionTextFR__c = (String) table[2],
      HelpText = (String) table[3],
      NumberOfYears__c = (Integer) table[5],
      HasTotal__c = (Boolean) table[6],
      HasPercent__c = (Boolean) table[7],
      HasPicklistSecuredPlanned__c = (Boolean) table[8],
      HasPicklistPublicPrivate__c = (Boolean) table[9],
      IsActive = ACTIVATE_VERSIONS
    )
  );
}
insert versions;

// ---- 4) Assignments (dossier complet) ----
final List<AssessmentQuestionAssignment> assignments = new List<AssessmentQuestionAssignment>();
for (Integer index = 0; index < TABLES.size(); index++) {
  assignments.add(
    new AssessmentQuestionAssignment(
      AssessmentQuestionId = questions[index].Id,
      AssessmentQuestionSetId = sectionId,
      FundingOpportunity__c = FUNDING_OPPORTUNITY_ID,
      EOI__c = false,
      IsMandatory__c = (Boolean) TABLES[index][10]
    )
  );
}
insert assignments;

System.debug(questions.size() + ' questions tableau créées dans la section ' + sectionId + '.');
