public without sharing class PortalContactCreationService {
  public enum ErrorCode {
    NOT_OPERATIONAL_CONTACT,
    MISSING_DATA,
    INVALID_EMAIL,
    ROLE_ALREADY_ASSIGNED,
    ROLE_LIMIT_REACHED,
    EMAIL_ALREADY_REGISTERED,
    EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION,
    PORTAL_USER_CREATION_FAILED,
    INVALID_INPUT,
    DUPLICATE_CONTACT,
    UNEXPECTED_ERROR
  }

  public class ContactCreationException extends Exception {
    public ContactCreationException(ErrorCode errorCode) {
      this(errorCode.name());
    }
  }

  public class CreateContactRequest {
    @AuraEnabled public String firstName;
    @AuraEnabled public String lastName;
    @AuraEnabled public String email;
    @AuraEnabled public String phone;
    @AuraEnabled public String role;
  }

  public class PicklistOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;

    public PicklistOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  // Project bearers hold the operational contact role, so it is exempt from the role rules.
  private static final String ROLE_OPERATIONAL_CONTACT = 'Administrative or Operational Representative';
  private static final Integer MAXIMUM_ROLES = 4;
  private static final String EMAIL_PATTERN = '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$';

  private static final String PORTAL_PROFILE_NAME  = 'Portal User';
  private static final String OPERATIONAL_PERMISSION_SET_NAME = 'AXAFoundationOperationalPortalUser';
  private static final String USERNAME_SUFFIX      = '.axafoundation';
  private static final Integer ALIAS_MAX_LENGTH    = 8;
  private static final Integer NICKNAME_MAX_LENGTH = 40;

  private static final String DEFAULT_TIME_ZONE      = 'Europe/Paris';
  private static final String DEFAULT_LOCALE         = 'fr_FR';
  private static final String DEFAULT_LANGUAGE       = 'fr';
  private static final String DEFAULT_EMAIL_ENCODING = 'UTF-8';

  // Site.createExternalUser has no effect outside a site context, which no Apex test provides.
  @TestVisible
  private static Boolean isPortalUserCreationEnabled = true;

  // Only these roles can be given from the portal; createContact validates against the same list.
  private static final Set<String> SELECTABLE_ROLES = new Set<String>{
    'Legal Representative',
    ROLE_OPERATIONAL_CONTACT,
    'Project applicant lead'
  };

  public static List<PicklistOption> buildRoleOptions() {
    final List<PicklistOption> options = new List<PicklistOption>();
    for (Schema.PicklistEntry entry : Contact.Roles__c.getDescribe().getPicklistValues()) {
      if (entry.isActive() && SELECTABLE_ROLES.contains(entry.getValue())) {
        options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
      }
    }
    return options;
  }

  public static void createContact(CreateContactRequest request) {
    validateRequest(request);

    final Id runningContactId = getRunningUserContactId();
    final Account organization = findOperationalAccount(runningContactId);
    if (organization == null) {
      throw new ContactCreationException(ErrorCode.NOT_OPERATIONAL_CONTACT);
    }

    final Boolean isReplacingOperationalContact = request.role == ROLE_OPERATIONAL_CONTACT;
    if (!isReplacingOperationalContact) {
      enforceRoleRules(organization.Id, request.role);
    }

    final Contact existingContact = findContactByEmail(request.email);
    if (existingContact != null) {
      throw new ContactCreationException(
        existingContact.AccountId == organization.Id
          ? ErrorCode.EMAIL_ALREADY_REGISTERED
          : ErrorCode.EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION
      );
    }

    final Contact newContact = new Contact(
      AccountId = organization.Id,
      FirstName = request.firstName,
      LastName  = request.lastName,
      Email     = request.email,
      Phone     = request.phone,
      Roles__c  = request.role
    );
    try {
      Database.insert(newContact, true, AccessLevel.SYSTEM_MODE);
    } catch (DmlException e) {
      // Raised by the Contact duplicate rule, which blocks the insert.
      if (e.getDmlType(0) == StatusCode.DUPLICATES_DETECTED) {
        throw new ContactCreationException(ErrorCode.DUPLICATE_CONTACT);
      }
      throw e;
    }

    if (isReplacingOperationalContact) {
      organization.OperationalContact__c = newContact.Id;
      Database.update(organization, true, AccessLevel.SYSTEM_MODE);
    }

    createPortalUser(newContact);
  }

  private static void validateRequest(CreateContactRequest request) {
    if (
      request == null ||
      String.isBlank(request.firstName) ||
      String.isBlank(request.lastName) ||
      String.isBlank(request.email) ||
      String.isBlank(request.role)
    ) {
      throw new ContactCreationException(ErrorCode.MISSING_DATA);
    }
    if (!Pattern.matches(EMAIL_PATTERN, request.email.trim())) {
      throw new ContactCreationException(ErrorCode.INVALID_EMAIL);
    }

    // The request comes from the browser: lengths and the role are checked against the schema.
    final Boolean isFitting =
      request.firstName.length() <= Contact.FirstName.getDescribe().getLength() &&
      request.lastName.length() <= Contact.LastName.getDescribe().getLength() &&
      request.email.length() <= Contact.Email.getDescribe().getLength() &&
      (request.phone == null || request.phone.length() <= Contact.Phone.getDescribe().getLength());
    if (!isFitting || !isAllowedRole(request.role)) {
      throw new ContactCreationException(ErrorCode.INVALID_INPUT);
    }
  }

  private static Boolean isAllowedRole(String role) {
    for (PicklistOption option : buildRoleOptions()) {
      if (option.value == role) {
        return true;
      }
    }
    return false;
  }

  private static Id getRunningUserContactId() {
    final User runningUser = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ];
    return runningUser.ContactId;
  }

  private static Account findOperationalAccount(Id runningContactId) {
    if (runningContactId == null) {
      return null;
    }
    // Roles__c is the source of truth: a contact holding the role may not be Account.OperationalContact__c.
    final List<Contact> operationalContacts = [
      SELECT AccountId
      FROM Contact
      WHERE
        Id = :runningContactId
        AND AccountId != NULL
        AND Roles__c INCLUDES (:ROLE_OPERATIONAL_CONTACT)
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!operationalContacts.isEmpty()) {
      return new Account(Id = operationalContacts[0].AccountId);
    }

    final List<Account> organizations = [
      SELECT Id
      FROM Account
      WHERE OperationalContact__c = :runningContactId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return organizations.isEmpty() ? null : organizations[0];
  }

  // Roles__c is a multiselect picklist, so each contact may carry several roles.
  private static void enforceRoleRules(Id organizationId, String role) {
    final Set<String> assignedRoles = new Set<String>();
    for (Contact contactRecord : [
      SELECT Roles__c
      FROM Contact
      WHERE AccountId = :organizationId AND Roles__c != NULL
      WITH SYSTEM_MODE
    ]) {
      assignedRoles.addAll(contactRecord.Roles__c.split(';'));
    }

    if (assignedRoles.contains(role)) {
      throw new ContactCreationException(ErrorCode.ROLE_ALREADY_ASSIGNED);
    }
    if (assignedRoles.size() >= MAXIMUM_ROLES) {
      throw new ContactCreationException(ErrorCode.ROLE_LIMIT_REACHED);
    }
  }

  private static Contact findContactByEmail(String email) {
    final List<Contact> contacts = [
      SELECT Id, AccountId
      FROM Contact
      WHERE Email = :email
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return contacts.isEmpty() ? null : contacts[0];
  }

  private static void createPortalUser(Contact contactRecord) {
    if (!isPortalUserCreationEnabled) {
      return;
    }

    final User portalUser = new User(
      ProfileId = findPortalProfileId(),
      ContactId = contactRecord.Id,
      FirstName = contactRecord.FirstName,
      LastName  = contactRecord.LastName,
      Email     = contactRecord.Email,
      // Username  = contactRecord.Email + USERNAME_SUFFIX,
      Username  = contactRecord.Email,
      Alias     = buildAlias(contactRecord.LastName),
      CommunityNickname = buildCommunityNickname(contactRecord.Email),
      TimeZoneSidKey    = DEFAULT_TIME_ZONE,
      LocaleSidKey      = DEFAULT_LOCALE,
      LanguageLocaleKey = DEFAULT_LANGUAGE,
      EmailEncodingKey  = DEFAULT_EMAIL_ENCODING,
      UserPermissionsSFContentUser = true
    );

    try {
      Database.insert(portalUser, true, AccessLevel.SYSTEM_MODE);
      assignOperationalPermissionSet(portalUser.Id, contactRecord.Id);
      System.resetPassword(portalUser.Id, true);
    } catch (Exception e) {
      throw new ContactCreationException(ErrorCode.PORTAL_USER_CREATION_FAILED);
    }
  }

  @future
  private static void assignOperationalPermissionSet(Id userId, Id contactId) {
    final List<Contact> contacts = [
      SELECT
        Roles__c
      FROM
        Contact
      WHERE
        Id = :contactId
        AND Roles__c = :ROLE_OPERATIONAL_CONTACT
      WITH
        SYSTEM_MODE
      LIMIT
        1
    ];
    if (contacts.isEmpty()) {
      return;
    }

    final PermissionSet operationalPermissionSet = [
      SELECT
        Id
      FROM
        PermissionSet
      WHERE
        Name = :OPERATIONAL_PERMISSION_SET_NAME
      WITH
        SYSTEM_MODE
      LIMIT
        1
    ];
    Database.insert(
      new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = operationalPermissionSet.Id),
      true,
      AccessLevel.SYSTEM_MODE
    );
  }

  private static Id findPortalProfileId() {
    return [
      SELECT Id
      FROM Profile
      WHERE Name = :PORTAL_PROFILE_NAME
      WITH SYSTEM_MODE
      LIMIT 1
    ].Id;
  }

  private static String buildAlias(String lastName) {
    final String alias = lastName.deleteWhitespace().toLowerCase();
    return alias.length() > ALIAS_MAX_LENGTH ? alias.substring(0, ALIAS_MAX_LENGTH) : alias;
  }

  private static String buildCommunityNickname(String email) {
    final String nickname = email.replaceAll('[^a-zA-Z0-9]', '');
    return nickname.length() > NICKNAME_MAX_LENGTH
      ? nickname.substring(0, NICKNAME_MAX_LENGTH)
      : nickname;
  }
}