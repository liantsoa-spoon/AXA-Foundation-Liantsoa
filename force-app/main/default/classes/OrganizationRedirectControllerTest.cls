@isTest
private class OrganizationRedirectControllerTest {
  @testSetup
  static void setupTestData() {
    TestDataFactory.createPortalFixture();
    TestDataFactory.createOrganizationOwner();
  }

  @isTest
  static void testGetOrganizationIdReturnsAccountOfPortalUser() {
    final User portalUser = TestDataFactory.getPortalUser();
    final Account organization = [
      SELECT Id
      FROM Account
      WHERE LegalName__c = :TestDataFactory.DEFAULT_ORGANIZATION_LEGAL_NAME
    ];

    System.runAs(portalUser) {
      Test.startTest();
      final Id organizationId = OrganizationRedirectController.getOrganizationId();
      Test.stopTest();

      Assert.areEqual(organization.Id, organizationId, 'The portal user should be redirected to their own organization');
    }
  }

  @isTest
  static void testGetOrganizationIdReturnsNullWhenUserHasNoContact() {
    final User internalUser = TestDataFactory.createOrganizationOwner();

    System.runAs(internalUser) {
      Test.startTest();
      final Id organizationId = OrganizationRedirectController.getOrganizationId();
      Test.stopTest();

      Assert.isNull(organizationId, 'A user without a contact has no organization');
    }
  }
}