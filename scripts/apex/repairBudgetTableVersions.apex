/**
 * Recopie la configuration des tableaux budget (NumberOfYears__c, HasTotal__c, HasPercent__c,
 * HasPicklistSecuredPlanned__c, HasPicklistPublicPrivate__c) des templates du Common Core sur les versions des
 * questions tableau clonées dans les Funding Opportunities avant que le clonage ne copie ces champs.
 *
 * Correspondance par Name de question. Seules les versions dont la configuration diffère du template sont modifiées.
 * Relançable : une seconde exécution ne trouve plus rien à corriger.
 */

final Boolean DRY_RUN = true;

// ---- 1) Configuration des templates du Common Core, par Name de question ----
final Map<String, AssessmentQuestionVersion> templateVersionsByQuestionName = new Map<String, AssessmentQuestionVersion>();
final Set<Id> templateQuestionIds = new Set<Id>();
for (AssessmentQuestionAssignment assignment : [
  SELECT AssessmentQuestionId
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = null
  AND AssessmentQuestion.isTable__c = true
]) {
  templateQuestionIds.add(assignment.AssessmentQuestionId);
}
for (AssessmentQuestionVersion version : [
  SELECT AssessmentQuestion.Name, NumberOfYears__c, HasTotal__c, HasPercent__c, HasPicklistSecuredPlanned__c,
    HasPicklistPublicPrivate__c
  FROM AssessmentQuestionVersion
  WHERE AssessmentQuestionId IN :templateQuestionIds
  ORDER BY IsActive ASC, CreatedDate ASC
]) {
  // Tri croissant : la version active la plus récente l'emporte.
  templateVersionsByQuestionName.put(version.AssessmentQuestion.Name, version);
}

// ---- 2) Versions des questions tableau clonées dans les Funding Opportunities ----
final Set<Id> clonedQuestionIds = new Set<Id>();
for (AssessmentQuestionAssignment assignment : [
  SELECT AssessmentQuestionId
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c != null
  AND AssessmentQuestion.isTable__c = true
  AND AssessmentQuestion.Name IN :templateVersionsByQuestionName.keySet()
]) {
  clonedQuestionIds.add(assignment.AssessmentQuestionId);
}
clonedQuestionIds.removeAll(templateQuestionIds);

final List<AssessmentQuestionVersion> versionsToUpdate = new List<AssessmentQuestionVersion>();
for (AssessmentQuestionVersion version : [
  SELECT Id, AssessmentQuestion.Name, NumberOfYears__c, HasTotal__c, HasPercent__c, HasPicklistSecuredPlanned__c,
    HasPicklistPublicPrivate__c
  FROM AssessmentQuestionVersion
  WHERE AssessmentQuestionId IN :clonedQuestionIds
]) {
  final AssessmentQuestionVersion template = templateVersionsByQuestionName.get(version.AssessmentQuestion.Name);
  final Boolean isDifferent = version.NumberOfYears__c != template.NumberOfYears__c
    || version.HasTotal__c != template.HasTotal__c
    || version.HasPercent__c != template.HasPercent__c
    || version.HasPicklistSecuredPlanned__c != template.HasPicklistSecuredPlanned__c
    || version.HasPicklistPublicPrivate__c != template.HasPicklistPublicPrivate__c;
  if (!isDifferent) {
    continue;
  }
  System.debug(version.Id + ' "' + version.AssessmentQuestion.Name + '" -> ' + template.NumberOfYears__c + ' année(s)');
  versionsToUpdate.add(
    new AssessmentQuestionVersion(
      Id                           = version.Id,
      NumberOfYears__c             = template.NumberOfYears__c,
      HasTotal__c                  = template.HasTotal__c,
      HasPercent__c                = template.HasPercent__c,
      HasPicklistSecuredPlanned__c = template.HasPicklistSecuredPlanned__c,
      HasPicklistPublicPrivate__c  = template.HasPicklistPublicPrivate__c
    )
  );
}

System.debug(versionsToUpdate.size() + ' versions à corriger.');
if (DRY_RUN) {
  System.debug('DRY_RUN : rien n\'est modifié. Passer DRY_RUN à false pour corriger.');
  return;
}
update versionsToUpdate;
System.debug('Correction terminée.');
