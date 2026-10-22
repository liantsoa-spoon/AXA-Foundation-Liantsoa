/**
 * @description       : Returns the portal form URL for a Funding Opportunity to the form link quick action.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 05-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   05-10-2026   KRA      Initial version
 **/
public with sharing class FundingOppFormLinkController {

  @AuraEnabled
  public static String getFormURL(Id fundingOpportunityId) {
    try {
      return FundingOppFormLinkService.refreshFormURLs(new List<Id>{ fundingOpportunityId })[0];
    } catch (Exception e) {
      final AuraHandledException auraException = new AuraHandledException(e.getMessage());
      auraException.setMessage(e.getMessage());
      throw auraException;
    }
  }
}