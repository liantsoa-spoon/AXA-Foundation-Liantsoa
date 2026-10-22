/**
 * @description       : Test class for ApplicationFormSubmissionService.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 22-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver    Date         Author   Modification
 * 1.0    05-10-2026   LAN      Initial version
 * 1.1    05-10-2026   LAN      Test that the connected user must be linked to a Contact and to an Account
 * 1.2    05-10-2026   LAN      Test the Stage rules of the ticket (EOI Approved, other stages, colleague forms)
 * 1.3    06-10-2026   LAN      Test the colleague form found through the Account stamped on the Application Form
 * 1.4    07-10-2026   LAN      Test that only the Project applicant lead role fills the application form
 * 1.5    07-10-2026   LAN      Test canConnectedUserEditApplicationForm: internal users keep their access
 * 1.6    07-10-2026   LAN      Test isEditAllowed returned with the check of a colleague form
 * 1.7    08-10-2026   LAN      Test the codes of the submission check errors
 * 1.8    08-10-2026   LAN      Test that a submitted EOI blocks the full application until it is approved
 * 1.9    08-10-2026   LAN      Run the resolveResult tests as the Org admin user too
 * 1.10   09-10-2026   LAN      buildError and the error codes now come from FormLanguageService
 * 1.11   09-10-2026   LAN      Create the community user with the Portal User profile and the candidate permission sets
 * 1.12   22-10-2026   LAN      Stop using ConsentementCGUAcceptees__c in the tests
 **/
@IsTest
private class ApplicationFormSubmissionService_TEST {
  // The custom profile of the portal: the standard external profiles are disabled for user creation in the org.
  private static final String PORTAL_PROFILE_NAME = 'Portal User';
  private static final Set<String> CANDIDATE_PERMISSION_SET_NAMES = new Set<String>{
    'PortalCandidate',
    'PortalCandidateAFAccess',
    'PortalCandidateAssessmentAccess',
    'PortalCandidateFOAccess'
  };
  private static final String ADMIN_LAST_NAME = 'OrgSubmissionAdmin';
  private static final String OTHER_LAST_NAME = 'OrgSubmissionOther';
  private static final String CONTACT_LAST_NAME = 'OrgSubmissionContact';
  private static final String STATUS_NONE = ApplicationFormSubmissionService.STATUS_NONE;
  private static final String STATUS_BLOCKED = ApplicationFormSubmissionService.STATUS_ALREADY_SUBMITTED;

  @TestSetup
  static void setupTestData() {
    final Account account = new Account(Name = 'Test Organization');
    insert account;
    insert new Contact(FirstName = 'Test', LastName = CONTACT_LAST_NAME, AccountId = account.Id);

    // The users are setup objects: they are created in a separate context from the data above.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      createUsers();
    }
  }

  private static void createUsers() {
    final UserRole role = new UserRole(Name = 'Org Submission Test Role', DeveloperName = 'Org_Submission_Test_Role');
    insert role;

    final Profile adminProfile = [
      SELECT
        Id
      FROM
        Profile
      WHERE
        Name = 'System Administrator'
      LIMIT
        1
    ];
    final List<User> users = new List<User>{
      buildUser(ADMIN_LAST_NAME, adminProfile.Id, role.Id),
      buildUser(OTHER_LAST_NAME, adminProfile.Id, null)
    };
    insert users;

    final List<PermissionSet> permissionSets = [
      SELECT
        Id
      FROM
        PermissionSet
      WHERE
        Name IN ('Admin_Access', 'Grantmaking_Manager')
    ];
    final List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (User user : users) {
      for (PermissionSet permissionSet : permissionSets) {
        assignments.add(new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = permissionSet.Id));
      }
    }
    insert assignments;
  }

  @IsTest
  static void checkExistingSubmission_givenNullFundingOpportunity_returnsNone() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(null);
      Assert.areEqual(STATUS_NONE, result.status, 'No Funding Opportunity means no block');
      Assert.isNull(result.applicationFormId, 'No Application Form is returned');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenNoApplicationForm_returnsNone() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();

      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(ApplicationFormSubmissionService.STATUS_NONE, result.status, 'A new form is allowed');
      Assert.isFalse(result.isOwnApplicationForm, 'There is no own Application Form');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenOwnEoiDraft_returnsOpenEoi() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();
      final Id applicationFormId = createApplicationForm(fundingOpportunityId, 'EOI Draft');

      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(ApplicationFormSubmissionService.STATUS_OPEN_EOI, result.status, 'The EOI draft is resumed');
      Assert.areEqual(applicationFormId, result.applicationFormId, 'The existing Application Form is returned');
      Assert.isTrue(result.isOwnApplicationForm, 'The form belongs to the connected user');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenOwnDraft_returnsOpenFullApplication() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();
      final Id applicationFormId = createApplicationForm(fundingOpportunityId, 'Draft');
      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);
      Assert.areEqual(
        ApplicationFormSubmissionService.STATUS_OPEN_FULL_APPLICATION,
        result.status,
        'The full application draft is resumed'
      );
      Assert.areEqual(applicationFormId, result.applicationFormId, 'The existing Application Form is returned');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenOwnEoiSubmitted_returnsAlreadySubmitted() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();
      final Id applicationFormId = createApplicationForm(fundingOpportunityId, 'EOI Submitted');

      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(ApplicationFormSubmissionService.STATUS_ALREADY_SUBMITTED, result.status, 'The EOI blocks');
      Assert.areEqual(applicationFormId, result.applicationFormId, 'The submitted form is returned for the link');
      Assert.areEqual('Test FO', result.programName, 'The program name fills the message');
      Assert.isTrue(result.isOwnApplicationForm, 'The form belongs to the connected user');
      Assert.isTrue(result.isEditAllowed, 'The creator gets the blocking message, not the read-only form');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenOwnSubmitted_returnsAlreadySubmitted() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();
      createApplicationForm(fundingOpportunityId, 'Submitted');

      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(STATUS_BLOCKED, result.status, 'The application blocks');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenFormOnAnotherFundingOpportunity_returnsNone() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id otherFundingOpportunityId = createFundingOpportunity();
      createApplicationForm(otherFundingOpportunityId, 'Submitted');
      final Id fundingOpportunityId = createFundingOpportunity();

      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(ApplicationFormSubmissionService.STATUS_NONE, result.status, 'Another program does not block');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenOwnStageAfterSubmission_returnsAlreadySubmitted() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();
      createApplicationForm(fundingOpportunityId, 'Under Evaluation');

      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(STATUS_BLOCKED, result.status, 'Every other stage blocks');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenOwnEoiApproved_returnsOpenFullApplication() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();
      final Id applicationFormId = createApplicationForm(fundingOpportunityId, 'EOI Approved');

      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(
        ApplicationFormSubmissionService.STATUS_OPEN_FULL_APPLICATION,
        result.status,
        'An approved EOI opens the full application'
      );
      Assert.areEqual(applicationFormId, result.applicationFormId, 'The existing Application Form is returned');
    }
  }

  @IsTest
  static void checkExistingSubmission_givenSubmittedFormOfUserWithoutSameAccount_returnsNone() {
    Id fundingOpportunityId;
    System.runAs(getUser(OTHER_LAST_NAME)) {
      fundingOpportunityId = createFundingOpportunity();
      createApplicationForm(fundingOpportunityId, 'Submitted');
    }

    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(
        ApplicationFormSubmissionService.STATUS_NONE,
        result.status,
        'A user without Contact only sees the forms they created'
      );
    }
  }

  @IsTest
  static void checkExistingSubmission_givenFormOfColleagueWithSameAccount_returnsAlreadySubmitted() {
    Id fundingOpportunityId;
    Id applicationFormId;
    System.runAs(getUser(OTHER_LAST_NAME)) {
      fundingOpportunityId = createFundingOpportunity();
      applicationFormId = createApplicationForm(fundingOpportunityId, 'EOI Submitted');
      update new ApplicationForm(Id = applicationFormId, AccountId = getAccountId());
    }

    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(STATUS_BLOCKED, result.status, 'The form stamped with the same Account blocks');
      Assert.areEqual(applicationFormId, result.applicationFormId, 'The colleague form is returned');
      Assert.isFalse(result.isOwnApplicationForm, 'The form belongs to a colleague');
    }
  }

  private static Boolean isEditAllowedOnColleagueFormWithRole(final String role) {
    Id fundingOpportunityId;
    System.runAs(getUser(OTHER_LAST_NAME)) {
      fundingOpportunityId = createFundingOpportunity();
      final Id applicationFormId = createApplicationForm(fundingOpportunityId, 'EOI Submitted');
      update new ApplicationForm(Id = applicationFormId, AccountId = getAccountId());
    }

    Boolean isEditAllowed;
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Contact contact = new Contact(
        FirstName = 'Test',
        LastName  = 'OrgSubmissionColleague',
        AccountId = getAccountId(),
        Roles__c  = role
      );
      insert contact;
      ApplicationFormSubmissionService.contactIdOverride = contact.Id;
      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(STATUS_BLOCKED, result.status, 'The colleague form is found through the Account');
      isEditAllowed = result.isEditAllowed;
    }
    return isEditAllowed;
  }

  @IsTest
  static void checkExistingSubmission_givenColleagueFormAndOperationalContact_returnsEditNotAllowed() {
    Assert.isFalse(
      isEditAllowedOnColleagueFormWithRole('Administrative or Operational Representative'),
      'The operational representative reads the colleague form'
    );
  }

  @IsTest
  static void checkExistingSubmission_givenColleagueFormAndApplicantLeadContact_returnsEditNotAllowed() {
    Assert.isFalse(
      isEditAllowedOnColleagueFormWithRole('Project applicant lead'),
      'Whatever the role, only the creator edits the form'
    );
  }

  @IsTest
  static void checkExistingSubmission_givenNoFormAndOperationalContact_returnsEditAllowed() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Contact contact = new Contact(
        FirstName = 'Test',
        LastName  = 'OrgSubmissionOperational',
        AccountId = getAccountId(),
        Roles__c  = 'Administrative or Operational Representative'
      );
      insert contact;
      ApplicationFormSubmissionService.contactIdOverride = contact.Id;

      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(createFundingOpportunity());

      Assert.areEqual(STATUS_NONE, result.status, 'No form exists for the organization');
      Assert.isTrue(result.isEditAllowed, 'Any Contact of the organization starts the form');
    }
  }

  @IsTest
  static void getConnectedAccountId_givenContactWithAccount_returnsTheAccountOfTheContact() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();

      final Id accountId = ApplicationFormSubmissionService.getConnectedAccountId();

      Assert.areEqual(getAccountId(), accountId, 'The Account of the Contact');
    }
  }

  @IsTest
  static void getConnectedAccountId_givenUserWithoutContact_throwsException() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      try {
        ApplicationFormSubmissionService.getConnectedAccountId();
        Assert.fail('A user without Contact must be refused');
      } catch (ApplicationFormSubmissionService.SubmissionCheckException e) {
        Assert.areEqual(
          'The connected user is not linked to a Contact.',
          e.getMessage(),
          'The missing Contact is named'
        );
        Assert.areEqual(FormLanguageService.ERROR_USER_NOT_LINKED, e.code, 'The code of the missing Contact');
      }
    }
  }
  @IsTest
  static void checkExistingSubmission_givenCommunityUserWithAccount_returnsNone() {
    final User adminUser = getUser(ADMIN_LAST_NAME);
    Id fundingOpportunityId;
    User communityUser;
    System.runAs(adminUser) {
      fundingOpportunityId = createFundingOpportunity();
      communityUser = createCommunityUser('one');
    }

    System.runAs(communityUser) {
      final ApplicationFormSubmissionService.SubmissionCheckResult result = check(fundingOpportunityId);

      Assert.areEqual(
        ApplicationFormSubmissionService.STATUS_NONE,
        result.status,
        'The Account scope is resolved and nothing exists yet'
      );
    }
  }

  @IsTest
  static void checkExistingSubmission_givenUserWithoutContact_throwsException() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id fundingOpportunityId = createFundingOpportunity();

      try {
        check(fundingOpportunityId);
        Assert.fail('A user without Contact must be refused');
      } catch (ApplicationFormSubmissionService.SubmissionCheckException e) {
        Assert.areEqual(
          'The connected user is not linked to a Contact.',
          e.getMessage(),
          'The missing Contact is named'
        );
        Assert.areEqual(FormLanguageService.ERROR_USER_NOT_LINKED, e.code, 'The code of the missing Contact');
      }
    }
  }

  @IsTest
  static void canConnectedUserEditApplicationForm_givenNoCreator_returnsTrue() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      Assert.isTrue(
        ApplicationFormSubmissionService.canConnectedUserEditApplicationForm(null),
        'A form without creator does not exist yet: any Contact starts it'
      );
    }
  }

  @IsTest
  static void canConnectedUserEditApplicationForm_givenConnectedUserAsCreator_returnsTrue() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      Assert.isTrue(
        ApplicationFormSubmissionService.canConnectedUserEditApplicationForm(UserInfo.getUserId()),
        'The creator edits the form'
      );
    }
  }

  @IsTest
  static void canConnectedUserEditApplicationForm_givenColleagueAsCreator_returnsFalse() {
    final Id colleagueId = getUser(OTHER_LAST_NAME).Id;
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      Assert.isFalse(
        ApplicationFormSubmissionService.canConnectedUserEditApplicationForm(colleagueId),
        'A colleague only reads the form'
      );
    }
  }

  @IsTest
  static void canConnectedUserEditApplicationForm_givenInternalUserAndOtherCreator_returnsTrue() {
    final Id creatorId = getUser(OTHER_LAST_NAME).Id;
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      Assert.isTrue(
        ApplicationFormSubmissionService.canConnectedUserEditApplicationForm(creatorId),
        'An internal user has no Contact and keeps its access'
      );
    }
  }

  @IsTest
  static void checkExistingSubmission_givenContactWithoutAccount_throwsException() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id fundingOpportunityId = createFundingOpportunity();
      final Contact contactWithoutAccount = new Contact(FirstName = 'Test', LastName = 'OrgSubmissionNoAccount');
      insert contactWithoutAccount;
      ApplicationFormSubmissionService.contactIdOverride = contactWithoutAccount.Id;

      try {
        check(fundingOpportunityId);
        Assert.fail('A Contact without Account must be refused');
      } catch (ApplicationFormSubmissionService.SubmissionCheckException e) {
        Assert.areEqual(
          'The Contact of the connected user is not linked to an Account.',
          e.getMessage(),
          'The missing Account is named'
        );
        Assert.areEqual(FormLanguageService.ERROR_ORGANIZATION_NOT_LINKED, e.code, 'The code of the missing Account');
      }
    }
  }

  // isSubmissionBlocked

  @IsTest
  static void isSubmissionBlocked_givenSubmittedForm_returnsTrue() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();
      createApplicationForm(fundingOpportunityId, 'Submitted');

      final Boolean isBlocked = ApplicationFormSubmissionService.isSubmissionBlocked(fundingOpportunityId);
      Assert.isTrue(isBlocked, 'The submission is blocked');
    }
  }

  @IsTest
  static void isSubmissionBlocked_givenDraftForm_returnsFalse() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      useTestContact();
      final Id fundingOpportunityId = createFundingOpportunity();
      createApplicationForm(fundingOpportunityId, 'Draft');

      final Boolean isBlocked = ApplicationFormSubmissionService.isSubmissionBlocked(fundingOpportunityId);
      Assert.isFalse(isBlocked, 'A draft does not block');
    }
  }

  // resolveResult: the colleague rules, on in-memory forms

  @IsTest
  static void resolveResult_givenColleagueSubmittedForm_returnsAlreadySubmittedWithoutOwnership() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id currentUserId = getUser(ADMIN_LAST_NAME).Id;
      final Id colleagueId = getUser(OTHER_LAST_NAME).Id;
      final ApplicationForm colleagueForm = buildApplicationForm(1, 'Submitted', colleagueId);

      final List<ApplicationForm> forms = new List<ApplicationForm>{ colleagueForm };

      final ApplicationFormSubmissionService.SubmissionCheckResult result = resolve(forms, currentUserId);

      Assert.areEqual(STATUS_BLOCKED, result.status, 'A colleague submission blocks');
      Assert.isFalse(result.isOwnApplicationForm, 'The form belongs to a colleague');
      Assert.areEqual(colleagueForm.Id, result.applicationFormId, 'The colleague form is returned');
    }
  }

  @IsTest
  static void resolveResult_givenColleagueDraft_returnsAlreadySubmitted() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id currentUserId = getUser(ADMIN_LAST_NAME).Id;
      final Id colleagueId = getUser(OTHER_LAST_NAME).Id;

      for (String stage : new List<String>{ 'EOI Draft', 'Draft' }) {
        final List<ApplicationForm> forms = new List<ApplicationForm>{ buildApplicationForm(1, stage, colleagueId) };

        final ApplicationFormSubmissionService.SubmissionCheckResult result = resolve(forms, currentUserId);

        Assert.areEqual(STATUS_BLOCKED, result.status, 'A colleague form at stage ' + stage + ' blocks');
        Assert.isFalse(result.isOwnApplicationForm, 'The form belongs to a colleague');
      }
    }
  }

  @IsTest
  static void resolveResult_givenOwnAndColleagueSubmittedForms_prefersOwnForm() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id currentUserId = getUser(ADMIN_LAST_NAME).Id;
      final Id colleagueId = getUser(OTHER_LAST_NAME).Id;
      final ApplicationForm ownForm = buildApplicationForm(2, 'EOI Submitted', currentUserId);

      final List<ApplicationForm> forms = new List<ApplicationForm>{
        buildApplicationForm(1, 'Submitted', colleagueId),
        ownForm
      };

      final ApplicationFormSubmissionService.SubmissionCheckResult result = resolve(forms, currentUserId);

      Assert.areEqual(ownForm.Id, result.applicationFormId, 'The own form is returned so the link can be shown');
      Assert.isTrue(result.isOwnApplicationForm, 'The form belongs to the connected user');
    }
  }

  @IsTest
  static void resolveResult_givenOwnDraftAndColleagueSubmitted_returnsAlreadySubmitted() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id currentUserId = getUser(ADMIN_LAST_NAME).Id;
      final Id colleagueId = getUser(OTHER_LAST_NAME).Id;

      final List<ApplicationForm> forms = new List<ApplicationForm>{
        buildApplicationForm(1, 'Draft', currentUserId),
        buildApplicationForm(2, 'Submitted', colleagueId)
      };

      final ApplicationFormSubmissionService.SubmissionCheckResult result = resolve(forms, currentUserId);

      Assert.areEqual(
        ApplicationFormSubmissionService.STATUS_ALREADY_SUBMITTED,
        result.status,
        'The colleague submission wins over the own draft'
      );
    }
  }

  @IsTest
  static void resolveResult_givenNoForm_returnsNone() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id currentUserId = getUser(ADMIN_LAST_NAME).Id;

      final ApplicationFormSubmissionService.SubmissionCheckResult result = resolve(
        new List<ApplicationForm>(),
        currentUserId
      );

      Assert.areEqual(ApplicationFormSubmissionService.STATUS_NONE, result.status, 'Nothing to resolve');
    }
  }

  @IsTest
  static void resolveResult_givenOwnEoiSubmittedOnFullApplicationForm_returnsAlreadySubmitted() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id currentUserId = getUser(ADMIN_LAST_NAME).Id;
      final ApplicationForm ownForm = buildApplicationForm(1, 'EOI Submitted', currentUserId);

      final ApplicationFormSubmissionService.SubmissionCheckResult result =
        ApplicationFormSubmissionService.resolveResult(
          new List<ApplicationForm>{ ownForm },
          currentUserId,
          null,
          false
        );

      Assert.areEqual(
        ApplicationFormSubmissionService.STATUS_ALREADY_SUBMITTED,
        result.status,
        'A submitted EOI blocks until it is approved'
      );
      Assert.areEqual(ownForm.Id, result.applicationFormId, 'The submitted EOI is linked in the message');
    }
  }

  @IsTest
  static void resolveResult_givenOwnEoiSubmittedOnEoiOnlyForm_returnsAlreadySubmitted() {
    System.runAs(getUser(ADMIN_LAST_NAME)) {
      final Id currentUserId = getUser(ADMIN_LAST_NAME).Id;

      final ApplicationFormSubmissionService.SubmissionCheckResult result =
        ApplicationFormSubmissionService.resolveResult(
          new List<ApplicationForm>{ buildApplicationForm(1, 'EOI Submitted', currentUserId) },
          currentUserId,
          null,
          true
        );

      Assert.areEqual(
        ApplicationFormSubmissionService.STATUS_ALREADY_SUBMITTED,
        result.status,
        'The EOI alone is blocked once submitted'
      );
    }
  }

  // Test data

  private static ApplicationFormSubmissionService.SubmissionCheckResult check(final Id fundingOpportunityId) {
    return ApplicationFormSubmissionService.checkExistingSubmission(fundingOpportunityId);
  }

  private static ApplicationFormSubmissionService.SubmissionCheckResult resolve(
    final List<ApplicationForm> applicationForms,
    final Id currentUserId
  ) {
    return ApplicationFormSubmissionService.resolveResult(applicationForms, currentUserId, null);
  }

  private static User buildUser(final String lastName, final Id profileId, final Id roleId) {
    return new User(
      Alias = lastName.left(8),
      Email = lastName + '@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = lastName,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      UserRoleId = roleId,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = lastName + DateTime.now().getTime() + '@testorg.com'
    );
  }

  // An internal user has no Contact: the service is given the Contact of the test Account instead.
  private static void useTestContact() {
    ApplicationFormSubmissionService.contactIdOverride = getContactId();
  }

  private static Id getContactId() {
    return [
      SELECT
        Id
      FROM
        Contact
      WHERE
        LastName = :CONTACT_LAST_NAME
      LIMIT
        1
    ].Id;
  }

  private static Id getAccountId() {
    return [
      SELECT
        AccountId
      FROM
        Contact
      WHERE
        LastName = :CONTACT_LAST_NAME
      LIMIT
        1
    ].AccountId;
  }

  private static User getUser(final String lastName) {
    return [
      SELECT
        Id
      FROM
        User
      WHERE
        LastName = :lastName
      LIMIT
        1
    ];
  }

  private static Id createFundingOpportunity() {
    final Program program = new Program(Name = 'Test Program ' + Math.abs(Crypto.getRandomInteger()));
    insert program;
    final FundingOpportunity fundingOpportunity = new FundingOpportunity(
      Name = 'Test FO',
      Status = 'Draft',
      ProgramId = program.Id
    );
    insert fundingOpportunity;
    return fundingOpportunity.Id;
  }

  private static Id createApplicationForm(final Id fundingOpportunityId, final String stage) {
    final ApplicationForm applicationForm = new ApplicationForm(
      RecordTypeId = SchemaUtilities.getRecordTypeId(ApplicationForm.SObjectType, 'CallForProjects'),
      ReferenceRecordId = fundingOpportunityId,
      ProgrammeRattache__c = fundingOpportunityId,
      UsageType = 'Grantmaking',
      Stage = stage
    );
    insert applicationForm;
    return applicationForm.Id;
  }

  // CreatedById cannot be set on an inserted record, so the colleague rules run on in-memory forms.
  private static ApplicationForm buildApplicationForm(final Integer index, final String stage, final Id createdById) {
    final String keyPrefix = ApplicationForm.SObjectType.getDescribe().getKeyPrefix();
    final String suffix = String.valueOf(index).leftPad(12, '0');
    return (ApplicationForm) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{
          'attributes' => new Map<String, String>{ 'type' => 'ApplicationForm' },
          'Id' => keyPrefix + suffix,
          'Name' => 'Form ' + index,
          'Stage' => stage,
          'CreatedById' => createdById
        }
      ),
      ApplicationForm.class
    );
  }

  private static User createCommunityUser(final String suffix) {
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

    final Account account = new Account(Name = 'Test Organization ' + suffix);
    insert account;
    final Contact contact = new Contact(FirstName = 'Test', LastName = 'Community ' + suffix, AccountId = account.Id);
    insert contact;

    final User communityUser = buildUser('Community' + suffix, profiles[0].Id, null);
    communityUser.ContactId = contact.Id;
    insert communityUser;

    // A candidate reads the Grantmaking objects through the permission sets assigned to the portal users.
    final List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permissionSet : [
      SELECT
        Id
      FROM
        PermissionSet
      WHERE
        Name IN :CANDIDATE_PERMISSION_SET_NAMES
    ]) {
      assignments.add(new PermissionSetAssignment(AssigneeId = communityUser.Id, PermissionSetId = permissionSet.Id));
    }
    insert assignments;
    return communityUser;
  }
}