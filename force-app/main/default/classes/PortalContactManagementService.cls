public without sharing class PortalContactManagementService {
  public enum ErrorCode {
    NOT_OPERATIONAL_CONTACT,
    MISSING_DATA,
    INVALID_EMAIL,
    ROLE_ALREADY_ASSIGNED,
    EMAIL_ALREADY_REGISTERED,
    EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION,
    PORTAL_USER_CREATION_FAILED,
    UNEXPECTED_ERROR
  }

  public class ContactManagementException extends Exception {
    public ContactManagementException(ErrorCode errorCode) {
      this(errorCode.name());
    }
  }

  public class CreateContactRequest {
    @InvocableVariable(required=true)
    public String firstName;
    @InvocableVariable(required=true)
    public String lastName;
    @InvocableVariable(required=true)
    public String email;
    @InvocableVariable
    public String phone;
    @InvocableVariable(required=true)
    public String role;
  }

  public class CreateContactResult {
    @InvocableVariable
    public Boolean isSuccess;
    @InvocableVariable
    public String errorCode;
  }

  private static final String ROLE_PROJECT_APPLICANT_LEAD = 'Project applicant lead';
  private static final String EMAIL_PATTERN = '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$';

  private static final String PORTAL_PROFILE_NAME  = 'Portal User';
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

  @InvocableMethod(label='Create Portal Contact' description='Creates a contact for the organization of the running user, enforcing the one-contact-per-role rule.' category='Portal')
  public static List<CreateContactResult> createContacts(
    List<CreateContactRequest> requests
  ) {
    final List<CreateContactResult> results = new List<CreateContactResult>();
    for (CreateContactRequest request : requests) {
      results.add(createContact(request));
    }
    return results;
  }

  private static CreateContactResult createContact(CreateContactRequest request) {
    final CreateContactResult result = new CreateContactResult();
    try {
      validateRequest(request);

      final Id runningContactId = getRunningUserContactId();
      final Account organization = findOperationalAccount(runningContactId);
      if (organization == null) {
        throw new ContactManagementException(ErrorCode.NOT_OPERATIONAL_CONTACT);
      }

      if (request.role != ROLE_PROJECT_APPLICANT_LEAD && roleAlreadyAssigned(organization.Id, request.role)) {
        throw new ContactManagementException(ErrorCode.ROLE_ALREADY_ASSIGNED);
      }

      final Contact existingContact = findContactByEmail(request.email);
      if (existingContact != null) {
        throw new ContactManagementException(
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
      Database.insert(newContact, true, AccessLevel.SYSTEM_MODE);

      createPortalUser(organization.Id, newContact);

      result.isSuccess = true;
    } catch (ContactManagementException e) {
      result.isSuccess = false;
      result.errorCode = e.getMessage();
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Portal contact creation failed: ' + e.getStackTraceString());
      result.isSuccess = false;
      result.errorCode = ErrorCode.UNEXPECTED_ERROR.name();
    }
    return result;
  }

  private static void validateRequest(CreateContactRequest request) {
    if (
      String.isBlank(request.firstName) ||
      String.isBlank(request.lastName) ||
      String.isBlank(request.email) ||
      String.isBlank(request.role)
    ) {
      throw new ContactManagementException(ErrorCode.MISSING_DATA);
    }
    if (!Pattern.matches(EMAIL_PATTERN, request.email.trim())) {
      throw new ContactManagementException(ErrorCode.INVALID_EMAIL);
    }
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
    final List<Account> organizations = [
      SELECT Id
      FROM Account
      WHERE OperationalContact__c = :runningContactId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return organizations.isEmpty() ? null : organizations[0];
  }

  private static Boolean roleAlreadyAssigned(Id organizationId, String role) {
    return ![
      SELECT Id
      FROM Contact
      WHERE AccountId = :organizationId AND Roles__c = :role
      WITH SYSTEM_MODE
      LIMIT 1
    ].isEmpty();
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

  private static void createPortalUser(Id organizationId, Contact contactRecord) {
    if (!isPortalUserCreationEnabled) {
      return;
    }

    final User portalUser = new User(
      ProfileId = findPortalProfileId(),
      FirstName = contactRecord.FirstName,
      LastName  = contactRecord.LastName,
      Email     = contactRecord.Email,
      Username  = contactRecord.Email + USERNAME_SUFFIX,
      Alias     = buildAlias(contactRecord.LastName),
      CommunityNickname = buildCommunityNickname(contactRecord.Email),
      TimeZoneSidKey    = DEFAULT_TIME_ZONE,
      LocaleSidKey      = DEFAULT_LOCALE,
      LanguageLocaleKey = DEFAULT_LANGUAGE,
      EmailEncodingKey  = DEFAULT_EMAIL_ENCODING
    );

    Id portalUserId;
    try {
      portalUserId = Site.createExternalUser(portalUser, organizationId, null, true);
    } catch (Site.ExternalUserCreateException e) {
      throw new ContactManagementException(ErrorCode.PORTAL_USER_CREATION_FAILED);
    }
    if (portalUserId == null) {
      throw new ContactManagementException(ErrorCode.PORTAL_USER_CREATION_FAILED);
    }
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