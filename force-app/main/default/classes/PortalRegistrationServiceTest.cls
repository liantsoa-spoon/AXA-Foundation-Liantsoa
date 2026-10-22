@isTest
private class PortalRegistrationServiceTest {
  private static final String NEW_LEGAL_NAME = 'Brand New Legal Name';
  private static final String CANDIDATE_EMAIL = 'candidate@org-test.com';
  private static final String LEGAL_REPRESENTATIVE_EMAIL = 'legalrep@org-test.com';
  private static final String OTHER_LEGAL_FORM = 'Other (please specify)';

  private static final String DATA_ACCEPTANCE_FORM_NAME = 'Data Acceptance';
  private static final String DATA_ACCEPTANCE_EN_NAME   = 'Data Acceptance EN';
  private static final String DATA_ACCEPTANCE_FR_NAME   = 'Data Acceptance FR';
  private static final String DATA_ACCEPTANCE_EN_URL    = 'https://example.com/data-acceptance-en';
  private static final String DATA_ACCEPTANCE_FR_URL    = 'https://example.com/data-acceptance-fr';

  @testSetup
  static void setupTestData() {
    TestDataFactory.createPortalFixture();
    createDataAcceptanceForm('1', Date.today().addDays(-1), null);
  }

  private static AuthorizationForm createDataAcceptanceForm(
    String revisionNumber,
    Date effectiveFromDate,
    Date effectiveToDate
  ) {
    final AuthorizationForm dataAcceptanceForm = new AuthorizationForm(
      Name              = DATA_ACCEPTANCE_FORM_NAME,
      RevisionNumber    = revisionNumber,
      EffectiveFromDate = effectiveFromDate,
      EffectiveToDate   = effectiveToDate
    );
    insert dataAcceptanceForm;

    final AuthorizationFormText englishText = new AuthorizationFormText(
      Name                     = DATA_ACCEPTANCE_EN_NAME,
      AuthorizationFormId      = dataAcceptanceForm.Id,
      Locale                   = 'en_US',
      FullAuthorizationFormUrl = DATA_ACCEPTANCE_EN_URL
    );
    final AuthorizationFormText frenchText = new AuthorizationFormText(
      Name                     = DATA_ACCEPTANCE_FR_NAME,
      AuthorizationFormId      = dataAcceptanceForm.Id,
      Locale                   = 'fr_FR',
      FullAuthorizationFormUrl = DATA_ACCEPTANCE_FR_URL
    );
    insert new List<AuthorizationFormText>{ englishText, frenchText };

    dataAcceptanceForm.DefaultAuthFormTextId = englishText.Id;
    update dataAcceptanceForm;
    return dataAcceptanceForm;
  }

  private static Id findDataAcceptanceFormTextId() {
    return findDataAcceptanceFormTextId(DATA_ACCEPTANCE_EN_NAME);
  }

  private static Id findDataAcceptanceFormTextId(String formTextName) {
    return [
      SELECT
        Id
      FROM
        AuthorizationFormText
      WHERE
        Name = :formTextName
      ORDER BY
        AuthorizationForm.RevisionNumber DESC
      LIMIT
        1
    ].Id;
  }

  private static void expireDataAcceptanceForms() {
    final List<AuthorizationForm> dataAcceptanceForms = [
      SELECT
        Id
      FROM
        AuthorizationForm
      WHERE
        Name = :DATA_ACCEPTANCE_FORM_NAME
    ];
    for (AuthorizationForm dataAcceptanceForm : dataAcceptanceForms) {
      dataAcceptanceForm.EffectiveToDate = Date.today().addDays(-1);
    }
    update dataAcceptanceForms;
  }

  private static String firstValue(Schema.DescribeFieldResult fieldDescribe) {
    final List<PortalRegistrationService.PicklistOption> options =
      PortalRegistrationService.buildPicklistOptions(fieldDescribe);
    return options.isEmpty() ? null : options[0].value;
  }

  private static PortalRegistrationService.ContactInput buildContactInput(String email) {
    final PortalRegistrationService.ContactInput contactInput = new PortalRegistrationService.ContactInput();
    contactInput.salutation = firstValue(Contact.Salutation.getDescribe());
    contactInput.firstName = 'Cara';
    contactInput.lastName = 'Candidate';
    contactInput.title = 'Director';
    contactInput.birthdate = Date.newInstance(1990, 1, 1);
    contactInput.phone = '0102030405';
    contactInput.email = email;
    return contactInput;
  }

  private static PortalRegistrationService.OrganizationInput buildOrganizationInput() {
    final PortalRegistrationService.OrganizationInput organizationInput = new PortalRegistrationService.OrganizationInput();
    organizationInput.name = 'New Foundation';
    organizationInput.legalForm = firstValue(Account.LegalForm__c.getDescribe());
    organizationInput.identificationNumber = 'ID-123';
    organizationInput.foundingDate = Date.newInstance(2010, 5, 20);
    organizationInput.country = 'France';
    organizationInput.street = '1 rue de Test';
    organizationInput.postalCode = '75001';
    organizationInput.foundingBackground = 'Background';
    organizationInput.description = 'Description';
    organizationInput.keyDates = 'Key dates';
    organizationInput.objectives = 'Objectives';
    organizationInput.mainActivities = 'Main activities';
    organizationInput.authorizedToIssueTaxReceipts = firstValue(Account.AuthorizedToIssueTaxReceipts__c.getDescribe());
    organizationInput.keyFigures = 'Key figures';
    organizationInput.website = 'https://example.com';

    final PortalRegistrationService.ContactInput legalRepresentative = new PortalRegistrationService.ContactInput();
    legalRepresentative.salutation = firstValue(Contact.Salutation.getDescribe());
    legalRepresentative.title      = 'President';
    legalRepresentative.firstName  = 'Leo';
    legalRepresentative.lastName   = 'Representative';
    legalRepresentative.birthdate  = Date.newInstance(1975, 6, 15);
    legalRepresentative.email      = LEGAL_REPRESENTATIVE_EMAIL;
    legalRepresentative.phone      = '0605040302';
    organizationInput.legalRepresentative = legalRepresentative;
    return organizationInput;
  }

  private static void assertRegistrationError(
    String legalName,
    PortalRegistrationService.ContactInput candidate,
    PortalRegistrationService.OrganizationInput organization,
    PortalRegistrationService.ErrorCode expectedCode
  ) {
    try {
      PortalRegistrationService.registerCandidate(legalName, candidate, organization, findDataAcceptanceFormTextId());
      Assert.fail('Expected ' + expectedCode.name());
    } catch (PortalRegistrationService.RegistrationException e) {
      Assert.areEqual(expectedCode.name(), e.getMessage(), 'Unexpected error code');
    }
  }

  @isTest
  static void testBuildPicklistOptionsReturnsActiveValues() {
    Test.startTest();
    final List<PortalRegistrationService.PicklistOption> options =
      PortalRegistrationService.buildPicklistOptions(Account.LegalForm__c.getDescribe());
    Test.stopTest();

    Assert.isFalse(options.isEmpty(), 'The legal form picklist should have active values');
    for (PortalRegistrationService.PicklistOption option : options) {
      Assert.isNotNull(option.label, 'Every option needs a label');
      Assert.isNotNull(option.value, 'Every option needs a value');
    }
  }

  @isTest
  static void testSearchMatchingOrganizationLegalNamesFindsMatches() {
    TestDataFactory.createOrganization('Alpha', 'Zeta Foundation Test');

    Test.startTest();
    final List<String> legalNames = PortalRegistrationService.searchMatchingOrganizationLegalNames('foundation');
    Test.stopTest();

    Assert.areEqual(2, legalNames.size(), 'Both matching legal names should be returned');
    Assert.areEqual(TestDataFactory.DEFAULT_ORGANIZATION_LEGAL_NAME, legalNames[0], 'Results should be sorted by legal name');
    Assert.areEqual('Zeta Foundation Test', legalNames[1], 'Results should be sorted by legal name');
  }

  @isTest
  static void testSearchMatchingOrganizationLegalNamesLimitsSuggestions() {
    final List<Id> accountIds = new List<Id>();
    for (Integer i = 0; i < 11; i++) {
      Account acc = TestDataFactory.createOrganization(
        'Searchable ' + i,
        'Searchable Legal ' + String.valueOf(100 + i)
      );
      accountIds.add(acc.Id);
    }
    Test.setFixedSearchResults(accountIds);

    Test.startTest();
    final List<String> legalNames = PortalRegistrationService.searchMatchingOrganizationLegalNames('Searchable Legal');
    Test.stopTest();

    Assert.areEqual(10, legalNames.size(), 'At most ten suggestions should be returned');
  }

  @isTest
  static void testSearchMatchingOrganizationLegalNamesIgnoresInvalidSearches() {
    Test.startTest();
    final List<String> nullResult = PortalRegistrationService.searchMatchingOrganizationLegalNames(null);
    final List<String> shortResult = PortalRegistrationService.searchMatchingOrganizationLegalNames('ab');
    final List<String> longResult = PortalRegistrationService.searchMatchingOrganizationLegalNames(
      'a'.repeat(Account.LegalName__c.getDescribe().getLength() + 1)
    );
    final List<String> wildcardResult = PortalRegistrationService.searchMatchingOrganizationLegalNames('%%%');
    final List<String> underscoreResult = PortalRegistrationService.searchMatchingOrganizationLegalNames('___');
    Test.stopTest();

    Assert.isTrue(nullResult.isEmpty(), 'A null search should return nothing');
    Assert.isTrue(shortResult.isEmpty(), 'A search under three characters should return nothing');
    Assert.isTrue(longResult.isEmpty(), 'A search longer than the field should return nothing');
    Assert.isTrue(wildcardResult.isEmpty(), 'Wildcards should be escaped and matched literally');
    Assert.isTrue(underscoreResult.isEmpty(), 'Wildcards should be escaped and matched literally');
  }

  @isTest
  static void testCheckOrganizationExistsReturnsFalseWhenUnknown() {
    Test.startTest();
    final PortalRegistrationService.OrganizationLookupResult result =
      PortalRegistrationService.checkOrganizationExists(NEW_LEGAL_NAME);
    Test.stopTest();

    Assert.isFalse(result.exists, 'An unknown organization should not exist');
    Assert.isNull(result.operationalContactName, 'No operational contact name expected');
  }

  @isTest
  static void testCheckOrganizationExistsReturnsOperationalContactName() {
    Test.startTest();
    final PortalRegistrationService.OrganizationLookupResult result =
      PortalRegistrationService.checkOrganizationExists(TestDataFactory.DEFAULT_ORGANIZATION_LEGAL_NAME);
    Test.stopTest();

    Assert.isTrue(result.exists, 'The organization should exist');
    Assert.areEqual('Olivia Operational', result.operationalContactName, 'The operational contact name should be returned');
    Assert.areEqual(1, [SELECT COUNT() FROM User WHERE Contact.Email = :TestDataFactory.DEFAULT_OPERATIONAL_EMAIL], 'No extra portal user should be created');
  }

  @isTest
  static void testCheckOrganizationExistsWithoutOperationalContact() {
    TestDataFactory.createOrganization('No Contact Foundation', 'No Contact Legal Name');

    Test.startTest();
    final PortalRegistrationService.OrganizationLookupResult result =
      PortalRegistrationService.checkOrganizationExists('No Contact Legal Name');
    Test.stopTest();

    Assert.isTrue(result.exists, 'The organization should exist');
    Assert.isNull(result.operationalContactName, 'An organization without operational contact has no name');
  }

  @isTest
  static void testCheckOrganizationExistsCreatesMissingPortalUser() {
    final Account organization = TestDataFactory.createOrganization('Pending Foundation', 'Pending Legal Name');
    final Contact operationalContact = TestDataFactory.createOperationalContact(organization, 'pending@org-test.com');
    PortalRegistrationService.isPortalUserCreationEnabled = true;

    System.runAs(TestDataFactory.createOrganizationOwner()) {
      Test.startTest();
      final PortalRegistrationService.OrganizationLookupResult result =
        PortalRegistrationService.checkOrganizationExists('Pending Legal Name');
      Test.stopTest();

      Assert.isTrue(result.exists, 'The organization should exist');
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM User WHERE ContactId = :operationalContact.Id],
        'A portal user should be created for the operational contact'
      );
    }
  }

  @isTest
  static void testCheckOrganizationExistsSkipsPortalUserWhenDisabled() {
    final Account organization = TestDataFactory.createOrganization('Pending Foundation', 'Pending Legal Name');
    final Contact operationalContact = TestDataFactory.createOperationalContact(organization, 'pending@org-test.com');
    PortalRegistrationService.isPortalUserCreationEnabled = false;

    Test.startTest();
    PortalRegistrationService.checkOrganizationExists('Pending Legal Name');
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM User WHERE ContactId = :operationalContact.Id], 'No portal user should be created when disabled');
  }

  @isTest
  static void testCheckOrganizationExistsFailsWhenOperationalContactHasNoEmail() {
    final Account organization = TestDataFactory.createOrganization('Pending Foundation', 'Pending Legal Name');
    final Contact operationalContact = TestDataFactory.createContact(
      organization.Id,
      'Nora',
      'NoEmail',
      null,
      TestDataFactory.ROLE_OPERATIONAL_CONTACT
    );
    organization.OperationalContact__c = operationalContact.Id;
    update organization;
    PortalRegistrationService.isPortalUserCreationEnabled = true;

    Test.startTest();
    try {
      PortalRegistrationService.checkOrganizationExists('Pending Legal Name');
      Assert.fail('Expected PORTAL_USER_CREATION_FAILED');
    } catch (PortalRegistrationService.RegistrationException e) {
      Assert.areEqual(
        PortalRegistrationService.ErrorCode.PORTAL_USER_CREATION_FAILED.name(),
        e.getMessage(),
        'A portal user cannot be created without an email'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCheckOrganizationExistsRejectsTooLongLegalName() {
    Test.startTest();
    try {
      PortalRegistrationService.checkOrganizationExists('a'.repeat(Account.LegalName__c.getDescribe().getLength() + 1));
      Assert.fail('Expected INVALID_INPUT');
    } catch (PortalRegistrationService.RegistrationException e) {
      Assert.areEqual(PortalRegistrationService.ErrorCode.INVALID_INPUT.name(), e.getMessage(), 'Unexpected error code');
    }
    Test.stopTest();
  }

  @isTest
  static void testRegisterCandidateCreatesOrganizationAndContacts() {
    PortalRegistrationService.isPortalUserCreationEnabled = false;

    Test.startTest();
    PortalRegistrationService.registerCandidate(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      buildOrganizationInput(),
      findDataAcceptanceFormTextId()
    );
    Test.stopTest();

    final Account organization = [
      SELECT Name, LegalForm__c, IdentificationNum__c, BillingCountry,
        OperationalContact__c, LegalRepresentative__c
      FROM Account
      WHERE LegalName__c = :NEW_LEGAL_NAME
    ];
    final Contact candidate = [SELECT Id, Roles__c, Title FROM Contact WHERE Email = :CANDIDATE_EMAIL];
    final Contact legalRepresentative = [SELECT Id, Roles__c FROM Contact WHERE Email = :LEGAL_REPRESENTATIVE_EMAIL];

    Assert.areEqual('New Foundation', organization.Name, 'The organization name should be saved');
    Assert.areEqual('ID-123', organization.IdentificationNum__c, 'The identification number should be saved');
    Assert.areEqual(candidate.Id, organization.OperationalContact__c, 'The candidate should be the operational contact');
    Assert.areEqual(legalRepresentative.Id, organization.LegalRepresentative__c, 'The legal representative should be linked');
    Assert.areEqual(TestDataFactory.ROLE_OPERATIONAL_CONTACT, candidate.Roles__c, 'The candidate should get the operational role');
    Assert.areEqual(TestDataFactory.ROLE_LEGAL_REPRESENTATIVE, legalRepresentative.Roles__c, 'The legal representative should get the legal role');
    Assert.areEqual('Director', candidate.Title, 'The candidate title should be saved');
  }

  @isTest
  static void testRegisterCandidateWithoutLegalRepresentative() {
    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.legalRepresentative.lastName = ' ';
    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      organizationInput,
      PortalRegistrationService.ErrorCode.MISSING_DATA
    );
  }

  @isTest
  static void testRegisterCandidateWithoutLegalRepresentativeInput() {
    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.legalRepresentative = null;
    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      organizationInput,
      PortalRegistrationService.ErrorCode.MISSING_DATA
    );
  }

  @isTest
  static void testRegisterCandidateCreatesPortalUser() {
    PortalRegistrationService.isPortalUserCreationEnabled = true;

    System.runAs(TestDataFactory.createOrganizationOwner()) {
      Test.startTest();
      PortalRegistrationService.registerCandidate(
        NEW_LEGAL_NAME,
        buildContactInput(CANDIDATE_EMAIL),
        buildOrganizationInput(),
        findDataAcceptanceFormTextId()
      );
      Test.stopTest();
    }

    final List<User> portalUsers = [SELECT Username FROM User WHERE Contact.Email = :CANDIDATE_EMAIL];
    Assert.areEqual(1, portalUsers.size(), 'A portal user should be created for the candidate');
    Assert.areEqual(
      CANDIDATE_EMAIL,
      portalUsers[0].Username,
      'The username should be built from the email'
    );

    final List<User> legalRepresentativeUsers = [
      SELECT
        Username
      FROM
        User
      WHERE
        Contact.Email = :LEGAL_REPRESENTATIVE_EMAIL
    ];
    Assert.areEqual(1, legalRepresentativeUsers.size(), 'A portal user should be created for the legal representative');
    Assert.areEqual(
      LEGAL_REPRESENTATIVE_EMAIL,
      legalRepresentativeUsers[0].Username,
      'The legal representative username should be built from the email'
    );
  }

  @isTest
  static void testRegisterCandidateAssignsOperationalPermissionSet() {
    PortalRegistrationService.isPortalUserCreationEnabled = true;

    System.runAs(TestDataFactory.createOrganizationOwner()) {
      Test.startTest();
      PortalRegistrationService.registerCandidate(
        NEW_LEGAL_NAME,
        buildContactInput(CANDIDATE_EMAIL),
        buildOrganizationInput(),
        findDataAcceptanceFormTextId()
      );
      Test.stopTest();
    }

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE Assignee.Contact.Email = :CANDIDATE_EMAIL
          AND PermissionSet.Name = 'PortalOperationalPortalUser'
      ],
      'The operational contact should get the operational permission set'
    );
  }

  @isTest
  static void testPortalUserWithOtherRoleGetsNoOperationalPermissionSet() {
    final Account organization = TestDataFactory.createOrganization('Other Role Foundation', 'Other Role Legal Name');
    final Contact contact = TestDataFactory.createContact(
      organization.Id,
      'Lena',
      'Legal',
      'otherrole@org-test.com',
      TestDataFactory.ROLE_LEGAL_REPRESENTATIVE
    );
    organization.OperationalContact__c = contact.Id;
    update organization;
    PortalRegistrationService.isPortalUserCreationEnabled = true;

    System.runAs(TestDataFactory.createOrganizationOwner()) {
      Test.startTest();
      PortalRegistrationService.checkOrganizationExists('Other Role Legal Name');
      Test.stopTest();
    }

    Assert.areEqual(1, [SELECT COUNT() FROM User WHERE ContactId = :contact.Id], 'A portal user should be created');
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE Assignee.ContactId = :contact.Id
          AND PermissionSet.Name = 'PortalOperationalPortalUser'
      ],
      'Other roles must not get the operational permission set'
    );
  }

  @isTest
  static void testRegisterCandidateFailsWhenPortalUserCannotBeCreated() {
    PortalRegistrationService.isPortalUserCreationEnabled = true;

    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput(null),
      buildOrganizationInput(),
      PortalRegistrationService.ErrorCode.PORTAL_USER_CREATION_FAILED
    );
  }

  @isTest
  static void testRegisterCandidateRejectsExistingOrganization() {
    assertRegistrationError(
      TestDataFactory.DEFAULT_ORGANIZATION_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      buildOrganizationInput(),
      PortalRegistrationService.ErrorCode.ORGANIZATION_ALREADY_HAS_CONTACT
    );
  }

  @isTest
  static void testRegisterCandidateRequiresOrganizationDetails() {
    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      null,
      PortalRegistrationService.ErrorCode.ORGANIZATION_DETAILS_REQUIRED
    );

    PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.name = ' ';
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.ORGANIZATION_DETAILS_REQUIRED);

    organizationInput = buildOrganizationInput();
    organizationInput.legalForm = null;
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.ORGANIZATION_DETAILS_REQUIRED);

    organizationInput = buildOrganizationInput();
    organizationInput.identificationNumber = null;
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.ORGANIZATION_DETAILS_REQUIRED);

    organizationInput = buildOrganizationInput();
    organizationInput.country = '';
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.ORGANIZATION_DETAILS_REQUIRED);

    organizationInput = buildOrganizationInput();
    organizationInput.legalForm = OTHER_LEGAL_FORM;
    organizationInput.otherLegalForm = ' ';
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.ORGANIZATION_DETAILS_REQUIRED);

    organizationInput = buildOrganizationInput();
    organizationInput.country = 'Senegal';
    organizationInput.taxIdentificationNumber = ' ';
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.ORGANIZATION_DETAILS_REQUIRED);
  }

  @isTest
  static void testRegisterCandidateRequiresLegalRepresentativeFirstName() {
    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.legalRepresentative.firstName = ' ';
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.MISSING_DATA);
  }

  @IsTest
  static void registerCandidate_blankLegalRepresentativeField_throwsMissingData() {
    final List<PortalRegistrationService.OrganizationInput> organizationInputs =
      new List<PortalRegistrationService.OrganizationInput>{
        buildOrganizationInput(),
        buildOrganizationInput(),
        buildOrganizationInput(),
        buildOrganizationInput(),
        buildOrganizationInput(),
        buildOrganizationInput(),
        buildOrganizationInput()
      };
    organizationInputs[0].legalRepresentative.salutation = ' ';
    organizationInputs[1].legalRepresentative.title      = ' ';
    organizationInputs[2].legalRepresentative.firstName  = ' ';
    organizationInputs[3].legalRepresentative.lastName   = ' ';
    organizationInputs[4].legalRepresentative.birthdate  = null;
    organizationInputs[5].legalRepresentative.email      = ' ';
    organizationInputs[6].legalRepresentative.phone      = ' ';

    for (PortalRegistrationService.OrganizationInput organizationInput : organizationInputs) {
      assertRegistrationError(
        NEW_LEGAL_NAME,
        buildContactInput(CANDIDATE_EMAIL),
        organizationInput,
        PortalRegistrationService.ErrorCode.MISSING_DATA
      );
    }
  }

  @isTest
  static void testRegisterCandidateSavesTaxIdentificationNumberOutsideFrance() {
    PortalRegistrationService.isPortalUserCreationEnabled = false;
    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.country = 'Senegal';
    organizationInput.identificationNumber = null;
    organizationInput.taxIdentificationNumber = 'SN-123';

    Test.startTest();
    PortalRegistrationService.registerCandidate(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      organizationInput,
      findDataAcceptanceFormTextId()
    );
    Test.stopTest();

    final Account organization = [SELECT IdentificationNum__c, TIN__c FROM Account WHERE LegalName__c = :NEW_LEGAL_NAME];
    Assert.areEqual('SN-123', organization.TIN__c, 'The tax identification number should be saved outside France');
    Assert.isNull(organization.IdentificationNum__c, 'The identification number is optional outside France');
  }

  @isTest
  static void testRegisterCandidateSavesBothIdentificationNumbers() {
    PortalRegistrationService.isPortalUserCreationEnabled = false;
    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.taxIdentificationNumber = 'FR-123';

    Test.startTest();
    PortalRegistrationService.registerCandidate(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      organizationInput,
      findDataAcceptanceFormTextId()
    );
    Test.stopTest();

    final Account organization = [SELECT IdentificationNum__c, TIN__c FROM Account WHERE LegalName__c = :NEW_LEGAL_NAME];
    Assert.areEqual('ID-123', organization.IdentificationNum__c, 'The identification number should be saved');
    Assert.areEqual('FR-123', organization.TIN__c, 'The optional tax identification number should also be saved');
  }

  @isTest
  static void testRegisterCandidateRejectsUnlistedCountries() {
    PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.country = 'Frnace';
    organizationInput.taxIdentificationNumber = 'FR-123';
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.INVALID_INPUT);

    organizationInput = buildOrganizationInput();
    organizationInput.country = 'World';
    organizationInput.taxIdentificationNumber = 'WO-123';
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.INVALID_INPUT);
  }

  @isTest
  static void testRegisterCandidateSavesOtherLegalForm() {
    PortalRegistrationService.isPortalUserCreationEnabled = false;
    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.legalForm = OTHER_LEGAL_FORM;
    organizationInput.otherLegalForm = 'Cooperative';

    Test.startTest();
    PortalRegistrationService.registerCandidate(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      organizationInput,
      findDataAcceptanceFormTextId()
    );
    Test.stopTest();

    final Account organization = [SELECT LegalForm__c, OtherLegalForm__c FROM Account WHERE LegalName__c = :NEW_LEGAL_NAME];
    Assert.areEqual(OTHER_LEGAL_FORM, organization.LegalForm__c, 'The legal form should be saved');
    Assert.areEqual('Cooperative', organization.OtherLegalForm__c, 'The other legal form should be saved');
  }

  @isTest
  static void testRegisterCandidateIgnoresOtherLegalFormForListedLegalForm() {
    PortalRegistrationService.isPortalUserCreationEnabled = false;
    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.otherLegalForm = 'Cooperative';

    Test.startTest();
    PortalRegistrationService.registerCandidate(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      organizationInput,
      findDataAcceptanceFormTextId()
    );
    Test.stopTest();

    final Account organization = [SELECT OtherLegalForm__c FROM Account WHERE LegalName__c = :NEW_LEGAL_NAME];
    Assert.isNull(organization.OtherLegalForm__c, 'The other legal form should only be saved with the Other legal form');
  }

  @isTest
  static void testRegisterCandidateRejectsInvalidEmails() {
    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput('not-an-email'),
      buildOrganizationInput(),
      PortalRegistrationService.ErrorCode.INVALID_EMAIL
    );

    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.legalRepresentative.email = 'not-an-email';
    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      organizationInput,
      PortalRegistrationService.ErrorCode.INVALID_EMAIL
    );
  }

  @isTest
  static void testRegisterCandidateRejectsInvalidInput() {
    PortalRegistrationService.ContactInput candidate = buildContactInput(CANDIDATE_EMAIL);
    candidate.firstName = 'a'.repeat(Contact.FirstName.getDescribe().getLength() + 1);
    assertRegistrationError(NEW_LEGAL_NAME, candidate, buildOrganizationInput(), PortalRegistrationService.ErrorCode.INVALID_INPUT);

    candidate = buildContactInput(CANDIDATE_EMAIL);
    candidate.salutation = 'Not A Salutation';
    assertRegistrationError(NEW_LEGAL_NAME, candidate, buildOrganizationInput(), PortalRegistrationService.ErrorCode.INVALID_INPUT);

    PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.name = 'a'.repeat(Account.Name.getDescribe().getLength() + 1);
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.INVALID_INPUT);

    organizationInput = buildOrganizationInput();
    organizationInput.legalForm = 'Not A Legal Form';
    assertRegistrationError(NEW_LEGAL_NAME, candidate, buildOrganizationInput(), PortalRegistrationService.ErrorCode.INVALID_INPUT);

    organizationInput = buildOrganizationInput();
    organizationInput.legalForm = OTHER_LEGAL_FORM;
    organizationInput.otherLegalForm = 'a'.repeat(Account.OtherLegalForm__c.getDescribe().getLength() + 1);
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.INVALID_INPUT);

    organizationInput = buildOrganizationInput();
    organizationInput.country = 'Senegal';
    organizationInput.taxIdentificationNumber = 'a'.repeat(Account.TIN__c.getDescribe().getLength() + 1);
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.INVALID_INPUT);

    organizationInput = buildOrganizationInput();
    organizationInput.authorizedToIssueTaxReceipts = 'Not An Option';
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.INVALID_INPUT);

    organizationInput = buildOrganizationInput();
    organizationInput.legalRepresentative.lastName = 'a'.repeat(Contact.LastName.getDescribe().getLength() + 1);
    assertRegistrationError(NEW_LEGAL_NAME, buildContactInput(CANDIDATE_EMAIL), organizationInput, PortalRegistrationService.ErrorCode.INVALID_INPUT);

    candidate = buildContactInput(CANDIDATE_EMAIL);
    candidate.birthdate = Date.newInstance(1899, 12, 31);
    assertRegistrationError(
      NEW_LEGAL_NAME,
      candidate,
      buildOrganizationInput(),
      PortalRegistrationService.ErrorCode.INVALID_INPUT
    );

    organizationInput = buildOrganizationInput();
    organizationInput.legalRepresentative.birthdate = Date.today().addDays(1);
    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      organizationInput,
      PortalRegistrationService.ErrorCode.INVALID_INPUT
    );
  }

  @IsTest
  static void registerCandidate_earliestAndLatestAllowedBirthdates_savesBirthdates() {
    PortalRegistrationService.isPortalUserCreationEnabled = false;
    final PortalRegistrationService.ContactInput candidate = buildContactInput(CANDIDATE_EMAIL);
    candidate.birthdate = Date.newInstance(1900, 1, 1);
    final PortalRegistrationService.OrganizationInput organizationInput = buildOrganizationInput();
    organizationInput.legalRepresentative.birthdate = Date.today();

    Test.startTest();
    PortalRegistrationService.registerCandidate(
      NEW_LEGAL_NAME,
      candidate,
      organizationInput,
      findDataAcceptanceFormTextId()
    );
    Test.stopTest();

    final Map<String, Date> birthdatesByEmail = new Map<String, Date>();
    for (Contact contact : [
      SELECT
        Email,
        Birthdate
      FROM
        Contact
      WHERE
        Email IN (:CANDIDATE_EMAIL, :LEGAL_REPRESENTATIVE_EMAIL)
    ]) {
      birthdatesByEmail.put(contact.Email, contact.Birthdate);
    }
    Assert.areEqual(
      candidate.birthdate,
      birthdatesByEmail.get(CANDIDATE_EMAIL),
      'The earliest accepted birthdate should be saved'
    );
    Assert.areEqual(
      Date.today(),
      birthdatesByEmail.get(LEGAL_REPRESENTATIVE_EMAIL),
      'Today should be accepted as a birthdate'
    );
  }

  @isTest
  static void testRegisterCandidateRejectsEmailAlreadyRegistered() {
    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput(TestDataFactory.DEFAULT_OPERATIONAL_EMAIL),
      buildOrganizationInput(),
      PortalRegistrationService.ErrorCode.EMAIL_ALREADY_REGISTERED
    );
  }

  @isTest
  static void testRegisterCandidateRejectsEmailOfContactWithoutPortalUser() {
    final Account otherOrganization = TestDataFactory.createOrganization('Other Foundation', 'Other Foundation Legal');
    TestDataFactory.createContact(otherOrganization.Id, 'Otto', 'Other', CANDIDATE_EMAIL, null);

    assertRegistrationError(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      buildOrganizationInput(),
      PortalRegistrationService.ErrorCode.EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION
    );
  }

  @IsTest
  static void getDataAcceptanceDocument_frenchLanguage_returnsFrenchText() {
    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('fr');
    Test.stopTest();

    Assert.areEqual(findDataAcceptanceFormTextId(DATA_ACCEPTANCE_FR_NAME), document.formTextId, 'French text expected');
    Assert.areEqual(DATA_ACCEPTANCE_FR_URL, document.url, 'The French document URL should be returned');
  }

  @IsTest
  static void getDataAcceptanceDocument_exactLocale_returnsMatchingText() {
    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('en-US');
    Test.stopTest();

    Assert.areEqual(findDataAcceptanceFormTextId(DATA_ACCEPTANCE_EN_NAME), document.formTextId, 'English text expected');
    Assert.areEqual(DATA_ACCEPTANCE_EN_URL, document.url, 'The English document URL should be returned');
  }

  @IsTest
  static void getDataAcceptanceDocument_otherRegionOfLanguage_returnsSameLanguageText() {
    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('fr-CA');
    Test.stopTest();

    Assert.areEqual(
      findDataAcceptanceFormTextId(DATA_ACCEPTANCE_FR_NAME),
      document.formTextId,
      'A text in the same language should be used when the region differs'
    );
  }

  @IsTest
  static void getDataAcceptanceDocument_unknownLanguage_returnsDefaultText() {
    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('de');
    Test.stopTest();

    Assert.areEqual(
      findDataAcceptanceFormTextId(DATA_ACCEPTANCE_EN_NAME),
      document.formTextId,
      'The default text should be used for a language without text'
    );
  }

  @IsTest
  static void getDataAcceptanceDocument_blankLanguage_returnsDefaultText() {
    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument(null);
    Test.stopTest();

    Assert.areEqual(
      findDataAcceptanceFormTextId(DATA_ACCEPTANCE_EN_NAME),
      document.formTextId,
      'The default text should be used without language'
    );
  }

  @IsTest
  static void getDataAcceptanceDocument_noDefaultTextAndUnknownLanguage_returnsNull() {
    final AuthorizationForm dataAcceptanceForm = [
      SELECT
        Id
      FROM
        AuthorizationForm
      WHERE
        Name = :DATA_ACCEPTANCE_FORM_NAME
    ];
    dataAcceptanceForm.DefaultAuthFormTextId = null;
    update dataAcceptanceForm;

    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('de');
    Test.stopTest();

    Assert.isNull(document, 'No document expected without matching or default text');
  }

  @IsTest
  static void getDataAcceptanceDocument_expiredForm_returnsNull() {
    expireDataAcceptanceForms();

    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('fr');
    Test.stopTest();

    Assert.isNull(document, 'An expired form should not be offered');
  }

  @IsTest
  static void getDataAcceptanceDocument_formEndingToday_returnsText() {
    final AuthorizationForm dataAcceptanceForm = [
      SELECT
        Id
      FROM
        AuthorizationForm
      WHERE
        Name = :DATA_ACCEPTANCE_FORM_NAME
    ];
    dataAcceptanceForm.EffectiveToDate = Date.today();
    update dataAcceptanceForm;

    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('fr');
    Test.stopTest();

    Assert.isNotNull(document, 'A form ending today should still be offered');
  }

  @IsTest
  static void getDataAcceptanceDocument_formStartingTomorrow_returnsCurrentRevision() {
    createDataAcceptanceForm('2', Date.today().addDays(1), null);

    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('fr');
    Test.stopTest();

    Assert.areEqual('1', findRevisionNumber(document.formTextId), 'A future revision should not be offered yet');
  }

  @IsTest
  static void getDataAcceptanceDocument_newerActiveRevision_returnsNewerRevisionText() {
    createDataAcceptanceForm('2', Date.today(), null);

    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationService.getDataAcceptanceDocument('fr');
    Test.stopTest();

    Assert.areEqual('2', findRevisionNumber(document.formTextId), 'The highest active revision should be offered');
  }

  @IsTest
  static void registerCandidate_acceptedFrenchText_recordsOrganizationConsentForEveryLanguage() {
    assertConsentsRecordedForEveryLanguage(DATA_ACCEPTANCE_FR_NAME);
  }

  @IsTest
  static void registerCandidate_acceptedEnglishText_recordsOrganizationConsentForEveryLanguage() {
    assertConsentsRecordedForEveryLanguage(DATA_ACCEPTANCE_EN_NAME);
  }

  private static void assertConsentsRecordedForEveryLanguage(String acceptedFormTextName) {
    PortalRegistrationService.isPortalUserCreationEnabled = false;

    Test.startTest();
    PortalRegistrationService.registerCandidate(
      NEW_LEGAL_NAME,
      buildContactInput(CANDIDATE_EMAIL),
      buildOrganizationInput(),
      findDataAcceptanceFormTextId(acceptedFormTextName)
    );
    Test.stopTest();

    final Id organizationId = [SELECT Id FROM Account WHERE LegalName__c = :NEW_LEGAL_NAME].Id;
    final Map<String, AuthorizationFormConsent> consentsByFormTextName = new Map<String, AuthorizationFormConsent>();
    for (AuthorizationFormConsent consent : [
      SELECT
        Name,
        ConsentGiverId,
        AuthorizationFormText.Name,
        Status,
        ConsentCapturedSourceType,
        ConsentCapturedSource,
        ConsentCapturedDateTime
      FROM
        AuthorizationFormConsent
    ]) {
      consentsByFormTextName.put(consent.AuthorizationFormText.Name, consent);
    }

    Assert.areEqual(
      new Set<String>{ DATA_ACCEPTANCE_EN_NAME, DATA_ACCEPTANCE_FR_NAME },
      consentsByFormTextName.keySet(),
      'One consent per language version expected'
    );
    for (String formTextName : consentsByFormTextName.keySet()) {
      final AuthorizationFormConsent consent = consentsByFormTextName.get(formTextName);
      Assert.areEqual(organizationId, consent.ConsentGiverId, 'The organization should be the consent giver');
      Assert.areEqual(formTextName, consent.Name, 'The consent should be named after the text');
      Assert.areEqual('Signed', consent.Status, 'Signed expected');
      Assert.areEqual('Web', consent.ConsentCapturedSourceType, 'Web expected');
      Assert.areEqual('Portal Registration', consent.ConsentCapturedSource, 'The registration should be the source');
      Assert.isNotNull(consent.ConsentCapturedDateTime, 'The capture date should be recorded');
    }
  }

  @IsTest
  static void registerCandidate_missingDataAcceptance_throwsDataAcceptanceNotAccepted() {
    assertDataAcceptanceRejected(null);
  }

  @IsTest
  static void registerCandidate_expiredDataAcceptanceText_throwsDataAcceptanceNotAccepted() {
    final Id formTextId = findDataAcceptanceFormTextId();
    expireDataAcceptanceForms();
    assertDataAcceptanceRejected(formTextId);
  }

  @IsTest
  static void registerCandidate_olderRevisionText_throwsDataAcceptanceNotAccepted() {
    final Id olderFormTextId = findDataAcceptanceFormTextId();
    createDataAcceptanceForm('2', Date.today(), null);
    assertDataAcceptanceRejected(olderFormTextId);
  }

  @IsTest
  static void registerCandidate_otherAuthorizationFormText_throwsDataAcceptanceNotAccepted() {
    final AuthorizationForm otherForm = new AuthorizationForm(Name = 'Terms and Conditions', RevisionNumber = '1');
    insert otherForm;
    final AuthorizationFormText otherText = new AuthorizationFormText(
      Name                = 'Terms and Conditions EN',
      AuthorizationFormId = otherForm.Id,
      Locale              = 'en_US'
    );
    insert otherText;
    assertDataAcceptanceRejected(otherText.Id);
  }

  private static String findRevisionNumber(Id formTextId) {
    return [
      SELECT
        AuthorizationForm.RevisionNumber
      FROM
        AuthorizationFormText
      WHERE
        Id = :formTextId
    ].AuthorizationForm.RevisionNumber;
  }

  private static void assertDataAcceptanceRejected(Id formTextId) {
    PortalRegistrationService.isPortalUserCreationEnabled = false;

    Test.startTest();
    try {
      PortalRegistrationService.registerCandidate(
        NEW_LEGAL_NAME,
        buildContactInput(CANDIDATE_EMAIL),
        buildOrganizationInput(),
        formTextId
      );
      Assert.fail('Expected ' + PortalRegistrationService.ErrorCode.DATA_ACCEPTANCE_NOT_ACCEPTED.name());
    } catch (PortalRegistrationService.RegistrationException e) {
      Assert.areEqual(
        PortalRegistrationService.ErrorCode.DATA_ACCEPTANCE_NOT_ACCEPTED.name(),
        e.getMessage(),
        'Unexpected error code'
      );
    }
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE LegalName__c = :NEW_LEGAL_NAME], 'No organization expected');
    Assert.areEqual(0, [SELECT COUNT() FROM AuthorizationFormConsent], 'No consent expected');
  }
}
