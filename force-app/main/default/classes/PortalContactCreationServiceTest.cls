@isTest
private class PortalContactCreationServiceTest {
  private static final String NEW_EMAIL = 'new.contact@axa-test.com';

  @testSetup
  static void setupTestData() {
    TestDataFactory.createPortalFixture();
  }

  private static Account getOrganization() {
    return [
      SELECT Id, OperationalContact__c
      FROM Account
      WHERE LegalName__c = :TestDataFactory.DEFAULT_ORGANIZATION_LEGAL_NAME
    ];
  }

  private static List<String> getNonOperationalRoles() {
    final List<String> roles = new List<String>();
    for (PortalContactCreationService.PicklistOption option : PortalContactCreationService.buildRoleOptions()) {
      if (option.value != TestDataFactory.ROLE_OPERATIONAL_CONTACT) {
        roles.add(option.value);
      }
    }
    return roles;
  }

  private static PortalContactCreationService.CreateContactRequest buildRequest(String email, String role) {
    final PortalContactCreationService.CreateContactRequest request =
      new PortalContactCreationService.CreateContactRequest();
    request.firstName = 'Nina';
    request.lastName = 'Newcomer';
    request.email = email;
    request.phone = '0605040302';
    request.role = role;
    return request;
  }

  private static void assertCreationError(
    PortalContactCreationService.CreateContactRequest request,
    PortalContactCreationService.ErrorCode expectedCode
  ) {
    try {
      PortalContactCreationService.createContact(request);
      Assert.fail('Expected ' + expectedCode.name());
    } catch (PortalContactCreationService.ContactCreationException e) {
      Assert.areEqual(expectedCode.name(), e.getMessage(), 'Unexpected error code');
    }
  }

  @isTest
  static void testBuildRoleOptionsReturnsActivePicklistValues() {
    Test.startTest();
    final List<PortalContactCreationService.PicklistOption> options = PortalContactCreationService.buildRoleOptions();
    Test.stopTest();

    Assert.isFalse(options.isEmpty(), 'The Roles picklist should have active values');
    Boolean hasOperationalRole = false;
    for (PortalContactCreationService.PicklistOption option : options) {
      Assert.isNotNull(option.label, 'Every option needs a label');
      Assert.isNotNull(option.value, 'Every option needs a value');
      hasOperationalRole = hasOperationalRole || option.value == TestDataFactory.ROLE_OPERATIONAL_CONTACT;
    }
    Assert.isTrue(hasOperationalRole, 'The operational contact role should be offered');
  }

  @isTest
  static void testCreateContactWithRegularRole() {
    PortalContactCreationService.isPortalUserCreationEnabled = false;
    final Account organization = getOrganization();
    final String role = getNonOperationalRoles()[0];

    System.runAs(TestDataFactory.getPortalUser()) {
      Test.startTest();
      PortalContactCreationService.createContact(buildRequest(NEW_EMAIL, role));
      Test.stopTest();
    }

    final Contact created = [SELECT AccountId, FirstName, LastName, Phone, Roles__c FROM Contact WHERE Email = :NEW_EMAIL];
    Assert.areEqual(organization.Id, created.AccountId, 'The contact should join the organization of the running user');
    Assert.areEqual('Nina', created.FirstName, 'First name should be copied from the request');
    Assert.areEqual('Newcomer', created.LastName, 'Last name should be copied from the request');
    Assert.areEqual('0605040302', created.Phone, 'Phone should be copied from the request');
    Assert.areEqual(role, created.Roles__c, 'Role should be copied from the request');
    Assert.areEqual(
      organization.OperationalContact__c,
      getOrganization().OperationalContact__c,
      'A regular role must not replace the operational contact'
    );
  }

  @isTest
  static void testCreateContactWithoutPhone() {
    PortalContactCreationService.isPortalUserCreationEnabled = false;
    final PortalContactCreationService.CreateContactRequest request = buildRequest(NEW_EMAIL, getNonOperationalRoles()[0]);
    request.phone = null;

    System.runAs(TestDataFactory.getPortalUser()) {
      Test.startTest();
      PortalContactCreationService.createContact(request);
      Test.stopTest();
    }

    Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Email = :NEW_EMAIL], 'The contact should be created without a phone');
  }

  @isTest
  static void testCreateContactReplacingOperationalContact() {
    PortalContactCreationService.isPortalUserCreationEnabled = false;

    System.runAs(TestDataFactory.getPortalUser()) {
      Test.startTest();
      PortalContactCreationService.createContact(buildRequest(NEW_EMAIL, TestDataFactory.ROLE_OPERATIONAL_CONTACT));
      Test.stopTest();
    }

    final Contact created = [SELECT Id FROM Contact WHERE Email = :NEW_EMAIL];
    Assert.areEqual(
      created.Id,
      getOrganization().OperationalContact__c,
      'The new contact should become the operational contact'
    );
  }

  @isTest
  static void testCreateContactCreatesPortalUser() {
    PortalContactCreationService.isPortalUserCreationEnabled = true;

    System.runAs(TestDataFactory.getPortalUser()) {
      Test.startTest();
      PortalContactCreationService.createContact(buildRequest(NEW_EMAIL, getNonOperationalRoles()[0]));
      Test.stopTest();
    }

    final Contact created = [SELECT Id FROM Contact WHERE Email = :NEW_EMAIL];
    final List<User> portalUsers = [SELECT Username FROM User WHERE ContactId = :created.Id];
    Assert.areEqual(1, portalUsers.size(), 'A portal user should be created for the new contact');
    Assert.areEqual(
      NEW_EMAIL,
      portalUsers[0].Username,
      'The username should be built from the email'
    );
  }

  @isTest
  static void testCreateContactFailsWhenPortalUsernameIsTaken() {
    PortalContactCreationService.isPortalUserCreationEnabled = true;
    final Account organization = getOrganization();
    final Contact holder = TestDataFactory.createContact(organization.Id, 'Hugo', 'Holder', 'holder@axa-test.com', null);
    TestDataFactory.createPortalUser(holder, NEW_EMAIL);

    System.runAs(TestDataFactory.getPortalUser()) {
      assertCreationError(
        buildRequest(NEW_EMAIL, getNonOperationalRoles()[0]),
        PortalContactCreationService.ErrorCode.PORTAL_USER_CREATION_FAILED
      );
    }
  }

  @isTest
  static void testCreateContactRejectsMissingData() {
    final String role = getNonOperationalRoles()[0];

    System.runAs(TestDataFactory.getPortalUser()) {
      assertCreationError(null, PortalContactCreationService.ErrorCode.MISSING_DATA);

      PortalContactCreationService.CreateContactRequest request = buildRequest(NEW_EMAIL, role);
      request.firstName = ' ';
      assertCreationError(request, PortalContactCreationService.ErrorCode.MISSING_DATA);

      request = buildRequest(NEW_EMAIL, role);
      request.lastName = null;
      assertCreationError(request, PortalContactCreationService.ErrorCode.MISSING_DATA);

      assertCreationError(buildRequest('', role), PortalContactCreationService.ErrorCode.MISSING_DATA);
      assertCreationError(buildRequest(NEW_EMAIL, null), PortalContactCreationService.ErrorCode.MISSING_DATA);
    }
  }

  @isTest
  static void testCreateContactRejectsInvalidEmail() {
    System.runAs(TestDataFactory.getPortalUser()) {
      assertCreationError(
        buildRequest('not-an-email', getNonOperationalRoles()[0]),
        PortalContactCreationService.ErrorCode.INVALID_EMAIL
      );
    }
  }

  @isTest
  static void testCreateContactRejectsInvalidInput() {
    final String role = getNonOperationalRoles()[0];

    System.runAs(TestDataFactory.getPortalUser()) {
      PortalContactCreationService.CreateContactRequest request = buildRequest(NEW_EMAIL, role);
      request.firstName = 'a'.repeat(Contact.FirstName.getDescribe().getLength() + 1);
      assertCreationError(request, PortalContactCreationService.ErrorCode.INVALID_INPUT);

      request = buildRequest(NEW_EMAIL, role);
      request.lastName = 'a'.repeat(Contact.LastName.getDescribe().getLength() + 1);
      assertCreationError(request, PortalContactCreationService.ErrorCode.INVALID_INPUT);

      request = buildRequest(NEW_EMAIL, role);
      request.phone = '1'.repeat(Contact.Phone.getDescribe().getLength() + 1);
      assertCreationError(request, PortalContactCreationService.ErrorCode.INVALID_INPUT);

      request = buildRequest('a@' + 'b'.repeat(Contact.Email.getDescribe().getLength()) + '.com', role);
      assertCreationError(request, PortalContactCreationService.ErrorCode.INVALID_INPUT);

      assertCreationError(
        buildRequest(NEW_EMAIL, 'Not A Role'),
        PortalContactCreationService.ErrorCode.INVALID_INPUT
      );
    }
  }

  @isTest
  static void testCreateContactRejectsUserWhoIsNotOperationalContact() {
    final Account otherOrganization = TestDataFactory.createOrganization('Other Foundation', 'Other Foundation Legal');
    final Contact regularContact = TestDataFactory.createContact(
      otherOrganization.Id,
      'Rita',
      'Regular',
      'regular@axa-test.com',
      null
    );
    final User regularUser = TestDataFactory.createPortalUser(regularContact);

    System.runAs(regularUser) {
      assertCreationError(
        buildRequest(NEW_EMAIL, getNonOperationalRoles()[0]),
        PortalContactCreationService.ErrorCode.NOT_OPERATIONAL_CONTACT
      );
    }
  }

  @isTest
  static void testCreateContactAllowsUserHoldingOperationalRoleWithoutAccountLookup() {
    final Account organization = TestDataFactory.createOrganization('Role Foundation', 'Role Foundation Legal');
    final Contact roleHolder = TestDataFactory.createContact(
      organization.Id,
      'Olga',
      'Operational',
      'olga@axa-test.com',
      'Administrative or Operational Representative'
    );
    final User roleHolderUser = TestDataFactory.createPortalUser(roleHolder);

    System.runAs(roleHolderUser) {
      PortalContactCreationService.createContact(buildRequest(NEW_EMAIL, getNonOperationalRoles()[0]));
    }

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Contact WHERE Email = :NEW_EMAIL AND AccountId = :organization.Id],
      'The contact should be created in the role holder organization'
    );
  }

  @isTest
  static void testCreateContactRejectsUserWithoutContact() {
    System.runAs(TestDataFactory.createOrganizationOwner()) {
      assertCreationError(
        buildRequest(NEW_EMAIL, getNonOperationalRoles()[0]),
        PortalContactCreationService.ErrorCode.NOT_OPERATIONAL_CONTACT
      );
    }
  }

  @isTest
  static void testCreateContactRejectsRoleAlreadyAssigned() {
    final String role = getNonOperationalRoles()[0];
    TestDataFactory.createContact(getOrganization().Id, 'Rolf', 'Roleholder', 'roleholder@axa-test.com', role);

    System.runAs(TestDataFactory.getPortalUser()) {
      assertCreationError(buildRequest(NEW_EMAIL, role), PortalContactCreationService.ErrorCode.ROLE_ALREADY_ASSIGNED);
    }
  }

  @isTest
  static void testCreateContactRejectsWhenRoleLimitReached() {
    final List<String> roles = getNonOperationalRoles();
    Assert.isTrue(roles.size() >= 4, 'The role limit test needs at least four non-operational roles');
    // The operational contact already holds one role, so three more reach the limit of four.
    TestDataFactory.createContact(
      getOrganization().Id,
      'Lena',
      'Limit',
      'limit@axa-test.com',
      roles[0] + ';' + roles[1] + ';' + roles[2]
    );

    System.runAs(TestDataFactory.getPortalUser()) {
      assertCreationError(buildRequest(NEW_EMAIL, roles[3]), PortalContactCreationService.ErrorCode.ROLE_LIMIT_REACHED);
    }
  }

  @isTest
  static void testCreateContactAllowsOperationalRoleWhenRoleLimitReached() {
    PortalContactCreationService.isPortalUserCreationEnabled = false;
    final List<String> roles = getNonOperationalRoles();
    Assert.isTrue(roles.size() >= 3, 'The test needs at least three non-operational roles');
    TestDataFactory.createContact(
      getOrganization().Id,
      'Lena',
      'Limit',
      'limit@axa-test.com',
      roles[0] + ';' + roles[1] + ';' + roles[2]
    );

    System.runAs(TestDataFactory.getPortalUser()) {
      Test.startTest();
      PortalContactCreationService.createContact(buildRequest(NEW_EMAIL, TestDataFactory.ROLE_OPERATIONAL_CONTACT));
      Test.stopTest();
    }

    Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Email = :NEW_EMAIL], 'The operational role is exempt from the role rules');
  }

  @isTest
  static void testCreateContactRejectsEmailAlreadyRegisteredInOrganization() {
    TestDataFactory.createContact(getOrganization().Id, 'Eva', 'Existing', NEW_EMAIL, null);

    System.runAs(TestDataFactory.getPortalUser()) {
      assertCreationError(
        buildRequest(NEW_EMAIL, getNonOperationalRoles()[0]),
        PortalContactCreationService.ErrorCode.EMAIL_ALREADY_REGISTERED
      );
    }
  }

  @isTest
  static void testCreateContactRejectsEmailOfAnotherOrganization() {
    final Account otherOrganization = TestDataFactory.createOrganization('Other Foundation', 'Other Foundation Legal');
    TestDataFactory.createContact(otherOrganization.Id, 'Otto', 'Other', NEW_EMAIL, null);

    System.runAs(TestDataFactory.getPortalUser()) {
      assertCreationError(
        buildRequest(NEW_EMAIL, getNonOperationalRoles()[0]),
        PortalContactCreationService.ErrorCode.EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION
      );
    }
  }

  @isTest
  static void testCreateContactPropagatesNonDuplicateDmlErrors() {
    PortalContactCreationService.isPortalUserCreationEnabled = false;
    // Passes the format check of the service but is refused by the platform email validation.
    final PortalContactCreationService.CreateContactRequest request =
      buildRequest('test@domain..com', getNonOperationalRoles()[0]);

    System.runAs(TestDataFactory.getPortalUser()) {
      Test.startTest();
      try {
        PortalContactCreationService.createContact(request);
        Assert.fail('Expected the DML error to propagate');
      } catch (DmlException e) {
        Assert.areNotEqual(StatusCode.DUPLICATES_DETECTED, e.getDmlType(0), 'Only duplicate errors are translated');
      }
      Test.stopTest();
    }
  }
}