@isTest
private class PortalContactCreationControllerTest {
  private static final String NEW_EMAIL = 'new.contact@axa-test.com';

  @testSetup
  static void setupTestData() {
    TestDataFactory.createPortalFixture();
  }

  private static String getRegularRole() {
    for (PortalContactCreationService.PicklistOption option : PortalContactCreationService.buildRoleOptions()) {
      if (option.value != TestDataFactory.ROLE_OPERATIONAL_CONTACT) {
        return option.value;
      }
    }
    return null;
  }

  private static void assertCreateContactError(String email, String firstName, String expectedMessage) {
    try {
      PortalContactCreationController.createContact(firstName, 'Newcomer', email, '0605040302', getRegularRole());
      Assert.fail('Expected ' + expectedMessage);
    } catch (AuraHandledException e) {
      Assert.areEqual(expectedMessage, e.getMessage(), 'Unexpected error code');
    }
  }

  @isTest
  static void testGetRoleOptionsReturnsRoles() {
    System.runAs(TestDataFactory.getPortalUser()) {
      Test.startTest();
      final List<PortalContactCreationService.PicklistOption> options = PortalContactCreationController.getRoleOptions();
      Test.stopTest();

      Assert.isFalse(options.isEmpty(), 'The role options should be returned');
    }
  }

  @isTest
  static void testCreateContactSuccess() {
    PortalContactCreationService.isPortalUserCreationEnabled = false;

    System.runAs(TestDataFactory.getPortalUser()) {
      Test.startTest();
      PortalContactCreationController.createContact('Nina', 'Newcomer', NEW_EMAIL, '0605040302', getRegularRole());
      Test.stopTest();
    }

    final Contact created = [SELECT FirstName, LastName, Phone, Roles__c FROM Contact WHERE Email = :NEW_EMAIL];
    Assert.areEqual('Nina', created.FirstName, 'First name should be saved');
    Assert.areEqual('Newcomer', created.LastName, 'Last name should be saved');
    Assert.areEqual('0605040302', created.Phone, 'Phone should be saved');
    Assert.areEqual(getRegularRole(), created.Roles__c, 'Role should be saved');
  }

  @isTest
  static void testCreateContactConvertsServiceErrorToAuraException() {
    System.runAs(TestDataFactory.getPortalUser()) {
      assertCreateContactError(
        'not-an-email',
        'Nina',
        PortalContactCreationService.ErrorCode.INVALID_EMAIL.name()
      );
      assertCreateContactError(
        NEW_EMAIL,
        null,
        PortalContactCreationService.ErrorCode.MISSING_DATA.name()
      );
    }
  }

  @isTest
  static void testCreateContactRejectsUserWithoutOperationalContact() {
    System.runAs(TestDataFactory.createOrganizationOwner()) {
      assertCreateContactError(
        NEW_EMAIL,
        'Nina',
        PortalContactCreationService.ErrorCode.NOT_OPERATIONAL_CONTACT.name()
      );
    }
  }

  @isTest
  static void testCreateContactHidesUnexpectedErrors() {
    PortalContactCreationService.isPortalUserCreationEnabled = false;

    System.runAs(TestDataFactory.getPortalUser()) {
      // Passes the format check of the service but is refused by the platform email validation.
      assertCreateContactError(
        'test@domain..com',
        'Nina',
        PortalContactCreationService.ErrorCode.UNEXPECTED_ERROR.name()
      );
    }
  }
}