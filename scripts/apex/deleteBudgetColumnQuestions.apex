/**
 * Supprime les anciennes questions-colonnes du budget (une question par colonne), remplacées par les questions tableau
 * (une question par tableau, voir seedBudgetTables.apex) :
 * - ObjectAPIName__c = BudgetCategory ou BudgetCategoryValue ;
 * - ObjectAPIName__c = Benefit sur une question qui n'est pas un tableau (isTable__c = false).
 * Les nouvelles questions tableau (isTable__c = true, ObjectAPIName__c = Budget ou Benefit) ne sont jamais touchées.
 *
 * Avec INCLUDE_FIXED_AMOUNT_QUESTIONS, il supprime aussi les deux questions Fixed des montants (Budget.Amount et
 * ApplicationForm.RequestedAmount) : le bloc budget les affiche désormais, calculées à partir des tableaux.
 *
 * Portée : le Common Core (FundingOpportunity__c vide) et les Funding Opportunities listées dans
 * FUNDING_OPPORTUNITY_IDS ; laisser INCLUDE_ALL_FUNDING_OPPORTUNITIES à true pour traiter toutes celles qui en ont.
 *
 * Une version Active ne peut plus être supprimée par la plateforme : sa question est gardée, mais son assignment est
 * supprimé, ce qui la retire du formulaire et du clonage. Les questions dont toutes les versions sont en Draft sont
 * supprimées avec leurs versions.
 */

final Boolean INCLUDE_COMMON_CORE = true;
final Boolean INCLUDE_ALL_FUNDING_OPPORTUNITIES = false;
final Set<Id> FUNDING_OPPORTUNITY_IDS = new Set<Id>{ '119KK0000000232YAA' };
final Boolean INCLUDE_FIXED_AMOUNT_QUESTIONS = true;
final Boolean DRY_RUN = true;

// ---- 1) Assignments des anciennes questions-colonnes dans la portée ----
final List<AssessmentQuestionAssignment> assignments = new List<AssessmentQuestionAssignment>();
for (AssessmentQuestionAssignment assignment : [
  SELECT Id, AssessmentQuestionId, FundingOpportunity__c, AssessmentQuestion.Name,
    AssessmentQuestion.RecordType.DeveloperName, AssessmentQuestion.ObjectAPIName__c,
    AssessmentQuestion.FieldAPIName__c
  FROM AssessmentQuestionAssignment
  WHERE AssessmentQuestion.ObjectAPIName__c IN ('BudgetCategory', 'BudgetCategoryValue')
  OR (AssessmentQuestion.ObjectAPIName__c = 'Benefit' AND AssessmentQuestion.isTable__c = false)
  OR (AssessmentQuestion.ObjectAPIName__c = 'Budget' AND AssessmentQuestion.FieldAPIName__c = 'Amount')
  OR (AssessmentQuestion.ObjectAPIName__c = 'ApplicationForm' AND AssessmentQuestion.FieldAPIName__c = 'RequestedAmount')
]) {
  final Boolean isFixedAmountQuestion = assignment.AssessmentQuestion.RecordType.DeveloperName == 'Fixed'
    && (assignment.AssessmentQuestion.FieldAPIName__c == 'Amount'
    || assignment.AssessmentQuestion.FieldAPIName__c == 'RequestedAmount');
  final Boolean isColumnQuestion = assignment.AssessmentQuestion.ObjectAPIName__c != 'Budget'
    && assignment.AssessmentQuestion.ObjectAPIName__c != 'ApplicationForm';
  if (!isColumnQuestion && !(isFixedAmountQuestion && INCLUDE_FIXED_AMOUNT_QUESTIONS)) {
    continue;
  }
  final Boolean isCommonCore = assignment.FundingOpportunity__c == null;
  final Boolean isInScope = isCommonCore
    ? INCLUDE_COMMON_CORE
    : INCLUDE_ALL_FUNDING_OPPORTUNITIES || FUNDING_OPPORTUNITY_IDS.contains(assignment.FundingOpportunity__c);
  if (isInScope) {
    assignments.add(assignment);
  }
}
final Set<Id> questionIds = new Set<Id>();
for (AssessmentQuestionAssignment assignment : assignments) {
  questionIds.add(assignment.AssessmentQuestionId);
}

// ---- 2) Questions supprimables : sans autre assignment et sans version active ----
final Set<Id> keptQuestionIds = new Set<Id>();
for (AssessmentQuestionAssignment otherAssignment : [
  SELECT AssessmentQuestionId
  FROM AssessmentQuestionAssignment
  WHERE AssessmentQuestionId IN :questionIds
  AND Id NOT IN :assignments
]) {
  keptQuestionIds.add(otherAssignment.AssessmentQuestionId);
}
final List<AssessmentQuestionVersion> draftVersions = new List<AssessmentQuestionVersion>();
for (AssessmentQuestionVersion version : [
  SELECT Id, AssessmentQuestionId, Status
  FROM AssessmentQuestionVersion
  WHERE AssessmentQuestionId IN :questionIds
]) {
  if (version.Status == 'Draft') {
    draftVersions.add(version);
  } else {
    keptQuestionIds.add(version.AssessmentQuestionId);
  }
}
final List<AssessmentQuestion> deletableQuestions = new List<AssessmentQuestion>();
final List<AssessmentQuestionVersion> deletableVersions = new List<AssessmentQuestionVersion>();
for (Id questionId : questionIds) {
  if (!keptQuestionIds.contains(questionId)) {
    deletableQuestions.add(new AssessmentQuestion(Id = questionId));
  }
}
for (AssessmentQuestionVersion version : draftVersions) {
  if (!keptQuestionIds.contains(version.AssessmentQuestionId)) {
    deletableVersions.add(version);
  }
}

System.debug(
  assignments.size() + ' assignments à supprimer ; ' + deletableQuestions.size() + ' questions (et '
  + deletableVersions.size() + ' versions Draft) supprimables ; ' + keptQuestionIds.size()
  + ' questions gardées (version active ou autre assignment).'
);
if (DRY_RUN) {
  System.debug('DRY_RUN : rien n\'est supprimé. Passer DRY_RUN à false pour supprimer.');
  return;
}

// ---- 3) Suppressions ----
delete assignments;
delete deletableVersions;
delete deletableQuestions;
System.debug('Suppression terminée.');
