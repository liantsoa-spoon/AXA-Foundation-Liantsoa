/**
 * @description       : Trigger handler for FundingOpportunity.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 12-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   LAN      Initial version
 * 1.1   02-10-2026   LAN      Only a Draft Funding Opportunity without Application Form can be deleted
 * 1.2   12-10-2026   KRA      Extend BaseTriggerHandler
 **/
public with sharing class FundingOpportunityTriggerHandler extends BaseTriggerHandler {

  public static Boolean isCatalogueSeedingEnabled = true;

  protected override void afterInsert(List<SObject> newRecords) {
    if (!isCatalogueSeedingEnabled) {
      return;
    }

    final Set<Id> fundingOpportunityIds = new Set<Id>();
    for (FundingOpportunity fundingOpportunity : (List<FundingOpportunity>) newRecords) {
      fundingOpportunityIds.add(fundingOpportunity.Id);
    }

    final Savepoint savepoint = Database.setSavepoint();
    try {
      ApplicationFormLifecycleService.cloneTemplateQuestionCataloguesToFundingOpportunities(fundingOpportunityIds);
    } catch (Exception clonageException) {
      Database.rollback(savepoint);
      System.debug(LoggingLevel.ERROR,
        'Clone du catalogue en échec pour les Funding Opportunities ' + fundingOpportunityIds
        + ' : ' + clonageException.getMessage()
        + '\n' + clonageException.getStackTraceString());
    }
  }

  protected override void beforeDelete(List<SObject> oldRecords) {
    final List<FundingOpportunity> oldFundingOpportunities = (List<FundingOpportunity>) oldRecords;
    final Set<Id> fundingOpportunityIdsWithApplicationForms =
      getFundingOpportunityIdsWithApplicationForms(
        new Map<Id, FundingOpportunity>(oldFundingOpportunities).keySet()
      );

    final Set<Id> deletableFundingOpportunityIds = new Set<Id>();
    for (FundingOpportunity fundingOpportunity : oldFundingOpportunities) {
      if (fundingOpportunity.Status != FundingOpportunityConstants.Status.DRAFT) {
        fundingOpportunity.addError('Only a Funding Opportunity in Draft status can be deleted.');
      } else if (fundingOpportunityIdsWithApplicationForms.contains(fundingOpportunity.Id)) {
        fundingOpportunity.addError('A Funding Opportunity with Application Forms attached cannot be deleted.');
      } else {
        deletableFundingOpportunityIds.add(fundingOpportunity.Id);
      }
    }

    ApplicationFormCatalogueQueryService.deleteClonedCatalogues(deletableFundingOpportunityIds);
  }

  private static Set<Id> getFundingOpportunityIdsWithApplicationForms(Set<Id> fundingOpportunityIds) {
    final Set<Id> fundingOpportunityIdsWithApplicationForms = new Set<Id>();
    for (ApplicationForm applicationForm : [
      SELECT
        ReferenceRecordId,
        ProgrammeRattache__c
      FROM
        ApplicationForm
      WHERE
        ProgrammeRattache__c IN :fundingOpportunityIds
    ]) {
      if (fundingOpportunityIds.contains(applicationForm.ReferenceRecordId)) {
        fundingOpportunityIdsWithApplicationForms.add(applicationForm.ReferenceRecordId);
      }
      if (fundingOpportunityIds.contains(applicationForm.ProgrammeRattache__c)) {
        fundingOpportunityIdsWithApplicationForms.add(applicationForm.ProgrammeRattache__c);
      }
    }
    return fundingOpportunityIdsWithApplicationForms;
  }
}