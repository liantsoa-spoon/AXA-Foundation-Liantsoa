/**
 * @description       : Creates the test records shared by the project's test classes.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 22-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   05-10-2026   KRA      Initial version
 * 1.1   10-07-2026   AGO      Merged Portal & Standard Test Data Factories
 * 1.2   08-10-2026   KRA      Add the question catalogue builders
 * 1.3   22-10-2026   LAN      Stop setting ConsentementCGUAcceptees__c on the test organizations
 **/
@IsTest
public class TestDataFactory {

  // =========================================================================
  // CONSTANTS
  // =========================================================================

  // User & Profile Constants
  private static final String USERNAME_PREFIX = 'test.user.';
  private static final String USERNAME_DOMAIN = '@org.test';
  private static final String USERNAME_PATTERN = USERNAME_PREFIX + '%' + USERNAME_DOMAIN;
  private static final Set<String> SYSTEM_ADMINISTRATOR_PROFILE_LOCALIZED_NAMES = new Set<String>{
    'System Administrator',
    'Administrateur système'
  };

  // Portal & Contact Roles Constants
  public static final String ROLE_OPERATIONAL_CONTACT = 'Administrative or Operational Representative';
  public static final String ROLE_LEGAL_REPRESENTATIVE = 'Legal Representative';
  public static final String PORTAL_PROFILE_NAME = 'Portal User';
  public static final String PORTAL_PERMISSION_SET_NAME = 'PortalGuestUser';
  public static final String USERNAME_SUFFIX = '.org-test.com';

  // Default Fixture Constants
  public static final String DEFAULT_ORGANIZATION_NAME = 'Org Test Foundation';
  public static final String DEFAULT_ORGANIZATION_LEGAL_NAME = 'Org Test Foundation Legal Name';
  public static final String DEFAULT_OPERATIONAL_EMAIL = 'operational@org-test.com';
  public static final String DEFAULT_OPERATIONAL_FIRST_NAME = 'Olivia';
  public static final String DEFAULT_OPERATIONAL_LAST_NAME = 'Operational';

  // Application Form Question Constants
  public static final String ASSESSMENT_QUESTION_DATA_TYPE_TEXT = 'Text';
  public static final String ASSESSMENT_QUESTION_QUESTION_CATEGORY_DEMOGRAPHIC = 'Demographic';

  private static final String OWNER_LAST_NAME = 'FactoryOwner';
  private static Integer sequence = 0;

  // =========================================================================
  // INNER CLASSES / FIXTURES
  // =========================================================================

  public class PortalFixture {
    public Account organization;
    public Contact operationalContact;
    public User portalUser;
  }

  // =========================================================================
  // USER CREATION & RETRIEVAL
  // =========================================================================

  public static User createUser(String profileName, List<String> permissionSetNames) {
    return insertUser(getProfileIdByLocalizedNames(new Set<String>{ profileName }), permissionSetNames);
  }

  public static User createAdminUser(List<String> permissionSetNames) {
    return insertUser(getProfileIdByLocalizedNames(SYSTEM_ADMINISTRATOR_PROFILE_LOCALIZED_NAMES), permissionSetNames);
  }

  public static User getUser(String profileName) {
    return getUserByLocalizedProfileNames(new Set<String>{ profileName });
  }

  public static User getAdminUser() {
    return getUserByLocalizedProfileNames(SYSTEM_ADMINISTRATOR_PROFILE_LOCALIZED_NAMES);
  }

  // Portal users can only be created for accounts whose owner has a role.
  public static User createOrganizationOwner() {
    final List<User> existingOwners = [
      SELECT
        Id
      FROM
        User
      WHERE
        LastName = :OWNER_LAST_NAME
      LIMIT
        1
    ];
    if (!existingOwners.isEmpty()) {
      return existingOwners[0];
    }

    final String uniqueKey = String.valueOf(DateTime.now().getTime()) + nextSequence();
    final User owner = new User(
      Alias = 'orgown',
      Email = 'factoryowner' + uniqueKey + '@org-test.com',
      EmailEncodingKey = 'UTF-8',
      LastName = OWNER_LAST_NAME,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'factoryowner' + uniqueKey + '@org-test.com'
    );

    System.runAs(new User(Id = UserInfo.getUserId())) {
      final UserRole ownerRole = new UserRole(
        Name = 'Org Test Owner Role ' + uniqueKey,
        DeveloperName = 'Org_Test_Owner_Role_' + uniqueKey
      );
      insert ownerRole;

      owner.UserRoleId = ownerRole.Id;
      owner.ProfileId = getProfileIdByLocalizedNames(SYSTEM_ADMINISTRATOR_PROFILE_LOCALIZED_NAMES);
      insert owner;
    }

    return owner;
  }

  public static User createPortalUser(Contact contactRecord) {
    return createPortalUser(contactRecord, contactRecord.Email);
  }

  public static User createPortalUser(Contact contactRecord, String username) {
    final String uniqueKey = String.valueOf(DateTime.now().getTime()) + nextSequence();
    final User portalUser = new User(
      ProfileId = [
        SELECT
          Id
        FROM
          Profile
        WHERE
          Name = :PORTAL_PROFILE_NAME
        LIMIT
          1
      ].Id,
      ContactId = contactRecord.Id,
      FirstName = contactRecord.FirstName,
      LastName = contactRecord.LastName,
      Email = contactRecord.Email,
      Username = username,
      Alias = 'portal' + Math.mod(Integer.valueOf(nextSequence()), 100),
      CommunityNickname = 'nick' + uniqueKey,
      TimeZoneSidKey = 'Europe/Paris',
      LocaleSidKey = 'fr_FR',
      LanguageLocaleKey = 'en_US',
      EmailEncodingKey = 'UTF-8'
    );

    final Id permissionSetId = [
      SELECT
        Id
      FROM
        PermissionSet
      WHERE
        Name = :PORTAL_PERMISSION_SET_NAME
      LIMIT
        1
    ].Id;

    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert portalUser;
      insert new PermissionSetAssignment(AssigneeId = portalUser.Id, PermissionSetId = permissionSetId);
    }

    return portalUser;
  }

  public static List<User> createPortalUsers(
    List<Contact> contacts,
    String profileName,
    List<String> permissionSetNames
  ) {
    final Id profileId = getProfileIdByLocalizedNames(new Set<String>{ profileName });
    final List<User> portalUsers = new List<User>();
    for (Contact contactRecord : contacts) {
      final String uniqueKey = String.valueOf(DateTime.now().getTime()) + nextSequence();
      portalUsers.add(
        new User(
          ProfileId         = profileId,
          ContactId         = contactRecord.Id,
          FirstName         = contactRecord.FirstName,
          LastName          = contactRecord.LastName,
          Email             = contactRecord.Email,
          Username          = contactRecord.Email + '.' + uniqueKey,
          Alias             = 'portal' + Math.mod(Integer.valueOf(nextSequence()), 100),
          CommunityNickname = 'nick' + uniqueKey,
          TimeZoneSidKey    = 'Europe/Paris',
          LocaleSidKey      = 'fr_FR',
          LanguageLocaleKey = 'fr',
          EmailEncodingKey  = 'UTF-8'
        )
      );
    }

    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert portalUsers;
      assignPermissionSets(portalUsers, permissionSetNames);
    }
    return portalUsers;
  }

  public static User getPortalUser() {
    return getPortalUser(DEFAULT_OPERATIONAL_LAST_NAME);
  }

  public static User getPortalUser(String lastName) {
    return [
      SELECT
        Id,
        ContactId,
        Contact.AccountId
      FROM
        User
      WHERE
        LastName = :lastName
        AND Profile.Name = :PORTAL_PROFILE_NAME
      LIMIT
        1
    ];
  }

  // =========================================================================
  // ACCOUNT & CONTACT CREATION
  // =========================================================================

  public static Account createOrganization(String name, String legalName) {
    final Account organization = new Account(
      Name = name,
      LegalName__c = legalName,
      OwnerId = createOrganizationOwner().Id
    );
    insertAllowingDuplicates(organization);
    return organization;
  }

  public static Contact createContact(Id accountId, String firstName, String lastName, String email, String roles) {
    final Contact contactRecord = new Contact(
      AccountId = accountId,
      FirstName = firstName,
      LastName = lastName,
      Email = email,
      Phone = '0102030405',
      Roles__c = roles
    );
    insertAllowingDuplicates(contactRecord);
    return contactRecord;
  }

  public static Contact createOperationalContact(Account organization, String email) {
    final Contact operationalContact = createContact(
      organization.Id,
      DEFAULT_OPERATIONAL_FIRST_NAME,
      DEFAULT_OPERATIONAL_LAST_NAME,
      email,
      ROLE_OPERATIONAL_CONTACT
    );

    final Account accountToUpdate = new Account(
      Id = organization.Id,
      OperationalContact__c = operationalContact.Id
    );
    update accountToUpdate;

    return operationalContact;
  }

  // =========================================================================
  // PORTAL FIXTURES
  // =========================================================================

  public static PortalFixture createPortalFixture() {
    return createPortalFixture(
      DEFAULT_ORGANIZATION_NAME,
      DEFAULT_ORGANIZATION_LEGAL_NAME,
      DEFAULT_OPERATIONAL_EMAIL
    );
  }

  public static PortalFixture createPortalFixture(String name, String legalName, String operationalEmail) {
    final PortalFixture fixture = new PortalFixture();
    fixture.organization = createOrganization(name, legalName);
    fixture.operationalContact = createOperationalContact(fixture.organization, operationalEmail);
    fixture.portalUser = createPortalUser(fixture.operationalContact);
    return fixture;
  }

  // =========================================================================
  // DOMAIN OBJECT BUILDERS
  // =========================================================================

  public static Program createPillar(String name) {
    final Program pillar = new Program(Name = name);
    insert pillar;
    return pillar;
  }

  public static FundingOpportunity buildFundingOpportunity(
    String name,
    String recordTypeDeveloperName,
    Id pillarId
  ) {
    return new FundingOpportunity(
      Name = name,
      ProgramId = pillarId,
      RecordTypeId = new RecordTypeProvider.RecordTypeReference(
        FundingOpportunity.SObjectType,
        recordTypeDeveloperName
      ).Id
    );
  }

  public static FundingOpportunity createFundingOpportunityWithoutCatalogue(
    RecordTypeProvider.RecordTypeReference recordType,
    Id pillarId
  ) {
    final FundingOpportunity fundingOpportunity =
      buildFundingOpportunity('Program', recordType.DeveloperName, pillarId);
    FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled = false;
    try {
      insert fundingOpportunity;
    } finally {
      FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled = true;
    }
    return fundingOpportunity;
  }

  public static AssessmentQuestionSet createAssessmentQuestionSet(String name, Decimal sequence) {
    final AssessmentQuestionSet section = new AssessmentQuestionSet(
      Name          = name,
      DeveloperName = buildUniqueDeveloperName('TestSection'),
      Sequence__c   = sequence
    );
    insert section;
    return section;
  }

  public static AssessmentQuestion createAssessmentQuestion(String name) {
    final AssessmentQuestion question = new AssessmentQuestion(
      Name                 = name,
      DeveloperName        = buildUniqueDeveloperName('TestQuestion'),
      DataType             = ASSESSMENT_QUESTION_DATA_TYPE_TEXT,
      QuestionCategory     = ASSESSMENT_QUESTION_QUESTION_CATEGORY_DEMOGRAPHIC,
      MaximumCharacters__c = 255,
      Sequence__c          = 1
    );
    insert question;
    return question;
  }

  public static AssessmentQuestionAssignment createAssessmentQuestionAssignment(
    Id questionId,
    Id sectionId,
    Id fundingOpportunityId,
    Id pillarId,
    Boolean isEOI
  ) {
    final AssessmentQuestionAssignment questionAssignment = new AssessmentQuestionAssignment(
      AssessmentQuestionId    = questionId,
      AssessmentQuestionSetId = sectionId,
      FundingOpportunity__c   = fundingOpportunityId,
      Program__c              = pillarId,
      EOI__c                  = isEOI,
      IsMandatory__c          = true
    );
    insert questionAssignment;
    return questionAssignment;
  }

  public static String buildUniqueDeveloperName(String prefix) {
    return prefix + nextSequence();
  }

  // =========================================================================
  // SCHEMA HELPERS
  // =========================================================================

  public static Set<String> getActivePicklistValues(Schema.SObjectField field) {
    final Set<String> activePicklistValues = new Set<String>();
    for (Schema.PicklistEntry picklistEntry : field.getDescribe().getPicklistValues()) {
      if (picklistEntry.isActive()) {
        activePicklistValues.add(picklistEntry.getValue());
      }
    }
    return activePicklistValues;
  }

  // =========================================================================
  // PRIVATE HELPERS
  // =========================================================================

  private static Id getProfileIdByLocalizedNames(Set<String> localizedProfileNames) {
    final List<Profile> profiles = [
      SELECT
        Id
      FROM
        Profile
      WHERE
        Name IN :localizedProfileNames
      LIMIT
        1
    ];
    Assert.isFalse(profiles.isEmpty(), 'Profile not found: ' + localizedProfileNames);
    return profiles[0].Id;
  }

  private static User insertUser(Id profileId, List<String> permissionSetNames) {
    final User testUser = new User(
      Alias = 'testuser',
      Email = 'test.user' + USERNAME_DOMAIN,
      EmailEncodingKey = 'UTF-8',
      LastName = 'Test User',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'Europe/Paris',
      Username = USERNAME_PREFIX + Math.abs(Crypto.getRandomInteger()) + USERNAME_DOMAIN
    );

    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert testUser;
      assignPermissionSets(new List<User>{ testUser }, permissionSetNames);
    }

    return testUser;
  }

  // Must run inside System.runAs, after the users are inserted, to avoid mixed DML.
  private static void assignPermissionSets(List<User> users, List<String> permissionSetNames) {
    final Set<String> missingPermissionSetNames = new Set<String>(permissionSetNames);
    final Set<Id> permissionSetLicenseIds = new Set<Id>();
    final List<PermissionSetAssignment> permissionSetAssignments = new List<PermissionSetAssignment>();

    for (PermissionSet permissionSet : [
      SELECT
        Id,
        Name,
        LicenseId
      FROM
        PermissionSet
      WHERE
        Name IN :permissionSetNames
    ]) {
      missingPermissionSetNames.remove(permissionSet.Name);
      if (permissionSet.LicenseId?.getSObjectType() == PermissionSetLicense.SObjectType) {
        permissionSetLicenseIds.add(permissionSet.LicenseId);
      }
      for (User assignee : users) {
        permissionSetAssignments.add(
          new PermissionSetAssignment(AssigneeId = assignee.Id, PermissionSetId = permissionSet.Id)
        );
      }
    }

    Assert.isTrue(
      missingPermissionSetNames.isEmpty(),
      'Permission sets not found: ' + missingPermissionSetNames
    );

    final List<PermissionSetLicenseAssign> permissionSetLicenseAssignments = new List<PermissionSetLicenseAssign>();
    for (Id permissionSetLicenseId : permissionSetLicenseIds) {
      for (User assignee : users) {
        permissionSetLicenseAssignments.add(
          new PermissionSetLicenseAssign(AssigneeId = assignee.Id, PermissionSetLicenseId = permissionSetLicenseId)
        );
      }
    }

    insert permissionSetLicenseAssignments;
    insert permissionSetAssignments;
  }

  private static User getUserByLocalizedProfileNames(Set<String> localizedProfileNames) {
    return [
      SELECT
        Id
      FROM
        User
      WHERE
        Username LIKE :USERNAME_PATTERN
        AND Profile.Name IN :localizedProfileNames
      LIMIT
        1
    ];
  }

  private static void insertAllowingDuplicates(SObject record) {
    final Database.DMLOptions options = new Database.DMLOptions();
    options.DuplicateRuleHeader.allowSave = true;
    options.DuplicateRuleHeader.runAsCurrentUser = true;

    final Database.SaveResult result = Database.insert(record, options);
    if (!result.isSuccess()) {
      final List<String> errMessages = new List<String>();
      for (Database.Error err : result.getErrors()) {
        errMessages.add(err.getMessage());
      }
      Assert.fail('Failed to insert ' + record.getSObjectType() + ': ' + String.join(errMessages, ', '));
    }
  }

  private static String nextSequence() {
    sequence++;
    return String.valueOf(sequence);
  }
}