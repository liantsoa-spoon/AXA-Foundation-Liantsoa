/**
 * Supprime ce que seedBudgetTableQuestions.apex a créé sur la Funding Opportunity de test : la section
 * "Project budget", ses questions-colonnes (versions Draft, assignments, questions) et, si demandé, les
 * Budgets des tableaux enregistrés sur les Application Forms de cette Funding Opportunity.
 *
 * Seules les questions-colonnes nommées dans COLUMN_NAMES et rattachées à cette Funding Opportunity sont
 * visées : les questions Fixed de la section (budget total, montant demandé) ne sont jamais touchées, et la
 * section n'est supprimée que si elle est vide. Une question dont une version n'est plus Draft n'est pas supprimée : son
 * assignment l'est, ce qui la retire du formulaire.
 */

final Id FUNDING_OPPORTUNITY_ID = '<A_RENSEIGNER>';
final String SECTION_NAME = 'Project budget';
final Set<String> TABLE_KEYS = new Set<String>{ 'Budget Item Name', 'Budget Requested Name', 'Budget Funder Name' };
final Set<String> COLUMN_NAMES = new Set<String>{
  'Budget Item Name', 'Budget Item Year 1', 'Budget Item Year 2', 'Budget Item Year 3', 'Budget Item Year 4',
  'Budget Item Year 5', 'Budget Requested Name', 'Budget Requested Year 1', 'Budget Requested Year 2',
  'Budget Requested Year 3', 'Budget Requested Year 4', 'Budget Requested Year 5', 'Budget Funder Name', 'Budget Funder Status', 'Budget Funder Type',
  'Budget Funder Year 1', 'Budget Funder Year 2', 'Budget Funder Year 3'
};
final Boolean DELETE_SAVED_BUDGETS = true;
final Boolean DRY_RUN = false;

// ---- 1) Assignments visés ----
final List<AssessmentQuestionAssignment> assignments = [
  SELECT Id, AssessmentQuestionId, AssessmentQuestionSetId
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = :FUNDING_OPPORTUNITY_ID
  AND AssessmentQuestionSet.Name = :SECTION_NAME
  AND AssessmentQuestion.Name IN :COLUMN_NAMES
  AND AssessmentQuestion.RecordType.DeveloperName = 'Dynamic'
];
final Set<Id> questionIds = new Set<Id>();
final Set<Id> sectionIds = new Set<Id>();
for (AssessmentQuestionAssignment assignment : assignments) {
  questionIds.add(assignment.AssessmentQuestionId);
  sectionIds.add(assignment.AssessmentQuestionSetId);
}

final List<AssessmentQuestionVersion> versions = [
  SELECT Id, AssessmentQuestionId, Status
  FROM AssessmentQuestionVersion
  WHERE AssessmentQuestionId IN :questionIds
];
final Set<Id> lockedQuestionIds = new Set<Id>();
final List<AssessmentQuestionVersion> draftVersions = new List<AssessmentQuestionVersion>();
for (AssessmentQuestionVersion version : versions) {
  if (version.Status == 'Draft') {
    draftVersions.add(version);
  } else {
    lockedQuestionIds.add(version.AssessmentQuestionId);
  }
}
final List<AssessmentQuestion> deletableQuestions = new List<AssessmentQuestion>();
for (Id questionId : questionIds) {
  if (!lockedQuestionIds.contains(questionId)) {
    deletableQuestions.add(new AssessmentQuestion(Id = questionId));
  }
}

// ---- 2) Budgets des tableaux enregistrés (sous le Budget des Application Forms) ----
List<Budget> tableBudgets = new List<Budget>();
if (DELETE_SAVED_BUDGETS) {
  tableBudgets = [
    SELECT Id, Name
    FROM Budget
    WHERE (Description IN :TABLE_KEYS OR Name IN :TABLE_KEYS)
    AND ParentBudgetId IN (
      SELECT BudgetId FROM ApplicationForm WHERE ReferenceRecordId = :FUNDING_OPPORTUNITY_ID
    )
  ];
}

System.debug(assignments.size() + ' assignments, ' + draftVersions.size() + ' versions Draft, '
  + deletableQuestions.size() + ' questions supprimables, ' + lockedQuestionIds.size() + ' questions activées (gardées), '
  + sectionIds.size() + ' section(s), ' + tableBudgets.size() + ' Budget(s) de tableau.');
if (DRY_RUN) {
  System.debug('DRY_RUN : rien n\'est supprimé. Passer DRY_RUN à false pour supprimer.');
  return;
}

// ---- 3) Suppressions : les lignes et les périodes partent avec leur Budget de tableau ----
if (!tableBudgets.isEmpty()) {
  final Set<Id> tableBudgetIds = new Map<Id, Budget>(tableBudgets).keySet();
  delete [SELECT Id FROM BudgetCategory WHERE BudgetId IN :tableBudgetIds];
  delete [SELECT Id FROM BudgetPeriod WHERE BudgetId IN :tableBudgetIds];
  delete tableBudgets;
}
delete assignments;
delete draftVersions;
delete deletableQuestions;

// La section n'est supprimée que si plus aucun assignment ne la rattache.
final List<AssessmentQuestionSet> emptySections = [
  SELECT Id
  FROM AssessmentQuestionSet
  WHERE Id IN :sectionIds
  AND Id NOT IN (SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment)
];
delete emptySections;
System.debug('Suppression terminée : ' + emptySections.size() + ' section(s) supprimée(s).');
