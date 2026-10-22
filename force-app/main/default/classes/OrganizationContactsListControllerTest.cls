@isTest
private class OrganizationContactsListControllerTest {
  @testSetup
  static void setupTestData() {
    final TestDataFactory.PortalFixture fixture = TestDataFactory.createPortalFixture();
    TestDataFactory.createContact(
      fixture.organization.Id,
      'Zoe',
      'Zulu',
      'zoe.zulu@axa-test.com',
      TestDataFactory.ROLE_LEGAL_REPRESENTATIVE
    );
    TestDataFactory.createContact(fixture.organization.Id, 'Adam', 'Alpha', 'adam.alpha@axa-test.com', null);

    final Account otherOrganization = TestDataFactory.createOrganization('Other Foundation', 'Other Foundation Legal');
    TestDataFactory.createContact(otherOrganization.Id, 'Other', 'Person', 'other.person@axa-test.com', null);
  }

  @isTest
  static void testGetContactsReturnsOwnOrganizationContactsSortedByName() {
    final User portalUser = TestDataFactory.getPortalUser();

    System.runAs(portalUser) {
      Test.startTest();
      final List<OrganizationContactsListController.ContactSummary> summaries =
        OrganizationContactsListController.getContacts();
      Test.stopTest();

      Assert.areEqual(3, summaries.size(), 'Only the contacts of the user organization should be returned');
      Assert.areEqual('Adam Alpha', summaries[0].name, 'Contacts should be sorted by name');
      Assert.areEqual('Olivia Operational', summaries[1].name, 'Contacts should be sorted by name');
      Assert.areEqual('Zoe Zulu', summaries[2].name, 'Contacts should be sorted by name');

      Assert.isNotNull(summaries[1].id, 'The summary should carry the contact Id');
      Assert.areEqual(TestDataFactory.ROLE_OPERATIONAL_CONTACT, summaries[1].role, 'The summary should carry the roles');
      Assert.areEqual(TestDataFactory.DEFAULT_OPERATIONAL_EMAIL, summaries[1].email, 'The summary should carry the email');
      Assert.areEqual('0102030405', summaries[1].phone, 'The summary should carry the phone');
      Assert.isNull(summaries[0].role, 'A contact without roles should have a null role');
    }
  }

  @isTest
  static void testGetContactsReturnsEmptyListWhenUserHasNoContact() {
    final User internalUser = TestDataFactory.createOrganizationOwner();

    System.runAs(internalUser) {
      Test.startTest();
      final List<OrganizationContactsListController.ContactSummary> summaries =
        OrganizationContactsListController.getContacts();
      Test.stopTest();

      Assert.isTrue(summaries.isEmpty(), 'A user without a contact has no organization contacts');
    }
  }
}