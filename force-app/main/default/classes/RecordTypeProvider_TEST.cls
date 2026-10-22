/**
 * @description       : Test class for RecordTypeProvider
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 08-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   08-10-2026   KRA      Initial version
 **/
@IsTest
private class RecordTypeProvider_TEST {
  private static final String CALL_FOR_PROJECTS_DEVELOPER_NAME =
    FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS.DeveloperName;
  private static final String DIRECT_MANAGEMENT_DEVELOPER_NAME =
    FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT.DeveloperName;

  @IsTest
  static void recordTypeReference_givenNullObjectType_throwsRecordTypeException() {
    try {
      new RecordTypeProvider.RecordTypeReference(null, CALL_FOR_PROJECTS_DEVELOPER_NAME);
      Assert.fail('Expected a missing object type to be rejected.');
    } catch (RecordTypeProvider.RecordTypeException e) {
      Assert.areEqual('Object type is required.', e.getMessage());
    }
  }

  @IsTest
  static void recordTypeReference_givenBlankDeveloperName_throwsRecordTypeException() {
    for (String blankDeveloperName : new List<String>{ null, '', ' ' }) {
      try {
        new RecordTypeProvider.RecordTypeReference(FundingOpportunity.SObjectType, blankDeveloperName);
        Assert.fail('Expected a blank developer name to be rejected.');
      } catch (RecordTypeProvider.RecordTypeException e) {
        Assert.areEqual('Record type developer name is required.', e.getMessage());
      }
    }
  }

  @IsTest
  static void recordTypeReference_givenObjectTypeAndDeveloperName_exposesDeveloperName() {
    final RecordTypeProvider.RecordTypeReference recordTypeReference =
      new RecordTypeProvider.RecordTypeReference(FundingOpportunity.SObjectType, CALL_FOR_PROJECTS_DEVELOPER_NAME);

    Assert.areEqual(CALL_FOR_PROJECTS_DEVELOPER_NAME, recordTypeReference.DeveloperName);
  }

  @IsTest
  static void id_givenExistingRecordType_returnsItsIdOnEveryRead() {
    final RecordTypeProvider.RecordTypeReference recordTypeReference =
      new RecordTypeProvider.RecordTypeReference(FundingOpportunity.SObjectType, CALL_FOR_PROJECTS_DEVELOPER_NAME);

    Test.startTest();
    final Id firstReadId  = recordTypeReference.Id;
    final Id secondReadId = recordTypeReference.Id;
    Test.stopTest();

    Assert.areEqual(getExpectedRecordTypeId(CALL_FOR_PROJECTS_DEVELOPER_NAME), firstReadId);
    Assert.areEqual(firstReadId, secondReadId);
  }

  @IsTest
  static void id_givenTwoRecordTypesOfSameObject_returnsEachId() {
    final RecordTypeProvider.RecordTypeReference callForProjectsReference =
      new RecordTypeProvider.RecordTypeReference(FundingOpportunity.SObjectType, CALL_FOR_PROJECTS_DEVELOPER_NAME);
    final RecordTypeProvider.RecordTypeReference directManagementReference =
      new RecordTypeProvider.RecordTypeReference(FundingOpportunity.SObjectType, DIRECT_MANAGEMENT_DEVELOPER_NAME);

    Test.startTest();
    final Id callForProjectsId  = callForProjectsReference.Id;
    final Id directManagementId = directManagementReference.Id;
    Test.stopTest();

    Assert.areEqual(getExpectedRecordTypeId(CALL_FOR_PROJECTS_DEVELOPER_NAME), callForProjectsId);
    Assert.areEqual(getExpectedRecordTypeId(DIRECT_MANAGEMENT_DEVELOPER_NAME), directManagementId);
  }

  @IsTest
  static void id_givenUnknownDeveloperName_throwsRecordTypeException() {
    final RecordTypeProvider.RecordTypeReference recordTypeReference =
      new RecordTypeProvider.RecordTypeReference(FundingOpportunity.SObjectType, 'Unknown');

    Test.startTest();
    try {
      final Id recordTypeId = recordTypeReference.Id;
      Assert.fail('Expected an unknown record type to be rejected, got ' + recordTypeId + '.');
    } catch (RecordTypeProvider.RecordTypeException e) {
      Assert.areEqual(
        'No record type with developer name \'Unknown\' was found on FundingOpportunity.',
        e.getMessage()
      );
    }
    Test.stopTest();
  }

  private static Id getExpectedRecordTypeId(String developerName) {
    return Schema.SObjectType.FundingOpportunity.getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }
}