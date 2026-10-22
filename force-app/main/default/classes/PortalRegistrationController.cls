/**
 * @description       : Validates the portal registration component's input and reports each outcome as a code.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 20-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   24-09-2026   KRA      Initial version
 * 1.1   20-10-2026   LAN      Expose the data acceptance policy and require it instead of the terms and conditions
 * 1.2   20-10-2026   LAN      Return the data acceptance document as a ConsentService.ConsentDocument
 **/
public with sharing class PortalRegistrationController {
  private static final String EMAIL_PATTERN = '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$';

  @AuraEnabled(cacheable=true)
  public static List<String> suggestOrganizations(String legalNameInput) {
    if (String.isBlank(legalNameInput)) {
      return new List<String>();
    }
    try {
      return PortalRegistrationService.searchMatchingOrganizationLegalNames(legalNameInput.trim());
    } catch (Exception e) {
      throw convertToAuraException(e);
    }
  }

  @AuraEnabled
  public static PortalRegistrationService.OrganizationLookupResult checkOrganizationExists(String legalNameInput) {
    if (String.isBlank(legalNameInput)) {
      throw buildAuraException(PortalRegistrationService.ErrorCode.LEGAL_NAME_REQUIRED);
    }
    try {
      return PortalRegistrationService.checkOrganizationExists(legalNameInput.trim());
    } catch (Exception e) {
      throw convertToAuraException(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static PortalRegistrationService.RegistrationPicklists getRegistrationPicklists() {
    final PortalRegistrationService.RegistrationPicklists picklists =
      new PortalRegistrationService.RegistrationPicklists();

    picklists.salutations = PortalRegistrationService.buildPicklistOptions(Contact.Salutation.getDescribe());
    picklists.legalForms  = PortalRegistrationService.buildPicklistOptions(Account.LegalForm__c.getDescribe());
    picklists.authorizedToIssueTaxReceipts = PortalRegistrationService.buildPicklistOptions(
      Account.AuthorizedToIssueTaxReceipts__c.getDescribe()
    );
    picklists.countries = PortalRegistrationService.buildCountryOptions();

    return picklists;
  }

  @AuraEnabled(cacheable=true)
  public static ConsentService.ConsentDocument getDataAcceptanceDocument(String language) {
    try {
      return PortalRegistrationService.getDataAcceptanceDocument(language);
    } catch (Exception e) {
      throw convertToAuraException(e);
    }
  }

  @AuraEnabled
  public static void registerCandidate(
    String legalNameInput,
    Map<String, Object> candidateInput,
    Map<String, Object> organizationInput,
    Id dataAcceptanceFormTextId
  ) {
    // Aura leaves inner class parameters empty, so the conversion is done here rather than by the framework.
    // Strict deserialization rejects any field the wrapper classes do not declare.
    final PortalRegistrationService.ContactInput candidate =
      (PortalRegistrationService.ContactInput) deserializeStrict(
        candidateInput,
        PortalRegistrationService.ContactInput.class
      );
    final PortalRegistrationService.OrganizationInput organization =
      (PortalRegistrationService.OrganizationInput) deserializeStrict(
        organizationInput,
        PortalRegistrationService.OrganizationInput.class
      );

    if (
      String.isBlank(legalNameInput) ||
      candidate == null ||
      String.isBlank(candidate.firstName) ||
      String.isBlank(candidate.lastName) ||
      String.isBlank(candidate.email)
    ) {
      throw buildAuraException(PortalRegistrationService.ErrorCode.MISSING_DATA);
    }
    candidate.email = candidate.email.trim();
    if (!Pattern.matches(EMAIL_PATTERN, candidate.email)) {
      throw buildAuraException(PortalRegistrationService.ErrorCode.INVALID_EMAIL);
    }
    // The service also checks that the text belongs to the active revision of the policy.
    if (dataAcceptanceFormTextId == null) {
      throw buildAuraException(PortalRegistrationService.ErrorCode.DATA_ACCEPTANCE_NOT_ACCEPTED);
    }

    try {
      PortalRegistrationService.registerCandidate(
        legalNameInput.trim(),
        candidate,
        organization,
        dataAcceptanceFormTextId
      );
    } catch (Exception e) {
      throw convertToAuraException(e);
    }
  }

  private static Object deserializeStrict(Map<String, Object> source, System.Type targetType) {
    if (source == null) {
      return null;
    }
    try {
      return JSON.deserializeStrict(JSON.serialize(source), targetType);
    } catch (JSONException e) {
      throw buildAuraException(PortalRegistrationService.ErrorCode.INVALID_INPUT);
    }
  }

  private static AuraHandledException convertToAuraException(Exception sourceException) {
    if (sourceException instanceof PortalRegistrationService.RegistrationException) {
      return buildAuraException(sourceException.getMessage());
    }

    System.debug(LoggingLevel.ERROR, 'Portal registration failed: ' + sourceException.getStackTraceString());
    return buildAuraException(PortalRegistrationService.ErrorCode.UNEXPECTED_ERROR);
  }

  private static AuraHandledException buildAuraException(PortalRegistrationService.ErrorCode errorCode) {
    return buildAuraException(errorCode.name());
  }

  private static AuraHandledException buildAuraException(String errorCode) {
    final AuraHandledException auraException = new AuraHandledException(errorCode);
    auraException.setMessage(errorCode);
    return auraException;
  }
}