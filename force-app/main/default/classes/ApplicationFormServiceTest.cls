@isTest
private class ApplicationFormServiceTest {

    @testSetup
    static void setupTestData() {
        // Create user with Standard Profile
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User testUser = new User(
            Alias = 'orgadmin',
            Email = 'orgadmin@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'OrgAdminUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'orgadmin' + DateTime.now().getTime() + '@testorg.com'
        );
        insert testUser;

        // Query both Permission Sets (by API Name or Label)
        List<PermissionSet> psList = [
            SELECT Id 
            FROM PermissionSet 
            WHERE Name IN ('Admin_Access', 'Grantmaking_Manager') 
               OR Label IN ('Admin Access', 'Grantmaking Manager')
        ];

        // Assign permission sets to the test user
        List<PermissionSetAssignment> psaList = new List<PermissionSetAssignment>();
        for (PermissionSet ps : psList) {
            psaList.add(new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = ps.Id
            ));
        }
        insert psaList;
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE LastName = 'OrgAdminUser' LIMIT 1];
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
        testDataFactory.createPillar('Test Pillar');

        FundingOpportunity fo = new FundingOpportunity(Name = 'Test FO');
        fo.ProgramId = [SELECT Id FROM Program WHERE Name = 'Test Pillar' LIMIT 1].Id;
        if (isCallForProjects) {
            fo.RecordTypeId = callForProjectsRecordTypeId();
        }
        insert fo;
        return fo.Id;
    }

    private static ApplicationForm buildInMemoryApplicationForm(Id id, Id fundingOpportunityId) {
        return new ApplicationForm(Id = id, ProgrammeRattache__c = fundingOpportunityId);
    }

    private static Id insertApplicationForm(Id fundingOpportunityId) {
        ApplicationForm appForm = new ApplicationForm(UsageType = 'Grantmaking', ProgrammeRattache__c = fundingOpportunityId);
        insert appForm;
        return appForm.Id;
    }

    @isTest
    static void testGenerateEoiPdfsOnlyForAapFundingOpportunities() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();
            Id aapFundingOpportunityId = createFundingOpportunity(true);
            Id nonAapFundingOpportunityId = createFundingOpportunity(false);
            Id aapAppFormId = insertApplicationForm(aapFundingOpportunityId);
            Id nonAapAppFormId = insertApplicationForm(nonAapFundingOpportunityId);

            List<ApplicationForm> forms = new List<ApplicationForm>{
                buildInMemoryApplicationForm(aapAppFormId, aapFundingOpportunityId),
                buildInMemoryApplicationForm(nonAapAppFormId, nonAapFundingOpportunityId)
            };

            Test.startTest();
            ApplicationFormService.generateEoiPdfs(forms);
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :aapAppFormId], 'Expected an EOI PDF for the Call for Projects application form');
            Assert.areEqual(0, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :nonAapAppFormId], 'Non Call-for-Projects application forms should not get an EOI PDF');
        }
    }

    @isTest
    static void testGenerateApplicationPdfsForAllFundingOpportunities() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();
            Id fundingOpportunityId = createFundingOpportunity(false);
            Id appFormId = insertApplicationForm(fundingOpportunityId);

            List<ApplicationForm> forms = new List<ApplicationForm>{
                buildInMemoryApplicationForm(appFormId, fundingOpportunityId)
            };

            Test.startTest();
            ApplicationFormService.generateApplicationPdfs(forms);
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :appFormId], 'Expected a full application PDF regardless of Funding Opportunity record type');
        }
    }

    @isTest
    static void testGenerateEoiPdfsWithNoAapFundingOpportunitiesGeneratesNothing() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();
            Id fundingOpportunityId = createFundingOpportunity(false);
            Id appFormId = insertApplicationForm(fundingOpportunityId);

            List<ApplicationForm> forms = new List<ApplicationForm>{
                buildInMemoryApplicationForm(appFormId, fundingOpportunityId)
            };

            Test.startTest();
            ApplicationFormService.generateEoiPdfs(forms);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM DocumentGenerationProcess WHERE ReferenceObject = :appFormId], 'No Call-for-Projects Funding Opportunity should mean no EOI PDFs');
        }
    }

    @isTest
    static void testGenerateApplicationPdfsThrowsWhenTemplateMissing() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Id fundingOpportunityId = createFundingOpportunity(false);
            Id appFormId = insertApplicationForm(fundingOpportunityId);

            List<ApplicationForm> forms = new List<ApplicationForm>{
                buildInMemoryApplicationForm(appFormId, fundingOpportunityId)
            };

            try {
                Test.startTest();
                ApplicationFormService.generateApplicationPdfs(forms);
                Test.stopTest();
                Assert.isTrue(false, 'Expected an AuraHandledException when the PDF template File is missing');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('No document template File found'), 'Unexpected error message: ' + e.getMessage());
            }
        }
    }

    @isTest
    static void testGenerateEoiPdfsWithEmptyListIsNoOp() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            createPdfTemplate();

            Test.startTest();
            ApplicationFormService.generateEoiPdfs(new List<ApplicationForm>());
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM DocumentGenerationProcess], 'An empty list of application forms should generate nothing');
        }
    }
}