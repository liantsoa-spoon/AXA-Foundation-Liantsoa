public with sharing class OrganizationRedirectController {
  @AuraEnabled(cacheable=true)
  public static Id getOrganizationId() {
    final User runningUser = [
      SELECT Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ];
    return runningUser.Contact?.AccountId;
  }
}