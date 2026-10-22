/**
 * @description       : Builds, updates, and returns portal form URLs for Funding Opportunities.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 05-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   05-10-2026   KRA      Initial version
 **/
public without sharing class FundingOppFormLinkService {

  public class PortalNotFoundException extends Exception {}

  private static final String LOGIN_PAGE_PATH = '/login';
  private static final String FORM_PAGE_PATH_WITH_FUNDING_OPPORTUNITY_ID_PARAMETER = '/formulaire?id=';

  @TestVisible
  private static String portalUrlPathPrefix = 'portal';
  @TestVisible
  private static String cachedPortalBaseURL;

  @InvocableMethod(
    label='Refresh Form URLs'
    description='Builds portal form URLs, updates FormURL__c when needed, and returns the URLs.'
  )
  public static List<String> refreshFormURLs(List<Id> fundingOpportunityIds) {
    final List<String> formURLs = new List<String>();
    if (fundingOpportunityIds == null || fundingOpportunityIds.isEmpty()) {
      return formURLs;
    }

    final Map<Id, String> formURLsByFundingOpportunityId = updateFormURLs(new Set<Id>(fundingOpportunityIds));
    for (Id fundingOpportunityId : fundingOpportunityIds) {
      formURLs.add(formURLsByFundingOpportunityId.get(fundingOpportunityId));
    }
    return formURLs;
  }

  private static Map<Id, String> updateFormURLs(Set<Id> fundingOpportunityIds) {
    final String formURLPrefix = getPortalBaseURL() + FORM_PAGE_PATH_WITH_FUNDING_OPPORTUNITY_ID_PARAMETER;
    final Map<Id, String> formURLsByFundingOpportunityId = new Map<Id, String>();
    final List<FundingOpportunity> fundingOpportunitiesToUpdate = new List<FundingOpportunity>();

    for (FundingOpportunity fundingOpportunity : [
      SELECT
        Id,
        FormURL__c
      FROM
        FundingOpportunity
      WHERE
        Id IN :fundingOpportunityIds
      WITH
        SYSTEM_MODE
    ]) {
      final String formURL = formURLPrefix + fundingOpportunity.Id;
      formURLsByFundingOpportunityId.put(fundingOpportunity.Id, formURL);

      if (!formURL.equals(fundingOpportunity.FormURL__c)) {
        fundingOpportunitiesToUpdate.add(new FundingOpportunity(Id = fundingOpportunity.Id, FormURL__c = formURL));
      }
    }

    if (!fundingOpportunitiesToUpdate.isEmpty()) {
      Database.update(fundingOpportunitiesToUpdate, AccessLevel.SYSTEM_MODE);
    }
    return formURLsByFundingOpportunityId;
  }

  private static String getPortalBaseURL() {
    if (cachedPortalBaseURL == null) {
      final List<Network> portalNetworks = [
        SELECT
          Id
        FROM
          Network
        WHERE
          UrlPathPrefix = :portalUrlPathPrefix
        WITH
          SYSTEM_MODE
        LIMIT
          1
      ];
      if (portalNetworks.isEmpty()) {
        throw new PortalNotFoundException(
          'No Experience Cloud site has the URL path prefix "' + portalUrlPathPrefix + '".'
        );
      }
      cachedPortalBaseURL = Network.getLoginUrl(portalNetworks[0].Id).removeEnd('/').removeEnd(LOGIN_PAGE_PATH);
    }
    return cachedPortalBaseURL;
  }
}