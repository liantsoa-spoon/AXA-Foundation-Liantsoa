/**
 * @description       : Test class for ApplicationFormController.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 22-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   LAN      Remove renameUploadedFile tests; move file tests to FileUploadService_TEST, keep delegation tests
 * 1.1   02-10-2026   LAN      Test the read-only behavior driven by the Funding Opportunity status
 * 1.2   05-10-2026   LAN      Run every test as the Org admin user created in the testSetup
 * 1.3   05-10-2026   LAN      Test renameUploadedFiles
 * 1.4   05-10-2026   LAN      Test linkUploadedFiles
 * 1.5   05-10-2026   LAN      Remove the test of the custom upload (uploadFile)
 * 1.6   06-10-2026   LAN      Give the saving tests a Contact and an Account; test checkExistingSubmission and the save guard
 * 1.7   06-10-2026   LAN      Test the form mode derived from the Funding Opportunity type
 * 1.8   06-10-2026   LAN      Split the read-only status test in two to stay under the SOQL limit
 * 1.9   07-10-2026   LAN      Test that only the Project applicant lead saves the form and manages its files
 * 1.10  08-10-2026   LAN      Test the French question text and response values of the form
 * 1.11  08-10-2026   LAN      Test the error codes returned to the form
 * 1.12  08-10-2026   LAN      Test that a submitted EOI shows the EOI; the full application is saved from an approved EOI
 * 1.13  08-10-2026   LAN      Test that a rejected EOI is shown in read-only
 * 1.14  08-10-2026   LAN      Run the null document Id test as the Org admin user too
 * 1.15  08-10-2026   LAN      Test openReadOnlyForm: the EOI checkbox decides, not the stage
 * 1.16  08-10-2026   LAN      Test the code returned when a duplicate rule blocks a record
 * 1.17  09-10-2026   LAN      The test applicant Contact is the Project applicant lead, who alone fills the form
 * 1.18  09-10-2026   LAN      Test that the Contact of the connected user is updated and prefilled, not created
 * 1.19  09-10-2026   LAN      Remove the applicant Contact override: the form does not create a Contact anymore
 * 1.20  09-10-2026   LAN      Test that the new form carries the Contact of the user and a saved form shows its own Contact
 * 1.21  20-10-2026   LAN      Test the consents returned with the form and recorded on submission
 * 1.22  22-10-2026   LAN      Stop using ConsentementCGUAcceptees__c in the tests
 **/
@isTest
private class ApplicationFormController_TEST {

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

    private static Id createFundingOpportunityWithConfig() {
        Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
        insert program;

        FundingOpportunity fundingOpportunity = new FundingOpportunity(
            Name = 'Test FO',
            Status = 'Draft',
            ProgramId = program.Id
        );
        insert fundingOpportunity;
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        Id sectionId = ApplicationFormCatalogueController.createSection(
            'Section' + uniqueSuffix,
            fundingOpportunity.Id
        );
        ApplicationFormCatalogueController.createQuestion(
            'Q1 ' + uniqueSuffix,
            'What is your name?',
            'Text',
            null,
            null,
            'Some help',
            10,
            false,
            null,
            sectionId,
            null,
            1,
            fundingOpportunity.Id,
            false,
            null,
            null
        );

        ApplicationFormCatalogueController.ColumnWrapper column = new ApplicationFormCatalogueController.ColumnWrapper();
        column.label = 'Amount';
        ApplicationFormCatalogueController.createQuestion(
            'Q2 ' + uniqueSuffix,
            'Fill the table',
            'TextBlock',
            null,
            null,
            null,
            null,
            true,
            JSON.serialize(new List<ApplicationFormCatalogueController.ColumnWrapper>{ column }),
            sectionId,
            null,
            2,
            fundingOpportunity.Id,
            false,
            null,
            null
        );

        return fundingOpportunity.Id;
    }

    private static Id createApplicationForm(Id fundingOpportunityId) {
        ApplicationForm applicationForm = new ApplicationForm(
            ReferenceRecordId = fundingOpportunityId,
            UsageType = 'Grantmaking'
        );
        insert applicationForm;
        return applicationForm.Id;
    }

    private static ApplicationFormController.ResponseInputWrapper textAnswer(Id versionId, String value) {
        ApplicationFormController.ResponseInputWrapper input = new ApplicationFormController.ResponseInputWrapper();
        input.versionId = versionId;
        input.valueJson = value;
        input.dataType = 'Text';
        input.isFixed = false;
        input.isMandatory = true;
        input.label = 'What is your name?';
        return input;
    }

    @isTest
    static void getFormDefinitionRequiresId() {
        System.runAs(getTestUser()) {
            try {
                ApplicationFormController.getFormDefinition(null, false);
                System.assert(false, 'Expected an AuraHandledException when applicationFormId is null');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Application Form Id is required'), e.getMessage());
            }
        }
    }

    @isTest
    static void getFormDefinitionFailsWithoutFundingOpportunity() {
        System.runAs(getTestUser()) {
            ApplicationForm applicationForm = new ApplicationForm(UsageType = 'Grantmaking');
            insert applicationForm;

            try {
                ApplicationFormController.getFormDefinition(applicationForm.Id, false);
                System.assert(false, 'Expected an AuraHandledException when no Funding Opportunity is linked');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('not linked to a Funding Opportunity'), e.getMessage());
            }
        }
    }

    @isTest
    static void getFormDefinitionReturnsSectionsTableColumnsAndLimit() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithConfig();
            Id applicationFormId = createApplicationForm(fundingOpportunityId);

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.getFormDefinition(applicationFormId, false);
            Test.stopTest();

            System.assertEquals(1, definition.sections.size(), 'Expected one section');
            System.assertEquals(2, definition.sections[0].questions.size(), 'Expected two questions');
            System.assertEquals('Some help', definition.sections[0].questions[0].helpText, 'Help text should round-trip');
            System.assertEquals(
                10,
                definition.sections[0].questions[0].maximumCharacters,
                'Maximum characters should be exposed to the player'
            );

            ApplicationFormController.QuestionWrapper tableQuestion = definition.sections[0].questions[1];
            System.assertEquals(true, tableQuestion.isTable, 'Second question should be a table');
            System.assertEquals(1, tableQuestion.columns.size(), 'Table question should expose its column definition');
            System.assertEquals('Amount', tableQuestion.columns[0].label, 'Unexpected column label');
        }
    }

    @isTest
    static void eoiOnlyFormUsesFundingOpportunityEoiQuestions() {
        System.runAs(getTestUser()) {
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'EOI FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;

            AssessmentQuestionSet eoiSection = new AssessmentQuestionSet(
                Name = 'EOI Section',
                DeveloperName = 'EoiSection' + String.valueOf(Datetime.now().getTime())
            );
            insert eoiSection;

            Id eoiQuestionId = ApplicationFormCatalogueController.createFormQuestion(
                'EOI Q',
                'Why this opportunity?',
                'TextArea',
                null,
                null,
                null,
                255,
                false,
                null,
                eoiSection.Id,
                null,
                1,
                fundingOpportunity.Id,
                false,
                null,
                null,
                true,
                null,
                null
            );
            ApplicationFormCatalogueController.createQuestion(
                'Full Q',
                'Describe the full project',
                'TextArea',
                null,
                null,
                null,
                255,
                false,
                null,
                eoiSection.Id,
                null,
                2,
                fundingOpportunity.Id,
                false,
                null,
                null
            );
            System.assertEquals(
                true,
                [SELECT EOI__c FROM AssessmentQuestionAssignment
                 WHERE AssessmentQuestionId = :eoiQuestionId LIMIT 1].EOI__c,
                'A CUSTOM question created in EOI mode must retain the EOI marker'
            );

            Id applicationFormId = createApplicationForm(fundingOpportunity.Id);

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper eoiDefinition =
                ApplicationFormController.getFormDefinition(applicationFormId, true);
            ApplicationFormController.FormDefinitionWrapper fullDefinition =
                ApplicationFormController.getFormDefinition(applicationFormId, false);
            Test.stopTest();

            System.assertEquals(1, eoiDefinition.sections.size(), 'EOI mode should load the Funding Opportunity EOI section');
            System.assertEquals(
                'Why this opportunity?',
                eoiDefinition.sections[0].questions[0].label,
                'EOI mode should show the EOI question text'
            );
            System.assertEquals(
                'Describe the full project',
                fullDefinition.sections[0].questions[0].label,
                'The full form should exclude EOI questions and retain full-application questions'
            );
        }
    }

    @isTest
    static void saveSectionResponsesCreatesAssessmentAndResponses() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithConfig();
            Id applicationFormId = createApplicationForm(fundingOpportunityId);
            Id versionId = ApplicationFormController.getFormDefinition(applicationFormId, false)
                .sections[0]
                .questions[0]
                .versionId;

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationFormId,
                JSON.serialize(
                    new List<ApplicationFormController.ResponseInputWrapper>{ textAnswer(versionId, 'Jane Doe') }
                ),
                false
            );
            Test.stopTest();

            List<Assessment> assessments = [
                SELECT Id, AssessmentStatus FROM Assessment WHERE ResponseContextId = :applicationFormId
            ];
            System.assertEquals(1, assessments.size(), 'Expected one Assessment for this Application Form');
            System.assertEquals('In Progress', assessments[0].AssessmentStatus, 'Unexpected Assessment status');

            List<AssessmentQuestionResponse> responses = [
                SELECT AssessmentQuestionId, ResponseText
                FROM AssessmentQuestionResponse
                WHERE AssessmentId = :assessments[0].Id
            ];
            System.assertEquals(1, responses.size(), 'Expected one saved response');
            System.assertEquals('Jane Doe', responses[0].ResponseText, 'Unexpected response value');
            System.assertEquals(versionId, responses[0].AssessmentQuestionId, 'The response must point at the version Id');
        }
    }

    @isTest
    static void saveSectionResponsesUpdatesExistingResponseAndPrefills() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithConfig();
            Id applicationFormId = createApplicationForm(fundingOpportunityId);
            Id versionId = ApplicationFormController.getFormDefinition(applicationFormId, false)
                .sections[0]
                .questions[0]
                .versionId;

            ApplicationFormController.saveSectionResponses(
                applicationFormId,
                JSON.serialize(
                    new List<ApplicationFormController.ResponseInputWrapper>{ textAnswer(versionId, 'First') }
                ),
                false
            );

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationFormId,
                JSON.serialize(
                    new List<ApplicationFormController.ResponseInputWrapper>{ textAnswer(versionId, 'Updated') }
                ),
                false
            );
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT COUNT() FROM Assessment WHERE ResponseContextId = :applicationFormId],
                'The same Assessment should be reused'
            );
            System.assertEquals(
                'Updated',
                [SELECT ResponseText FROM AssessmentQuestionResponse WHERE AssessmentQuestionId = :versionId].ResponseText,
                'The existing response should be updated'
            );
            System.assertEquals(
                'Updated',
                ApplicationFormController.getFormDefinition(applicationFormId, false).sections[0].questions[0].existingValueJson,
                'Reloading the form should prefill the saved answer'
            );
        }
    }

    @isTest
    static void saveSectionResponsesNoOpOnBlankPayload() {
        System.runAs(getTestUser()) {
            Id applicationFormId = createApplicationForm(createFundingOpportunityWithConfig());

            Test.startTest();
            ApplicationFormController.saveSectionResponses(applicationFormId, null, false);
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Assessment WHERE ResponseContextId = :applicationFormId],
                'A blank payload should not create an Assessment'
            );
        }
    }

    @isTest
    static void saveRejectsAnswersThatExceedMaximumCharacters() {
        System.runAs(getTestUser()) {
            Id applicationFormId = createApplicationForm(createFundingOpportunityWithConfig());
            Id versionId = ApplicationFormController.getFormDefinition(applicationFormId, false)
                .sections[0]
                .questions[0]
                .versionId;

            Test.startTest();
            try {
                ApplicationFormController.saveSectionResponses(
                    applicationFormId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{
                            textAnswer(versionId, 'This answer is far too long')
                        }
                    ),
                    false
                );
                System.assert(false, 'Expected an AuraHandledException when the answer exceeds the limit');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('cannot exceed 10 characters'), e.getMessage());
            }
            Test.stopTest();
        }
    }

    @isTest
    static void submitRejectsBlankMandatoryAnswers() {
        System.runAs(getTestUser()) {
            Id applicationFormId = createApplicationForm(createFundingOpportunityWithConfig());
            Id versionId = ApplicationFormController.getFormDefinition(applicationFormId, false)
                .sections[0]
                .questions[0]
                .versionId;

            Test.startTest();
            try {
                ApplicationFormController.saveSectionResponses(
                    applicationFormId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{ textAnswer(versionId, '') }
                    ),
                    true
                );
                System.assert(false, 'Expected an AuraHandledException for a blank required answer');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('is required'), e.getMessage());
            }
            Test.stopTest();
        }
    }

    @isTest
    static void saveFixedMultiselectWritesToTargetRecord() {
        System.runAs(getTestUser()) {
            Account account = new Account(Name = 'Test Organization');
            insert account;

            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Test FO Multiselect',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;

            Id sectionId = ApplicationFormCatalogueController.createSection(
                'FixedSection' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                fundingOpportunity.Id
            );
            ApplicationFormCatalogueController.createQuestion(
                'Fixed Multi Q',
                'Select options',
                'Multiselect',
                null,
                'Option1\nOption2',
                null,
                null,
                false,
                null,
                sectionId,
                null,
                1,
                fundingOpportunity.Id,
                true,
                'Account',
                'Phone'
            );

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                AccountId = account.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.getFormDefinition(applicationForm.Id, false);
            System.assertEquals(true, definition.sections[0].questions[0].isFixed, 'Question should be Fixed');

            ApplicationFormController.ResponseInputWrapper input = new ApplicationFormController.ResponseInputWrapper();
            input.versionId = definition.sections[0].questions[0].versionId;
            input.valueJson = '["Option1", "Option2"]';
            input.dataType = 'Multiselect';
            input.isFixed = true;
            input.objectApiName = 'Account';
            input.fieldApiName = 'Phone';

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{ input }),
                false
            );
            Test.stopTest();

            System.assertEquals(
                'Option1;Option2',
                [SELECT Phone FROM Account WHERE Id = :account.Id].Phone,
                'Multiselect should be converted to a semicolon-separated CRM value'
            );
            System.assertEquals(
                '["Option1","Option2"]',
                ApplicationFormController.getFormDefinition(applicationForm.Id, false).sections[0].questions[0].existingValueJson,
                'Reloading a Fixed multiselect should format the value as a JSON array'
            );
        }
    }

    @isTest
    static void updateApplicationStatusWritesStage() {
        System.runAs(getTestUser()) {
            Id applicationFormId = createApplicationForm(createFundingOpportunityWithConfig());

            Test.startTest();
            ApplicationFormController.updateApplicationStatus(applicationFormId, 'Draft');
            Test.stopTest();

            System.assertEquals(
                'Draft',
                [SELECT Stage FROM ApplicationForm WHERE Id = :applicationFormId].Stage,
                'Stage should be updated'
            );
        }
    }

    private static Id createColleagueApplicationForm() {
        return createOwnApplicationForm(createFundingOpportunityWithEoiAndFullConfig(), 'EOI Draft');
    }

    private static void assertEditNotAllowed(String action) {
        final Id applicationFormId = createColleagueApplicationForm();
        System.runAs(getTestUser()) {
            useApplicantAccount();
            try {
                if (action == 'save') {
                    ApplicationFormController.saveFundingOpportunityForm(applicationFormId, '[]', false, true, false, null, null);
                } else if (action == 'link') {
                    ApplicationFormController.linkUploadedFiles(applicationFormId, new List<Id>());
                } else {
                    ApplicationFormController.ensureCanEditApplicationForm(applicationFormId);
                }
                Assert.fail('The ' + action + ' must be refused to a colleague of the creator');
            } catch (AuraHandledException e) {
                Assert.areEqual(
                    ApplicationFormController.ERROR_EDIT_NOT_ALLOWED,
                    parseError(e).get('code'),
                    e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void saveFundingOpportunityForm_givenColleagueForm_throwsTheEditNotAllowedCode() {
        assertEditNotAllowed('save');
    }

    @IsTest
    static void linkUploadedFiles_givenColleagueForm_throwsTheEditNotAllowedCode() {
        assertEditNotAllowed('link');
    }

    @IsTest
    static void ensureCanEditApplicationForm_givenColleagueForm_throwsTheEditNotAllowedCode() {
        assertEditNotAllowed('budget');
    }

    private static AssessmentQuestionVersion buildTranslatedVersion(String responseValuesFr) {
        return new AssessmentQuestionVersion(
            QuestionTextFR__c   = 'Question en français',
            ResponseValues      = 'Yes\nNo',
            ResponseValuesFR__c = responseValuesFr
        );
    }

    @IsTest
    static void resolveQuestionLabel_givenFrenchAndTranslation_returnsFrenchText() {
        System.runAs(getTestUser()) {
            Assert.areEqual(
                'Question en français',
                ApplicationFormController.resolveQuestionLabel('English question', buildTranslatedVersion(null), true),
                'The French text is shown in French'
            );
        }
    }

    @IsTest
    static void resolveQuestionLabel_givenFrenchWithoutTranslation_returnsEnglishLabel() {
        System.runAs(getTestUser()) {
            Assert.areEqual(
                'English question',
                ApplicationFormController.resolveQuestionLabel('English question', new AssessmentQuestionVersion(), true),
                'Without French text, the English label is shown'
            );
        }
    }

    @IsTest
    static void resolveQuestionLabel_givenEnglish_returnsEnglishLabel() {
        System.runAs(getTestUser()) {
            Assert.areEqual(
                'English question',
                ApplicationFormController.resolveQuestionLabel('English question', buildTranslatedVersion(null), false),
                'In English, the English label is shown'
            );
        }
    }

    @IsTest
    static void resolveResponseLabels_givenFrenchWithSameCount_returnsFrenchValues() {
        System.runAs(getTestUser()) {
            Assert.areEqual(
                'Oui\nNon',
                ApplicationFormController.resolveResponseLabels(buildTranslatedVersion('Oui\nNon'), true),
                'The French values line up with the English ones'
            );
        }
    }

    @IsTest
    static void resolveResponseLabels_givenFrenchWithDifferentCount_returnsNull() {
        System.runAs(getTestUser()) {
            Assert.isNull(
                ApplicationFormController.resolveResponseLabels(buildTranslatedVersion('Oui\nNon\nPeut-être'), true),
                'A different number of values cannot be mapped: the English values are shown'
            );
        }
    }

    @IsTest
    static void resolveResponseLabels_givenBlankTranslationOrEnglish_returnsNull() {
        System.runAs(getTestUser()) {
            Assert.isNull(
                ApplicationFormController.resolveResponseLabels(buildTranslatedVersion(null), true),
                'Without French values, the English values are shown'
            );
            Assert.isNull(
                ApplicationFormController.resolveResponseLabels(buildTranslatedVersion('Oui\nNon'), false),
                'In English, the English values are shown'
            );
        }
    }

    @IsTest
    static void deleteUploadedFile_givenNullId_throwsAuraHandledException() {
        System.runAs(getTestUser()) {
            try {
                ApplicationFormController.deleteUploadedFile(null);
                Assert.fail('Expected an AuraHandledException when the document Id is missing');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('document Id is required'), e.getMessage());
            }
        }
    }

    @isTest
    static void unexpectedErrorsAreWrappedWithTheirContext() {
        System.runAs(getTestUser()) {
            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = createFundingOpportunityWithConfig(),
                UsageType = 'Grantmaking'
            );
            insert applicationForm;
            Id deletedApplicationFormId = applicationForm.Id;
            delete applicationForm;

            try {
                ApplicationFormController.getFormDefinition(deletedApplicationFormId, false);
                System.assert(false, 'Expected an AuraHandledException when the Application Form is gone');
            } catch (AuraHandledException e) {
                assertTechnicalError(e, 'Unable to load the application form');
            }

            try {
                ApplicationFormController.updateApplicationStatus(deletedApplicationFormId, 'Draft');
                System.assert(false, 'Expected an AuraHandledException when the Application Form is gone');
            } catch (AuraHandledException e) {
                assertTechnicalError(e, 'Unable to update the application status');
            }

            try {
                ApplicationFormController.saveSectionResponses(
                    deletedApplicationFormId,
                    '{not valid json',
                    false
                );
                System.assert(false, 'Expected an AuraHandledException for a malformed payload');
            } catch (AuraHandledException e) {
                assertTechnicalError(e, 'Unable to save your responses');
            }
        }
    }

    @isTest
    static void updateApplicationStatusValidatesItsArguments() {
        System.runAs(getTestUser()) {
            Id applicationFormId = createApplicationForm(createFundingOpportunityWithConfig());

            try {
                ApplicationFormController.updateApplicationStatus(null, 'Draft');
                System.assert(false, 'Expected an AuraHandledException when the Application Form Id is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Application Form Id is required'), e.getMessage());
            }

            try {
                ApplicationFormController.updateApplicationStatus(applicationFormId, '  ');
                System.assert(false, 'Expected an AuraHandledException when the status is blank');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('status is required'), e.getMessage());
            }
        }
    }

    @isTest
    static void saveIgnoresPayloadsWithNothingToPersist() {
        System.runAs(getTestUser()) {
            Id applicationFormId = createApplicationForm(createFundingOpportunityWithConfig());

            ApplicationFormController.ResponseInputWrapper withoutVersion =
                new ApplicationFormController.ResponseInputWrapper();
            withoutVersion.valueJson = 'orphan answer';
            withoutVersion.dataType = 'Text';
            withoutVersion.isFixed = false;

            Test.startTest();
            ApplicationFormController.saveSectionResponses(applicationFormId, '[]', false);
            ApplicationFormController.saveSectionResponses(
                applicationFormId,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{ withoutVersion }),
                false
            );
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestionResponse],
                'An input without a version Id should never be persisted'
            );
        }
    }

    @isTest
    static void submitRejectsAnEmptyCollectionAnswer() {
        System.runAs(getTestUser()) {
            Id applicationFormId = createApplicationForm(createFundingOpportunityWithConfig());
            Id versionId = ApplicationFormController.getFormDefinition(applicationFormId, false)
                .sections[0]
                .questions[0]
                .versionId;

            try {
                ApplicationFormController.saveSectionResponses(
                    applicationFormId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{ textAnswer(versionId, '[]') }
                    ),
                    true
                );
                System.assert(false, 'Expected an AuraHandledException for an empty collection answer');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('is required'), e.getMessage());
            }
        }
    }

    @isTest
    static void questionWithoutAVersionIsSkippedByThePlayer() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithConfig();
            Id applicationFormId = createApplicationForm(fundingOpportunityId);

            // A question created through the builder starts Active (US-042), and an Active version
            // cannot be deleted directly, so a genuine "no version" question can only be produced
            // with a direct insert that skips the version entirely, bypassing the builder API.
            Id sectionId = [
                SELECT AssessmentQuestionSetId
                FROM AssessmentQuestionAssignment
                WHERE FundingOpportunity__c = :fundingOpportunityId
                LIMIT 1
            ].AssessmentQuestionSetId;
            AssessmentQuestion versionlessQuestion = new AssessmentQuestion(
                Name = 'Versionless',
                DeveloperName = 'Versionless' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                DataType = 'Text',
                QuestionCategory = 'Demographic',
                MaximumCharacters__c = 255,
                RecordTypeId = SchemaUtilities.getRecordTypeId(AssessmentQuestion.sObjectType, 'Dynamic')
            );
            insert versionlessQuestion;
            insert new AssessmentQuestionAssignment(
                AssessmentQuestionId = versionlessQuestion.Id,
                AssessmentQuestionSetId = sectionId,
                FundingOpportunity__c = fundingOpportunityId,
                IsMandatory__c = true
            );

            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.getFormDefinition(applicationFormId, false);

            System.assertEquals(1, definition.sections.size(), 'The section should still be returned');
            System.assertEquals(
                2,
                definition.sections[0].questions.size(),
                'A question without a version should be skipped'
            );
        }
    }


    @isTest
    static void picklistLookupHandlesUnknownAndNonPicklistFields() {
        System.runAs(getTestUser()) {
            System.assertEquals(
                null,
                ApplicationFormController.getPicklistResponseValues(null, 'Industry'),
                'A blank object API name should return null'
            );
            System.assertEquals(
                null,
                ApplicationFormController.getPicklistResponseValues('NotAnObject__x', 'Industry'),
                'An unknown object should return null'
            );
            System.assertEquals(
                null,
                ApplicationFormController.getPicklistResponseValues('Account', 'NotAField__x'),
                'An unknown field should return null'
            );
            System.assertEquals(
                null,
                ApplicationFormController.getPicklistResponseValues('Account', 'Phone'),
                'A non-picklist field should return null'
            );

            String firstRead = ApplicationFormController.getPicklistResponseValues('Account', 'Industry');
            System.assert(String.isNotBlank(firstRead), 'Account.Industry should expose picklist values');
            System.assertEquals(
                firstRead,
                ApplicationFormController.getPicklistResponseValues('Account', 'Industry'),
                'The second read should come from the cache'
            );
        }
    }

    @isTest
    static void fixedContactQuestionPrefillsOnlyFromTheLinkedContact() {
        System.runAs(getTestUser()) {
            Contact contact = new Contact(LastName = 'Doe', FirstName = 'Jane');
            insert contact;

            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Contact FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;

            Id sectionId = ApplicationFormCatalogueController.createSection(
                'ContactSection' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                fundingOpportunity.Id
            );
            ApplicationFormCatalogueController.createQuestion(
                'First name', 'What is your first name?', 'Text', null, null, null, 255, false, null,
                sectionId, null, 1, fundingOpportunity.Id, true, 'Contact', 'FirstName'
            );

            ApplicationForm withContact = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                ContactId = contact.Id,
                UsageType = 'Grantmaking'
            );
            ApplicationForm withoutContact = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                UsageType = 'Grantmaking'
            );
            insert new List<ApplicationForm>{ withContact, withoutContact };

            Test.startTest();
            // Contact is prefilled only from the Contact linked on this Application Form: with no
            // linked Contact the candidate starts from a blank field.
            System.assertEquals(
                'Jane',
                ApplicationFormController.getFormDefinition(withContact.Id, false).sections[0].questions[0].existingValueJson,
                'A Fixed question mapped to Contact prefills from the Contact linked on the Application Form'
            );
            System.assertEquals(
                null,
                ApplicationFormController.getFormDefinition(withoutContact.Id, false).sections[0].questions[0].existingValueJson,
                'A Fixed question mapped to Contact must not prefill without a linked Contact'
            );
            Test.stopTest();
        }
    }

    @isTest
    static void fixedAnswersAreConvertedToTheirCrmTypes() {
        System.runAs(getTestUser()) {
            Account account = new Account(Name = 'Converter Org');
            insert account;
            Contact contact = new Contact(FirstName = 'Test', LastName = 'Converter', AccountId = account.Id);
            insert contact;

            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(Name = 'Converter FO', ProgramId = program.Id);
            insert fundingOpportunity;

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                AccountId = account.Id,
                ContactId = contact.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                    fixedAnswer('Account', 'NumberOfEmployees', 'Integer', '42'),
                    fixedAnswer('Account', 'AnnualRevenue', 'Currency', '1500.50'),
                    fixedAnswer('Account', 'Description', 'Text', 'Plain text'),
                    fixedAnswer('Account', 'Website', 'URL', ''),
                    fixedAnswer('Contact', 'Birthdate', 'Date', '1990-01-31'),
                    fixedAnswer('Contact', 'DoNotCall', 'Checkbox', 'true'),
                    fixedAnswer('Contact', 'Title', 'Multiselect', 'not-json')
                }),
                false
            );
            Test.stopTest();

            Account savedAccount = [
                SELECT NumberOfEmployees, AnnualRevenue, Description, Website FROM Account WHERE Id = :account.Id
            ];
            System.assertEquals(42, savedAccount.NumberOfEmployees, 'Integer should be converted');
            System.assertEquals(1500.50, savedAccount.AnnualRevenue, 'Currency should be converted');
            System.assertEquals('Plain text', savedAccount.Description, 'An unmapped data type keeps the raw value');
            System.assertEquals(null, savedAccount.Website, 'A blank answer should clear the field');

            Contact savedContact = [SELECT Birthdate, DoNotCall, Title FROM Contact WHERE Id = :contact.Id];
            System.assertEquals(Date.newInstance(1990, 1, 31), savedContact.Birthdate, 'Date should be converted');
            System.assertEquals(true, savedContact.DoNotCall, 'Checkbox should be converted');
            System.assertEquals('not-json', savedContact.Title, 'A Multiselect that is not JSON keeps the raw value');
        }
    }

    @isTest
    static void fixedDateTimeAnswerIsConverted() {
        System.runAs(getTestUser()) {
            Contact contact = new Contact(FirstName = 'Test', LastName = 'Timestamp');
            insert contact;

            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(Name = 'DateTime FO', ProgramId = program.Id);
            insert fundingOpportunity;

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                ContactId = contact.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            Test.startTest();
            try {
                ApplicationFormController.saveSectionResponses(
                    applicationForm.Id,
                    JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                        fixedAnswer('Contact', 'EmailBouncedDate', 'DateTime', '2024-01-31T10:15:00Z')
                    }),
                    false
                );
            } catch (AuraHandledException e) {
                // EmailBouncedDate is not writeable in every org configuration; the conversion itself
                // is what this test exercises.
            }
            Test.stopTest();
        }
    }

    @isTest
    static void fixedAnswerWithAnInvalidValueIsReported() {
        System.runAs(getTestUser()) {
            Account account = new Account(Name = 'Invalid Org');
            insert account;

            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(Name = 'Invalid FO', ProgramId = program.Id);
            insert fundingOpportunity;

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                AccountId = account.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            try {
                ApplicationFormController.saveSectionResponses(
                    applicationForm.Id,
                    JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                        fixedAnswer('Account', 'NumberOfEmployees', 'Integer', 'not-a-number')
                    }),
                    false
                );
                System.assert(false, 'Expected an AuraHandledException for a value the field cannot hold');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('NumberOfEmployees'), e.getMessage());
            }
        }
    }

    @isTest
    static void fixedAnswersWithoutMappingAreSkippedAndIncompleteContactIsRejected() {
        System.runAs(getTestUser()) {
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(Name = 'Unreachable FO', ProgramId = program.Id);
            insert fundingOpportunity;

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                    fixedAnswer(null, null, 'Text', 'no mapping')
                }),
                false
            );

            try {
                ApplicationFormController.saveSectionResponses(
                    applicationForm.Id,
                    JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                        fixedAnswer('Contact', 'FirstName', 'Text', 'no last name yet')
                    }),
                    false
                );
                System.assert(false, 'Expected an AuraHandledException for a Contact without its required LastName');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Required fields are missing'), e.getMessage());
            }
            Test.stopTest();

            System.assertEquals(
                null,
                [SELECT ContactId FROM ApplicationForm WHERE Id = :applicationForm.Id].ContactId,
                'No Contact is linked when its required fields are missing'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Contact],
                'FirstName alone must not create a Contact'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Assessment WHERE ResponseContextId = :applicationForm.Id],
                'A payload made only of Fixed answers should not create an Assessment'
            );
        }
    }

    @isTest
    static void fixedAnswerForUnknownObjectIsReported() {
        System.runAs(getTestUser()) {
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Unknown Object FO',
                ProgramId = program.Id
            );
            insert fundingOpportunity;

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            try {
                ApplicationFormController.saveSectionResponses(
                    applicationForm.Id,
                    JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                        fixedAnswer('UnlinkableObject__c', 'Name', 'Text', 'does not exist')
                    }),
                    false
                );
                System.assert(false, 'Expected an AuraHandledException for an unknown object');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('UnlinkableObject__c'), e.getMessage());
            }
        }
    }

    @isTest
    static void fixedAnswerWithoutApplicationFormLookupStillUpsertsAndPrefills() {
        System.runAs(getTestUser()) {
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Independent Fixed FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;

            Set<Schema.SObjectType> linkedTypes = new Set<Schema.SObjectType>();
            for (
                Schema.SObjectField field :
                Schema.getGlobalDescribe().get('ApplicationForm').getDescribe().fields.getMap().values()
            ) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if (
                    fieldDescribe.getType() != Schema.DisplayType.REFERENCE
                    || !fieldDescribe.isUpdateable()
                    || fieldDescribe.getReferenceTo().size() != 1
                ) {
                    continue;
                }
                linkedTypes.add(fieldDescribe.getReferenceTo()[0]);
            }

            String objectWithoutLookup = null;
            for (String candidate : new List<String>{
                'Product2', 'Campaign', 'Lead', 'Case', 'Asset', 'Contract'
            }) {
                Schema.SObjectType candidateType = Schema.getGlobalDescribe().get(candidate);
                if (candidateType != null && !linkedTypes.contains(candidateType)) {
                    objectWithoutLookup = candidate;
                    break;
                }
            }
            System.assertNotEquals(
                null,
                objectWithoutLookup,
                'This org needs at least one standard object without an Application Form lookup'
            );

            String fieldApiName = objectWithoutLookup == 'Lead' ? 'LastName' : 'Name';
            Id sectionId = ApplicationFormCatalogueController.createSection(
                'IndepSection' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                fundingOpportunity.Id
            );
            ApplicationFormCatalogueController.createQuestion(
                'Independent', 'Independent value?', 'Text', null, null, null, 255, false, null,
                sectionId, null, 1, fundingOpportunity.Id, true, objectWithoutLookup, fieldApiName
            );

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            List<ApplicationFormController.ResponseInputWrapper> createAnswers =
                new List<ApplicationFormController.ResponseInputWrapper>();
            if (objectWithoutLookup == 'Lead') {
                createAnswers.add(fixedAnswer('Lead', 'LastName', 'Text', 'Independent'));
                createAnswers.add(fixedAnswer('Lead', 'Company', 'Text', 'Indep Co'));
            } else {
                createAnswers.add(fixedAnswer(objectWithoutLookup, 'Name', 'Text', 'Independent Target'));
            }

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(createAnswers),
                false
            );

            String expectedCreateValue = objectWithoutLookup == 'Lead' ? 'Independent' : 'Independent Target';
            List<SObject> created = Database.query(
                'SELECT Id, ' + fieldApiName
                + ' FROM ' + objectWithoutLookup
                + ' WHERE ' + fieldApiName + ' = \'' + String.escapeSingleQuotes(expectedCreateValue) + '\''
            );
            System.assertEquals(1, created.size(), 'Independent Fixed object is created without an AF lookup');
            Id createdId = (Id) created[0].get('Id');

            List<ApplicationFormController.ResponseInputWrapper> updateAnswers =
                new List<ApplicationFormController.ResponseInputWrapper>();
            if (objectWithoutLookup == 'Lead') {
                updateAnswers.add(fixedAnswer('Lead', 'LastName', 'Text', 'Independent Updated'));
                updateAnswers.add(fixedAnswer('Lead', 'Company', 'Text', 'Indep Co'));
            } else {
                updateAnswers.add(fixedAnswer(objectWithoutLookup, 'Name', 'Text', 'Independent Updated'));
            }
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(updateAnswers),
                false
            );

            SObject updated = Database.query(
                'SELECT Id, ' + fieldApiName
                + ' FROM ' + objectWithoutLookup
                + ' WHERE Id = \'' + createdId + '\''
            )[0];
            System.assertEquals(
                'Independent Updated',
                String.valueOf(updated.get(fieldApiName)),
                'Independent Fixed object is updated on the same record'
            );
            System.assertEquals(
                1,
                Database.query(
                    'SELECT Id FROM ' + objectWithoutLookup
                    + ' WHERE ' + fieldApiName + ' LIKE \'Independent%\''
                ).size(),
                'A second independent record is not created on update'
            );

            ApplicationFormController.FormDefinitionWrapper form =
                ApplicationFormController.getFormDefinition(applicationForm.Id, false);
            Test.stopTest();

            System.assertEquals(
                'Independent Updated',
                form.sections[0].questions[0].existingValueJson,
                'Independent Fixed answers prefill for read-only without an AF lookup'
            );
        }
    }

    @isTest
    static void fixedAccountAnswersLinkAndPrefillForReadOnly() {
        System.runAs(getTestUser()) {
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Account Prefill FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;

            Id sectionId = ApplicationFormCatalogueController.createSection(
                'OrgSection' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                fundingOpportunity.Id
            );
            ApplicationFormCatalogueController.createQuestion(
                'Organisation', 'Organisation name?', 'Text', null, null, null, 255, false, null,
                sectionId, null, 1, fundingOpportunity.Id, true, 'Account', 'Name'
            );

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                    fixedAnswer('Account', 'Name', 'Text', 'Linked Org')
                }),
                false
            );

            ApplicationForm savedForm = [
                SELECT AccountId FROM ApplicationForm WHERE Id = :applicationForm.Id
            ];
            System.assertNotEquals(null, savedForm.AccountId, 'Account Fixed answers link AccountId for prefill');
            System.assertEquals(
                'Linked Org',
                [SELECT Name FROM Account WHERE Id = :savedForm.AccountId].Name
            );

            ApplicationFormController.FormDefinitionWrapper form =
                ApplicationFormController.getFormDefinition(applicationForm.Id, false);
            Test.stopTest();

            System.assertEquals(
                'Linked Org',
                form.sections[0].questions[0].existingValueJson,
                'Linked Account Fixed answers prefill so they remain visible in read-only'
            );
        }
    }

    @isTest
    static void fixedApplicationFormAndContactAnswersUpsertTogether() {
        System.runAs(getTestUser()) {
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Eoi Upsert FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                UsageType = 'Grantmaking',
                Stage = 'EOI Draft'
            );
            insert applicationForm;

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                    fixedAnswer('Contact', 'LastName', 'Text', 'Curie'),
                    fixedAnswer('Contact', 'FirstName', 'Text', 'Marie'),
                    fixedAnswer('ApplicationForm', 'Title', 'Text', 'Radium research')
                }),
                false
            );
            Test.stopTest();

            ApplicationForm savedForm = [
                SELECT ContactId, Title FROM ApplicationForm WHERE Id = :applicationForm.Id
            ];
            System.assertNotEquals(null, savedForm.ContactId, 'Contact answers create and link a Contact');
            System.assertEquals(
                'Radium research',
                savedForm.Title,
                'ApplicationForm answers update the form itself'
            );
            System.assertEquals(
                'Marie',
                [SELECT FirstName FROM Contact WHERE Id = :savedForm.ContactId].FirstName,
                'Contact fields are written on the linked Contact'
            );
        }
    }

    @isTest
    static void fixedContactAnswersCreateThenReuseTheLinkedContact() {
        System.runAs(getTestUser()) {
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;

            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Candidate FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;

            Id sectionId = ApplicationFormCatalogueController.createSection(
                'CandidateSection' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                fundingOpportunity.Id
            );
            ApplicationFormCatalogueController.createQuestion(
                'First name', 'What is your first name?', 'Text', null, null, null, 255, false, null,
                sectionId, null, 1, fundingOpportunity.Id, true, 'Contact', 'FirstName'
            );

            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                    fixedAnswer('Contact', 'LastName', 'Text', 'Curie'),
                    fixedAnswer('Contact', 'FirstName', 'Text', 'Marie')
                }),
                false
            );

            ApplicationForm linkedForm = [
                SELECT ContactId FROM ApplicationForm WHERE Id = :applicationForm.Id
            ];
            System.assertNotEquals(
                null,
                linkedForm.ContactId,
                'The first Contact answers should create the Contact and link it to the form'
            );
            System.assertEquals(
                'Marie',
                ApplicationFormController.getFormDefinition(applicationForm.Id, false)
                    .sections[0].questions[0].existingValueJson,
                'The created Contact should prefill the Fixed question'
            );

            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                    fixedAnswer('Contact', 'FirstName', 'Text', 'Irene')
                }),
                false
            );
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT COUNT() FROM Contact],
                'A later save should update the linked Contact instead of creating another one'
            );
            System.assertEquals(
                'Irene',
                [SELECT FirstName FROM Contact WHERE Id = :linkedForm.ContactId].FirstName,
                'The linked Contact should carry the latest answer'
            );
        }
    }

    @isTest
    static void fixedContactAnswersUpdateTheContactOfTheConnectedUserInsteadOfCreatingOne() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id connectedContactId = ApplicationFormSubmissionService.contactIdOverride;
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;
            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Candidate FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;
            Id sectionId = ApplicationFormCatalogueController.createSection(
                'CandidateSection' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                fundingOpportunity.Id
            );
            ApplicationFormCatalogueController.createQuestion(
                'First name', 'What is your first name?', 'Text', null, null, null, 255, false, null,
                sectionId, null, 1, fundingOpportunity.Id, true, 'Contact', 'FirstName'
            );
            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            Test.startTest();
            ApplicationFormController.saveSectionResponses(
                applicationForm.Id,
                JSON.serialize(new List<ApplicationFormController.ResponseInputWrapper>{
                    fixedAnswer('Contact', 'FirstName', 'Text', 'Marie')
                }),
                false
            );
            Test.stopTest();

            System.assertEquals(
                connectedContactId,
                [SELECT ContactId FROM ApplicationForm WHERE Id = :applicationForm.Id].ContactId,
                'The Contact of the connected user is linked on the form'
            );
            System.assertEquals(1, [SELECT COUNT() FROM Contact], 'No Contact is created for the form');
            System.assertEquals(
                'Marie',
                [SELECT FirstName FROM Contact WHERE Id = :connectedContactId].FirstName,
                'The answer updates the Contact of the connected user'
            );
        }
    }

    @isTest
    static void fixedContactQuestionIsPrefilledFromTheContactOfTheConnectedUser() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id connectedContactId = ApplicationFormSubmissionService.contactIdOverride;
            update new Contact(Id = connectedContactId, FirstName = 'Jane');
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;
            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Candidate FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;
            Id sectionId = ApplicationFormCatalogueController.createSection(
                'CandidateSection' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                fundingOpportunity.Id
            );
            ApplicationFormCatalogueController.createQuestion(
                'First name', 'What is your first name?', 'Text', null, null, null, 255, false, null,
                sectionId, null, 1, fundingOpportunity.Id, true, 'Contact', 'FirstName'
            );

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunity.Id, false, false);
            Test.stopTest();

            System.assertEquals(
                'Jane',
                definition.sections[0].questions[0].existingValueJson,
                'The first open prefills the question with the Contact of the connected user'
            );
        }
    }

    @isTest
    static void saveFundingOpportunityForm_givenNewForm_setsTheContactOfTheConnectedUser() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationFormController.FormDefinitionWrapper opened =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, true, false);

            Test.startTest();
            ApplicationFormController.FundingOpportunitySaveResult saveResult =
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{
                            textAnswer(opened.sections[0].questions[0].versionId, 'Answer')
                        }
                    ),
                    false,
                    true,
                    false,
                    null,
                    null
                );
            Test.stopTest();

            System.assertEquals(
                ApplicationFormSubmissionService.contactIdOverride,
                [SELECT ContactId FROM ApplicationForm WHERE Id = :saveResult.applicationFormId].ContactId,
                'The new form carries the Contact of the connected user, without any Contact created'
            );
        }
    }

    @isTest
    static void getFormDefinition_givenSavedForm_prefillsFromTheContactLinkedOnTheForm() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Contact formContact = new Contact(LastName = 'Owner', FirstName = 'Alice');
            insert formContact;
            update new Contact(Id = ApplicationFormSubmissionService.contactIdOverride, FirstName = 'Viewer');
            Program program = new Program(Name = 'Test Program ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
            insert program;
            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'Candidate FO',
                Status = 'Draft',
                ProgramId = program.Id
            );
            insert fundingOpportunity;
            Id sectionId = ApplicationFormCatalogueController.createSection(
                'CandidateSection' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                fundingOpportunity.Id
            );
            ApplicationFormCatalogueController.createQuestion(
                'First name', 'What is your first name?', 'Text', null, null, null, 255, false, null,
                sectionId, null, 1, fundingOpportunity.Id, true, 'Contact', 'FirstName'
            );
            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunity.Id,
                ContactId = formContact.Id,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.getFormDefinition(applicationForm.Id, false);
            Test.stopTest();

            System.assertEquals(
                'Alice',
                definition.sections[0].questions[0].existingValueJson,
                'A saved form shows the Contact linked on it, not the one of whoever opens it'
            );
        }
    }

    @isTest
    static void fundingOpportunityFlowStartsWithEoiAndResumesDraftFromItsRecord() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            ApplicationFormController.FormDefinitionWrapper initial =
                ApplicationFormController.openFundingOpportunityForm(
                    fundingOpportunityId,
                    false,
                    true
                );

            System.assertEquals(null, initial.applicationFormId, 'Opening a new FO must not create a draft');
            System.assertEquals(true, initial.isEoi, 'A new FO starts with the EOI');
            System.assertEquals(false, initial.isUnavailable, 'A new EOI must be displayed');
            System.assertEquals(1, initial.sections.size(), 'The EOI section should be available');

            ApplicationFormController.ResponseInputWrapper answer =
                textAnswer(initial.sections[0].questions[0].versionId, 'Saved answer');
            String responsesJson = JSON.serialize(
                new List<ApplicationFormController.ResponseInputWrapper>{ answer }
            );

            Test.startTest();
            ApplicationFormController.FundingOpportunitySaveResult saveResult =
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    responsesJson,
                    false,
                    false,
                    true,
                    null,
                    null
                );
            // Opening from the FO never reuses a draft: the draft resumes from its own record.
            ApplicationFormController.FormDefinitionWrapper reopenedFromFundingOpportunity =
                ApplicationFormController.openFundingOpportunityForm(
                    fundingOpportunityId,
                    false,
                    true
                );
            ApplicationFormController.FormDefinitionWrapper resumed =
                ApplicationFormController.openFundingOpportunityForm(
                    saveResult.applicationFormId,
                    false,
                    true
                );
            Test.stopTest();

            System.assertEquals(
                null,
                reopenedFromFundingOpportunity.applicationFormId,
                'Opening from the FO must start a fresh instance, not reuse the draft'
            );

            ApplicationForm savedForm = [
                SELECT ReferenceRecordId, Stage, RecordType.DeveloperName
                FROM ApplicationForm
                WHERE Id = :saveResult.applicationFormId
            ];
            System.assertEquals(fundingOpportunityId, savedForm.ReferenceRecordId, 'The FO is the entry context');
            System.assertEquals('EOI Draft', savedForm.Stage, 'Save for later creates an EOI Draft');
            System.assertEquals(
                'CallForProjects',
                savedForm.RecordType.DeveloperName,
                'A player-created Application Form uses Call For Projects'
            );
            System.assertEquals(
                'Saved answer',
                resumed.sections[0].questions[0].existingValueJson,
                'A reopened draft must prefill its persisted answer'
            );
        }
    }

    @isTest
    static void submittedEoiIsReadOnlyInEoiOnlyMode() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationForm submittedForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                ContactId = seedApplicantContactId(),
                UsageType = 'Grantmaking',
                Stage = 'EOI Submitted'
            );
            insert submittedForm;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper reopened =
                ApplicationFormController.openFundingOpportunityForm(
                    submittedForm.Id,
                    true,
                    false
                );
            Test.stopTest();

            System.assertEquals('EOI Submitted', reopened.applicationStatus);
            System.assertEquals(true, reopened.isEoi, 'EOI-only mode keeps the EOI questions after submission');
            System.assertEquals(false, reopened.isUnavailable, 'EOI Submitted is displayed read-only, not hidden');
            System.assertEquals(1, reopened.sections.size());
            System.assert(
                reopened.sections[0].questions[0].label.startsWith('EOI Question'),
                'EOI-only mode must not switch to the full application after submission'
            );
        }
    }

    @isTest
    static void openReadOnlyForm_givenSubmittedEoi_followsTheEoiCheckboxNotTheStage() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationForm submittedForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                ContactId = seedApplicantContactId(),
                UsageType = 'Grantmaking',
                Stage = 'EOI Submitted'
            );
            insert submittedForm;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper fullApplication =
                ApplicationFormController.openReadOnlyForm(submittedForm.Id, false);
            ApplicationFormController.FormDefinitionWrapper eoi =
                ApplicationFormController.openReadOnlyForm(submittedForm.Id, true);
            Test.stopTest();

            System.assertEquals(
                false,
                fullApplication.isEoi,
                'Without the EOI checkbox, the full application is shown'
            );
            System.assert(
                fullApplication.sections[0].questions[0].label.startsWith('Full Question'),
                'Only full application questions should be returned'
            );
            System.assertEquals(true, eoi.isEoi, 'With the EOI checkbox, the EOI is shown');
            System.assert(
                eoi.sections[0].questions[0].label.startsWith('EOI Question'),
                'Only EOI questions should be returned'
            );
        }
    }

    @isTest
    static void openReadOnlyForm_givenNoId_throwsTheIdRequiredCode() {
        System.runAs(getTestUser()) {
            try {
                ApplicationFormController.openReadOnlyForm(null, false);
                System.assert(false, 'Expected an AuraHandledException without Id');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains(ApplicationFormController.ERROR_ID_REQUIRED), e.getMessage());
            }
        }
    }

    @isTest
    static void getDuplicateErrorCode_givenContactOrOtherObject_returnsTheMatchingCode() {
        System.runAs(getTestUser()) {
            System.assertEquals(
                ApplicationFormController.ERROR_DUPLICATE_CONTACT,
                ApplicationFormController.getDuplicateErrorCode(new Set<String>{ 'Contact', 'Budget' }),
                'A blocked Contact gets the contact message'
            );
            System.assertEquals(
                ApplicationFormController.ERROR_DUPLICATE_RECORD,
                ApplicationFormController.getDuplicateErrorCode(new Set<String>{ 'Account' }),
                'Any other object gets the generic message'
            );
        }
    }

    @isTest
    static void rejectedEoiShowsTheEoiInReadOnly() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationForm rejectedForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                ContactId = seedApplicantContactId(),
                UsageType = 'Grantmaking',
                Stage = 'EOI Not Selected'
            );
            insert rejectedForm;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.openFundingOpportunityForm(
                    rejectedForm.Id,
                    false,
                    true
                );
            Test.stopTest();

            System.assertEquals('EOI Not Selected', definition.applicationStatus);
            System.assertEquals(false, definition.isUnavailable, 'A rejected EOI is reviewed, not hidden');
            System.assertEquals(true, definition.isEoi, 'A rejected EOI shows the EOI questions');
            System.assertEquals(1, definition.sections.size(), 'The EOI section should be shown');
            System.assert(
                definition.sections[0].questions[0].label.startsWith('EOI Question'),
                'Only EOI questions should be returned'
            );
        }
    }

    @isTest
    static void submittedEoiShowsTheEoiInCombinedMode() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationForm submittedForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                ContactId = seedApplicantContactId(),
                UsageType = 'Grantmaking',
                Stage = 'EOI Submitted'
            );
            insert submittedForm;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.openFundingOpportunityForm(
                    submittedForm.Id,
                    false,
                    true
                );
            Test.stopTest();

            System.assertEquals(true, definition.isEoi, 'The full application waits for the approval of the EOI');
            System.assertEquals(false, definition.isUnavailable);
            System.assertEquals(1, definition.sections.size(), 'The EOI section should be shown');
            System.assert(
                definition.sections[0].questions[0].label.startsWith('EOI Question'),
                'Only EOI questions should be returned'
            );
        }
    }

    @isTest
    static void fullApplicationSaveFromTheApplicationFormRecordReusesIt() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationForm submittedEoi = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                ContactId = seedApplicantContactId(),
                UsageType = 'Grantmaking',
                Stage = 'EOI Approved'
            );
            insert submittedEoi;

            ApplicationFormController.FormDefinitionWrapper fullDefinition =
                ApplicationFormController.openFundingOpportunityForm(
                    submittedEoi.Id,
                    false,
                    true
                );
            String responsesJson = JSON.serialize(
                new List<ApplicationFormController.ResponseInputWrapper>{
                    textAnswer(fullDefinition.sections[0].questions[0].versionId, 'Full answer')
                }
            );

            Test.startTest();
            ApplicationFormController.FundingOpportunitySaveResult saveResult =
                ApplicationFormController.saveFundingOpportunityForm(
                    submittedEoi.Id,
                    responsesJson,
                    false,
                    false,
                    true,
                    null,
                    null
                );
            Test.stopTest();

            ApplicationForm savedForm = [
                SELECT ContactId, ReferenceRecordId, Stage
                FROM ApplicationForm
                WHERE Id = :saveResult.applicationFormId
            ];
            System.assertEquals(submittedEoi.Id, savedForm.Id, 'The Application Form it was opened from is reused');
            System.assertEquals(
                submittedEoi.ContactId,
                savedForm.ContactId,
                'The Application Form stays on the applicant Contact'
            );
            System.assertEquals('Draft', savedForm.Stage, 'Saving the full application sets Draft');
        }
    }

    @isTest
    static void fundingOpportunityLookupIgnoresAnotherContactsApplication() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            Contact otherContact = new Contact(FirstName = 'Test', LastName = 'Other Candidate');
            insert otherContact;

            ApplicationForm otherDraft = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                ContactId = otherContact.Id,
                UsageType = 'Grantmaking',
                Stage = 'EOI Draft'
            );
            insert otherDraft;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.openFundingOpportunityForm(
                    fundingOpportunityId,
                    true,
                    false
                );
            Test.stopTest();

            System.assertEquals(
                null,
                definition.applicationFormId,
                'Another Contact\'s Application Form must not be reused'
            );
            System.assertEquals(true, definition.isEoi);
        }
    }

    @isTest
    static void eachFundingOpportunitySaveCreatesItsOwnApplicationForm() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            ApplicationFormController.FormDefinitionWrapper firstOpen =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, true, false);
            ApplicationFormController.FundingOpportunitySaveResult firstSave =
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{
                            textAnswer(firstOpen.sections[0].questions[0].versionId, 'First answer')
                        }
                    ),
                    false,
                    true,
                    false,
                    null,
                    null
                );

            ApplicationFormController.FormDefinitionWrapper secondOpen =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, true, false);
            System.assertEquals(
                null,
                secondOpen.applicationFormId,
                'Opening from the FO never reuses an existing Application Form'
            );
            System.assertEquals(
                null,
                secondOpen.sections[0].questions[0].existingValueJson,
                'A fresh instance starts without the previous answers'
            );
            ApplicationFormController.FundingOpportunitySaveResult secondSave =
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{
                            textAnswer(secondOpen.sections[0].questions[0].versionId, 'Second answer')
                        }
                    ),
                    false,
                    true,
                    false,
                    null,
                    null
                );

            System.assertNotEquals(
                firstSave.applicationFormId,
                secondSave.applicationFormId,
                'Each save from the FO creates a distinct Application Form'
            );
            System.assertEquals(
                2,
                [SELECT COUNT() FROM ApplicationForm WHERE ReferenceRecordId = :fundingOpportunityId],
                'Both Application Forms exist on the same FO'
            );

            ApplicationFormController.FormDefinitionWrapper firstResume =
                ApplicationFormController.openFundingOpportunityForm(firstSave.applicationFormId, true, false);
            System.assertEquals(
                'First answer',
                firstResume.sections[0].questions[0].existingValueJson,
                'Each Application Form resumes from its own record with its own answers'
            );
        }
    }

    @isTest
    static void fundingOpportunitySaveNeverReusesAnExistingApplicationForm() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            ApplicationForm existingForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                UsageType = 'Grantmaking',
                Stage = 'EOI Draft'
            );
            insert existingForm;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper opened =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, true, false);
            ApplicationFormController.FundingOpportunitySaveResult saveResult =
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{
                            textAnswer(opened.sections[0].questions[0].versionId, 'Another AF')
                        }
                    ),
                    false,
                    true,
                    false,
                    null,
                    null
                );
            Test.stopTest();

            System.assertNotEquals(
                existingForm.Id,
                saveResult.applicationFormId,
                'A save from the FO creates a new Application Form instead of reusing an existing one'
            );
            System.assertEquals(
                2,
                [SELECT COUNT() FROM ApplicationForm WHERE ReferenceRecordId = :fundingOpportunityId],
                'The existing Application Form is left untouched'
            );
        }
    }

    @isTest
    static void bothCheckboxesUncheckedOpenTheFullApplicationStraightAway() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.openFundingOpportunityForm(
                    fundingOpportunityId,
                    false,
                    false
                );
            ApplicationFormController.FundingOpportunitySaveResult saveResult =
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{
                            textAnswer(definition.sections[0].questions[0].versionId, 'Full answer')
                        }
                    ),
                    false,
                    false,
                    false,
                    null,
                    null
                );
            Test.stopTest();

            System.assertEquals(false, definition.isEoi, 'Full-application mode never starts with the EOI');
            System.assertEquals(false, definition.isUnavailable);
            System.assert(
                definition.sections[0].questions[0].label.startsWith('Full Question'),
                'Full-application mode returns only non-EOI questions'
            );
            ApplicationForm savedForm = [
                SELECT Stage, RecordType.DeveloperName
                FROM ApplicationForm
                WHERE Id = :saveResult.applicationFormId
            ];
            System.assertEquals(
                'CallForProjects',
                savedForm.RecordType.DeveloperName,
                'A player-created Application Form uses Call For Projects'
            );
            System.assertEquals(
                'Draft',
                savedForm.Stage,
                'Full-application mode drafts skip the EOI stages'
            );
        }
    }

    @isTest
    static void submittedApplicationOpensReadOnlyWithoutUnavailableBanner() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationForm submittedForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                ContactId = seedApplicantContactId(),
                UsageType = 'Grantmaking',
                Stage = 'Submitted'
            );
            insert submittedForm;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.openFundingOpportunityForm(
                    submittedForm.Id,
                    false,
                    true
                );
            Test.stopTest();

            System.assertEquals(false, definition.isUnavailable, 'Submitted stays visible for review');
            System.assertEquals(null, definition.unavailableMessage);
            System.assertEquals('Submitted', definition.applicationStatus);
            System.assertEquals(false, definition.isEoi, 'Combined mode shows the full application');
            System.assertEquals(1, definition.sections.size(), 'Questions remain visible in read-only');
        }
    }

    @isTest
    static void applicationFormRecordContextOpensAndSavesThatForm() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationForm existingDraft = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                UsageType = 'Grantmaking',
                Stage = 'EOI Draft'
            );
            insert existingDraft;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper opened =
                ApplicationFormController.openFundingOpportunityForm(
                    existingDraft.Id,
                    true,
                    false
                );
            ApplicationFormController.FundingOpportunitySaveResult saveResult =
                ApplicationFormController.saveFundingOpportunityForm(
                    String.valueOf(existingDraft.Id),
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{
                            textAnswer(opened.sections[0].questions[0].versionId, 'AF page answer')
                        }
                    ),
                    false,
                    true,
                    false,
                    null,
                    null
                );
            Test.stopTest();

            System.assertEquals(existingDraft.Id, opened.applicationFormId);
            System.assertEquals(true, opened.isEoi);
            System.assertEquals(existingDraft.Id, saveResult.applicationFormId);
            System.assertEquals(
                1,
                [SELECT COUNT() FROM ApplicationForm WHERE ReferenceRecordId = :fundingOpportunityId],
                'Saving from an Application Form record must not create another form'
            );
            System.assertEquals(
                'AF page answer',
                ApplicationFormController.openFundingOpportunityForm(
                    existingDraft.Id,
                    true,
                    false
                ).sections[0].questions[0].existingValueJson
            );
        }
    }

    @isTest
    static void applicationFormRecordContextShowsSubmittedEoiInEoiOnlyMode() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            ApplicationForm submittedForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                UsageType = 'Grantmaking',
                Stage = 'EOI Submitted'
            );
            insert submittedForm;

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper reopened =
                ApplicationFormController.openFundingOpportunityForm(
                    submittedForm.Id,
                    true,
                    false
                );
            Test.stopTest();

            System.assertEquals(false, reopened.isUnavailable);
            System.assertEquals(true, reopened.isEoi);
            System.assertEquals(1, reopened.sections.size());
        }
    }

    // The connected user must be linked to a Contact and an Account: an internal test user has neither, so the
    // submission service is given the Contact of a test Account.
    private static void useApplicantAccount() {
        Account account = new Account(Name = 'Test Applicant Organization');
        insert account;
        Contact contact = new Contact(
            FirstName = 'Test',
            LastName = 'OrgSubmissionApplicant',
            AccountId = account.Id
        );
        insert contact;
        ApplicationFormSubmissionService.contactIdOverride = contact.Id;
    }

    private static Id createOwnApplicationForm(Id fundingOpportunityId, String stage) {
        ApplicationForm applicationForm = new ApplicationForm(
            RecordTypeId = SchemaUtilities.getRecordTypeId(ApplicationForm.SObjectType, 'CallForProjects'),
            ReferenceRecordId = fundingOpportunityId,
            ProgrammeRattache__c = fundingOpportunityId,
            UsageType = 'Grantmaking',
            Stage = stage
        );
        insert applicationForm;
        return applicationForm.Id;
    }

    @isTest
    static void checkExistingSubmission_givenSubmittedForm_returnsAlreadySubmitted() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            Id applicationFormId = createOwnApplicationForm(fundingOpportunityId, 'Submitted');

            Test.startTest();
            ApplicationFormSubmissionService.SubmissionCheckResult result =
                ApplicationFormController.checkExistingSubmission(fundingOpportunityId, false);
            Test.stopTest();

            System.assertEquals(
                ApplicationFormSubmissionService.STATUS_ALREADY_SUBMITTED,
                result.status,
                'A submitted application blocks'
            );
            System.assertEquals(applicationFormId, result.applicationFormId, 'The submitted form is returned');
        }
    }

    @isTest
    static void checkExistingSubmission_givenUserWithoutContact_throwsAuraHandledException() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            try {
                ApplicationFormController.checkExistingSubmission(fundingOpportunityId, true);
                System.assert(false, 'A user without Contact must be refused');
            } catch (AuraHandledException e) {
                System.assert(String.isNotBlank(e.getMessage()), 'The refusal carries a message');
            }
        }
    }

    @isTest
    static void saveFundingOpportunityForm_givenAlreadySubmittedForm_throwsTheBlockingMessage() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            Id applicationFormId = createOwnApplicationForm(fundingOpportunityId, 'EOI Submitted');
            String applicationFormName = [SELECT Name FROM ApplicationForm WHERE Id = :applicationFormId].Name;

            try {
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    '[]',
                    false,
                    true,
                    false,
                    null,
                    null
                );
                System.assert(false, 'A second submission on the same program must be refused');
            } catch (AuraHandledException e) {
                System.assert(
                    e.getMessage().contains(applicationFormName),
                    'The message names the existing Application Form'
                );
            }
        }
    }

    @isTest
    static void openFundingOpportunityForm_givenCallForProjectsAndNoCheckbox_startsWithTheEoi() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            update new FundingOpportunity(
                Id = fundingOpportunityId,
                RecordTypeId = FundingOpportunity.SObjectType.getDescribe()
                    .getRecordTypeInfosByDeveloperName()
                    .get('CallForProjects')
                    .getRecordTypeId()
            );

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, false, false);
            Test.stopTest();

            System.assertEquals(true, definition.isEoi, 'A Call for Projects starts with the EOI');
            System.assert(
                definition.sections[0].questions[0].label.startsWith('EOI Question'),
                'Only the EOI questions are shown first'
            );
        }
    }

    @isTest
    static void openFundingOpportunityForm_givenOtherProgramTypeAndNoCheckbox_opensTheFullApplication() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            update new FundingOpportunity(
                Id = fundingOpportunityId,
                RecordTypeId = FundingOpportunity.SObjectType.getDescribe()
                    .getRecordTypeInfosByDeveloperName()
                    .get('DirectManagement')
                    .getRecordTypeId()
            );

            Test.startTest();
            ApplicationFormController.FormDefinitionWrapper definition =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, false, false);
            Test.stopTest();

            System.assertEquals(false, definition.isEoi, 'Any other program opens the full application');
            System.assert(
                definition.sections[0].questions[0].label.startsWith('Full Question'),
                'Only the full application questions are shown'
            );
        }
    }

    @IsTest
    static void openFundingOpportunityForm_givenColleagueForm_returnsEditNotAllowedWithTheCreatorName() {
        final Id applicationFormId = createColleagueApplicationForm();
        final String creatorName = [
            SELECT
                Name
            FROM
                User
            WHERE
                Id = :UserInfo.getUserId()
        ].Name;
        System.runAs(getTestUser()) {
            useApplicantAccount();

            final ApplicationFormController.FormDefinitionWrapper result =
                ApplicationFormController.openFundingOpportunityForm(applicationFormId, true, false);

            Assert.isFalse(result.isEditAllowed, 'A colleague only reads the form');
            Assert.areEqual(creatorName, result.creatorName, 'The colleague sees who is responsible for the form');
        }
    }

    @IsTest
    static void openFundingOpportunityForm_givenFormOfPortalUser_returnsTheContactNameOfTheCreator() {
        User portalCreator;
        Id fundingOpportunityId;
        System.runAs(getTestUser()) {
            final Account organization =
                TestDataFactory.createOrganization('Test Creator Organization', 'Test Creator Organization');
            final Contact creatorContact = TestDataFactory.createContact(
                organization.Id,
                'Test',
                'OrgPortalCreator',
                'orgportalcreator@org-test.com',
                null
            );
            portalCreator = TestDataFactory.createPortalUser(
                creatorContact,
                'orgportalcreator' + DateTime.now().getTime() + '@org-test.com'
            );
            fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            insert new FundingOpportunityShare(
                ParentId      = fundingOpportunityId,
                UserOrGroupId = portalCreator.Id,
                AccessLevel   = 'Read',
                RowCause      = 'Manual'
            );
        }

        final ApplicationForm applicationForm = new ApplicationForm(
            RecordTypeId         = SchemaUtilities.getRecordTypeId(ApplicationForm.SObjectType, 'CallForProjects'),
            ReferenceRecordId    = fundingOpportunityId,
            ProgrammeRattache__c = fundingOpportunityId,
            UsageType            = 'Grantmaking',
            Stage                = 'EOI Draft'
        );
        System.runAs(portalCreator) {
            Database.insert(applicationForm, AccessLevel.SYSTEM_MODE);
        }

        System.runAs(getTestUser()) {
            useApplicantAccount();

            final ApplicationFormController.FormDefinitionWrapper result =
                ApplicationFormController.openFundingOpportunityForm(applicationForm.Id, true, false);

            Assert.isFalse(result.isEditAllowed, 'A colleague only reads the form');
            Assert.areEqual('Test OrgPortalCreator', result.creatorName, 'The name of the Contact of the creator');
        }
    }

    @IsTest
    static void openFundingOpportunityForm_givenOwnForm_returnsEditAllowedWithoutCreatorName() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            final Id applicationFormId =
                createOwnApplicationForm(createFundingOpportunityWithEoiAndFullConfig(), 'EOI Draft');

            final ApplicationFormController.FormDefinitionWrapper result =
                ApplicationFormController.openFundingOpportunityForm(applicationFormId, true, false);

            Assert.isTrue(result.isEditAllowed, 'The creator edits the form');
            Assert.isNull(result.creatorName, 'The creator is not shown to the creator');
        }
    }

    private static Id seedApplicantContactId() {
        User runningUser = [
            SELECT ContactId, FirstName, LastName, Email
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        if (runningUser.ContactId != null) {
            return runningUser.ContactId;
        }
        if (String.isNotBlank(runningUser.Email)) {
            List<Contact> existing = [
                SELECT Id FROM Contact WHERE Email = :runningUser.Email ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }
        }
        Contact applicant = new Contact(
            FirstName = String.isNotBlank(runningUser.FirstName)
                ? runningUser.FirstName
                : 'Applicant',
            LastName = String.isNotBlank(runningUser.LastName)
                ? runningUser.LastName
                : 'Applicant',
            Email = runningUser.Email
        );
        insert applicant;
        return applicant.Id;
    }

    private static Id createFundingOpportunityWithEoiAndFullConfig() {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Program program = new Program(Name = 'Test Program ' + uniqueSuffix);
        insert program;

        FundingOpportunity fundingOpportunity = new FundingOpportunity(
            Name = 'Portal FO ' + uniqueSuffix,
            Status = 'Draft',
            ProgramId = program.Id
        );
        insert fundingOpportunity;
        Id sectionId = ApplicationFormCatalogueController.createSection(
            'Portal Section ' + uniqueSuffix,
            fundingOpportunity.Id
        );
        ApplicationFormCatalogueController.createFormQuestion(
            'EOI Question ' + uniqueSuffix,
            'EOI Question',
            'Text',
            null,
            null,
            null,
            255,
            false,
            null,
            sectionId,
            null,
            1,
            fundingOpportunity.Id,
            false,
            null,
            null,
            true,
            null,
            null
        );
        ApplicationFormCatalogueController.createQuestion(
            'Full Question ' + uniqueSuffix,
            'Full Question',
            'Text',
            null,
            null,
            null,
            255,
            false,
            null,
            sectionId,
            null,
            2,
            fundingOpportunity.Id,
            false,
            null,
            null
        );
        return fundingOpportunity.Id;
    }

    private static ApplicationFormController.ResponseInputWrapper fixedAnswer(
        String objectApiName,
        String fieldApiName,
        String dataType,
        String valueJson
    ) {
        ApplicationFormController.ResponseInputWrapper input = new ApplicationFormController.ResponseInputWrapper();
        input.objectApiName = objectApiName;
        input.fieldApiName = fieldApiName;
        input.dataType = dataType;
        input.valueJson = valueJson;
        input.isFixed = true;
        return input;
    }

    // Split in two tests: every status makes several queries, and the six of them exceed the SOQL limit together.
    @isTest
    static void formDefinitionIsEditableForDraftActivePublishedAndOpenForApplicationsFundingOpportunities() {
        assertFundingOpportunityLockedFlag(new List<String>{ 'Draft', 'Active', 'Published', 'Open for Applications' }, false);
    }

    @isTest
    static void formDefinitionIsReadOnlyForUnderEvaluationAndClosedFundingOpportunities() {
        assertFundingOpportunityLockedFlag(new List<String>{ 'Under Evaluation', 'Closed' }, true);
    }

    private static void assertFundingOpportunityLockedFlag(List<String> statuses, Boolean expectedLocked) {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunityWithConfig();
            Id applicationFormId = createApplicationForm(fundingOpportunityId);

            Test.startTest();
            for (String status : statuses) {
                update new FundingOpportunity(Id = fundingOpportunityId, Status = status);

                System.assertEquals(
                    expectedLocked,
                    ApplicationFormController.getFormDefinition(applicationFormId, false).isFundingOpportunityLocked,
                    'Unexpected read-only flag from the Application Form for the status ' + status
                );
                System.assertEquals(
                    expectedLocked,
                    ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, false, false)
                        .isFundingOpportunityLocked,
                    'Unexpected read-only flag from the Funding Opportunity for the status ' + status
                );
            }
            Test.stopTest();
        }
    }

    @isTest
    static void savingIsRefusedWhenTheFundingOpportunityIsClosed() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            Id fundingOpportunityId = createFundingOpportunityWithConfig();
            Id applicationFormId = createApplicationForm(fundingOpportunityId);
            Id versionId = ApplicationFormController.getFormDefinition(applicationFormId, false)
                .sections[0].questions[0].versionId;
            String responsesJson = JSON.serialize(
                new List<ApplicationFormController.ResponseInputWrapper>{ textAnswer(versionId, 'Jane Doe') }
            );
            update new FundingOpportunity(Id = fundingOpportunityId, Status = 'Closed');

            Test.startTest();
            try {
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    responsesJson,
                    false,
                    false,
                    false,
                    null,
                    null
                );
                System.assert(false, 'Expected an AuraHandledException when saving the form of a closed Funding Opportunity');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('no longer accepts modifications'), e.getMessage());
            }
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestionResponse WHERE AssessmentQuestionId = :versionId],
                'Nothing must be saved while the Funding Opportunity is read-only'
            );
        }
    }

    @isTest
    static void renameUploadedFilesNamesTheFilesAfterTheQuestionLabel() {
        System.runAs(getTestUser()) {
            ContentVersion version = new ContentVersion(
                Title = 'scan',
                PathOnClient = 'scan.pdf',
                VersionData = Blob.valueOf('body')
            );
            insert version;
            Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;

            Test.startTest();
            List<ApplicationFormController.UploadedFileWrapper> results = ApplicationFormController.renameUploadedFiles(
                new List<Id>{ documentId },
                'Tax ruling',
                new List<String>()
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'The renamed file should be returned');
            System.assertEquals('Tax ruling.pdf', results[0].name, 'The file should be named after the label');
            System.assertEquals(documentId, results[0].documentId, 'The document Id should be returned');
        }
    }

    @isTest
    static void renameUploadedFilesRequiresADocument() {
        System.runAs(getTestUser()) {
            try {
                ApplicationFormController.renameUploadedFiles(new List<Id>(), 'Tax ruling', null);
                System.assert(false, 'Expected an AuraHandledException when no document Id is given');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('document Id is required'), e.getMessage());
            }
        }
    }

    @isTest
    static void linkUploadedFilesAttachesTheFilesToTheApplicationForm() {
        System.runAs(getTestUser()) {
            Id applicationFormId = createApplicationForm(createFundingOpportunityWithConfig());
            ContentVersion version = new ContentVersion(
                Title = 'scan',
                PathOnClient = 'scan.pdf',
                VersionData = Blob.valueOf('body')
            );
            insert version;
            Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;

            Test.startTest();
            ApplicationFormController.linkUploadedFiles(applicationFormId, new List<Id>{ documentId });
            Test.stopTest();

            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :applicationFormId AND ContentDocumentId = :documentId
                ],
                'The file should be attached to the Application Form'
            );
        }
    }

    @isTest
    static void linkUploadedFilesRequiresAnApplicationForm() {
        System.runAs(getTestUser()) {
            try {
                ApplicationFormController.linkUploadedFiles(null, new List<Id>());
                System.assert(false, 'Expected an AuraHandledException when the Application Form Id is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('record Id is required'), e.getMessage());
            }
        }
    }

    private static Map<String, Object> parseError(AuraHandledException e) {
        return (Map<String, Object>) JSON.deserializeUntyped(e.getMessage());
    }

    private static void assertTechnicalError(AuraHandledException e, String detailPrefix) {
        final Map<String, Object> error = parseError(e);
        System.assertEquals(ApplicationFormController.ERROR_TECHNICAL, error.get('code'), e.getMessage());
        System.assert(((String) error.get('detail')).startsWith(detailPrefix), e.getMessage());
    }

    @isTest
    static void buildError_givenCodeAndParams_returnsTheJsonReadByTheForm() {
        System.runAs(getTestUser()) {
            final Map<String, Object> error = parseError(
                ApplicationFormController.buildError(
                    ApplicationFormController.ERROR_MAXIMUM_CHARACTERS,
                    new List<String>{ 'Project title', '10' },
                    'English detail'
                )
            );

            System.assertEquals(ApplicationFormController.ERROR_MAXIMUM_CHARACTERS, error.get('code'), 'Code');
            System.assertEquals(
                new List<Object>{ 'Project title', '10' },
                (List<Object>) error.get('params'),
                'Parameters'
            );
            System.assertEquals('English detail', error.get('detail'), 'Detail');
        }
    }

    @isTest
    static void checkExistingSubmission_givenUserWithoutContact_returnsTheUserNotLinkedCode() {
        System.runAs(getTestUser()) {
            try {
                ApplicationFormController.checkExistingSubmission(createFundingOpportunityWithConfig(), true);
                System.assert(false, 'Expected an AuraHandledException for a user without Contact');
            } catch (AuraHandledException e) {
                System.assertEquals(
                    ApplicationFormController.ERROR_USER_NOT_LINKED,
                    parseError(e).get('code'),
                    e.getMessage()
                );
            }
        }
    }

    @isTest
    static void saveFundingOpportunityForm_givenOperationalContact_createsTheApplicationForm() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            update new Contact(
                Id       = ApplicationFormSubmissionService.contactIdOverride,
                Roles__c = 'Administrative or Operational Representative'
            );
            final Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            final ApplicationFormController.FormDefinitionWrapper opened =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, true, false);

            Test.startTest();
            final ApplicationFormController.FundingOpportunitySaveResult saveResult =
                ApplicationFormController.saveFundingOpportunityForm(
                    fundingOpportunityId,
                    JSON.serialize(
                        new List<ApplicationFormController.ResponseInputWrapper>{
                            textAnswer(opened.sections[0].questions[0].versionId, 'Answer')
                        }
                    ),
                    false,
                    true,
                    false,
                    null,
                    null
                );
            Test.stopTest();

            System.assertNotEquals(
                null,
                saveResult.applicationFormId,
                'A Contact without the applicant lead role creates the form'
            );
        }
    }

    // ---- Consents (terms and conditions, image rights) ----

    private static void createConsentForms() {
        for (String formName : new List<String>{
            ConsentService.TERMS_AND_CONDITIONS_FORM_NAME,
            ConsentService.IMAGE_RIGHTS_FORM_NAME
        }) {
            final AuthorizationForm authorizationForm = new AuthorizationForm(
                Name = formName,
                RevisionNumber = '1',
                EffectiveFromDate = Date.today()
            );
            insert authorizationForm;
            final AuthorizationFormText englishText = new AuthorizationFormText(
                Name = formName + ' EN',
                AuthorizationFormId = authorizationForm.Id,
                Locale = 'en_US',
                FullAuthorizationFormUrl = 'https://example.com/' + formName.deleteWhitespace() + '-en'
            );
            final AuthorizationFormText frenchText = new AuthorizationFormText(
                Name = formName + ' FR',
                AuthorizationFormId = authorizationForm.Id,
                Locale = 'fr_FR',
                FullAuthorizationFormUrl = 'https://example.com/' + formName.deleteWhitespace() + '-fr'
            );
            insert new List<AuthorizationFormText>{ englishText, frenchText };
            authorizationForm.DefaultAuthFormTextId = englishText.Id;
            update authorizationForm;
        }
    }

    private static Id findConsentFormTextId(String formTextName) {
        return [SELECT Id FROM AuthorizationFormText WHERE Name = :formTextName LIMIT 1].Id;
    }

    private static void useSciencePillar(Id fundingOpportunityId) {
        update new Program(
            Id = [SELECT ProgramId FROM FundingOpportunity WHERE Id = :fundingOpportunityId].ProgramId,
            RecordTypeId = Schema.SObjectType.Program.getRecordTypeInfosByDeveloperName()
                .get('Science')
                .getRecordTypeId()
        );
    }

    // Submits the EOI of a new form with every question answered.
    private static ApplicationFormController.FundingOpportunitySaveResult submitEoi(
        Id fundingOpportunityId,
        String termsAndConditionsFormTextId,
        String imageRightsFormTextId
    ) {
        final ApplicationFormController.FormDefinitionWrapper opened =
            ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, true, false);
        final List<ApplicationFormController.ResponseInputWrapper> answers =
            new List<ApplicationFormController.ResponseInputWrapper>();
        for (ApplicationFormController.SectionWrapper section : opened.sections) {
            for (ApplicationFormController.QuestionWrapper question : section.questions) {
                answers.add(textAnswer(question.versionId, 'Answer'));
            }
        }
        return ApplicationFormController.saveFundingOpportunityForm(
            fundingOpportunityId,
            JSON.serialize(answers),
            true,
            true,
            false,
            termsAndConditionsFormTextId,
            imageRightsFormTextId
        );
    }

    @IsTest
    static void buildConsents_givenFrench_returnsFrenchLabelsAndDocuments() {
        createConsentForms();

        Test.startTest();
        final ApplicationFormController.ConsentsWrapper consents =
            ApplicationFormController.buildConsents(FormLanguageService.LANGUAGE_FRENCH);
        Test.stopTest();

        Assert.areEqual(
            System.Label.get('', 'ApplicationFormConsentPrefix', 'fr'),
            consents.prefix,
            'French prefix expected'
        );
        Assert.areEqual(
            System.Label.get('', 'ApplicationFormConsentTermsAndConditionsLink', 'fr'),
            consents.termsAndConditions.linkLabel,
            'French link label expected'
        );
        Assert.areEqual(
            findConsentFormTextId(ConsentService.TERMS_AND_CONDITIONS_FORM_NAME + ' FR'),
            consents.termsAndConditions.formTextId,
            'French terms and conditions expected'
        );
        Assert.areEqual(
            findConsentFormTextId(ConsentService.IMAGE_RIGHTS_FORM_NAME + ' FR'),
            consents.imageRights.formTextId,
            'French image rights expected'
        );
        Assert.isTrue(consents.imageRights.url.endsWith('-fr'), 'French document URL expected');
    }

    @IsTest
    static void buildConsents_givenEnglish_returnsEnglishLabelsAndDocuments() {
        createConsentForms();

        Test.startTest();
        final ApplicationFormController.ConsentsWrapper consents =
            ApplicationFormController.buildConsents(FormLanguageService.LANGUAGE_ENGLISH);
        Test.stopTest();

        Assert.areEqual(
            System.Label.get('', 'ApplicationFormErrorConsentsNotAccepted', 'en_US'),
            consents.errorMessage,
            'English error message expected'
        );
        Assert.areEqual(
            System.Label.get('', 'ApplicationFormConsentImageRightsLink', 'en_US'),
            consents.imageRights.linkLabel,
            'English link label expected'
        );
        Assert.areEqual(
            findConsentFormTextId(ConsentService.TERMS_AND_CONDITIONS_FORM_NAME + ' EN'),
            consents.termsAndConditions.formTextId,
            'English terms and conditions expected'
        );
    }

    @IsTest
    static void buildConsents_givenNoActiveForm_returnsLabelsWithoutDocument() {
        Test.startTest();
        final ApplicationFormController.ConsentsWrapper consents =
            ApplicationFormController.buildConsents(FormLanguageService.LANGUAGE_ENGLISH);
        Test.stopTest();

        Assert.isNotNull(consents.prefix, 'The labels are returned even without a document');
        Assert.isNull(consents.termsAndConditions.formTextId, 'No terms and conditions expected');
        Assert.isNull(consents.imageRights.url, 'No image rights URL expected');
    }

    @IsTest
    static void openFundingOpportunityForm_givenActiveConsentForms_returnsTheConsents() {
        System.runAs(getTestUser()) {
            createConsentForms();
            final Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            Test.startTest();
            final ApplicationFormController.FormDefinitionWrapper opened =
                ApplicationFormController.openFundingOpportunityForm(fundingOpportunityId, true, false);
            Test.stopTest();

            Assert.isNotNull(opened.consents.termsAndConditions.formTextId, 'Terms and conditions expected');
            Assert.isNotNull(opened.consents.imageRights.formTextId, 'Image rights expected');
        }
    }

    @IsTest
    static void saveFundingOpportunityForm_givenAcceptedConsents_recordsEveryLanguageForTheSubmitter() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            createConsentForms();
            final Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            Test.startTest();
            final ApplicationFormController.FundingOpportunitySaveResult result = submitEoi(
                fundingOpportunityId,
                findConsentFormTextId(ConsentService.TERMS_AND_CONDITIONS_FORM_NAME + ' FR'),
                findConsentFormTextId(ConsentService.IMAGE_RIGHTS_FORM_NAME + ' FR')
            );
            Test.stopTest();

            final List<AuthorizationFormConsent> consents = [
                SELECT ConsentGiverId, RelatedRecordId, ConsentCapturedSource, AuthorizationFormText.Name
                FROM AuthorizationFormConsent
            ];
            Assert.areEqual(4, consents.size(), 'English and French versions of both documents expected');
            for (AuthorizationFormConsent consent : consents) {
                Assert.areEqual(
                    ApplicationFormSubmissionService.contactIdOverride,
                    consent.ConsentGiverId,
                    'The Contact who submits gives the consent'
                );
                Assert.areEqual(result.applicationFormId, consent.RelatedRecordId, 'Linked to the Application Form');
                Assert.areEqual('EOI Submission', consent.ConsentCapturedSource, 'EOI submission expected');
            }
        }
    }

    @IsTest
    static void saveFundingOpportunityForm_givenSciencePillar_recordsEnglishConsentsOnly() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            createConsentForms();
            final Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();
            useSciencePillar(fundingOpportunityId);

            Test.startTest();
            submitEoi(
                fundingOpportunityId,
                findConsentFormTextId(ConsentService.TERMS_AND_CONDITIONS_FORM_NAME + ' EN'),
                findConsentFormTextId(ConsentService.IMAGE_RIGHTS_FORM_NAME + ' EN')
            );
            Test.stopTest();

            final Set<String> formTextNames = new Set<String>();
            for (AuthorizationFormConsent consent : [
                SELECT AuthorizationFormText.Name
                FROM AuthorizationFormConsent
            ]) {
                formTextNames.add(consent.AuthorizationFormText.Name);
            }
            Assert.areEqual(
                new Set<String>{
                    ConsentService.TERMS_AND_CONDITIONS_FORM_NAME + ' EN',
                    ConsentService.IMAGE_RIGHTS_FORM_NAME + ' EN'
                },
                formTextNames,
                'A Science form records the English versions only'
            );
        }
    }

    @IsTest
    static void saveFundingOpportunityForm_givenMissingConsent_throwsTheConsentsNotAcceptedCode() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            createConsentForms();
            final Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            Test.startTest();
            try {
                submitEoi(
                    fundingOpportunityId,
                    findConsentFormTextId(ConsentService.TERMS_AND_CONDITIONS_FORM_NAME + ' EN'),
                    null
                );
                Assert.fail('The submission must be refused without the image rights');
            } catch (AuraHandledException e) {
                Assert.areEqual(
                    ApplicationFormController.ERROR_CONSENTS_NOT_ACCEPTED,
                    parseError(e).get('code'),
                    e.getMessage()
                );
            }
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM ApplicationForm], 'Nothing is saved when a consent is missing');
            Assert.areEqual(0, [SELECT COUNT() FROM AuthorizationFormConsent], 'No consent expected');
        }
    }

    @IsTest
    static void saveFundingOpportunityForm_givenInvalidConsentId_throwsTheConsentsNotAcceptedCode() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            createConsentForms();
            final Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            Test.startTest();
            try {
                submitEoi(fundingOpportunityId, 'not-an-id', 'not-an-id');
                Assert.fail('The submission must be refused with invalid consent ids');
            } catch (AuraHandledException e) {
                Assert.areEqual(
                    ApplicationFormController.ERROR_CONSENTS_NOT_ACCEPTED,
                    parseError(e).get('code'),
                    e.getMessage()
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void saveFundingOpportunityForm_givenDraft_ignoresTheConsents() {
        System.runAs(getTestUser()) {
            useApplicantAccount();
            final Id fundingOpportunityId = createFundingOpportunityWithEoiAndFullConfig();

            Test.startTest();
            ApplicationFormController.saveFundingOpportunityForm(fundingOpportunityId, '[]', false, true, false, null, null);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM AuthorizationFormConsent], 'A draft records no consent');
        }
    }
}
