/**
 * @description       : Test class for FundingOppFormLinkService
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 05-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   05-10-2026   KRA      Initial version
 **/
@IsTest
private class FundingOppFormLinkService_TEST {

  private static final String PORTAL_BASE_URL = 'https://portal.test/portal/s';
  private static final String SUPER_ADMINISTRATOR_PROFILE_NAME = 'Super Administrator';
  private static final String MINIMUM_ACCESS_PROFILE_NAME      = 'Minimum Access - Salesforce';

  @TestSetup
  static void createTestData() {
    FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled = false;
    final Id pillarId = TestDataFactory.createPillar('Form Link Test Pillar').Id;
    insert new List<FundingOpportunity>{
      TestDataFactory.buildFundingOpportunity('Call For Projects Program', 'CallForProjects', pillarId),
      TestDataFactory.buildFundingOpportunity('Direct Management Program', 'DirectManagement', pillarId)
    };

    final List<String> permissionSetNames = new List<String>{ 'AXA_Foundation_Admin', 'GrantmakingManager' };
    TestDataFactory.createAdminUser(permissionSetNames);
    TestDataFactory.createUser(SUPER_ADMINISTRATOR_PROFILE_NAME, permissionSetNames);
    TestDataFactory.createUser(MINIMUM_ACCESS_PROFILE_NAME, new List<String>());
  }

  @IsTest
  static void refreshFormURLs_givenAnyRecordType_returnsFormURL() {
    final Id callForProjectsId  = getAnyFundingOpportunityIdByRecordType('CallForProjects');
    final Id directManagementId = getAnyFundingOpportunityIdByRecordType('DirectManagement');
    FundingOppFormLinkService.cachedPortalBaseURL = PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getAdminUser()) {
      Assert.areEqual(
        new List<String>{ buildExpectedFormURL(callForProjectsId), buildExpectedFormURL(directManagementId) },
        FundingOppFormLinkService.refreshFormURLs(new List<Id>{ callForProjectsId, directManagementId }),
        'Call for Projects and Direct Management programs must link to the same form page'
      );
    }
  }

  @IsTest
  static void refreshFormURLs_givenReadOnlyField_updatesFormURL() {
    final Id fundingOpportunityId = getAnyFundingOpportunityIdByRecordType('CallForProjects');
    FundingOppFormLinkService.cachedPortalBaseURL = PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getUser(SUPER_ADMINISTRATOR_PROFILE_NAME)) {
      final Schema.DescribeFieldResult formURLField = Schema.SObjectType.FundingOpportunity.fields.FormURL__c;
      Assert.isTrue(formURLField.isAccessible(), 'The test user must be able to read FormURL__c');
      Assert.isFalse(formURLField.isUpdateable(), 'FormURL__c must be read-only for the test user');

      FundingOppFormLinkService.refreshFormURLs(new List<Id>{ fundingOpportunityId });
    }

    Assert.areEqual(
      buildExpectedFormURL(fundingOpportunityId),
      getUpdatedFormURL(fundingOpportunityId),
      'The service must update the form URL even though the field is read-only for the user'
    );
  }

  @IsTest
  static void refreshFormURLs_givenUserWithoutAccess_returnsAndUpdatesFormURL() {
    final Id fundingOpportunityId = getAnyFundingOpportunityIdByRecordType('CallForProjects');
    final String expectedFormURL = buildExpectedFormURL(fundingOpportunityId);
    FundingOppFormLinkService.cachedPortalBaseURL = PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getUser(MINIMUM_ACCESS_PROFILE_NAME)) {
      Assert.isFalse(
        Schema.SObjectType.FundingOpportunity.isAccessible(),
        'The test user must not be able to read Funding Opportunities'
      );
      Assert.areEqual(
        new List<String>{ expectedFormURL },
        FundingOppFormLinkService.refreshFormURLs(new List<Id>{ fundingOpportunityId }),
        'A user without access to the Funding Opportunity, such as a portal candidate, must still get its form URL'
      );
    }

    Assert.areEqual(
      expectedFormURL,
      getUpdatedFormURL(fundingOpportunityId),
      'The service must update the form URL even though the user cannot access the Funding Opportunity'
    );
  }

  @IsTest
  static void refreshFormURLs_givenUpToDateFormURL_skipsUpdate() {
    final List<Id> fundingOpportunityIds = new List<Id>{ getAnyFundingOpportunityIdByRecordType('CallForProjects') };
    FundingOppFormLinkService.cachedPortalBaseURL = PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getAdminUser()) {
      FundingOppFormLinkService.refreshFormURLs(fundingOpportunityIds);
      final Integer dmlStatementsBeforeSecondRefresh = Limits.getDmlStatements();
      FundingOppFormLinkService.refreshFormURLs(fundingOpportunityIds);

      Assert.areEqual(
        dmlStatementsBeforeSecondRefresh,
        Limits.getDmlStatements(),
        'An up-to-date form URL must not be updated again'
      );
    }
  }

  @IsTest
  static void refreshFormURLs_givenStaleFormURL_overwritesFormURL() {
    final Id fundingOpportunityId = getAnyFundingOpportunityIdByRecordType('CallForProjects');
    Database.update(
      new FundingOpportunity(Id = fundingOpportunityId, FormURL__c = 'https://stale.test/portal/s/formulaire'),
      AccessLevel.SYSTEM_MODE
    );
    FundingOppFormLinkService.cachedPortalBaseURL = PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getAdminUser()) {
      FundingOppFormLinkService.refreshFormURLs(new List<Id>{ fundingOpportunityId });
    }

    Assert.areEqual(
      buildExpectedFormURL(fundingOpportunityId),
      getUpdatedFormURL(fundingOpportunityId),
      'A stale form URL, such as one copied by a sandbox refresh, must be overwritten'
    );
  }

  @IsTest
  static void refreshFormURLs_givenMixedInput_preservesOrderAndUpdatesUniqueRecords() {
    final Id callForProjectsId  = getAnyFundingOpportunityIdByRecordType('CallForProjects');
    final Id directManagementId = getAnyFundingOpportunityIdByRecordType('DirectManagement');
    final String callForProjectsFormURL = buildExpectedFormURL(callForProjectsId);
    FundingOppFormLinkService.cachedPortalBaseURL = PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getAdminUser()) {
      final Integer dmlStatementsBefore = Limits.getDmlStatements();
      final Integer dmlRowsBefore       = Limits.getDmlRows();

      Assert.areEqual(
        new List<String>{
          callForProjectsFormURL,
          null,
          buildExpectedFormURL(directManagementId),
          callForProjectsFormURL
        },
        FundingOppFormLinkService.refreshFormURLs(
          new List<Id>{ callForProjectsId, null, directManagementId, callForProjectsId }
        ),
        'Each input must get its form URL at its own position, repeated Ids included'
      );
      Assert.areEqual(
        dmlStatementsBefore + 1,
        Limits.getDmlStatements(),
        'All form URLs must be updated in one DML statement'
      );
      Assert.areEqual(dmlRowsBefore + 2, Limits.getDmlRows(), 'A repeated Funding Opportunity must be updated once');
    }
  }

  @IsTest
  static void refreshFormURLs_given200FundingOpportunities_usesOneQueryAndOneDMLStatement() {
    FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled = false;
    final Id pillarId = [
      SELECT
        Id
      FROM
        Program
      LIMIT
        1
    ].Id;
    final List<FundingOpportunity> fundingOpportunities = new List<FundingOpportunity>();
    for (Integer index = 0; index < 200; index++) {
      fundingOpportunities.add(
        TestDataFactory.buildFundingOpportunity('Bulk Program ' + index, 'CallForProjects', pillarId)
      );
    }
    insert fundingOpportunities;
    final List<Id> fundingOpportunityIds =
      new List<Id>(new Map<Id, FundingOpportunity>(fundingOpportunities).keySet());
    FundingOppFormLinkService.cachedPortalBaseURL = PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getAdminUser()) {
      final Integer dmlStatementsBeforeFirstRefresh = Limits.getDmlStatements();
      FundingOppFormLinkService.refreshFormURLs(fundingOpportunityIds);
      Assert.areEqual(
        dmlStatementsBeforeFirstRefresh + 1,
        Limits.getDmlStatements(),
        'The 200 form URLs must be updated in one DML statement'
      );

      final Integer queriesBeforeSecondRefresh = Limits.getQueries();
      FundingOppFormLinkService.refreshFormURLs(fundingOpportunityIds);
      Assert.areEqual(
        queriesBeforeSecondRefresh + 1,
        Limits.getQueries(),
        'The 200 Funding Opportunities must be read in one query'
      );
    }
  }

  @IsTest
  static void refreshFormURLs_givenDeletedFundingOpportunity_returnsNullWithoutUpdate() {
    final Id fundingOpportunityId = getAnyFundingOpportunityIdByRecordType('CallForProjects');
    Database.update(new FundingOpportunity(Id = fundingOpportunityId, Status = 'Draft'), AccessLevel.SYSTEM_MODE);
    Database.delete(new FundingOpportunity(Id = fundingOpportunityId), AccessLevel.SYSTEM_MODE);
    FundingOppFormLinkService.cachedPortalBaseURL = PORTAL_BASE_URL;

    System.runAs(TestDataFactory.getAdminUser()) {
      final Integer dmlStatementsBefore = Limits.getDmlStatements();

      Assert.areEqual(
        new List<String>{ null },
        FundingOppFormLinkService.refreshFormURLs(new List<Id>{ fundingOpportunityId }),
        'A deleted Funding Opportunity must get no form URL'
      );
      Assert.areEqual(
        dmlStatementsBefore,
        Limits.getDmlStatements(),
        'A deleted Funding Opportunity must not be updated'
      );
    }
  }

  @IsTest
  static void refreshFormURLs_givenNullOrEmptyList_returnsEmptyList() {
    final Integer queriesBefore = Limits.getQueries();

    Assert.isTrue(
      FundingOppFormLinkService.refreshFormURLs(null).isEmpty(),
      'A null list must return an empty list'
    );
    Assert.isTrue(
      FundingOppFormLinkService.refreshFormURLs(new List<Id>()).isEmpty(),
      'An empty list must return an empty list'
    );
    Assert.areEqual(queriesBefore, Limits.getQueries(), 'No query must run without Funding Opportunities');
  }

  @IsTest
  static void refreshFormURLs_givenMissingPortal_throwsPortalNotFoundException() {
    final String missingUrlPathPrefix = 'missing-portal';
    FundingOppFormLinkService.portalUrlPathPrefix = missingUrlPathPrefix;

    try {
      FundingOppFormLinkService.refreshFormURLs(
        new List<Id>{ getAnyFundingOpportunityIdByRecordType('CallForProjects') }
      );
      Assert.fail('A missing portal must raise a PortalNotFoundException');
    } catch (FundingOppFormLinkService.PortalNotFoundException e) {
      Assert.isTrue(
        e.getMessage().contains(missingUrlPathPrefix),
        'The error must name the missing URL path prefix: ' + e.getMessage()
      );
    }
  }

  // ============================== <Helpers> ==============================

  private static Id getAnyFundingOpportunityIdByRecordType(String recordTypeDeveloperName) {
    return [
      SELECT
        Id
      FROM
        FundingOpportunity
      WHERE
        RecordType.DeveloperName = :recordTypeDeveloperName
      LIMIT
        1
    ].Id;
  }

  private static String getUpdatedFormURL(Id fundingOpportunityId) {
    return [
      SELECT
        FormURL__c
      FROM
        FundingOpportunity
      WHERE
        Id = :fundingOpportunityId
    ].FormURL__c;
  }

  private static String buildExpectedFormURL(Id fundingOpportunityId) {
    return PORTAL_BASE_URL + '/formulaire?id=' + fundingOpportunityId;
  }

  // ============================== </Helpers> ==============================
}