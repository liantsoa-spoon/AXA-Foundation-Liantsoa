@isTest
private class PortalRegistrationControllerTest {
  private static final String NEW_LEGAL_NAME = 'Brand New Legal Name';
  private static final String CANDIDATE_EMAIL = 'candidate@org-test.com';

  private static final String DATA_ACCEPTANCE_FORM_NAME = 'Data Acceptance';
  private static final String DATA_ACCEPTANCE_FR_URL    = 'https://example.com/data-acceptance-fr';

  @testSetup
  static void setupTestData() {
    TestDataFactory.createPortalFixture();

    final AuthorizationForm dataAcceptanceForm = new AuthorizationForm(
      Name              = DATA_ACCEPTANCE_FORM_NAME,
      RevisionNumber    = '1',
      EffectiveFromDate = Date.today()
    );
    insert dataAcceptanceForm;
    insert new List<AuthorizationFormText>{
      new AuthorizationFormText(
        Name                     = 'Data Acceptance EN',
        AuthorizationFormId      = dataAcceptanceForm.Id,
        Locale                   = 'en_US',
        FullAuthorizationFormUrl = 'https://example.com/data-acceptance-en'
      ),
      new AuthorizationFormText(
        Name                     = 'Data Acceptance FR',
        AuthorizationFormId      = dataAcceptanceForm.Id,
        Locale                   = 'fr_FR',
        FullAuthorizationFormUrl = DATA_ACCEPTANCE_FR_URL
      )
    };
  }

  private static Id findDataAcceptanceFormTextId() {
    return [
      SELECT
        Id
      FROM
        AuthorizationFormText
      WHERE
        AuthorizationForm.Name = :DATA_ACCEPTANCE_FORM_NAME
      ORDER BY
        Name ASC
      LIMIT
        1
    ].Id;
  }

  private static String firstValue(Schema.DescribeFieldResult fieldDescribe) {
    final List<PortalRegistrationService.PicklistOption> options =
      PortalRegistrationService.buildPicklistOptions(fieldDescribe);
    return options.isEmpty() ? null : options[0].value;
  }

  private static Map<String, Object> buildCandidate(String email) {
    return new Map<String, Object>{
      'firstName' => 'Cara',
      'lastName' => 'Candidate',
      'phone' => '0102030405',
      'birthdate' => '1990-01-01',
      'email' => email
    };
  }

  private static Map<String, Object> buildOrganization() {
    return new Map<String, Object>{
      'name' => 'New Foundation',
      'legalForm' => firstValue(Account.LegalForm__c.getDescribe()),
      'identificationNumber' => 'ID-123',
      'country' => 'France',
      'street' => '1 rue de Test',
      'postalCode' => '75001',
      'foundingDate' => '2010-05-20',
      'authorizedToIssueTaxReceipts' => firstValue(Account.AuthorizedToIssueTaxReceipts__c.getDescribe()),
      'legalRepresentative' => new Map<String, Object>{
        'salutation' => firstValue(Contact.Salutation.getDescribe()),
        'title'      => 'President',
        'firstName'  => 'Leo',
        'lastName'   => 'Representative',
        'birthdate'  => '1975-06-15',
        'email'      => 'legalrep@org-test.com',
        'phone'      => '0605040302'
      }
    };
  }

  private static void assertRegisterError(
    String legalName,
    Map<String, Object> candidate,
    Map<String, Object> organization,
    Id dataAcceptanceFormTextId,
    String expectedMessage
  ) {
    try {
      PortalRegistrationController.registerCandidate(legalName, candidate, organization, dataAcceptanceFormTextId);
      Assert.fail('Expected ' + expectedMessage);
    } catch (AuraHandledException e) {
      Assert.areEqual(expectedMessage, e.getMessage(), 'Unexpected error code');
    }
  }

  @isTest
  static void testSuggestOrganizations() {
    Test.startTest();
    final List<String> blankResult = PortalRegistrationController.suggestOrganizations('  ');
    final List<String> noResult = PortalRegistrationController.suggestOrganizations('zzzz no match');
    final List<String> matches = PortalRegistrationController.suggestOrganizations(' test foundation ');
    Test.stopTest();

    Assert.isTrue(blankResult.isEmpty(), 'A blank search should return nothing');
    Assert.isTrue(noResult.isEmpty(), 'An unknown name should return nothing');
    Assert.areEqual(1, matches.size(), 'The search term should be trimmed and matched');
    Assert.areEqual(TestDataFactory.DEFAULT_ORGANIZATION_LEGAL_NAME, matches[0], 'The legal name should be suggested');
  }

  @isTest
  static void testCheckOrganizationExists() {
    Test.startTest();
    final PortalRegistrationService.OrganizationLookupResult found =
      PortalRegistrationController.checkOrganizationExists(' ' + TestDataFactory.DEFAULT_ORGANIZATION_LEGAL_NAME + ' ');
    final PortalRegistrationService.OrganizationLookupResult missing =
      PortalRegistrationController.checkOrganizationExists(NEW_LEGAL_NAME);
    Test.stopTest();

    Assert.isTrue(found.exists, 'The organization should be found');
    Assert.areEqual('Olivia Operational', found.operationalContactName, 'The operational contact name should be returned');
    Assert.isFalse(missing.exists, 'An unknown organization should not be found');
  }

  @isTest
  static void testCheckOrganizationExistsRequiresLegalName() {
    Test.startTest();
    try {
      PortalRegistrationController.checkOrganizationExists(' ');
      Assert.fail('Expected LEGAL_NAME_REQUIRED');
    } catch (AuraHandledException e) {
      Assert.areEqual(PortalRegistrationService.ErrorCode.LEGAL_NAME_REQUIRED.name(), e.getMessage(), 'Unexpected error code');
    }
    Test.stopTest();
  }

  @isTest
  static void testCheckOrganizationExistsConvertsServiceError() {
    Test.startTest();
    try {
      PortalRegistrationController.checkOrganizationExists('a'.repeat(Account.LegalName__c.getDescribe().getLength() + 1));
      Assert.fail('Expected INVALID_INPUT');
    } catch (AuraHandledException e) {
      Assert.areEqual(PortalRegistrationService.ErrorCode.INVALID_INPUT.name(), e.getMessage(), 'Unexpected error code');
    }
    Test.stopTest();
  }

  @isTest
  static void testGetRegistrationPicklists() {
    Test.startTest();
    final PortalRegistrationService.RegistrationPicklists picklists = PortalRegistrationController.getRegistrationPicklists();
    Test.stopTest();

    Assert.isNotNull(picklists.salutations, 'Salutations should be returned');
    Assert.isFalse(picklists.legalForms.isEmpty(), 'Legal forms should be returned');
    Assert.isNotNull(picklists.authorizedToIssueTaxReceipts, 'Tax receipt options should be returned');
    Assert.isFalse(picklists.countries.isEmpty(), 'Countries should be returned');
  }

  @isTest
  static void testRegisterCandidateSuccess() {
    PortalRegistrationService.isPortalUserCreationEnabled = false;

    Test.startTest();
    PortalRegistrationController.registerCandidate(
      ' ' + NEW_LEGAL_NAME + ' ',
      buildCandidate(' ' + CANDIDATE_EMAIL + ' '),
      buildOrganization(),
      findDataAcceptanceFormTextId()
    );
    Test.stopTest();

    final Account organization = [SELECT OperationalContact__c, LegalRepresentative__c FROM Account WHERE LegalName__c = :NEW_LEGAL_NAME];
    final Contact candidate = [SELECT Id, Email, Roles__c FROM Contact WHERE Email = :CANDIDATE_EMAIL];
    Assert.areEqual(candidate.Id, organization.OperationalContact__c, 'The candidate should be the operational contact');
    Assert.areEqual(TestDataFactory.ROLE_OPERATIONAL_CONTACT, candidate.Roles__c, 'The candidate should get the operational role');
    Assert.isNotNull(organization.LegalRepresentative__c, 'The legal representative should be linked');
  }

  @isTest
  static void testRegisterCandidateRequiresMandatoryData() {
    final Map<String, Object> organization = buildOrganization();
    final Id formTextId = findDataAcceptanceFormTextId();

    assertRegisterError(' ', buildCandidate(CANDIDATE_EMAIL), organization, formTextId, PortalRegistrationService.ErrorCode.MISSING_DATA.name());
    assertRegisterError(NEW_LEGAL_NAME, null, organization, formTextId, PortalRegistrationService.ErrorCode.MISSING_DATA.name());

    final Map<String, Object> noFirstName = buildCandidate(CANDIDATE_EMAIL);
    noFirstName.put('firstName', '');
    assertRegisterError(NEW_LEGAL_NAME, noFirstName, organization, formTextId, PortalRegistrationService.ErrorCode.MISSING_DATA.name());

    final Map<String, Object> noLastName = buildCandidate(CANDIDATE_EMAIL);
    noLastName.put('lastName', null);
    assertRegisterError(NEW_LEGAL_NAME, noLastName, organization, formTextId, PortalRegistrationService.ErrorCode.MISSING_DATA.name());

    assertRegisterError(NEW_LEGAL_NAME, buildCandidate(' '), organization, formTextId, PortalRegistrationService.ErrorCode.MISSING_DATA.name());
  }

  @isTest
  static void testRegisterCandidateRejectsInvalidEmail() {
    assertRegisterError(
      NEW_LEGAL_NAME,
      buildCandidate('not-an-email'),
      buildOrganization(),
      findDataAcceptanceFormTextId(),
      PortalRegistrationService.ErrorCode.INVALID_EMAIL.name()
    );
  }

  @isTest
  static void registerCandidate_missingDataAcceptance_throwsDataAcceptanceNotAccepted() {
    assertRegisterError(
      NEW_LEGAL_NAME,
      buildCandidate(CANDIDATE_EMAIL),
      buildOrganization(),
      null,
      PortalRegistrationService.ErrorCode.DATA_ACCEPTANCE_NOT_ACCEPTED.name()
    );
  }

  @isTest
  static void registerCandidate_inactiveDataAcceptance_convertsServiceError() {
    final Id formTextId = findDataAcceptanceFormTextId();
    final AuthorizationForm dataAcceptanceForm = [
      SELECT
        Id
      FROM
        AuthorizationForm
      WHERE
        Name = :DATA_ACCEPTANCE_FORM_NAME
    ];
    dataAcceptanceForm.EffectiveToDate = Date.today().addDays(-1);
    update dataAcceptanceForm;

    assertRegisterError(
      NEW_LEGAL_NAME,
      buildCandidate(CANDIDATE_EMAIL),
      buildOrganization(),
      formTextId,
      PortalRegistrationService.ErrorCode.DATA_ACCEPTANCE_NOT_ACCEPTED.name()
    );
  }

  @isTest
  static void getDataAcceptanceDocument_frenchLanguage_returnsFrenchDocument() {
    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationController.getDataAcceptanceDocument('fr');
    Test.stopTest();

    Assert.areEqual(DATA_ACCEPTANCE_FR_URL, document.url, 'The French document should be returned');
  }

  @isTest
  static void getDataAcceptanceDocument_noActiveForm_returnsNull() {
    final AuthorizationForm dataAcceptanceForm = [
      SELECT
        Id
      FROM
        AuthorizationForm
      WHERE
        Name = :DATA_ACCEPTANCE_FORM_NAME
    ];
    dataAcceptanceForm.EffectiveFromDate = Date.today().addDays(1);
    update dataAcceptanceForm;

    Test.startTest();
    final ConsentService.ConsentDocument document =
      PortalRegistrationController.getDataAcceptanceDocument('fr');
    Test.stopTest();

    Assert.isNull(document, 'No document expected without an active form');
  }

  @isTest
  static void testRegisterCandidateRejectsUnknownFields() {
    final Map<String, Object> candidateWithUnknownField = buildCandidate(CANDIDATE_EMAIL);
    candidateWithUnknownField.put('unexpectedField', 'value');
    assertRegisterError(
      NEW_LEGAL_NAME,
      candidateWithUnknownField,
      buildOrganization(),
      findDataAcceptanceFormTextId(),
      PortalRegistrationService.ErrorCode.INVALID_INPUT.name()
    );

    final Map<String, Object> organizationWithUnknownField = buildOrganization();
    organizationWithUnknownField.put('unexpectedField', 'value');
    assertRegisterError(
      NEW_LEGAL_NAME,
      buildCandidate(CANDIDATE_EMAIL),
      organizationWithUnknownField,
      findDataAcceptanceFormTextId(),
      PortalRegistrationService.ErrorCode.INVALID_INPUT.name()
    );
  }

  @isTest
  static void testRegisterCandidateConvertsServiceErrors() {
    assertRegisterError(
      TestDataFactory.DEFAULT_ORGANIZATION_LEGAL_NAME,
      buildCandidate(CANDIDATE_EMAIL),
      buildOrganization(),
      findDataAcceptanceFormTextId(),
      PortalRegistrationService.ErrorCode.ORGANIZATION_ALREADY_HAS_CONTACT.name()
    );
    assertRegisterError(
      NEW_LEGAL_NAME,
      buildCandidate(CANDIDATE_EMAIL),
      null,
      findDataAcceptanceFormTextId(),
      PortalRegistrationService.ErrorCode.ORGANIZATION_DETAILS_REQUIRED.name()
    );
  }

  @isTest
  static void testRegisterCandidateHidesUnexpectedErrors() {
    PortalRegistrationService.isPortalUserCreationEnabled = false;

    // Passes the format check of the controller but is refused by the platform email validation.
    assertRegisterError(
      NEW_LEGAL_NAME,
      buildCandidate('test@domain..com'),
      buildOrganization(),
      findDataAcceptanceFormTextId(),
      PortalRegistrationService.ErrorCode.UNEXPECTED_ERROR.name()
    );
  }
}