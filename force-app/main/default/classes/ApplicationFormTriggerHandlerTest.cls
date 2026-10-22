/**
 * @description       : Test class for ApplicationFormTriggerHandler
 * @author            : Ashita Gopaul
 * @last modified on  : 12-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   23-09-2026   AGO      Initial version
 * 1.1   12-10-2026   KRA      Attach the test Funding Opportunity to a pillar
 **/
@isTest
private class ApplicationFormTriggerHandlerTest {

    @testSetup
    static void setupTestData() {
        // Create a user with Standard Profile
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User testUser = new User(
            Alias = 'axaadmin',
            Email = 'axaadmin@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'AXAAdminUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'axaadmin' + DateTime.now().getTime() + '@testorg.com'
        );
        insert testUser;

        // Fetch and assign the 'AXA Foundation Admin' Permission Set
        PermissionSet ps = [
            SELECT Id 
            FROM PermissionSet 
            WHERE Name = 'AXA_Foundation_Admin' OR Label = 'AXA Foundation Admin' 
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id, 
            PermissionSetId = ps.Id
        );

        PermissionSet psGrantmaking = [
            SELECT Id 
            FROM PermissionSet 
            WHERE Label = 'Grantmaking Manager' 
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id, 
            PermissionSetId = psGrantmaking.Id
        );
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE LastName = 'AXAAdminUser' LIMIT 1];
    }

    private static Id callForProjectsRecordTypeId() {
        return Schema.SObjectType.FundingOpportunity.getRecordTypeInfosByName().get('Call for Projects').getRecordTypeId();
    }

    private static void createPdfTemplate() {
        ContentVersion cv = new ContentVersion(
            Title = Label.ApplicationFormPdfTemplateName,
            PathOnClient = Label.ApplicationFormPdfTemplateName + '.docx',
            VersionData = Blob.valueOf('template')
        );
        insert cv;
    }

    private static Id createFundingOpportunity(Boolean isCallForProjects) {
        FundingOpportunity fo = new FundingOpportunity(
            Name      = 'Test FO',
            ProgramId = TestDataFactory.createPillar('Test Pillar').Id
        );
        if (isCallForProjects) {
            fo.RecordTypeId = callForProjectsRecordTypeId();
        }
        insert fo;
        return fo.Id;
    }

    private static Id createApplicationForm(Id fundingOpportunityId) {
        ApplicationForm appForm = new ApplicationForm(
            UsageType = 'Grantmaking',
            ProgrammeRattache__c = fundingOpportunityId,
            Stage = 'Draft'
        );
        insert appForm;
        return appForm.Id;
    }

    @isTest
    static void testStageChangeToEoiSubmittedOnAapFundingOpportunityGeneratesPdf() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();
            Id fundingOpportunityId = createFundingOpportunity(true);
            Id appFormId = createApplicationForm(fundingOpportunityId);

            Test.startTest();
            update new ApplicationForm(Id = appFormId, Stage = 'EOI Submitted');
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :appFormId], 'Expected a document generation request for the EOI PDF');
        }
    }

    @isTest
    static void testStageChangeToEoiSubmittedOnNonAapFundingOpportunitySkipsPdf() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();
            Id fundingOpportunityId = createFundingOpportunity(false);
            Id appFormId = createApplicationForm(fundingOpportunityId);

            Test.startTest();
            update new ApplicationForm(Id = appFormId, Stage = 'EOI Submitted');
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :appFormId], 'Non Call-for-Projects FundingOpportunity should not generate an EOI PDF');
        }
    }

    @isTest
    static void testStageChangeToSubmittedGeneratesApplicationPdf() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();
            Id fundingOpportunityId = createFundingOpportunity(false);
            Id appFormId = createApplicationForm(fundingOpportunityId);

            Test.startTest();
            update new ApplicationForm(Id = appFormId, Stage = 'Submitted');
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :appFormId], 'Expected a document generation request for the full application PDF');
        }
    }

    @isTest
    static void testStageChangeToUnrelatedValueSkipsPdfGeneration() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();
            Id fundingOpportunityId = createFundingOpportunity(false);
            Id appFormId = createApplicationForm(fundingOpportunityId);

            Test.startTest();
            update new ApplicationForm(Id = appFormId, Stage = 'Draft');
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :appFormId], 'An unrelated Stage value should not trigger PDF generation');
        }
    }

    @isTest
    static void testUpdateWithoutStageChangeSkipsPdfGeneration() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();
            Id fundingOpportunityId = createFundingOpportunity(false);
            Id appFormId = createApplicationForm(fundingOpportunityId);

            Test.startTest();
            update new ApplicationForm(Id = appFormId, UsageType = 'Grantmaking');
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :appFormId], 'No Stage change should mean no PDF generation attempt');
        }
    }
}