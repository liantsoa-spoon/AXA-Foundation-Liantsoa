@isTest
private class DecisionComitePathControllerTest {

    private static Id createApplicationForm() {
        ApplicationForm appForm = new ApplicationForm(UsageType = 'Grantmaking');
        insert appForm;
        return appForm.Id;
    }

    @isTest
    static void testGetCurrentStatusReturnsFieldValue() {
        Id appFormId = createApplicationForm();
        update new ApplicationForm(Id = appFormId, Stage = 'EOI Draft');

        Test.startTest();
        String status = DecisionComitePathController.getCurrentStatus(appFormId, 'Stage');
        Test.stopTest();

        Assert.areEqual('EOI Draft', status, 'Unexpected Stage value returned');
    }

    @isTest
    static void testGetCurrentStatusReturnsNullWhenRecordNotFound() {
        Id appFormId = createApplicationForm();
        delete new ApplicationForm(Id = appFormId);

        Test.startTest();
        String status = DecisionComitePathController.getCurrentStatus(appFormId, 'Stage');
        Test.stopTest();

        Assert.areEqual(null, status, 'Expected null when the record no longer exists');
    }

    @isTest
    static void testGetCurrentStatusRejectsInvalidFieldName() {
        Id appFormId = createApplicationForm();

        try {
            DecisionComitePathController.getCurrentStatus(appFormId, 'Stage; DELETE');
            Assert.isTrue(false, 'Expected an AuraHandledException for an invalid field name');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid field name'), 'Unexpected error message: ' + e.getMessage());
        }
    }

    @isTest
    static void testGetCurrentStatusRejectsBlankFieldName() {
        try {
            DecisionComitePathController.getCurrentStatus(createApplicationForm(), '');
            Assert.isTrue(false, 'Expected an AuraHandledException for a blank field name');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid field name'), 'Unexpected error message: ' + e.getMessage());
        }
    }

    @isTest
    static void testUpdateStatusPersistsNewValue() {
        Id appFormId = createApplicationForm();

        Test.startTest();
        DecisionComitePathController.updateStatus(appFormId, 'Stage', 'Draft');
        Test.stopTest();

        ApplicationForm updated = [SELECT Stage FROM ApplicationForm WHERE Id = :appFormId];
        Assert.areEqual('Draft', updated.Stage, 'Stage should have been updated');
    }

    @isTest
    static void testUpdateStatusRejectsInvalidFieldName() {
        Id appFormId = createApplicationForm();

        try {
            DecisionComitePathController.updateStatus(appFormId, 'Stage=1;--', 'Draft');
            Assert.isTrue(false, 'Expected an AuraHandledException for an invalid field name');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid field name'), 'Unexpected error message: ' + e.getMessage());
        }
    }
}