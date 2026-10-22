public without sharing class OrganizationContactsListController {
  public class ContactSummary {
    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String role;
    @AuraEnabled public String email;
    @AuraEnabled public String phone;
  }

  @AuraEnabled(cacheable=true)
  public static List<ContactSummary> getContacts() {
    final Id accountId = getRunningUsersAccountId();
    if (accountId == null) {
      return new List<ContactSummary>();
    }

    final List<ContactSummary> summaries = new List<ContactSummary>();
    for (Contact contactRecord : [
      SELECT Id, Name, Roles__c, Email, Phone
      FROM Contact
      WHERE AccountId = :accountId
      WITH SYSTEM_MODE
      ORDER BY Name ASC
    ]) {
      final ContactSummary summary = new ContactSummary();
      summary.id    = contactRecord.Id;
      summary.name  = contactRecord.Name;
      summary.role  = contactRecord.Roles__c;
      summary.email = contactRecord.Email;
      summary.phone = contactRecord.Phone;
      summaries.add(summary);
    }
    return summaries;
  }

  private static Id getRunningUsersAccountId() {
    final List<User> runningUsers = [
      SELECT Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return runningUsers.isEmpty() ? null : runningUsers[0].Contact.AccountId;
  }
}