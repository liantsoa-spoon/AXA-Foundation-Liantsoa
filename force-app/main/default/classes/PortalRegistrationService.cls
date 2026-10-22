/**
 * @description       : Registers a portal candidate on the organization matching the submitted legal name.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 22-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   24-09-2026   KRA      Initial version
 * 1.1   20-10-2026   LAN      Require the data acceptance policy and record the organization's consents
 * 1.2   20-10-2026   LAN      Delegate the consent documents and records to ConsentService
 * 1.3   22-10-2026   LAN      Stop setting ConsentementCGUAcceptees__c, the consent is an AuthorizationFormConsent
 **/
public without sharing class PortalRegistrationService {
  public enum ErrorCode {
    LEGAL_NAME_REQUIRED,
    MISSING_DATA,
    INVALID_EMAIL,
    DATA_ACCEPTANCE_NOT_ACCEPTED,
    ORGANIZATION_ALREADY_HAS_CONTACT,
    ORGANIZATION_DETAILS_REQUIRED,
    EMAIL_ALREADY_REGISTERED,
    EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION,
    PORTAL_USER_CREATION_FAILED,
    INVALID_INPUT,
    DUPLICATE_ORGANIZATION,
    DUPLICATE_CONTACT,
    UNEXPECTED_ERROR
  }

  public class RegistrationException extends Exception {
    public RegistrationException(ErrorCode errorCode) {
      this(errorCode.name());
    }
  }

  public class ContactInput {
    @AuraEnabled public String salutation;
    @AuraEnabled public String firstName;
    @AuraEnabled public String lastName;
    @AuraEnabled public String title;
    @AuraEnabled public Date   birthdate;
    @AuraEnabled public String phone;
    @AuraEnabled public String email;
  }

  public class OrganizationInput {
    @AuraEnabled public String name;
    @AuraEnabled public String legalForm;
    @AuraEnabled public String otherLegalForm;
    @AuraEnabled public String identificationNumber;
    @AuraEnabled public String taxIdentificationNumber;
    @AuraEnabled public Date   foundingDate;
    @AuraEnabled public String country;
    @AuraEnabled public String street;
    @AuraEnabled public String postalCode;
    @AuraEnabled public String foundingBackground;
    @AuraEnabled public String description;
    @AuraEnabled public String keyDates;
    @AuraEnabled public String objectives;
    @AuraEnabled public String mainActivities;
    @AuraEnabled public String authorizedToIssueTaxReceipts;
    @AuraEnabled public String keyFigures;
    @AuraEnabled public String website;
    @AuraEnabled public ContactInput legalRepresentative;
  }

  public class RegistrationPicklists {
    @AuraEnabled public List<PicklistOption> salutations;
    @AuraEnabled public List<PicklistOption> legalForms;
    @AuraEnabled public List<PicklistOption> authorizedToIssueTaxReceipts;
    @AuraEnabled public List<PicklistOption> countries;
  }

  public class OrganizationLookupResult {
    @AuraEnabled public Boolean exists;
    @AuraEnabled public String operationalContactName;

    public OrganizationLookupResult(Boolean exists, String operationalContactName) {
      this.exists = exists;
      this.operationalContactName = operationalContactName;
    }
  }

  public class PicklistOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;

    public PicklistOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  private static final String CONSENT_CAPTURED_SOURCE = 'Portal Registration';

  private static final String ROLES_LEGAL_REPRESENTATIVE = 'Legal Representative';
  private static final String ROLES_ADMINISTRATIVE_OR_OPERATIONAL_REPRESENTATIVE =
    'Administrative or Operational Representative';

  private static final String OTHER_LEGAL_FORM = 'Other (please specify)';
  private static final String FRANCE           = 'France';

  // The Country value set also lists regions, which are not a country of registration.
  private static final Set<String> NON_COUNTRY_VALUES = new Set<String>{ 'World', 'European Union' };

  private static final String EMAIL_PATTERN = '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$';

  private static final Date EARLIEST_BIRTHDATE = Date.newInstance(1900, 1, 1);

  private static final Integer MINIMUM_SEARCH_LENGTH = 3;
  private static final Integer MAXIMUM_SUGGESTIONS   = 10;

  private static final String PORTAL_PROFILE_NAME  = 'Portal User';
  private static final String OPERATIONAL_PERMISSION_SET_NAME = 'PortalOperationalPortalUser';
  private static final String USERNAME_SUFFIX      = '.org-test.com';
  private static final Integer ALIAS_MAX_LENGTH    = 8;
  private static final Integer NICKNAME_MAX_LENGTH = 40;

  @TestVisible
  private static Boolean isPortalUserCreationEnabled = true;

  private static final String DEFAULT_TIME_ZONE      = 'Europe/Paris';
  private static final String DEFAULT_LOCALE         = 'fr_FR';
  private static final String DEFAULT_LANGUAGE       = 'fr';
  private static final String DEFAULT_EMAIL_ENCODING = 'UTF-8';

  public static List<PicklistOption> buildPicklistOptions(Schema.DescribeFieldResult fieldDescribeResult) {
    final List<PicklistOption> options = new List<PicklistOption>();
    for (Schema.PicklistEntry entry : fieldDescribeResult.getPicklistValues()) {
      if (entry.isActive()) {
        options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
      }
    }
    return options;
  }

  // Apex can only describe a global value set through a field that uses it.
  public static List<PicklistOption> buildCountryOptions() {
    final List<PicklistOption> options = new List<PicklistOption>();
    for (PicklistOption option : buildPicklistOptions(ApplicationForm.ProjectCountry__c.getDescribe())) {
      if (!NON_COUNTRY_VALUES.contains(option.value)) {
        options.add(option);
      }
    }
    return options;
  }

  public static List<String> searchMatchingOrganizationLegalNames(String legalNameInput) {
    if (
      legalNameInput == null ||
      legalNameInput.length() < MINIMUM_SEARCH_LENGTH ||
      legalNameInput.length() > Account.LegalName__c.getDescribe().getLength()
    ) {
      return new List<String>();
    }

    final List<String> legalNames = new List<String>();
    for (Account organization : [
      SELECT
        LegalName__c
      FROM
        Account
      WHERE
        LegalName__c LIKE :('%' + legalNameInput.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%')
      WITH
        SYSTEM_MODE
      ORDER BY
        LegalName__c ASC
      LIMIT
        :MAXIMUM_SUGGESTIONS
    ]) {
      legalNames.add(organization.LegalName__c);
    }
    return legalNames;
  }

  public static OrganizationLookupResult checkOrganizationExists(String legalNameInput) {
    requireFits(legalNameInput, Account.LegalName__c);
    final Account organization = findOrganizationByLegalName(legalNameInput);
    if (organization == null) {
      return new OrganizationLookupResult(false, null);
    }

    final Contact operationalContact = organization.OperationalContact__r;
    if (operationalContact != null && !hasPortalUser(operationalContact.Id)) {
      createPortalUser(operationalContact.Id, toContactInput(operationalContact));
    }

    return new OrganizationLookupResult(
      true,
      operationalContact == null ? null : operationalContact.FirstName + ' ' + operationalContact.LastName
    );
  }

  private static Account findOrganizationByLegalName(String legalNameInput) {
    final List<Account> organizations = [
      SELECT
        Id,
        OperationalContact__r.Id,
        OperationalContact__r.Salutation,
        OperationalContact__r.FirstName,
        OperationalContact__r.LastName,
        OperationalContact__r.Title,
        OperationalContact__r.Birthdate,
        OperationalContact__r.Phone,
        OperationalContact__r.Email
      FROM
        Account
      WHERE
        LegalName__c = :legalNameInput
      WITH
        SYSTEM_MODE
      LIMIT
        1
    ];
    return organizations.isEmpty() ? null : organizations[0];
  }

  private static ContactInput toContactInput(Contact source) {
    final ContactInput contactInput = new ContactInput();
    contactInput.salutation = source.Salutation;
    contactInput.firstName  = source.FirstName;
    contactInput.lastName   = source.LastName;
    contactInput.title      = source.Title;
    contactInput.birthdate  = source.Birthdate;
    contactInput.phone      = source.Phone;
    contactInput.email      = source.Email;
    return contactInput;
  }

  public static ConsentService.ConsentDocument getDataAcceptanceDocument(String language) {
    return ConsentService.getActiveDocument(ConsentService.DATA_ACCEPTANCE_FORM_NAME, language);
  }

  // The registration is not tied to a program: every language version of the policy is consented to.
  private static List<AuthorizationFormText> requireActiveDataAcceptanceTexts(Id acceptedFormTextId) {
    try {
      return ConsentService.requireActiveTexts(ConsentService.DATA_ACCEPTANCE_FORM_NAME, acceptedFormTextId, false);
    } catch (ConsentService.ConsentException e) {
      throw new RegistrationException(ErrorCode.DATA_ACCEPTANCE_NOT_ACCEPTED);
    }
  }

  public static void registerCandidate(
    String legalNameInput,
    ContactInput candidateInput,
    OrganizationInput organizationInput,
    Id dataAcceptanceFormTextId
  ) {
    final List<AuthorizationFormText> dataAcceptanceTexts =
      requireActiveDataAcceptanceTexts(dataAcceptanceFormTextId);
    validateContactInput(candidateInput);
    if (checkOrganizationExists(legalNameInput).exists) {
      throw new RegistrationException(ErrorCode.ORGANIZATION_ALREADY_HAS_CONTACT);
    }
    if (organizationInput == null) {
      throw new RegistrationException(ErrorCode.ORGANIZATION_DETAILS_REQUIRED);
    }
    validateOrganizationInput(organizationInput);

    final Contact existingContact = findContactByEmail(candidateInput.email);
    if (existingContact != null) {
      throw new RegistrationException(
        hasPortalUser(existingContact.Id)
          ? ErrorCode.EMAIL_ALREADY_REGISTERED
          : ErrorCode.EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION
      );
    }

    final Account organization = insertOrganization(legalNameInput, organizationInput);

    final Contact operationalContact = buildContact(
      organization.Id,
      candidateInput,
      ROLES_ADMINISTRATIVE_OR_OPERATIONAL_REPRESENTATIVE
    );
    final ContactInput legalRepresentativeInput =
      organizationInput.legalRepresentative;
    final Contact legalRepresentative = buildContact(
      organization.Id,
      legalRepresentativeInput,
      ROLES_LEGAL_REPRESENTATIVE
    );

    try {
      Database.insert(
        new List<Contact>{ operationalContact, legalRepresentative },
        true,
        AccessLevel.SYSTEM_MODE
      );
    } catch (DmlException e) {
      throwIfDuplicateDetected(e, ErrorCode.DUPLICATE_CONTACT);
      throw e;
    }

    organization.OperationalContact__c  = operationalContact.Id;
    organization.LegalRepresentative__c = legalRepresentative.Id;
    Database.update(organization, true, AccessLevel.SYSTEM_MODE);

    ConsentService.insertConsents(organization.Id, dataAcceptanceTexts, null, CONSENT_CAPTURED_SOURCE);

    createPortalUser(operationalContact.Id, candidateInput);
    createPortalUser(legalRepresentative.Id, legalRepresentativeInput);
  }

  // Everything below the controller is untrusted: lengths and picklist values are checked
  // against the schema here rather than relying on the LWC's own limits.
  private static void validateContactInput(ContactInput contactInput) {
    requireFits(contactInput.firstName, Contact.FirstName);
    requireFits(contactInput.lastName, Contact.LastName);
    requireFits(contactInput.title, Contact.Title);
    requireFits(contactInput.phone, Contact.Phone);
    requireFits(contactInput.email, Contact.Email);
    requireAllowedValue(contactInput.salutation, Contact.Salutation.getDescribe());
    if (String.isNotBlank(contactInput.email) && !Pattern.matches(EMAIL_PATTERN, contactInput.email.trim())) {
      throw new RegistrationException(ErrorCode.INVALID_EMAIL);
    }
    if (
      contactInput.birthdate != null &&
      (contactInput.birthdate < EARLIEST_BIRTHDATE || contactInput.birthdate > Date.today())
    ) {
      throw new RegistrationException(ErrorCode.INVALID_INPUT);
    }
  }

  private static void validateOrganizationInput(OrganizationInput organizationInput) {
    if (
      String.isBlank(organizationInput.name) ||
      String.isBlank(organizationInput.legalForm) ||
      String.isBlank(organizationInput.country) ||
      String.isBlank(
        isRegisteredInFrance(organizationInput)
          ? organizationInput.identificationNumber
          : organizationInput.taxIdentificationNumber
      ) ||
      (organizationInput.legalForm == OTHER_LEGAL_FORM && String.isBlank(organizationInput.otherLegalForm))
    ) {
      throw new RegistrationException(ErrorCode.ORGANIZATION_DETAILS_REQUIRED);
    }

    requireFits(organizationInput.name, Account.Name);
    requireFits(organizationInput.otherLegalForm, Account.OtherLegalForm__c);
    requireFits(organizationInput.identificationNumber, Account.IdentificationNum__c);
    requireFits(organizationInput.taxIdentificationNumber, Account.TIN__c);
    requireFits(organizationInput.street, Account.BillingStreet);
    requireFits(organizationInput.postalCode, Account.BillingPostalCode);
    requireFits(organizationInput.foundingBackground, Account.FoundingBackground__c);
    requireFits(organizationInput.description, Account.Description);
    requireFits(organizationInput.keyDates, Account.KeyDates__c);
    requireFits(organizationInput.objectives, Account.Objectives__c);
    requireFits(organizationInput.mainActivities, Account.MainActivities__c);
    requireFits(organizationInput.keyFigures, Account.KeyFigures__c);
    requireFits(organizationInput.website, Account.Website);
    requireAllowedValue(organizationInput.legalForm, Account.LegalForm__c.getDescribe());
    requireAllowedValue(
      organizationInput.authorizedToIssueTaxReceipts,
      Account.AuthorizedToIssueTaxReceipts__c.getDescribe()
    );
    requireAllowedValue(organizationInput.country, buildCountryOptions());

    final ContactInput legalRepresentativeInput = organizationInput.legalRepresentative;
    if (
      legalRepresentativeInput == null ||
      String.isBlank(legalRepresentativeInput.salutation) ||
      String.isBlank(legalRepresentativeInput.title) ||
      String.isBlank(legalRepresentativeInput.firstName) ||
      String.isBlank(legalRepresentativeInput.lastName) ||
      legalRepresentativeInput.birthdate == null ||
      String.isBlank(legalRepresentativeInput.email) ||
      String.isBlank(legalRepresentativeInput.phone)
    ) {
      throw new RegistrationException(ErrorCode.MISSING_DATA);
    }
    validateContactInput(legalRepresentativeInput);
  }

  // Mirrors the RequireIdentificationNumOrTINByCountry validation rule.
  private static Boolean isRegisteredInFrance(OrganizationInput organizationInput) {
    return organizationInput.country == FRANCE;
  }

  private static void requireFits(String value, Schema.SObjectField field) {
    if (value != null && value.length() > field.getDescribe().getLength()) {
      throw new RegistrationException(ErrorCode.INVALID_INPUT);
    }
  }

  private static void requireAllowedValue(String value, Schema.DescribeFieldResult fieldDescribeResult) {
    requireAllowedValue(value, buildPicklistOptions(fieldDescribeResult));
  }

  private static void requireAllowedValue(String value, List<PicklistOption> allowedOptions) {
    if (String.isBlank(value)) {
      return;
    }
    for (PicklistOption option : allowedOptions) {
      if (option.value == value) {
        return;
      }
    }
    throw new RegistrationException(ErrorCode.INVALID_INPUT);
  }

  private static Contact findContactByEmail(String email) {
    final List<Contact> contacts = [
      SELECT
        Id
      FROM
        Contact
      WHERE
        Email = :email
      WITH
        SYSTEM_MODE
      LIMIT
        1
    ];
    return contacts.isEmpty() ? null : contacts[0];
  }

  private static Boolean hasPortalUser(Id contactId) {
    return ![
      SELECT
        Id
      FROM
        User
      WHERE
        ContactId = :contactId
      WITH
        SYSTEM_MODE
      LIMIT
        1
    ].isEmpty();
  }

  private static Account insertOrganization(
    String legalNameInput,
    OrganizationInput organizationInput
  ) {
    final Account organization = new Account(
      Name = organizationInput.name,
      LegalName__c = legalNameInput,
      LegalForm__c = organizationInput.legalForm,
      OtherLegalForm__c = organizationInput.legalForm == OTHER_LEGAL_FORM ? organizationInput.otherLegalForm : null,
      IdentificationNum__c = organizationInput.identificationNumber,
      TIN__c = organizationInput.taxIdentificationNumber,
      FoundingDate__c = organizationInput.foundingDate,
      BillingCountry = organizationInput.country,
      BillingStreet = organizationInput.street,
      BillingPostalCode = organizationInput.postalCode,
      FoundingBackground__c = organizationInput.foundingBackground,
      Description = organizationInput.description,
      KeyDates__c = organizationInput.keyDates,
      Objectives__c = organizationInput.objectives,
      MainActivities__c = organizationInput.mainActivities,
      AuthorizedToIssueTaxReceipts__c = organizationInput.authorizedToIssueTaxReceipts,
      KeyFigures__c = organizationInput.keyFigures,
      Website = organizationInput.website
    );
    try {
      Database.insert(organization, true, AccessLevel.SYSTEM_MODE);
    } catch (DmlException e) {
      throwIfDuplicateDetected(e, ErrorCode.DUPLICATE_ORGANIZATION);
      throw e;
    }
    return organization;
  }

  // Raised by the Account and Contact duplicate rules, which block the insert.
  private static void throwIfDuplicateDetected(DmlException dmlException, ErrorCode errorCode) {
    if (dmlException.getDmlType(0) == StatusCode.DUPLICATES_DETECTED) {
      throw new RegistrationException(errorCode);
    }
  }

  private static Contact buildContact(
    Id organizationId,
    ContactInput contactInput,
    String role
  ) {
    return new Contact(
      AccountId  = organizationId,
      Salutation = contactInput.salutation,
      FirstName  = contactInput.firstName,
      LastName   = contactInput.lastName,
      Title      = contactInput.title,
      Birthdate  = contactInput.birthdate,
      Phone      = contactInput.phone,
      Email      = contactInput.email,
      Roles__c   = role
    );
  }

  // The user is attached to the existing Contact; Site.createExternalUser would create a duplicate Contact.
  private static void createPortalUser(
    Id contactId,
    ContactInput contactInput
  ) {
    if (!isPortalUserCreationEnabled) {
      return;
    }
    if (String.isBlank(contactInput.email) || String.isBlank(contactInput.lastName)) {
      throw new RegistrationException(ErrorCode.PORTAL_USER_CREATION_FAILED);
    }

    final User portalUser = new User(
      ProfileId = findPortalProfileId(),
      ContactId = contactId,
      FirstName = contactInput.firstName,
      LastName  = contactInput.lastName,
      Email     = contactInput.email,
      // Username  = contactInput.email + USERNAME_SUFFIX,
      Username  = contactInput.Email,
      Alias     = buildAlias(contactInput.lastName),
      CommunityNickname = buildCommunityNickname(contactInput.email),
      TimeZoneSidKey    = DEFAULT_TIME_ZONE,
      LocaleSidKey      = DEFAULT_LOCALE,
      LanguageLocaleKey = DEFAULT_LANGUAGE,
      EmailEncodingKey  = DEFAULT_EMAIL_ENCODING,
      UserPermissionsSFContentUser = true
    );

    try {
      Database.insert(portalUser, true, AccessLevel.SYSTEM_MODE);
      assignOperationalPermissionSet(portalUser.Id, contactId);
      System.resetPassword(portalUser.Id, true);
    } catch (Exception e) {
      throw new RegistrationException(ErrorCode.PORTAL_USER_CREATION_FAILED);
    }
  }

  // Runs in its own transaction: PermissionSetAssignment is a setup object and cannot be inserted
  // after the Account/Contact DML of the registration (MIXED_DML_OPERATION).
  @future
  private static void assignOperationalPermissionSet(Id userId, Id contactId) {
    final List<Contact> contacts = [
      SELECT
        Roles__c
      FROM
        Contact
      WHERE
        Id = :contactId
        AND Roles__c = :ROLES_ADMINISTRATIVE_OR_OPERATIONAL_REPRESENTATIVE
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
      SELECT
        Id
      FROM
        Profile
      WHERE
        Name = :PORTAL_PROFILE_NAME
      WITH
        SYSTEM_MODE
      LIMIT
        1
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