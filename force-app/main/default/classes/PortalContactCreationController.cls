public with sharing class PortalContactCreationController {
  @AuraEnabled
  public static List<PortalContactCreationService.PicklistOption> getRoleOptions() {
    try {
      return PortalContactCreationService.buildRoleOptions();
    } catch (Exception e) {
      throw convertToAuraException(e);
    }
  }

  @AuraEnabled
  public static void createContact(
    String firstName,
    String lastName,
    String email,
    String phone,
    String role
  ) {
    final PortalContactCreationService.CreateContactRequest request =
      new PortalContactCreationService.CreateContactRequest();
    request.firstName = firstName;
    request.lastName  = lastName;
    request.email     = email;
    request.phone     = phone;
    request.role      = role;

    try {
      PortalContactCreationService.createContact(request);
    } catch (Exception e) {
      throw convertToAuraException(e);
    }
  }

  private static AuraHandledException convertToAuraException(Exception sourceException) {
    if (sourceException instanceof PortalContactCreationService.ContactCreationException) {
      return buildAuraException(sourceException.getMessage());
    }

    System.debug(LoggingLevel.ERROR, 'Portal contact creation failed: ' + sourceException.getStackTraceString());
    return buildAuraException(PortalContactCreationService.ErrorCode.UNEXPECTED_ERROR.name());
  }

  private static AuraHandledException buildAuraException(String errorCode) {
    final AuraHandledException auraException = new AuraHandledException(errorCode);
    auraException.setMessage(errorCode);
    return auraException;
  }
}