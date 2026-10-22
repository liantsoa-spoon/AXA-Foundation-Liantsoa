/**
 * @description       : Test class for FundingOppFormLinkController
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 05-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   05-10-2026   KRA      Initial version
 **/
@IsTest
private class FundingOppFormLinkController_TEST {

  private static final String STUB_PORTAL_BASE_URL = 'https://portal.test/portal/s';

  @TestSetup
  static void createTestData() {
    FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled = false;
    insert TestDataFactory.buildFundingOpportunity(
      'Call For Projects Program',
      'CallForProjects',
      TestDataFactory.createPillar('Form Link Test Pillar').Id
    );
    TestDataFactory.createAdminUser(new List<String>{ 'AXA_Foundation_Admin', 'GrantmakingManager' });
  }

  @IsTest
  static void getFormURL_givenFundingOpportunity_returnsFormURL() {
    final Id fundingOpportunityId = getAnyFundingOpportunityId();
    FundingOppFormLinkService.cachedPortalBaseURL = STUB_PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getAdminUser()) {
      Assert.areEqual(
        FundingOppFormLinkService.refreshFormURLs(new List<Id>{ fundingOpportunityId })[0],
        FundingOppFormLinkController.getFormURL(fundingOpportunityId),
        'The controller must return the form URL built by the service'
      );
    }
  }

  @IsTest
  static void getFormURL_givenNullId_returnsNull() {
    FundingOppFormLinkService.cachedPortalBaseURL = STUB_PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getAdminUser()) {
      Assert.isNull(FundingOppFormLinkController.getFormURL(null), 'A null Id must return no form URL');
    }
  }

  @IsTest
  static void getFormURL_givenMissingPortal_throwsAuraHandledException() {
    final String missingUrlPathPrefix = 'missing-portal';
    FundingOppFormLinkService.portalUrlPathPrefix = missingUrlPathPrefix;

    try {
      FundingOppFormLinkController.getFormURL(getAnyFundingOpportunityId());
      Assert.fail('A missing portal must raise an AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().contains(missingUrlPathPrefix),
        'The error must reach the component with its message: ' + e.getMessage()
      );
    }
  }

  private static Id getAnyFundingOpportunityId() {
    return [
      SELECT
        Id
      FROM
        FundingOpportunity
      LIMIT
        1
    ].Id;
  }
}