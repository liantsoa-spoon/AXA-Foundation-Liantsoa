/**
 * @description       : 
 * @author            : VSP
 * @group             : 
 * @last modified on  : 06-10-2026 
 * @last modified by  : VSP
**/
public with sharing class RecipientSelectorController {
    private static final Integer MIN_SEARCH_LENGTH = 2;
    private static final Integer DEFAULT_MAX_RESULTS = 10;
    private static final Integer MAX_RESULTS_LIMIT = 50;
    private static final Integer MAX_ACCOUNT_RESULTS = 5;
    private static final Integer MAX_CONTACTS_PER_ACCOUNT = 200;

    @AuraEnabled(cacheable=true)
    public static List<Contact> searchContacts(String searchTerm, Integer maxResults, List<Id> excludedIds) {
        if (!isValidSearchTerm(searchTerm)) {
            return new List<Contact>();
        }
        String likeTerm = toLikeTerm(searchTerm);
        Integer rowLimit = (maxResults == null || maxResults < 1)
            ? DEFAULT_MAX_RESULTS
            : Math.min(maxResults, MAX_RESULTS_LIMIT);
        List<Id> excluded = nonNull(excludedIds);
        return [
            SELECT Id, Name, Email, AccountId, Account.Name
            FROM Contact
            WHERE (Name LIKE :likeTerm OR Email LIKE :likeTerm OR Account.Name LIKE :likeTerm)
                AND Id NOT IN :excluded
            WITH USER_MODE
            ORDER BY Name
            LIMIT :rowLimit
        ];
    }

    // Accounts whose name matches the search, with the number of contacts not yet selected
    @AuraEnabled(cacheable=true)
    public static List<AccountOption> searchAccounts(String searchTerm, List<Id> excludedIds) {
        List<AccountOption> options = new List<AccountOption>();
        if (!isValidSearchTerm(searchTerm)) {
            return options;
        }
        String likeTerm = toLikeTerm(searchTerm);
        List<Id> excluded = nonNull(excludedIds);
        for (AggregateResult result : [
            SELECT AccountId, Account.Name accountName, COUNT(Id) contactCount
            FROM Contact
            WHERE Account.Name LIKE :likeTerm AND Id NOT IN :excluded
            WITH USER_MODE
            GROUP BY AccountId, Account.Name
            ORDER BY Account.Name
            LIMIT :MAX_ACCOUNT_RESULTS
        ]) {
            options.add(
                new AccountOption(
                    (Id) result.get('AccountId'),
                    (String) result.get('accountName'),
                    (Integer) result.get('contactCount')
                )
            );
        }
        return options;
    }

    @AuraEnabled
    public static List<Contact> getAccountContacts(Id accountId, List<Id> excludedIds) {
        if (accountId == null) {
            return new List<Contact>();
        }
        List<Id> excluded = nonNull(excludedIds);
        return [
            SELECT Id, Name, Email, AccountId, Account.Name
            FROM Contact
            WHERE AccountId = :accountId AND Id NOT IN :excluded
            WITH USER_MODE
            ORDER BY Name
            LIMIT :MAX_CONTACTS_PER_ACCOUNT
        ];
    }

    private static Boolean isValidSearchTerm(String searchTerm) {
        return String.isNotBlank(searchTerm) && searchTerm.trim().length() >= MIN_SEARCH_LENGTH;
    }

    private static String toLikeTerm(String searchTerm) {
        return '%' + searchTerm.trim() + '%';
    }

    private static List<Id> nonNull(List<Id> ids) {
        return ids == null ? new List<Id>() : ids;
    }

    public class AccountOption {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer contactCount;

        public AccountOption(Id id, String name, Integer contactCount) {
            this.id = id;
            this.name = name;
            this.contactCount = contactCount;
        }
    }
}