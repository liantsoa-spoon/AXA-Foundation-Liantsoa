@IsTest
private class RecipientSelectorControllerTest {
    @TestSetup
    static void setup() {
        insert new List<Contact>{
            new Contact(FirstName = 'Jean', LastName = 'Dupont', Email = 'jean.dupont@example.com'),
            new Contact(FirstName = 'Marie', LastName = 'Durand', Email = 'marie.durand@example.com'),
            new Contact(FirstName = 'Luc', LastName = 'Dumas'),
            new Contact(FirstName = 'Paul', LastName = 'Martin')
        };
    }

    @IsTest
    static void returnsMatchingContacts() {
        Test.startTest();
        List<Contact> results = RecipientSelectorController.searchContacts('Du', null, null);
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'Dupont, Durand and Dumas should match');
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