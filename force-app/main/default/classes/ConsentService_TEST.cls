/**
 * @description       : Test class for ConsentService.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 21-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   20-10-2026   LAN      Initial version
 * 1.1   21-10-2026   LAN      Run every test as the admin or the portal candidate user created in the testSetup
 **/
@IsTest
private class ConsentService_TEST {
  private static final String FORM_NAME = ConsentService.TERMS_AND_CONDITIONS_FORM_NAME;
  private static final String EN_NAME   = 'Terms and Conditions EN';
  private static final String FR_NAME   = 'Terms and Conditions FR';
  private static final String EN_URL    = 'https://example.com/terms-en';
  private static final String FR_URL    = 'https://example.com/terms-fr';

  private static final String ADMIN_LAST_NAME     = 'OrgConsentAdmin';
  private static final String CANDIDATE_LAST_NAME = 'OrgConsentCandidate';
  // The custom profile of the portal: the standard external profiles are disabled for user creation in the org.
  private static final String PORTAL_PROFILE_NAME = 'Portal User';
  private static final Set<String> ADMIN_PERMISSION_SET_NAMES = new Set<String>{
    'Admin_Access',
    'Grantmaking_Manager'
  };
  private static final Set<String> CANDIDATE_PERMISSION_SET_NAMES = new Set<String>{
    'PortalCandidate',
    'PortalCandidateAFAccess',
    'PortalCandidateAssessmentAccess',
    'PortalCandidateFOAccess'
  };

  @TestSetup
  static void setupTestData() {
    // The users are setup objects: they are created in a separate context from the data below.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      createAdminUser();
    }
    // The portal user needs an Account owner with a role: the admin owns the candidate's organization.
    System.runAs(getAdminUser()) {
      createCandidateUser();
    }
    System.runAs(getAdminUser()) {
      createForm(FORM_NAME, '1', Date.today().addDays(-1), null);
    }
  }

  private static void createAdminUser() {
    final UserRole role = new UserRole(Name = 'Org Consent Test Role', DeveloperName = 'Org_Consent_Test_Role');
    insert role;

    final User adminUser = buildUser(
      ADMIN_LAST_NAME,
      [
        SELECT
          Id
        FROM
          Profile
        WHERE
          Name = 'System Administrator'
        LIMIT
          1
      ].Id
    );
    adminUser.UserRoleId = role.Id;
    insert adminUser;
    assignPermissionSets(adminUser.Id, ADMIN_PERMISSION_SET_NAMES);
  }

  private static void createCandidateUser() {
    final List<Profile> profiles = [
      SELECT
        Id
      FROM
        Profile
      WHERE
        Name = :PORTAL_PROFILE_NAME
      LIMIT
        1
    ];
    Assert.isFalse(profiles.isEmpty(), 'The Portal User profile of the org portal is required in the org');

    final Account organization = TestDataFactory.createOrganization('Candidate Foundation', 'Candidate Legal Name');
    final Contact contact = new Contact(
      FirstName = 'Test',
      LastName  = CANDIDATE_LAST_NAME,
      AccountId = organization.Id
    );
    insert contact;

    final User candidateUser = buildUser(CANDIDATE_LAST_NAME, profiles[0].Id);
    candidateUser.ContactId = contact.Id;
    insert candidateUser;
    // A candidate reads the Grantmaking objects through the permission sets assigned to the portal users.
    assignPermissionSets(candidateUser.Id, CANDIDATE_PERMISSION_SET_NAMES);
  }

  private static User buildUser(String lastName, Id profileId) {
    return new User(
      Alias             = lastName.left(8),
      Email             = lastName + '@testorg.com',
      EmailEncodingKey  = 'UTF-8',
      LastName          = lastName,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey      = 'en_US',
      ProfileId         = profileId,
      TimeZoneSidKey    = 'Europe/Paris',
      Username          = lastName + DateTime.now().getTime() + '@testorg.com'
    );
  }

  private static void assignPermissionSets(Id userId, Set<String> permissionSetNames) {
    final List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permissionSet : [
      SELECT
        Id
      FROM
        PermissionSet
      WHERE
        Name IN :permissionSetNames
    ]) {
      assignments.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSet.Id));
    }
    insert assignments;
  }

  private static User getAdminUser() {
    return getUser(ADMIN_LAST_NAME);
  }

  private static User getCandidateUser() {
    return getUser(CANDIDATE_LAST_NAME);
  }

  private static User getUser(String lastName) {
    return [
      SELECT
        Id,
        ContactId
      FROM
        User
      WHERE
        LastName = :lastName
      LIMIT
        1
    ];
  }

  private static AuthorizationForm createForm(
    String formName,
    String revisionNumber,
    Date effectiveFromDate,
    Date effectiveToDate
  ) {
    final AuthorizationForm authorizationForm = new AuthorizationForm(
      Name              = formName,
      RevisionNumber    = revisionNumber,
      EffectiveFromDate = effectiveFromDate,
      EffectiveToDate   = effectiveToDate
    );
    insert authorizationForm;

    final AuthorizationFormText englishText = new AuthorizationFormText(
      Name                     = formName + ' EN',
      AuthorizationFormId      = authorizationForm.Id,
      Locale                   = 'en_US',
      FullAuthorizationFormUrl = EN_URL
    );
    final AuthorizationFormText frenchText = new AuthorizationFormText(
      Name                     = formName + ' FR',
      AuthorizationFormId      = authorizationForm.Id,
      Locale                   = 'fr_FR',
      FullAuthorizationFormUrl = FR_URL
    );
    insert new List<AuthorizationFormText>{ englishText, frenchText };

    authorizationForm.DefaultAuthFormTextId = englishText.Id;
    update authorizationForm;
    return authorizationForm;
  }

  private static Id findFormTextId(String formTextName) {
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

  private static AuthorizationForm findForm() {
    return [
      SELECT
        Id
      FROM
        AuthorizationForm
      WHERE
        Name = :FORM_NAME
    ];
  }

  private static Set<String> toNames(List<AuthorizationFormText> formTexts) {
    final Set<String> names = new Set<String>();
    for (AuthorizationFormText formText : formTexts) {
      names.add(formText.Name);
    }
    return names;
  }

  private static void assertRejected(Id acceptedFormTextId, Boolean isEnglishOnly) {
    try {
      ConsentService.requireActiveTexts(FORM_NAME, acceptedFormTextId, isEnglishOnly);
      Assert.fail('A ConsentException was expected');
    } catch (ConsentService.ConsentException e) {
      Assert.areEqual(FORM_NAME, e.getMessage(), 'The exception should name the form');
    }
  }

  @IsTest
  static void getActiveDocument_frenchLanguage_returnsFrenchText() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'fr');
      Test.stopTest();

      Assert.areEqual(findFormTextId(FR_NAME), document.formTextId, 'French text expected');
      Assert.areEqual(FR_URL, document.url, 'French URL expected');
    }
  }

  @IsTest
  static void getActiveDocument_exactLocale_returnsMatchingText() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'en-US');
      Test.stopTest();

      Assert.areEqual(findFormTextId(EN_NAME), document.formTextId, 'English text expected');
      Assert.areEqual(EN_URL, document.url, 'English URL expected');
    }
  }

  @IsTest
  static void getActiveDocument_upperCaseLanguage_returnsSameLanguageText() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'FR');
      Test.stopTest();

      Assert.areEqual(findFormTextId(FR_NAME), document.formTextId, 'The form language code (FR) should match');
    }
  }

  @IsTest
  static void getActiveDocument_otherRegionOfLanguage_returnsSameLanguageText() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'fr-CA');
      Test.stopTest();

      Assert.areEqual(findFormTextId(FR_NAME), document.formTextId, 'Same language text expected');
    }
  }

  @IsTest
  static void getActiveDocument_unknownLanguage_returnsDefaultText() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'de');
      Test.stopTest();

      Assert.areEqual(findFormTextId(EN_NAME), document.formTextId, 'Default text expected');
    }
  }

  @IsTest
  static void getActiveDocument_blankLanguage_returnsDefaultText() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, null);
      Test.stopTest();

      Assert.areEqual(findFormTextId(EN_NAME), document.formTextId, 'Default text expected');
    }
  }

  @IsTest
  static void getActiveDocument_noDefaultTextAndUnknownLanguage_returnsNull() {
    System.runAs(getAdminUser()) {
      final AuthorizationForm authorizationForm = findForm();
      authorizationForm.DefaultAuthFormTextId = null;
      update authorizationForm;

      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'de');
      Test.stopTest();

      Assert.isNull(document, 'No document expected');
    }
  }

  @IsTest
  static void getActiveDocument_unknownForm_returnsNull() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument('Unknown Form', 'fr');
      Test.stopTest();

      Assert.isNull(document, 'No document expected for an unknown form');
    }
  }

  @IsTest
  static void getActiveDocument_expiredForm_returnsNull() {
    System.runAs(getAdminUser()) {
      final AuthorizationForm authorizationForm = findForm();
      authorizationForm.EffectiveToDate = Date.today().addDays(-1);
      update authorizationForm;

      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'fr');
      Test.stopTest();

      Assert.isNull(document, 'An expired form should not be offered');
    }
  }

  @IsTest
  static void getActiveDocument_formEndingToday_returnsText() {
    System.runAs(getAdminUser()) {
      final AuthorizationForm authorizationForm = findForm();
      authorizationForm.EffectiveToDate = Date.today();
      update authorizationForm;

      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'fr');
      Test.stopTest();

      Assert.isNotNull(document, 'A form ending today should still be offered');
    }
  }

  @IsTest
  static void getActiveDocument_formStartingTomorrow_returnsCurrentRevision() {
    System.runAs(getAdminUser()) {
      createForm(FORM_NAME, '2', Date.today().addDays(1), null);

      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'fr');
      Test.stopTest();

      Assert.areEqual('1', findRevisionNumber(document.formTextId), 'A future revision should not be offered yet');
    }
  }

  @IsTest
  static void getActiveDocument_newerActiveRevision_returnsNewerRevisionText() {
    System.runAs(getAdminUser()) {
      createForm(FORM_NAME, '2', Date.today(), null);

      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'fr');
      Test.stopTest();

      Assert.areEqual('2', findRevisionNumber(document.formTextId), 'The highest active revision should be offered');
    }
  }

  @IsTest
  static void requireActiveTexts_acceptedFrenchText_returnsEveryLanguage() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final List<AuthorizationFormText> formTexts =
        ConsentService.requireActiveTexts(FORM_NAME, findFormTextId(FR_NAME), false);
      Test.stopTest();

      Assert.areEqual(new Set<String>{ EN_NAME, FR_NAME }, toNames(formTexts), 'Every language version expected');
    }
  }

  @IsTest
  static void requireActiveTexts_englishOnly_returnsEnglishTextOnly() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      final List<AuthorizationFormText> formTexts =
        ConsentService.requireActiveTexts(FORM_NAME, findFormTextId(EN_NAME), true);
      Test.stopTest();

      Assert.areEqual(new Set<String>{ EN_NAME }, toNames(formTexts), 'Only the English version expected');
    }
  }

  @IsTest
  static void requireActiveTexts_englishOnlyWithoutEnglishText_throwsConsentException() {
    System.runAs(getAdminUser()) {
      final AuthorizationForm authorizationForm = findForm();
      authorizationForm.DefaultAuthFormTextId = null;
      update authorizationForm;
      delete [SELECT Id FROM AuthorizationFormText WHERE Name = :EN_NAME];
      assertRejected(findFormTextId(FR_NAME), true);
    }
  }

  @IsTest
  static void requireActiveTexts_missingText_throwsConsentException() {
    System.runAs(getAdminUser()) {
      assertRejected(null, false);
    }
  }

  @IsTest
  static void requireActiveTexts_expiredText_throwsConsentException() {
    System.runAs(getAdminUser()) {
      final Id formTextId = findFormTextId(EN_NAME);
      final AuthorizationForm authorizationForm = findForm();
      authorizationForm.EffectiveToDate = Date.today().addDays(-1);
      update authorizationForm;
      assertRejected(formTextId, false);
    }
  }

  @IsTest
  static void requireActiveTexts_olderRevisionText_throwsConsentException() {
    System.runAs(getAdminUser()) {
      final Id olderFormTextId = findFormTextId(EN_NAME);
      createForm(FORM_NAME, '2', Date.today(), null);
      assertRejected(olderFormTextId, false);
    }
  }

  @IsTest
  static void requireActiveTexts_textOfOtherForm_throwsConsentException() {
    System.runAs(getAdminUser()) {
      createForm(ConsentService.IMAGE_RIGHTS_FORM_NAME, '1', Date.today(), null);
      assertRejected(findFormTextId(ConsentService.IMAGE_RIGHTS_FORM_NAME + ' EN'), false);
    }
  }

  @IsTest
  static void insertConsents_formTexts_recordsOneSignedConsentPerText() {
    System.runAs(getAdminUser()) {
      final Account organization = TestDataFactory.createOrganization('Consent Foundation', 'Consent Legal Name');
      final List<AuthorizationFormText> formTexts =
        ConsentService.requireActiveTexts(FORM_NAME, findFormTextId(EN_NAME), false);

      Test.startTest();
      ConsentService.insertConsents(organization.Id, formTexts, organization.Id, 'Unit Test');
      Test.stopTest();

      final List<AuthorizationFormConsent> consents = [
        SELECT
          Name,
          ConsentGiverId,
          RelatedRecordId,
          AuthorizationFormText.Name,
          Status,
          ConsentCapturedSourceType,
          ConsentCapturedSource,
          ConsentCapturedDateTime
        FROM
          AuthorizationFormConsent
      ];
      Assert.areEqual(2, consents.size(), 'One consent per text expected');
      for (AuthorizationFormConsent consent : consents) {
        Assert.areEqual(consent.AuthorizationFormText.Name, consent.Name, 'The consent should be named after the text');
        Assert.areEqual(organization.Id, consent.ConsentGiverId, 'Consent giver expected');
        Assert.areEqual(organization.Id, consent.RelatedRecordId, 'Related record expected');
        Assert.areEqual('Signed', consent.Status, 'Signed expected');
        Assert.areEqual('Web', consent.ConsentCapturedSourceType, 'Web expected');
        Assert.areEqual('Unit Test', consent.ConsentCapturedSource, 'Source expected');
        Assert.isNotNull(consent.ConsentCapturedDateTime, 'Capture date expected');
      }
    }
  }

  @IsTest
  static void insertConsents_noFormText_recordsNothing() {
    System.runAs(getAdminUser()) {
      final Account organization = TestDataFactory.createOrganization('Consent Foundation', 'Consent Legal Name');

      Test.startTest();
      ConsentService.insertConsents(organization.Id, new List<AuthorizationFormText>(), null, 'Unit Test');
      Test.stopTest();

      Assert.areEqual(0, [SELECT COUNT() FROM AuthorizationFormConsent], 'No consent expected');
    }
  }

  // The guest and the portal users cannot read the authorization forms: the service reads them without sharing.
  @IsTest
  static void getActiveDocument_givenPortalCandidate_returnsDocument() {
    Id frenchTextId;
    System.runAs(getAdminUser()) {
      frenchTextId = findFormTextId(FR_NAME);
    }

    System.runAs(getCandidateUser()) {
      Test.startTest();
      final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(FORM_NAME, 'fr');
      Test.stopTest();

      Assert.areEqual(frenchTextId, document.formTextId, 'The candidate gets the French text');
      Assert.areEqual(FR_URL, document.url, 'The candidate gets the French URL');
    }
  }

  @IsTest
  static void insertConsents_givenPortalCandidate_recordsTheConsentsOfTheCandidate() {
    final User candidateUser = getCandidateUser();
    Id englishTextId;
    System.runAs(getAdminUser()) {
      englishTextId = findFormTextId(EN_NAME);
    }

    System.runAs(candidateUser) {
      Test.startTest();
      ConsentService.insertConsents(
        candidateUser.ContactId,
        ConsentService.requireActiveTexts(FORM_NAME, englishTextId, false),
        null,
        'Unit Test'
      );
      Test.stopTest();
    }

    System.runAs(getAdminUser()) {
      final List<AuthorizationFormConsent> consents = [
        SELECT
          ConsentGiverId
        FROM
          AuthorizationFormConsent
      ];
      Assert.areEqual(2, consents.size(), 'One consent per language version expected');
      for (AuthorizationFormConsent consent : consents) {
        Assert.areEqual(candidateUser.ContactId, consent.ConsentGiverId, 'The candidate gives the consent');
      }
    }
  }
}
