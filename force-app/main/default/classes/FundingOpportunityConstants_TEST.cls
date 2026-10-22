/**
 * @description       : Test class for FundingOpportunityConstants
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 13-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   08-10-2026   KRA      Initial version **/
@IsTest
private class FundingOpportunityConstants_TEST {
  @IsTest
  static void fundingOpportunityConstants_givenTestContext_createsInstance() {
    Assert.isNotNull(new FundingOpportunityConstants());
  }

  @IsTest
  static void recordTypes_givenDeclaredReferences_resolveToOrgRecordTypes() {
    final Map<String, Schema.RecordTypeInfo> recordTypeInfoByDeveloperName =
      Schema.SObjectType.FundingOpportunity.getRecordTypeInfosByDeveloperName();
    final RecordTypeProvider.RecordTypeReference callForProjects =
      FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS;
    final RecordTypeProvider.RecordTypeReference directManagement =
      FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT;

    Assert.areEqual(
      recordTypeInfoByDeveloperName.get(callForProjects.DeveloperName).getRecordTypeId(),
      callForProjects.Id
    );
    Assert.areEqual(
      recordTypeInfoByDeveloperName.get(directManagement.DeveloperName).getRecordTypeId(),
      directManagement.Id
    );
  }

  @IsTest
  static void picklistValues_givenDeclaredValues_areActiveValuesOfTheirField() {
    Assert.isTrue(
      TestDataFactory.getActivePicklistValues(FundingOpportunity.GeographicScope__c)
        .contains(FundingOpportunityConstants.GeographicScope.FRANCE)
    );
    Assert.isTrue(
      TestDataFactory.getActivePicklistValues(FundingOpportunity.Status)
        .contains(FundingOpportunityConstants.Status.DRAFT)
    );
    Assert.isTrue(
      TestDataFactory.getActivePicklistValues(FundingOpportunity.Theme__c)
        .contains(FundingOpportunityConstants.Theme.GLOBAL_CHAIRS)
    );
  }
}