/**
 * @description       : 
 * @author            : VSP
 * @group             : 
 * @last modified on  : 05-10-2026 
 * @last modified by  : VSP
**/
@IsTest
private class RecipientSelectorController_TEST {
    @TestSetup
    static void setup() {
        Account acme = new Account(Name = 'Acme Assurances');
        Account other = new Account(Name = 'Société Bêta');
        insert new List<Account>{ acme, other };

        insert new List<Contact>{
            new Contact(FirstName = 'Jean', LastName = 'Dupont', Email = 'jean.dupont@example.com', AccountId = other.Id),
            new Contact(FirstName = 'Marie', LastName = 'Durand', Email = 'marie.durand@example.com', AccountId = other.Id),
            new Contact(FirstName = 'Luc', LastName = 'Dumas', AccountId = other.Id),
            new Contact(FirstName = 'Paul', LastName = 'Martin', AccountId = acme.Id),
            new Contact(FirstName = 'Sophie', LastName = 'Bernard', AccountId = acme.Id)
        };
    }

    @IsTest
    static void returnsContactsOfMatchingAccount() {
        List<Contact> results = RecipientSelectorController.searchContacts('Acme', 10, null);

        Assert.areEqual(2, results.size(), 'Both contacts of Acme Assurances should be returned');
        for (Contact c : results) {
            Assert.areEqual('Acme Assurances', c.Account.Name);
        }
    }

    @IsTest
    static void returnsMatchingContacts() {
        Test.startTest();
        List<Contact> results = RecipientSelectorController.searchContacts('Du', null, null);
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'Dupont, Durand and Dumas should match');
    }

    @IsTest
    static void returnsMatchingAccountsWithContactCount() {
        List<RecipientSelectorController.AccountOption> options = RecipientSelectorController.searchAccounts(
            'Acme',
            null
        );

        Assert.areEqual(1, options.size());
        Assert.areEqual('Acme Assurances', options[0].name);
        Assert.areEqual(2, options[0].contactCount);
    }

    @IsTest
    static void accountCountIgnoresExcludedContacts() {
        Contact martin = [SELECT Id FROM Contact WHERE LastName = 'Martin'];

        List<RecipientSelectorController.AccountOption> options = RecipientSelectorController.searchAccounts(
            'Acme',
            new List<Id>{ martin.Id }
        );

        Assert.areEqual(1, options[0].contactCount);
    }

    @IsTest
    static void returnsNoAccountsForShortTerm() {
        Assert.areEqual(0, RecipientSelectorController.searchAccounts('A', null).size());
    }

    @IsTest
    static void returnsAllContactsOfAccount() {
        Account acme = [SELECT Id FROM Account WHERE Name = 'Acme Assurances'];
        Contact martin = [SELECT Id FROM Contact WHERE LastName = 'Martin'];

        Assert.areEqual(2, RecipientSelectorController.getAccountContacts(acme.Id, null).size());

        List<Contact> remaining = RecipientSelectorController.getAccountContacts(acme.Id, new List<Id>{ martin.Id });
        Assert.areEqual(1, remaining.size());
        Assert.areEqual('Sophie Bernard', remaining[0].Name);

        Assert.areEqual(0, RecipientSelectorController.getAccountContacts(null, null).size());
    }

    @IsTest
    static void returnsContactsMatchingEmail() {
        List<Contact> results = RecipientSelectorController.searchContacts('marie.durand@', 10, null);

        Assert.areEqual(1, results.size());
        Assert.areEqual('marie.durand@example.com', results[0].Email);

        Assert.areEqual(
            2,
            RecipientSelectorController.searchContacts('example.com', 10, null).size(),
            'Dupont and Durand have an example.com address'
        );
    }

    @IsTest
    static void limitsResultsToMaxResults() {
        Assert.areEqual(2, RecipientSelectorController.searchContacts('Du', 2, null).size());
    }

    @IsTest
    static void usesDefaultForInvalidMaxResults() {
        Assert.areEqual(3, RecipientSelectorController.searchContacts('Du', 0, null).size());
        Assert.areEqual(3, RecipientSelectorController.searchContacts('Du', -5, null).size());
    }

    @IsTest
    static void excludesGivenIds() {
        Contact dupont = [SELECT Id FROM Contact WHERE LastName = 'Dupont'];

        List<Contact> results = RecipientSelectorController.searchContacts('Du', 10, new List<Id>{ dupont.Id });

        Assert.areEqual(2, results.size());
        for (Contact c : results) {
            Assert.areNotEqual(dupont.Id, c.Id, 'Excluded contact should not be returned');
        }
    }

    @IsTest
    static void returnsEmptyListForShortOrBlankTerm() {
        Assert.areEqual(0, RecipientSelectorController.searchContacts(null, 10, null).size());
        Assert.areEqual(0, RecipientSelectorController.searchContacts('  ', 10, null).size());
        Assert.areEqual(0, RecipientSelectorController.searchContacts('D', 10, null).size());
    }

    @IsTest
    static void returnsEmptyListWhenNoMatch() {
        Assert.areEqual(0, RecipientSelectorController.searchContacts('Inexistant', 10, null).size());
    }
}