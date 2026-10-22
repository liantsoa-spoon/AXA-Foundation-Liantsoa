/**
 * @description : LWC entry point for "Communiquer les résultats de candidature" on a Programme (FundingOpportunity).
 *                Thin on purpose: all rules live in ApplicationResultEmailService.
 **/
public with sharing class ApplicationResultEmailController {
  /** Not cacheable: the screen must always show the real "already sent" state. */
  @AuraEnabled
  public static ApplicationResultEmailService.Overview getOverview(Id fundingOpportunityId) {
    try {
      return ApplicationResultEmailService.getOverview(fundingOpportunityId);
    } catch (Exception e) {
      throw toAuraException(e);
    }
  }

  @AuraEnabled
  public static ApplicationResultEmailService.SendSummary sendResults(
    Id fundingOpportunityId,
    List<Id> applicationFormIds
  ) {
    try {
      return ApplicationResultEmailService.sendResults(fundingOpportunityId, applicationFormIds);
    } catch (Exception e) {
      throw toAuraException(e);
    }
  }

  private static AuraHandledException toAuraException(Exception e) {
    final AuraHandledException auraException = new AuraHandledException(e.getMessage());
    auraException.setMessage(e.getMessage());
    return auraException;
  }
}