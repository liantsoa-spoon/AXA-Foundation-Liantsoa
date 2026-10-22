/**
 * Retire la section "Project Impact & Scope" du pool de templates (FundingOpportunity__c = null,
 * dupliqué en plusieurs exemplaires par des clonages successifs) et du Programme ciblé.
 *
 * Les clones rattachés à une AUTRE Funding Opportunity ne sont jamais touchés.
 *
 * Deux contraintes du modèle dictent l'ordre des suppressions :
 * - AssessmentQuestionResponse.AssessmentQuestionId référence la VERSION, pas la question
 *   (voir ApplicationFormController.saveSectionResponses), donc les réponses partent d'abord.
 * - AssessmentQuestionVersion.Status suit Draft -> Active -> Archived sans retour possible : une
 *   question déjà activée ne peut plus être supprimée par la plateforme (voir
 *   ApplicationFormLifecycleService.purgeOrphanedDraftQuestions). Son assignment est tout de même
 *   supprimé, ce qui la retire du catalogue et du pool ; l'enregistrement reste orphelin.
 */

final String SECTION_NAME = 'Project Impact & Scope';
final Id FUNDING_OPPORTUNITY_ID = '119KN000000004EYAQ';
final Boolean DELETE_TEMPLATE_TOO = true;
final Boolean DRY_RUN = false;

// ---- 1) Assignments visés : le clone du Programme et les templates (FundingOpportunity__c = null) ----
List<AssessmentQuestionAssignment> targetAssignments = new List<AssessmentQuestionAssignment>();
for (AssessmentQuestionAssignment aqa : [
    SELECT Id, AssessmentQuestionId, AssessmentQuestionSetId, FundingOpportunity__c,
           AssessmentQuestion.Name, AssessmentQuestion.RecordType.DeveloperName
    FROM AssessmentQuestionAssignment
    WHERE AssessmentQuestionSet.Name = :SECTION_NAME
]) {
    Boolean isClone = aqa.FundingOpportunity__c == FUNDING_OPPORTUNITY_ID;
    Boolean isTemplate = aqa.FundingOpportunity__c == null;
    if (isClone || (isTemplate && DELETE_TEMPLATE_TOO)) {
        targetAssignments.add(aqa);
    }
}

if (targetAssignments.isEmpty()) {
    System.debug('Aucun assignment à traiter pour la section "' + SECTION_NAME + '".');
    return;
}

Set<Id> questionIds = new Set<Id>();
Set<Id> sectionIds = new Set<Id>();
for (AssessmentQuestionAssignment aqa : targetAssignments) {
    questionIds.add(aqa.AssessmentQuestionId);
    sectionIds.add(aqa.AssessmentQuestionSetId);
}

// ---- 2) Versions : on ne purge que les questions restées en Draft ----
List<AssessmentQuestionVersion> versions = [
    SELECT Id, AssessmentQuestionId, Status
    FROM AssessmentQuestionVersion
    WHERE AssessmentQuestionId IN :questionIds
];
Set<Id> activatedQuestionIds = new Set<Id>();
Set<Id> versionIds = new Set<Id>();
for (AssessmentQuestionVersion version : versions) {
    versionIds.add(version.Id);
    if (version.Status != 'Draft') {
        activatedQuestionIds.add(version.AssessmentQuestionId);
    }
}

// ---- 3) Réponses déjà saisies sur ces versions ----
List<AssessmentQuestionResponse> responses = [
    SELECT Id FROM AssessmentQuestionResponse WHERE AssessmentQuestionId IN :versionIds
];

System.debug('Assignments à supprimer : ' + targetAssignments.size());
System.debug('Questions concernées : ' + questionIds.size()
    + ' dont ' + activatedQuestionIds.size() + ' activée(s) donc non supprimable(s)');
System.debug('Réponses à supprimer : ' + responses.size());

if (DRY_RUN) {
    System.debug('DRY_RUN actif : aucune suppression effectuée.');
    return;
}

// ---- 4) Suppression, dans l'ordre imposé par le modèle ----
if (!responses.isEmpty()) {
    delete responses;
}
delete targetAssignments;

List<AssessmentQuestionVersion> versionsToDelete = new List<AssessmentQuestionVersion>();
for (AssessmentQuestionVersion version : versions) {
    if (!activatedQuestionIds.contains(version.AssessmentQuestionId)) {
        versionsToDelete.add(version);
    }
}
if (!versionsToDelete.isEmpty()) {
    delete versionsToDelete;
}

// Une question encore rattachée ailleurs (autre Programme) est conservée.
Set<Id> stillAssignedQuestionIds = new Set<Id>();
for (AssessmentQuestionAssignment aqa : [
    SELECT AssessmentQuestionId FROM AssessmentQuestionAssignment
    WHERE AssessmentQuestionId IN :questionIds
]) {
    stillAssignedQuestionIds.add(aqa.AssessmentQuestionId);
}
List<AssessmentQuestion> questionsToDelete = new List<AssessmentQuestion>();
for (Id questionId : questionIds) {
    if (!stillAssignedQuestionIds.contains(questionId) && !activatedQuestionIds.contains(questionId)) {
        questionsToDelete.add(new AssessmentQuestion(Id = questionId));
    }
}
if (!questionsToDelete.isEmpty()) {
    delete questionsToDelete;
}

// ---- 5) Sections devenues vides (une section encore utilisée par une autre FO est gardée) ----
Set<Id> stillUsedSectionIds = new Set<Id>();
for (AssessmentQuestionAssignment aqa : [
    SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment
    WHERE AssessmentQuestionSetId IN :sectionIds
]) {
    stillUsedSectionIds.add(aqa.AssessmentQuestionSetId);
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

System.debug('Terminé : ' + questionsToDelete.size() + ' question(s) purgée(s), '
    + sectionsToDelete.size() + ' section(s) supprimée(s), '
    + activatedQuestionIds.size() + ' question(s) activée(s) laissée(s) orpheline(s).');
