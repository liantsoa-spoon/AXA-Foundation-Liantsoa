/**
 * @description       : Test class for ApplicationFormCatalogueController.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 08-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   02-10-2026   LAN      Initial version
 * 1.1   02-10-2026   LAN      Test the section numbering per mode and the server-side question sequence
 * 1.2   02-10-2026   LAN      Test that reordering sections and questions keeps the existing range of numbers
 * 1.3   05-10-2026   LAN      Run every test as the AXA admin user created in the testSetup
 * 1.4   06-10-2026   LAN      Test the form version reads of ApplicationFormCatalogueQueryService
 * 1.5   08-10-2026   LAN      Test the name generated from the text and the French translation of a question
 * 1.6   08-10-2026   LAN      Test the error codes returned to the LWC
 * 1.7   08-10-2026   LAN      Test the French translation saved with the question, in a single call
 * 1.8   09-10-2026   LAN      Test the preconfigured checks and the cleaning of the cloned catalogues of the query service
 **/
@isTest
private class ApplicationFormCatalogueController_TEST {

    @testSetup
    static void setupTestData() {
        // Create user with Standard Profile
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

        // Query both Permission Sets (by API Name or Label)
        List<PermissionSet> psList = [
            SELECT Id 
            FROM PermissionSet 
            WHERE Name IN ('AXA_Foundation_Admin', 'Grantmaking_Manager') 
               OR Label IN ('AXA Foundation Admin', 'Grantmaking Manager')
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
        return [SELECT Id FROM User WHERE LastName = 'AXAAdminUser' LIMIT 1];
    }

    private static String uniqueLabel(String prefix) {
        return prefix + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static Id createFundingOpportunity() {
        Program program = new Program(Name = uniqueLabel('Test Program'));
        insert program;

        FundingOpportunity fundingOpportunity = new FundingOpportunity(
            Name = 'Test Funding Opportunity',
            Status = 'Draft',
            ProgramId = program.Id
        );
        insert fundingOpportunity;
        return fundingOpportunity.Id;
    }

    private static Id createDynamicQuestion(
        String name,
        String questionText,
        String dataType,
        Id sectionId,
        Id fundingOpportunityId
    ) {
        return createDynamicQuestion(
            name,
            questionText,
            dataType,
            sectionId,
            fundingOpportunityId,
            dataType == 'Text' || dataType == 'TextArea' ? 255 : null
        );
    }

    private static Id createDynamicQuestion(
        String name,
        String questionText,
        String dataType,
        Id sectionId,
        Id fundingOpportunityId,
        Decimal maximumCharacters
    ) {
        return ApplicationFormCatalogueController.createQuestion(
            name,
            questionText,
            dataType,
            null,
            null,
            null,
            maximumCharacters,
            false,
            null,
            sectionId,
            null,
            1,
            fundingOpportunityId,
            false,
            null,
            null
        );
    }

    @isTest
    static void createSectionAndQuestionReturnsActiveCatalog() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();

            Test.startTest();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section A'), fundingOpportunityId);
            createDynamicQuestion('Question 1', 'Question 1 text?', 'Text', sectionId, fundingOpportunityId);
            createDynamicQuestion('Question 2', 'Question 2 text?', 'Integer', sectionId, fundingOpportunityId);
            Test.stopTest();

            List<ApplicationFormCatalogueController.SectionWrapper> catalog =
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId);
            System.assertEquals(1, catalog.size(), 'Expected one section on the Funding Opportunity');
            System.assertEquals(2, catalog[0].questions.size(), 'Expected two questions in the section');
            System.assertEquals(true, catalog[0].questions[0].isActive, 'A new question must start as Active');
            System.assertEquals(false, catalog[0].questions[0].isFixed, 'A question created without isFixed is Dynamic');
        }
    }

    @isTest
    static void emptySectionIsNotReturnedInTheCatalog() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            ApplicationFormCatalogueController.createSection(uniqueLabel('Empty Section'), fundingOpportunityId);

            List<ApplicationFormCatalogueController.SectionWrapper> catalog =
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId);

            // A section's FO membership is derived from its Assignments, so it has none until a question is added.
            System.assertEquals(0, catalog.size(), 'A section without questions is not part of the FO catalog');
        }
    }

    @isTest
    static void catalogueMutationsRequireActiveFundingOpportunity() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(
                uniqueLabel('Active Section'),
                fundingOpportunityId
            );
            Id questionId = createDynamicQuestion(
                'Active Question',
                'Active question?',
                'Text',
                sectionId,
                fundingOpportunityId
            );
            update new FundingOpportunity(
                Id = fundingOpportunityId,
                Status = 'Open for Applications'
            );

            Test.startTest();
            try {
                ApplicationFormCatalogueController.createSection(
                    uniqueLabel('Blocked Section'),
                    fundingOpportunityId
                );
                System.assert(false, 'A section must not be created once the Funding Opportunity no longer allows form editing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('status is Active'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.updateQuestion(
                    questionId,
                    'Blocked Question',
                    'Blocked question?',
                    'Text',
                    null,
                    null,
                    null,
                    255,
                    false,
                    null,
                    null,
                    null
                );
                System.assert(false, 'A question must not be updated once the Funding Opportunity no longer allows form editing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('status is Active'), e.getMessage());
            }
            Test.stopTest();
        }
    }

    @isTest
    static void catalogueMutationsAreAllowedForActiveStatus() {
        System.runAs(getTestUser()) {
            Test.startTest();
            for (String status : new List<String>{ 'Active' }) {
                Id fundingOpportunityId = createFundingOpportunity();
                update new FundingOpportunity(Id = fundingOpportunityId, Status = status);

                Id sectionId = ApplicationFormCatalogueController.createSection(
                    uniqueLabel(status + ' Section'),
                    fundingOpportunityId
                );
                Id questionId = createDynamicQuestion(
                    status + ' Question',
                    status + ' question?',
                    'Text',
                    sectionId,
                    fundingOpportunityId
                );

                System.assertNotEquals(null, sectionId, 'A section can be created while the status is ' + status);
                System.assertNotEquals(null, questionId, 'A question can be created while the status is ' + status);
            }
            Test.stopTest();
        }
    }

    @isTest
    static void catalogueMutationsAreBlockedForNonActiveStatuses() {
        System.runAs(getTestUser()) {
            for (String status : new List<String>{ 'Draft', 'Published', 'Under Evaluation', 'Closed' }) {
                Id fundingOpportunityId = createFundingOpportunity();
                update new FundingOpportunity(Id = fundingOpportunityId, Status = status);

                try {
                    ApplicationFormCatalogueController.createSection(uniqueLabel('Blocked Section'), fundingOpportunityId);
                    System.assert(false, 'A section must not be created while the status is ' + status);
                } catch (AuraHandledException e) {
                    System.assert(e.getMessage().contains('status is Active'), e.getMessage());
                }
            }
        }
    }

    @isTest
    static void createQuestionPersistsMaximumCharacters() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            Test.startTest();
            Id questionId = createDynamicQuestion(
                'Limited Q',
                'Limited question?',
                'Text',
                sectionId,
                fundingOpportunityId,
                200
            );
            Test.stopTest();

            ApplicationFormCatalogueController.QuestionDetailWrapper detail =
                ApplicationFormCatalogueController.getQuestionForEdit(questionId);
            System.assertEquals(200, detail.maximumCharacters, 'Maximum characters should round-trip on create');

            List<ApplicationFormCatalogueController.SectionWrapper> catalog =
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId);
            System.assertEquals(200, catalog[0].questions[0].maximumCharacters, 'The catalog tree should expose the limit');
        }
    }

    @isTest
    static void createQuestionRejectsInvalidMaximumCharacters() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            try {
                createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId, 0);
                System.assert(false, 'Expected an AuraHandledException for a non-positive limit');
            } catch (AuraHandledException e) {
                System.assert(
                    e.getMessage().contains('positive whole number'),
                    'Unexpected error message: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void createQuestionRequiresMaximumCharactersForText() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            try {
                createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId, null);
                System.assert(false, 'Expected an AuraHandledException when Maximum Characters is missing');
            } catch (AuraHandledException e) {
                System.assert(
                    e.getMessage().contains('Maximum Characters is required'),
                    'Unexpected error message: ' + e.getMessage()
                );
            }
        }
    }

    @isTest
    static void createFixedQuestionRequiresObjectAndFieldApiName() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            try {
                ApplicationFormCatalogueController.createQuestion(
                    'Fixed Q', 'Fixed Q?', 'Text', null, null, null, 255, false, null,
                    sectionId, null, 1, fundingOpportunityId, true, null, 'Phone'
                );
                System.assert(false, 'Expected an AuraHandledException when Object API Name is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Object API Name is required'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.createQuestion(
                    'Fixed Q', 'Fixed Q?', 'Text', null, null, null, 255, false, null,
                    sectionId, null, 1, fundingOpportunityId, true, 'Contact', null
                );
                System.assert(false, 'Expected an AuraHandledException when Field API Name is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Field API Name is required'), e.getMessage());
            }
        }
    }

    @isTest
    static void fixedQuestionCannotBeEditedOrPermanentlyRemoved() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            Id questionId = ApplicationFormCatalogueController.createQuestion(
                'Phone', 'Phone Number?', 'Telephone', null, null, null, null, false, null,
                sectionId, null, 1, fundingOpportunityId, true, 'Contact', 'Phone'
            );

            List<ApplicationFormCatalogueController.SectionWrapper> catalog =
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId);
            System.assertEquals(true, catalog[0].questions[0].isFixed, 'Question should be flagged as Fixed');

            ApplicationFormCatalogueController.QuestionDetailWrapper detail =
                ApplicationFormCatalogueController.getQuestionForEdit(questionId);
            System.assertEquals(true, detail.isFixed, 'Detail should flag the question as Fixed');
            System.assertEquals('Contact', detail.objectApiName, 'Object API Name should round-trip');
            System.assertEquals('Phone', detail.fieldApiName, 'Field API Name should round-trip');

            try {
                ApplicationFormCatalogueController.updateQuestion(
                    questionId, 'New Name', 'New Text?', 'Text', null, null, null, 255, false, null, null, null
                );
                System.assert(false, 'Expected an AuraHandledException when editing a Fixed question');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('cannot be edited'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.removeQuestionAssignment(catalog[0].questions[0].assignmentId, true);
                System.assert(false, 'Expected an AuraHandledException when permanently removing a Fixed question');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('cannot be removed'), e.getMessage());
            }
        }
    }

    @isTest
    static void sectionContainingFixedQuestionCannotBeEditedOrRemoved() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Mixed Section'), fundingOpportunityId);
            ApplicationFormCatalogueController.createQuestion(
                'Phone', 'Phone Number?', 'Telephone', null, null, null, null, false, null,
                sectionId, null, 1, fundingOpportunityId, true, 'Contact', 'Phone'
            );

            try {
                ApplicationFormCatalogueController.updateSection(sectionId, 'Renamed');
                System.assert(false, 'Expected an AuraHandledException when editing a Fixed section');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('cannot be edited'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.removeSectionAssignments(fundingOpportunityId, sectionId, true);
                System.assert(false, 'Expected an AuraHandledException when removing a Fixed section');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('cannot be removed'), e.getMessage());
            }
        }
    }

    @isTest
    static void moveQuestionBlocksFixedQuestionsButAllowsMixedTargets() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id dynamicSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Dynamic Section'), fundingOpportunityId);
            Id mixedSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Mixed Section'), fundingOpportunityId);

            createDynamicQuestion('Q1', 'Q1?', 'Text', dynamicSectionId, fundingOpportunityId);
            // A second question keeps the source section from being emptied by the move below.
            createDynamicQuestion('Q2', 'Q2?', 'Text', dynamicSectionId, fundingOpportunityId);
            ApplicationFormCatalogueController.createQuestion(
                'Phone', 'Phone Number?', 'Telephone', null, null, null, null, false, null,
                mixedSectionId, null, 1, fundingOpportunityId, true, 'Contact', 'Phone'
            );

            List<ApplicationFormCatalogueController.SectionWrapper> catalog =
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId);
            Id dynamicAssignmentId;
            Id fixedAssignmentId;
            for (ApplicationFormCatalogueController.SectionWrapper section : catalog) {
                for (ApplicationFormCatalogueController.QuestionWrapper question : section.questions) {
                    if (question.isFixed == true) {
                        fixedAssignmentId = question.assignmentId;
                    } else {
                        dynamicAssignmentId = question.assignmentId;
                    }
                }
            }

            try {
                ApplicationFormCatalogueController.moveQuestion(fixedAssignmentId, dynamicSectionId, new List<Id>());
                System.assert(false, 'Expected an AuraHandledException when moving a Fixed question');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Fixed question cannot be moved'), e.getMessage());
            }

            // A Dynamic question can be moved into any section, even one that holds Fixed questions.
            ApplicationFormCatalogueController.moveQuestion(dynamicAssignmentId, mixedSectionId, new List<Id>());
            System.assertEquals(
                mixedSectionId,
                [SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment WHERE Id = :dynamicAssignmentId]
                    .AssessmentQuestionSetId,
                'A Dynamic question can be moved into a section holding Fixed questions'
            );
        }
    }

    @isTest
    static void createTableQuestionStoresColumns() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section With Table'), fundingOpportunityId);

            ApplicationFormCatalogueController.ColumnWrapper column = new ApplicationFormCatalogueController.ColumnWrapper();
            column.label = 'Amount';

            Test.startTest();
            Id questionId = ApplicationFormCatalogueController.createQuestion(
                'Table Question',
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
                1,
                fundingOpportunityId,
                false,
                null,
                null
            );
            Test.stopTest();

            List<ApplicationFormCatalogueController.ColumnWrapper> columns =
                ApplicationFormCatalogueController.getTableColumns(questionId);
            System.assertEquals(1, columns.size(), 'Expected one serialized table column');
            System.assertEquals('Amount', columns[0].label, 'Unexpected column label');
            System.assertEquals(
                true,
                ApplicationFormCatalogueController.getQuestionForEdit(questionId).isTable,
                'Detail should flag the question as a table'
            );
        }
    }

    @isTest
    static void updateDraftQuestionAndMandatoryFlag() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            Id questionId = createDynamicQuestion('Q', 'Original?', 'Text', sectionId, fundingOpportunityId, 50);

            Test.startTest();
            ApplicationFormCatalogueController.updateQuestion(
                questionId, 'Updated', 'Updated text?', 'TextArea', 'Desc', null, 'Help', 80, false, null, null, null
            );
            ApplicationFormCatalogueController.setQuestionMandatory(questionId, false);
            Test.stopTest();

            ApplicationFormCatalogueController.QuestionDetailWrapper detail =
                ApplicationFormCatalogueController.getQuestionForEdit(questionId);
            System.assertEquals('Updated', detail.name, 'Name should be updated');
            System.assertEquals('Updated text?', detail.questionText, 'Question text should be updated');
            System.assertEquals(80, detail.maximumCharacters, 'Maximum characters should be updated');
            System.assertEquals(false, detail.isMandatory, 'Mandatory flag should be updated');
        }
    }

    @isTest
    static void permanentlyDeleteOrphanedDraftQuestionPurgesIt() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            // Keep a normal (Active) question in the section so deleting the target below doesn't
            // violate the one-question-per-section minimum.
            createDynamicQuestion('Other Q', 'Other Q?', 'Text', sectionId, fundingOpportunityId);

            // A question created through the builder now starts Active (US-042), and deactivating it
            // afterwards lands on Status = Inactive, not Draft — so a genuine never-activated Draft
            // orphan can only be produced with a direct insert, bypassing the builder API.
            AssessmentQuestion question = new AssessmentQuestion(
                Name = 'Q',
                DeveloperName = 'Q' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                DataType = 'Text',
                QuestionCategory = 'Demographic',
                MaximumCharacters__c = 255,
                RecordTypeId = SchemaUtilities.getRecordTypeId(AssessmentQuestion.sObjectType, 'Dynamic')
            );
            insert question;
            insert new AssessmentQuestionVersion(
                Name = 'Q',
                AssessmentQuestionId = question.Id,
                QuestionText = 'Q?',
                IsActive = false
            );
            AssessmentQuestionAssignment assignment = new AssessmentQuestionAssignment(
                AssessmentQuestionId = question.Id,
                AssessmentQuestionSetId = sectionId,
                FundingOpportunity__c = fundingOpportunityId,
                IsMandatory__c = true
            );
            insert assignment;

            Test.startTest();
            ApplicationFormCatalogueController.removeQuestionAssignment(assignment.Id, true);
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestion WHERE Id = :question.Id],
                'A Draft orphan should be fully purged'
            );
        }
    }

    @isTest
    static void permanentlyDeleteActivatedQuestionLeavesItOrphaned() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            // A question created through the builder starts Active already (US-042); keep a second
            // question in the section so deleting the target doesn't violate the one-question-per-
            // section minimum.
            Id questionId = createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId);
            createDynamicQuestion('Other Q', 'Other Q?', 'Text', sectionId, fundingOpportunityId);
            Id assignmentId = null;
            for (ApplicationFormCatalogueController.QuestionWrapper question :
                    ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId)[0].questions) {
                if (question.questionId == questionId) {
                    assignmentId = question.assignmentId;
                }
            }

            Test.startTest();
            ApplicationFormCatalogueController.removeQuestionAssignment(assignmentId, true);
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT COUNT() FROM AssessmentQuestion WHERE Id = :questionId],
                'An activated question cannot be purged even once orphaned'
            );
        }
    }

    @isTest
    static void permanentlyDeleteSectionRemovesOrphanedDrafts() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('FO Section'), fundingOpportunityId);
            createDynamicQuestion('Q1', 'Q1?', 'Text', sectionId, fundingOpportunityId);
            createDynamicQuestion('Q2', 'Q2?', 'Text', sectionId, fundingOpportunityId);

            Test.startTest();
            ApplicationFormCatalogueController.removeSectionAssignments(fundingOpportunityId, sectionId, false);
            System.assertEquals(
                2,
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId)[0].questions.size(),
                'Deactivate is currently a no-op'
            );
            ApplicationFormCatalogueController.removeSectionAssignments(fundingOpportunityId, sectionId, true);
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestionSet WHERE Id = :sectionId],
                'An orphaned section should be deleted'
            );
        }
    }

    @isTest
    static void schemaUtilitiesReturnsRecordTypeIds() {
        System.runAs(getTestUser()) {
            System.assertNotEquals(
                null,
                SchemaUtilities.getRecordTypeId(AssessmentQuestion.sObjectType, 'Dynamic'),
                'Dynamic record type should exist'
            );
            System.assertEquals(
                null,
                SchemaUtilities.getRecordTypeId(AssessmentQuestion.sObjectType, 'DoesNotExist'),
                'Unknown developer name should return null'
            );
        }
    }

    @isTest
    static void updateSectionRenamesASectionMadeOfDynamicQuestions() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId);

            Test.startTest();
            ApplicationFormCatalogueController.updateSection(sectionId, 'Renamed Section');
            Test.stopTest();

            System.assertEquals(
                'Renamed Section',
                [SELECT Name FROM AssessmentQuestionSet WHERE Id = :sectionId].Name,
                'The section should be renamed'
            );
        }
    }

    @isTest
    static void blankOrMissingInputsAreRejectedBeforeAnyDml() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();

            try {
                ApplicationFormCatalogueController.createSection('   ', fundingOpportunityId);
                System.assert(false, 'Expected an AuraHandledException for a blank section label');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('section label is required'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.updateSection(null, 'Label');
                System.assert(false, 'Expected an AuraHandledException when the section Id is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('section Id is required'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.getQuestionForEdit(null);
                System.assert(false, 'Expected an AuraHandledException when the question Id is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('question Id is required'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.getTableColumns(null);
                System.assert(false, 'Expected an AuraHandledException when the question Id is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('question Id is required'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.setQuestionMandatory(null, true);
                System.assert(false, 'Expected an AuraHandledException when the question Id is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('question Id is required'), e.getMessage());
            }
        }
    }

    @isTest
    static void getTableColumnsReturnsAnEmptyListForANonTableQuestion() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            Id questionId = createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId);

            System.assertEquals(
                0,
                ApplicationFormCatalogueController.getTableColumns(questionId).size(),
                'A question with no serialized columns should return an empty list'
            );
        }
    }

    @isTest
    static void questionWithoutAVersionIsReported() {
        System.runAs(getTestUser()) {
            AssessmentQuestion question = new AssessmentQuestion(
                Name = 'Versionless',
                DeveloperName = 'Versionless' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                DataType = 'Text',
                QuestionCategory = 'Demographic',
                MaximumCharacters__c = 255,
                RecordTypeId = SchemaUtilities.getRecordTypeId(AssessmentQuestion.sObjectType, 'Dynamic')
            );
            insert question;

            try {
                ApplicationFormCatalogueController.getQuestionForEdit(question.Id);
                System.assert(false, 'Expected an AuraHandledException when the question has no version');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('No version found'), e.getMessage());
            }

            try {
                ApplicationFormCatalogueController.updateQuestion(
                    question.Id, 'Name', 'Text?', 'Text', null, null, null, 255, false, null, null, null
                );
                System.assert(false, 'Expected an AuraHandledException when the question has no version');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('No version found'), e.getMessage());
            }
        }
    }

    @isTest
    static void editingAnActivatedQuestionArchivesItAndCreatesANewActiveVersion() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            Id questionId = createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId);
            List<AssessmentQuestionVersion> originalVersions = [
                SELECT Id FROM AssessmentQuestionVersion WHERE AssessmentQuestionId = :questionId
            ];
            System.assertEquals(1, originalVersions.size(), 'The question should start with exactly one (active) version');

            ApplicationFormCatalogueController.updateQuestion(
                questionId, 'Name', 'Updated text?', 'Text', null, null, null, 255, false, null, null, null
            );

            List<AssessmentQuestionVersion> versions = [
                SELECT Id, IsActive, QuestionText
                FROM AssessmentQuestionVersion
                WHERE AssessmentQuestionId = :questionId
                ORDER BY IsActive DESC, CreatedDate DESC
            ];
            System.assertEquals(2, versions.size(), 'Editing an active question must archive it and create a new version');
            System.assertEquals(true, versions[0].IsActive, 'The new version must be active');
            System.assertEquals('Updated text?', versions[0].QuestionText, 'The new version must carry the edited text');
            System.assertEquals(originalVersions[0].Id, versions[1].Id, 'The original version must be preserved');
            System.assertEquals(false, versions[1].IsActive, 'The original version must be archived');
        }
    }

    @isTest
    static void updateQuestionReplacesTheSerializedTableColumns() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            Id questionId = createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId);

            ApplicationFormCatalogueController.ColumnWrapper firstColumn = new ApplicationFormCatalogueController.ColumnWrapper();
            firstColumn.label = 'Year';
            ApplicationFormCatalogueController.ColumnWrapper secondColumn = new ApplicationFormCatalogueController.ColumnWrapper();
            secondColumn.label = 'Budget';
            ApplicationFormCatalogueController.ColumnWrapper blankColumn = new ApplicationFormCatalogueController.ColumnWrapper();

            Test.startTest();
            ApplicationFormCatalogueController.updateQuestion(
                questionId,
                'Budget table',
                'Fill the budget',
                'TextBlock',
                null,
                null,
                null,
                null,
                true,
                JSON.serialize(
                    new List<ApplicationFormCatalogueController.ColumnWrapper>{ firstColumn, blankColumn, secondColumn }
                ),
                null,
                null
            );
            Test.stopTest();

            List<ApplicationFormCatalogueController.ColumnWrapper> columns =
                ApplicationFormCatalogueController.getTableColumns(questionId);
            System.assertEquals(2, columns.size(), 'Columns without a label should be dropped');
            System.assertEquals('Year', columns[0].label, 'Unexpected first column');
            System.assertEquals('Budget', columns[1].developerName, 'A developer name should be derived from the label');
        }
    }

    @isTest
    static void moveQuestionIntoAnotherDynamicSectionReordersTheTarget() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sourceSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Source'), fundingOpportunityId);
            Id targetSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Target'), fundingOpportunityId);
            Id movingQuestionId = createDynamicQuestion('Moving', 'Moving?', 'Text', sourceSectionId, fundingOpportunityId);
            createDynamicQuestion('Remaining', 'Remaining?', 'Text', sourceSectionId, fundingOpportunityId);
            Id stayingQuestionId = createDynamicQuestion('Staying', 'Staying?', 'Text', targetSectionId, fundingOpportunityId);

            Map<Id, Id> assignmentIdByQuestionId = new Map<Id, Id>();
            for (AssessmentQuestionAssignment aqa : [
                SELECT Id, AssessmentQuestionId
                FROM AssessmentQuestionAssignment
                WHERE FundingOpportunity__c = :fundingOpportunityId
            ]) {
                assignmentIdByQuestionId.put(aqa.AssessmentQuestionId, aqa.Id);
            }
            Id movingAssignmentId = assignmentIdByQuestionId.get(movingQuestionId);
            Id stayingAssignmentId = assignmentIdByQuestionId.get(stayingQuestionId);

            Test.startTest();
            ApplicationFormCatalogueController.moveQuestion(
                movingAssignmentId,
                targetSectionId,
                new List<Id>{ movingAssignmentId, stayingAssignmentId }
            );
            Test.stopTest();

            System.assertEquals(
                targetSectionId,
                [SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment WHERE Id = :movingAssignmentId]
                    .AssessmentQuestionSetId,
                'The question should now belong to the target section'
            );

            Map<Id, Decimal> sequenceByQuestionId = new Map<Id, Decimal>();
            for (AssessmentQuestion question : [
                SELECT Id, Sequence__c FROM AssessmentQuestion WHERE Id IN (:movingQuestionId, :stayingQuestionId)
            ]) {
                sequenceByQuestionId.put(question.Id, question.Sequence__c);
            }
            System.assertEquals(1, sequenceByQuestionId.get(movingQuestionId), 'The moved question should come first');
            System.assertEquals(2, sequenceByQuestionId.get(stayingQuestionId), 'The existing question should come second');
        }
    }

    @isTest
    static void moveQuestionReordersInsideASectionHoldingFixedQuestions() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Mixed Section'), fundingOpportunityId);
            ApplicationFormCatalogueController.createQuestion(
                'Phone', 'Phone Number?', 'Telephone', null, null, null, null, false, null,
                sectionId, null, 1, fundingOpportunityId, true, 'Contact', 'Phone'
            );
            Id firstQuestionId = createDynamicQuestion('First', 'First?', 'Text', sectionId, fundingOpportunityId);
            Id secondQuestionId = createDynamicQuestion('Second', 'Second?', 'Text', sectionId, fundingOpportunityId);

            Map<Id, Id> assignmentIdByQuestionId = new Map<Id, Id>();
            for (AssessmentQuestionAssignment aqa : [
                SELECT Id, AssessmentQuestionId
                FROM AssessmentQuestionAssignment
                WHERE FundingOpportunity__c = :fundingOpportunityId
            ]) {
                assignmentIdByQuestionId.put(aqa.AssessmentQuestionId, aqa.Id);
            }
            Id firstAssignmentId = assignmentIdByQuestionId.get(firstQuestionId);
            Id secondAssignmentId = assignmentIdByQuestionId.get(secondQuestionId);

            Test.startTest();
            ApplicationFormCatalogueController.moveQuestion(
                secondAssignmentId,
                sectionId,
                new List<Id>{ secondAssignmentId, firstAssignmentId }
            );
            Test.stopTest();

            System.assertEquals(
                sectionId,
                [SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment WHERE Id = :secondAssignmentId]
                    .AssessmentQuestionSetId,
                'The question must stay in its own section'
            );
            System.assertEquals(
                1,
                [SELECT Sequence__c FROM AssessmentQuestion WHERE Id = :secondQuestionId].Sequence__c,
                'The dragged question should now come first'
            );
            System.assertEquals(
                2,
                [SELECT Sequence__c FROM AssessmentQuestion WHERE Id = :firstQuestionId].Sequence__c,
                'The other question should now come second'
            );
        }
    }

    @isTest
    static void moveQuestionAllowsCustomQuestionInsideAndIntoPreconfiguredSection() {
        System.runAs(getTestUser()) {
            Program program = new Program(Name = uniqueLabel('Test Program'));
            insert program;
            FundingOpportunity fundingOpportunity = new FundingOpportunity(
                Name = 'FO Preconfigured Section',
                ProgramId = program.Id,
                Status = 'Draft'
            );
            insert fundingOpportunity;

            AssessmentQuestionSet templateSection = new AssessmentQuestionSet(
                Name = 'Template Section',
                DeveloperName = 'TemplateSection' + String.valueOf(Datetime.now().getTime())
            );
            insert templateSection;
            Id templateQuestionId = ApplicationFormCatalogueController.createQuestion(
                'Template Q', 'Template question?', 'Text', null, null, null, 120, false, null,
                templateSection.Id, null, 1, null, false, null, null
            );
            AssessmentQuestionAssignment templateAssignment = [
                SELECT Id FROM AssessmentQuestionAssignment WHERE AssessmentQuestionId = :templateQuestionId LIMIT 1
            ];
            update new AssessmentQuestionAssignment(Id = templateAssignment.Id, Program__c = program.Id);
            ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
                new Map<Id, Set<Id>>{ fundingOpportunity.Id => new Set<Id>{ templateAssignment.Id } }
            );

            List<ApplicationFormCatalogueController.SectionWrapper> catalog =
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunity.Id);
            Id preconfiguredSectionId = catalog[0].sectionId;
            Id clonedQuestionId = catalog[0].questions[0].questionId;
            Id clonedAssignmentId = catalog[0].questions[0].assignmentId;
            System.assertEquals(true, catalog[0].isPreconfigured, 'The cloned template section must be preconfigured');

            Id customQuestionId = createDynamicQuestion(
                'CUSTOM Q', 'Custom question?', 'Text', preconfiguredSectionId, fundingOpportunity.Id
            );
            Id otherSectionId = ApplicationFormCatalogueController.createSection(
                uniqueLabel('Other Section'),
                fundingOpportunity.Id
            );
            Id otherQuestionId = createDynamicQuestion(
                'Other Q', 'Other question?', 'Text', otherSectionId, fundingOpportunity.Id
            );
            // A second question keeps the source section from being emptied by the move.
            createDynamicQuestion('Other Q2', 'Other question 2?', 'Text', otherSectionId, fundingOpportunity.Id);

            Map<Id, Id> assignmentIdByQuestionId = new Map<Id, Id>();
            for (AssessmentQuestionAssignment aqa : [
                SELECT Id, AssessmentQuestionId
                FROM AssessmentQuestionAssignment
                WHERE FundingOpportunity__c = :fundingOpportunity.Id
            ]) {
                assignmentIdByQuestionId.put(aqa.AssessmentQuestionId, aqa.Id);
            }
            Id customAssignmentId = assignmentIdByQuestionId.get(customQuestionId);
            Id otherAssignmentId = assignmentIdByQuestionId.get(otherQuestionId);

            Test.startTest();
            // Reordering a custom question inside its own preconfigured section is allowed.
            ApplicationFormCatalogueController.moveQuestion(
                customAssignmentId,
                preconfiguredSectionId,
                new List<Id>{ customAssignmentId, clonedAssignmentId }
            );

            // A Dynamic question coming from another section can also be moved into it.
            ApplicationFormCatalogueController.moveQuestion(otherAssignmentId, preconfiguredSectionId, new List<Id>());
            Test.stopTest();

            System.assertEquals(
                preconfiguredSectionId,
                [SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment WHERE Id = :customAssignmentId]
                    .AssessmentQuestionSetId,
                'The custom question must stay in the preconfigured section'
            );
            System.assertEquals(
                1,
                [SELECT Sequence__c FROM AssessmentQuestion WHERE Id = :customQuestionId].Sequence__c,
                'The custom question should now come first'
            );
            System.assertEquals(
                2,
                [SELECT Sequence__c FROM AssessmentQuestion WHERE Id = :clonedQuestionId].Sequence__c,
                'The preconfigured clone should now come second'
            );
            System.assertEquals(
                preconfiguredSectionId,
                [SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment WHERE Id = :otherAssignmentId]
                    .AssessmentQuestionSetId,
                'A Dynamic question can be moved into a preconfigured section'
            );
        }
    }

    private static Id createEoiQuestion(String name, Id sectionId, Id fundingOpportunityId) {
        return ApplicationFormCatalogueController.createFormQuestion(
            name, name + '?', 'Text', null, null, null, 255, false, null,
            sectionId, null, 1, fundingOpportunityId, false, null, null, true, null, null
        );
    }

    private static Decimal getSectionSequence(Id sectionId) {
        return [SELECT Sequence__c FROM AssessmentQuestionSet WHERE Id = :sectionId].Sequence__c;
    }

    @isTest
    static void createSectionForModeNumbersSectionsInsideTheirOwnMode() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();

            Test.startTest();
            // Full application (non-EOI) sections are numbered 1, 2, ...
            Id firstSectionId = ApplicationFormCatalogueController.createSectionForMode('Full 1', fundingOpportunityId, false);
            createDynamicQuestion('Full Q1', 'Full Q1?', 'Text', firstSectionId, fundingOpportunityId);
            Id secondSectionId = ApplicationFormCatalogueController.createSectionForMode('Full 2', fundingOpportunityId, false);
            createDynamicQuestion('Full Q2', 'Full Q2?', 'Text', secondSectionId, fundingOpportunityId);

            // EOI sections start again at 1 even though non-EOI sections already exist.
            Id firstEoiSectionId = ApplicationFormCatalogueController.createSectionForMode('Eoi 1', fundingOpportunityId, true);
            createEoiQuestion('Eoi Q1', firstEoiSectionId, fundingOpportunityId);
            Id secondEoiSectionId = ApplicationFormCatalogueController.createSectionForMode('Eoi 2', fundingOpportunityId, true);
            createEoiQuestion('Eoi Q2', secondEoiSectionId, fundingOpportunityId);

            // Each mode keeps counting on its own, and createSection defaults to the non-EOI mode.
            Id thirdSectionId = ApplicationFormCatalogueController.createSectionForMode('Full 3', fundingOpportunityId, false);
            createDynamicQuestion('Full Q3', 'Full Q3?', 'Text', thirdSectionId, fundingOpportunityId);
            Id defaultModeSectionId = ApplicationFormCatalogueController.createSection('Default mode', fundingOpportunityId);
            Test.stopTest();

            System.assertEquals(1, getSectionSequence(firstSectionId), 'The first non-EOI section starts at 1');
            System.assertEquals(2, getSectionSequence(secondSectionId), 'The second non-EOI section follows');
            System.assertEquals(1, getSectionSequence(firstEoiSectionId), 'The first EOI section starts again at 1');
            System.assertEquals(2, getSectionSequence(secondEoiSectionId), 'The second EOI section follows');
            System.assertEquals(3, getSectionSequence(thirdSectionId), 'A non-EOI section ignores the EOI sections');
            System.assertEquals(4, getSectionSequence(defaultModeSectionId), 'createSection numbers among non-EOI sections');
        }
    }

    @isTest
    static void createQuestionWithoutSequenceGoesAfterTheLastQuestionOfItsSection() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            Test.startTest();
            // Empty section: the first question starts at 1.
            Id firstQuestionId = ApplicationFormCatalogueController.createQuestion(
                'First', 'First?', 'Text', null, null, null, 255, false, null,
                sectionId, null, null, fundingOpportunityId, false, null, null
            );
            // Templates carry global numbers: the next question must come after the highest one.
            update new AssessmentQuestion(Id = firstQuestionId, Sequence__c = 15);
            Id secondQuestionId = ApplicationFormCatalogueController.createQuestion(
                'Second', 'Second?', 'Text', null, null, null, 255, false, null,
                sectionId, null, null, fundingOpportunityId, false, null, null
            );
            // An explicit sequence is still honored.
            Id explicitQuestionId = ApplicationFormCatalogueController.createQuestion(
                'Explicit', 'Explicit?', 'Text', null, null, null, 255, false, null,
                sectionId, null, 3, fundingOpportunityId, false, null, null
            );
            Test.stopTest();

            System.assertEquals(
                16,
                [SELECT Sequence__c FROM AssessmentQuestion WHERE Id = :secondQuestionId].Sequence__c,
                'A question without sequence goes after the highest one of its section'
            );
            System.assertEquals(
                3,
                [SELECT Sequence__c FROM AssessmentQuestion WHERE Id = :explicitQuestionId].Sequence__c,
                'An explicit sequence must be kept'
            );
        }
    }

    @isTest
    static void createQuestionWithoutSequenceStartsAtOneInAnEmptySection() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            Test.startTest();
            Id questionId = ApplicationFormCatalogueController.createQuestion(
                'Only', 'Only?', 'Text', null, null, null, 255, false, null,
                sectionId, null, null, fundingOpportunityId, false, null, null
            );
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT Sequence__c FROM AssessmentQuestion WHERE Id = :questionId].Sequence__c,
                'The first question of a section starts at 1'
            );
        }
    }

    private static Map<Id, Id> getAssignmentIdByQuestionId(Id fundingOpportunityId) {
        Map<Id, Id> assignmentIdByQuestionId = new Map<Id, Id>();
        for (AssessmentQuestionAssignment aqa : [
            SELECT Id, AssessmentQuestionId
            FROM AssessmentQuestionAssignment
            WHERE FundingOpportunity__c = :fundingOpportunityId
        ]) {
            assignmentIdByQuestionId.put(aqa.AssessmentQuestionId, aqa.Id);
        }
        return assignmentIdByQuestionId;
    }

    private static void setQuestionSequences(Map<Id, Decimal> sequenceByQuestionId) {
        List<AssessmentQuestion> questions = new List<AssessmentQuestion>();
        for (Id questionId : sequenceByQuestionId.keySet()) {
            questions.add(new AssessmentQuestion(Id = questionId, Sequence__c = sequenceByQuestionId.get(questionId)));
        }
        update questions;
    }

    private static Decimal getQuestionSequence(Id questionId) {
        return [SELECT Sequence__c FROM AssessmentQuestion WHERE Id = :questionId].Sequence__c;
    }

    @isTest
    static void reorderSectionsReusesTheExistingRangeOfNumbers() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id firstSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('First'), fundingOpportunityId);
            createDynamicQuestion('Q1', 'Q1?', 'Text', firstSectionId, fundingOpportunityId);
            Id secondSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Second'), fundingOpportunityId);
            createDynamicQuestion('Q2', 'Q2?', 'Text', secondSectionId, fundingOpportunityId);
            Id thirdSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Third'), fundingOpportunityId);
            createDynamicQuestion('Q3', 'Q3?', 'Text', thirdSectionId, fundingOpportunityId);
            update new List<AssessmentQuestionSet>{
                new AssessmentQuestionSet(Id = firstSectionId, Sequence__c = 4),
                new AssessmentQuestionSet(Id = secondSectionId, Sequence__c = 7),
                new AssessmentQuestionSet(Id = thirdSectionId, Sequence__c = 9)
            };

            Test.startTest();
            ApplicationFormCatalogueController.reorderSections(new List<Id>{ thirdSectionId, firstSectionId, secondSectionId });
            Test.stopTest();

            System.assertEquals(4, getSectionSequence(thirdSectionId), 'The first section takes the lowest number of the range');
            System.assertEquals(7, getSectionSequence(firstSectionId), 'The second section takes the next number of the range');
            System.assertEquals(9, getSectionSequence(secondSectionId), 'The third section takes the highest number of the range');
        }
    }

    @isTest
    static void reorderSectionsKeepsTheNumbersOfTheSectionsThatDidNotMove() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            List<Id> sectionIds = new List<Id>();
            for (Integer i = 1; i <= 5; i++) {
                Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section ' + i), fundingOpportunityId);
                createDynamicQuestion('Q' + i, 'Q' + i + '?', 'Text', sectionId, fundingOpportunityId);
                sectionIds.add(sectionId);
            }
            // Cloned sections carry the overlapping numbers of their templates (1, 1, 2) and the
            // numbers given to the sections created afterwards (9, 10).
            update new List<AssessmentQuestionSet>{
                new AssessmentQuestionSet(Id = sectionIds[0], Sequence__c = 1),
                new AssessmentQuestionSet(Id = sectionIds[1], Sequence__c = 1),
                new AssessmentQuestionSet(Id = sectionIds[2], Sequence__c = 2),
                new AssessmentQuestionSet(Id = sectionIds[3], Sequence__c = 9),
                new AssessmentQuestionSet(Id = sectionIds[4], Sequence__c = 10)
            };

            Test.startTest();
            // Only the last two sections swap their places.
            ApplicationFormCatalogueController.reorderSections(
                new List<Id>{ sectionIds[0], sectionIds[1], sectionIds[2], sectionIds[4], sectionIds[3] }
            );
            Test.stopTest();

            System.assertEquals(1, getSectionSequence(sectionIds[0]), 'A section that did not move keeps its number');
            System.assertEquals(1, getSectionSequence(sectionIds[1]), 'A section that did not move keeps its number');
            System.assertEquals(2, getSectionSequence(sectionIds[2]), 'A section that did not move keeps its number');
            System.assertEquals(9, getSectionSequence(sectionIds[4]), 'The swapped section takes the number 9');
            System.assertEquals(10, getSectionSequence(sectionIds[3]), 'The swapped section takes the number 10');
        }
    }

    @isTest
    static void reorderQuestionsReusesTheExistingRangeOfNumbers() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            Id firstQuestionId = createDynamicQuestion('Q1', 'Q1?', 'Text', sectionId, fundingOpportunityId);
            Id secondQuestionId = createDynamicQuestion('Q2', 'Q2?', 'Text', sectionId, fundingOpportunityId);
            Id thirdQuestionId = createDynamicQuestion('Q3', 'Q3?', 'Text', sectionId, fundingOpportunityId);
            setQuestionSequences(new Map<Id, Decimal>{ firstQuestionId => 10, secondQuestionId => 11, thirdQuestionId => 12 });
            Map<Id, Id> assignmentIdByQuestionId = getAssignmentIdByQuestionId(fundingOpportunityId);

            Test.startTest();
            ApplicationFormCatalogueController.reorderQuestions(new List<Id>{
                assignmentIdByQuestionId.get(thirdQuestionId),
                assignmentIdByQuestionId.get(firstQuestionId),
                assignmentIdByQuestionId.get(secondQuestionId)
            });
            Test.stopTest();

            System.assertEquals(10, getQuestionSequence(thirdQuestionId), 'The dragged question takes the first number');
            System.assertEquals(11, getQuestionSequence(firstQuestionId), 'The numbers stay in the 10 to 12 range');
            System.assertEquals(12, getQuestionSequence(secondQuestionId), 'The numbers stay in the 10 to 12 range');
        }
    }

    @isTest
    static void moveQuestionKeepsTheRangeOfNumbersOfTheTargetSection() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sourceSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Source'), fundingOpportunityId);
            Id movingQuestionId = createDynamicQuestion('Moving', 'Moving?', 'Text', sourceSectionId, fundingOpportunityId);
            Id remainingQuestionId = createDynamicQuestion('Remaining', 'Remaining?', 'Text', sourceSectionId, fundingOpportunityId);
            Id targetSectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Target'), fundingOpportunityId);
            Id firstTargetQuestionId = createDynamicQuestion('T1', 'T1?', 'Text', targetSectionId, fundingOpportunityId);
            Id secondTargetQuestionId = createDynamicQuestion('T2', 'T2?', 'Text', targetSectionId, fundingOpportunityId);
            Id thirdTargetQuestionId = createDynamicQuestion('T3', 'T3?', 'Text', targetSectionId, fundingOpportunityId);
            setQuestionSequences(new Map<Id, Decimal>{
                movingQuestionId => 3,
                remainingQuestionId => 4,
                firstTargetQuestionId => 10,
                secondTargetQuestionId => 11,
                thirdTargetQuestionId => 12
            });
            Map<Id, Id> assignmentIdByQuestionId = getAssignmentIdByQuestionId(fundingOpportunityId);

            Test.startTest();
            // Dropped between the first and the second question of the target section.
            ApplicationFormCatalogueController.moveQuestion(
                assignmentIdByQuestionId.get(movingQuestionId),
                targetSectionId,
                new List<Id>{
                    assignmentIdByQuestionId.get(firstTargetQuestionId),
                    assignmentIdByQuestionId.get(movingQuestionId),
                    assignmentIdByQuestionId.get(secondTargetQuestionId),
                    assignmentIdByQuestionId.get(thirdTargetQuestionId)
                }
            );
            Test.stopTest();

            // The old number of the moved question (3) stays out of the target section: its range
            // (10 to 12) is extended by one number instead.
            System.assertEquals(10, getQuestionSequence(firstTargetQuestionId), 'The question before the drop keeps its number');
            System.assertEquals(11, getQuestionSequence(movingQuestionId), 'The moved question takes the next number');
            System.assertEquals(12, getQuestionSequence(secondTargetQuestionId), 'The questions after the drop move down by one');
            System.assertEquals(13, getQuestionSequence(thirdTargetQuestionId), 'The questions after the drop move down by one');
            System.assertEquals(
                4,
                getQuestionSequence(remainingQuestionId),
                'The source section is left untouched'
            );
        }
    }

    @isTest
    static void reorderingIgnoresEmptyInput() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            Test.startTest();
            ApplicationFormCatalogueController.reorderSections(null);
            ApplicationFormCatalogueController.reorderSections(new List<Id>());
            ApplicationFormCatalogueController.reorderQuestions(null);
            ApplicationFormCatalogueController.reorderQuestions(new List<Id>());
            Test.stopTest();

            System.assertEquals(
                1,
                [SELECT Sequence__c FROM AssessmentQuestionSet WHERE Id = :sectionId].Sequence__c,
                'Reordering nothing should leave the existing sequence untouched'
            );
        }
    }

    @isTest
    static void assignmentOnASharedSectionStillAppearsInTheFundingOpportunityCatalog() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            AssessmentQuestionSet sharedSection = new AssessmentQuestionSet(
                Name = uniqueLabel('Shared Section '),
                DeveloperName = 'SharedSection' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
            );
            insert sharedSection;

            createDynamicQuestion('Q', 'Q?', 'Text', sharedSection.Id, fundingOpportunityId);

            List<ApplicationFormCatalogueController.SectionWrapper> catalog =
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId);
            System.assertEquals(1, catalog.size(), 'The shared section should be rebuilt from its assignment');
            System.assertEquals(sharedSection.Id, catalog[0].sectionId, 'Unexpected section Id');
            System.assertEquals(1, catalog[0].questions.size(), 'The question should be listed under the shared section');
        }
    }
    
    // Each case deliberately targets a deleted record (or an invalid value) so the controller's
    // generic catch block runs and prefixes the underlying platform error with its own context.
    private static void assertWrapped(
        String expectedContext,
        Id assignmentId,
        Id deletedSectionId,
        Id deletedQuestionId,
        Id liveSectionId,
        Integer scenario
    ) {
        try {
            if (scenario == 1) {
                ApplicationFormCatalogueController.removeQuestionAssignment(assignmentId, true);
            } else if (scenario == 2) {
                ApplicationFormCatalogueController.removeSectionAssignments(null, deletedSectionId, true);
            } else if (scenario == 3) {
                ApplicationFormCatalogueController.updateSection(deletedSectionId, 'Renamed');
            } else if (scenario == 4) {
                ApplicationFormCatalogueController.updateQuestion(
                    deletedQuestionId, 'Name', 'Text?', 'Text', null, null, null, 255, false, null, null, null
                );
            } else if (scenario == 5) {
                ApplicationFormCatalogueController.getQuestionForEdit(deletedQuestionId);
            } else if (scenario == 6) {
                ApplicationFormCatalogueController.moveQuestion(assignmentId, liveSectionId, null);
            } else if (scenario == 7) {
                ApplicationFormCatalogueController.reorderSections(new List<Id>{ deletedQuestionId });
            } else {
                // "!!!" yields an empty API name, which the platform rejects on insert.
                createDynamicQuestion('!!!', 'Q?', 'Text', liveSectionId, null);
            }
            System.assert(false, 'Expected an AuraHandledException for scenario ' + scenario);
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains(expectedContext),
                'Scenario ' + scenario + ' returned an unexpected message: ' + e.getMessage()
            );
        }
    }

    @isTest
    static void reorderQuestionsReportsADuplicateAssignment() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId);
            Id assignmentId = ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId)[0]
                .questions[0]
                .assignmentId;

            try {
                ApplicationFormCatalogueController.reorderQuestions(new List<Id>{ assignmentId, assignmentId });
                System.assert(false, 'Expected an AuraHandledException when the same assignment is listed twice');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Unable to reorder the questions'), e.getMessage());
            }
        }
    }

    @isTest
    static void requiredIdsAreValidated() {
        System.runAs(getTestUser()) {
            try {
                ApplicationFormCatalogueController.getFundingOpportunityCatalog(null);
                System.assert(false, 'Expected an AuraHandledException when the Funding Opportunity Id is missing');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Funding Opportunity is required'), e.getMessage());
            }
        }
    }

    @isTest
    static void getFormVersionByQuestionId_givenNoQuestion_returnsAnEmptyMap() {
        System.runAs(getTestUser()) {
            Map<Id, AssessmentQuestionVersion> versionsByQuestionId =
                ApplicationFormCatalogueQueryService.getFormVersionByQuestionId(new Set<Id>());

            System.assert(versionsByQuestionId.isEmpty(), 'No question means no version');
        }
    }

    @isTest
    static void getFormVersionByQuestionId_givenQuestion_returnsItsLatestVersion() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section A'), fundingOpportunityId);
            createDynamicQuestion('Question 1', 'Question 1 text?', 'Text', sectionId, fundingOpportunityId);
            Id questionId = ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId)[0]
                .questions[0]
                .questionId;

            Map<Id, AssessmentQuestionVersion> versionsByQuestionId =
                ApplicationFormCatalogueQueryService.getFormVersionByQuestionId(new Set<Id>{ questionId });

            System.assertEquals(1, versionsByQuestionId.size(), 'The question has one version');
            System.assertNotEquals(null, versionsByQuestionId.get(questionId).Id, 'The version is returned');
        }
    }

    @isTest
    static void getAnsweredVersionById_givenVersion_returnsTheLimitsOfItsQuestion() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section A'), fundingOpportunityId);
            createDynamicQuestion('Question 1', 'Question 1 text?', 'Text', sectionId, fundingOpportunityId);
            Id questionId = ApplicationFormCatalogueController.getFundingOpportunityCatalog(fundingOpportunityId)[0]
                .questions[0]
                .questionId;
            Id versionId = ApplicationFormCatalogueQueryService.getFormVersionByQuestionId(new Set<Id>{ questionId })
                .get(questionId)
                .Id;

            Map<Id, AssessmentQuestionVersion> versionsById =
                ApplicationFormCatalogueQueryService.getAnsweredVersionById(new Set<Id>{ versionId });

            System.assertEquals(1, versionsById.size(), 'The answered version is returned');
            System.assertEquals('Text', versionsById.get(versionId).AssessmentQuestion.DataType, 'The data type');
            System.assertEquals(
                255,
                versionsById.get(versionId).AssessmentQuestion.MaximumCharacters__c,
                'The maximum number of characters of the question'
            );
        }
    }

    private static Id createTranslatedSelectQuestion(Id sectionId, Id fundingOpportunityId, String responseValuesFr) {
        return ApplicationFormCatalogueController.createFormQuestion(
            null, 'Do you agree?', 'Select', null, 'Yes\nNo', null, null, false, null,
            sectionId, null, 1, fundingOpportunityId, false, null, null, false, 'Êtes-vous d\'accord ?', responseValuesFr
        );
    }

    private static Id createSelectQuestion(Id sectionId, Id fundingOpportunityId) {
        return ApplicationFormCatalogueController.createQuestion(
            null, 'Do you agree?', 'Select', null, 'Yes\nNo', null, null, false, null,
            sectionId, null, 1, fundingOpportunityId, false, null, null
        );
    }

    @isTest
    static void createQuestion_givenNoName_namesTheQuestionAfterItsText() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            Id questionId = createDynamicQuestion(null, 'What is   your\nproject title?', 'Text', sectionId, fundingOpportunityId);

            System.assertEquals(
                'What is your project title?',
                [SELECT Name FROM AssessmentQuestion WHERE Id = :questionId].Name,
                'The name is the question text on one line'
            );
        }
    }

    @isTest
    static void resolveQuestionName_givenNameOrLongText_returnsNameOrTruncatedText() {
        System.runAs(getTestUser()) {
            System.assertEquals(
                'Given name',
                ApplicationFormCatalogueController.resolveQuestionName('Given name', 'Question text?'),
                'A given name is kept'
            );
            System.assertEquals(
                80,
                ApplicationFormCatalogueController.resolveQuestionName(null, 'x'.repeat(120)).length(),
                'The name generated from a long text is truncated to 80 characters'
            );
        }
    }

    @isTest
    static void createFormQuestion_givenFrenchTextAndValues_savesThemOnTheActiveVersion() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);

            Id questionId = createTranslatedSelectQuestion(sectionId, fundingOpportunityId, 'Oui\nNon');

            ApplicationFormCatalogueController.QuestionDetailWrapper detail =
                ApplicationFormCatalogueController.getQuestionForEdit(questionId);
            System.assertEquals('Êtes-vous d\'accord ?', detail.questionTextFr, 'The French text is saved');
            System.assertEquals('Oui\nNon', detail.responseValuesFr, 'The French values are saved');
        }
    }

    @isTest
    static void createFormQuestion_givenDifferentValueCount_throwsAndCreatesNoQuestion() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            final Integer questionCountBefore = [SELECT COUNT() FROM AssessmentQuestion];

            try {
                createTranslatedSelectQuestion(sectionId, fundingOpportunityId, 'Oui\nNon\nPeut-être');
                System.assert(false, 'Expected an AuraHandledException for a different number of values');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('TRANSLATION_LINE_COUNT_MISMATCH'), e.getMessage());
            }
            System.assertEquals(
                questionCountBefore,
                [SELECT COUNT() FROM AssessmentQuestion],
                'A rejected translation creates no question'
            );
        }
    }

    @isTest
    static void updateQuestion_givenDifferentValueCount_throwsAndKeepsTheVersion() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            Id questionId = createTranslatedSelectQuestion(sectionId, fundingOpportunityId, 'Oui\nNon');

            try {
                ApplicationFormCatalogueController.updateQuestion(
                    questionId, null, 'Do you agree?', 'Select', null, 'Yes\nNo', null, null, false, null,
                    'Êtes-vous d\'accord ?', 'Oui'
                );
                System.assert(false, 'Expected an AuraHandledException for a different number of values');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('TRANSLATION_LINE_COUNT_MISMATCH'), e.getMessage());
            }
            System.assertEquals(
                1,
                [SELECT COUNT() FROM AssessmentQuestionVersion WHERE AssessmentQuestionId = :questionId],
                'A rejected translation creates no new version'
            );
        }
    }

    @isTest
    static void getQuestionForEdit_givenFrenchUserAndMissingId_throwsErrorCode() {
        final User frenchUser = new User(
            Alias = 'axafr',
            Email = 'axafr@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'AXAFrenchUser',
            LanguageLocaleKey = LanguageService.LANGUAGE_FRENCH,
            LocaleSidKey = 'fr_FR',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Europe/Paris',
            Username = 'axafr' + DateTime.now().getTime() + '@testorg.com'
        );
        insert frenchUser;

        System.runAs(frenchUser) {
            try {
                ApplicationFormCatalogueController.getQuestionForEdit(null);
                System.assert(false, 'Expected an AuraHandledException for a missing question Id');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('"code":"QUESTION_ID_REQUIRED"'), e.getMessage());
            }
        }
    }

    @isTest
    static void getQuestionForEdit_givenEnglishUserAndMissingId_throwsErrorCode() {
        System.runAs(getTestUser()) {
            try {
                ApplicationFormCatalogueController.getQuestionForEdit(null);
                System.assert(false, 'Expected an AuraHandledException for a missing question Id');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('"code":"QUESTION_ID_REQUIRED"'), e.getMessage());
            }
        }
    }

    @isTest
    static void updateQuestion_givenBlankTranslation_clearsTheTranslation() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            Id questionId = createTranslatedSelectQuestion(sectionId, fundingOpportunityId, 'Oui\nNon');

            ApplicationFormCatalogueController.updateQuestion(
                questionId, null, 'Do you agree?', 'Select', null, 'Yes\nNo', null, null, false, null, ' ', null
            );

            ApplicationFormCatalogueController.QuestionDetailWrapper detail =
                ApplicationFormCatalogueController.getQuestionForEdit(questionId);
            System.assertEquals(null, detail.questionTextFr, 'A blank French text clears the translation');
            System.assertEquals(null, detail.responseValuesFr, 'Blank French values clear the translation');
        }
    }

    @isTest
    static void isTranslationExpected_givenNullOrFundingOpportunity_throwsOrAnswers() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            System.assertNotEquals(
                null,
                ApplicationFormCatalogueController.isTranslationExpected(fundingOpportunityId),
                'The answer is true or false'
            );
            try {
                ApplicationFormCatalogueController.isTranslationExpected(null);
                System.assert(false, 'Expected an AuraHandledException without Funding Opportunity');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Funding Opportunity is required'), e.getMessage());
            }
        }
    }

    // ---- ApplicationFormCatalogueQueryService: preconfigured template and cleaning of cloned catalogues ----

    private static AssessmentQuestionAssignment createTemplateAssignment(String sectionName, String questionName) {
        AssessmentQuestionSet section = new AssessmentQuestionSet(
            Name = sectionName,
            DeveloperName = 'Tpl' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert section;
        AssessmentQuestion question = new AssessmentQuestion(
            Name = questionName,
            DeveloperName = 'Tpl' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            DataType = 'Text',
            QuestionCategory = 'Demographic',
            MaximumCharacters__c = 255,
            RecordTypeId = SchemaUtilities.getRecordTypeId(AssessmentQuestion.sObjectType, 'Dynamic'),
            Sequence__c = 1
        );
        insert question;
        insert new AssessmentQuestionVersion(
            Name = questionName,
            AssessmentQuestionId = question.Id,
            QuestionText = questionName + ' ?',
            IsActive = true
        );
        AssessmentQuestionAssignment templateAssignment = new AssessmentQuestionAssignment(
            AssessmentQuestionId = question.Id,
            AssessmentQuestionSetId = section.Id,
            EOI__c = false,
            IsMandatory__c = true
        );
        insert templateAssignment;
        return templateAssignment;
    }

    // The Funding Opportunity assignment reuses the section and the question of the template: they are preconfigured.
    private static AssessmentQuestionAssignment assignTemplateToFundingOpportunity(
        AssessmentQuestionAssignment templateAssignment,
        Id fundingOpportunityId
    ) {
        AssessmentQuestionAssignment assignment = new AssessmentQuestionAssignment(
            AssessmentQuestionId = templateAssignment.AssessmentQuestionId,
            AssessmentQuestionSetId = templateAssignment.AssessmentQuestionSetId,
            FundingOpportunity__c = fundingOpportunityId,
            EOI__c = false,
            IsMandatory__c = true
        );
        insert assignment;
        return assignment;
    }

    @isTest
    static void getPreconfiguredAssignmentIds_givenMissingInputs_returnsAnEmptySet() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();

            System.assert(
                ApplicationFormCatalogueQueryService.getPreconfiguredAssignmentIds(null, new Set<Id>()).isEmpty(),
                'No Funding Opportunity means nothing is preconfigured'
            );
            System.assert(
                ApplicationFormCatalogueQueryService.getPreconfiguredAssignmentIds(fundingOpportunityId, null).isEmpty(),
                'No assignment means nothing is preconfigured'
            );
            System.assert(
                ApplicationFormCatalogueQueryService.getPreconfiguredAssignmentIds(fundingOpportunityId, new Set<Id>())
                    .isEmpty(),
                'An empty set of assignments means nothing is preconfigured'
            );
        }
    }

    @isTest
    static void preconfiguredChecks_givenQuestionAndSectionOfTheTemplate_detectThem() {
        System.runAs(getTestUser()) {
            AssessmentQuestionAssignment templateAssignment = createTemplateAssignment('Socle Commun', 'Question Socle');
            Id fundingOpportunityId = createFundingOpportunity();
            AssessmentQuestionAssignment assignment = assignTemplateToFundingOpportunity(
                templateAssignment,
                fundingOpportunityId
            );

            System.assert(
                ApplicationFormCatalogueQueryService.getPreconfiguredAssignmentIds(
                    fundingOpportunityId,
                    new Set<Id>{ assignment.Id }
                ).contains(assignment.Id),
                'The assignment of a template question is preconfigured'
            );
            System.assert(
                ApplicationFormCatalogueQueryService.isPreconfiguredQuestion(assignment.AssessmentQuestionId),
                'The question of the template is preconfigured'
            );
            System.assert(
                ApplicationFormCatalogueQueryService.isPreconfiguredSection(
                    fundingOpportunityId,
                    assignment.AssessmentQuestionSetId
                ),
                'The section of the template is preconfigured'
            );
            System.assert(
                ApplicationFormCatalogueQueryService.matchesPreconfiguredQuestion(
                    fundingOpportunityId,
                    assignment.AssessmentQuestionSetId,
                    'Question Socle'
                ),
                'The question name of the template matches'
            );
            System.assert(
                !ApplicationFormCatalogueQueryService.matchesPreconfiguredQuestion(
                    fundingOpportunityId,
                    assignment.AssessmentQuestionSetId,
                    'Another question'
                ),
                'Another question name does not match'
            );

            List<ApplicationFormCatalogueController.SectionWrapper> catalog =
                ApplicationFormCatalogueQueryService.getCatalogSections(fundingOpportunityId);
            System.assertEquals(true, catalog[0].isPreconfigured, 'The catalog flags the preconfigured section');
            System.assertEquals(
                true,
                catalog[0].questions[0].isPreconfigured,
                'The catalog flags the preconfigured question'
            );
        }
    }

    @isTest
    static void isPreconfiguredQuestion_givenQuestionOfNoFundingOpportunity_returnsFalse() {
        System.runAs(getTestUser()) {
            AssessmentQuestionAssignment templateAssignment = createTemplateAssignment('Socle Commun', 'Question Socle');

            System.assert(
                !ApplicationFormCatalogueQueryService.isPreconfiguredQuestion(templateAssignment.AssessmentQuestionId),
                'A question assigned to no Funding Opportunity is not preconfigured'
            );
        }
    }

    @isTest
    static void deleteClonedCatalogues_givenNoCatalogue_doesNothing() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();

            ApplicationFormCatalogueQueryService.deleteClonedCatalogues(null);
            ApplicationFormCatalogueQueryService.deleteClonedCatalogues(new Set<Id>());
            ApplicationFormCatalogueQueryService.deleteClonedCatalogues(new Set<Id>{ fundingOpportunityId });

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestionAssignment WHERE FundingOpportunity__c = :fundingOpportunityId],
                'A Funding Opportunity without catalogue has nothing to delete'
            );
        }
    }

    @isTest
    static void deleteClonedCatalogues_givenCatalogueWithAnswers_deletesItsAssignmentsSectionsAndResponses() {
        System.runAs(getTestUser()) {
            Id fundingOpportunityId = createFundingOpportunity();
            Id sectionId = ApplicationFormCatalogueController.createSection(uniqueLabel('Section'), fundingOpportunityId);
            Id questionId = createDynamicQuestion('Q', 'Q?', 'Text', sectionId, fundingOpportunityId);
            Id versionId = ApplicationFormCatalogueQueryService.getFormVersionByQuestionId(new Set<Id>{ questionId })
                .get(questionId)
                .Id;
            ApplicationForm applicationForm = new ApplicationForm(
                ReferenceRecordId = fundingOpportunityId,
                UsageType = 'Grantmaking'
            );
            insert applicationForm;
            Assessment assessment = new Assessment(
                Name = 'Assessment ' + applicationForm.Id,
                AssessmentStatus = 'In Progress',
                ResponseContextId = applicationForm.Id
            );
            insert assessment;
            insert new AssessmentQuestionResponse(
                Name = 'Response ' + versionId,
                AssessmentId = assessment.Id,
                AssessmentQuestionId = versionId,
                ProjetRattache__c = applicationForm.Id,
                ResponseText = 'An answer'
            );

            Test.startTest();
            ApplicationFormCatalogueQueryService.deleteClonedCatalogues(new Set<Id>{ fundingOpportunityId });
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestionAssignment WHERE FundingOpportunity__c = :fundingOpportunityId],
                'The assignments of the Funding Opportunity are deleted'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestionResponse WHERE AssessmentQuestionId = :versionId],
                'The responses to its questions are deleted'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestionSet WHERE Id = :sectionId],
                'The section left without assignment is deleted'
            );
        }
    }

    @isTest
    static void deleteClonedCatalogues_givenSectionUsedByAnotherFundingOpportunity_keepsIt() {
        System.runAs(getTestUser()) {
            AssessmentQuestionAssignment templateAssignment = createTemplateAssignment('Socle Commun', 'Question Socle');
            Id firstFundingOpportunityId = createFundingOpportunity();
            Id secondFundingOpportunityId = createFundingOpportunity();
            assignTemplateToFundingOpportunity(templateAssignment, firstFundingOpportunityId);
            assignTemplateToFundingOpportunity(templateAssignment, secondFundingOpportunityId);
            // Creating a Funding Opportunity already clones the templates onto it: the count is read before.
            final Integer secondAssignmentCount = [
                SELECT COUNT()
                FROM AssessmentQuestionAssignment
                WHERE FundingOpportunity__c = :secondFundingOpportunityId
            ];

            Test.startTest();
            ApplicationFormCatalogueQueryService.deleteClonedCatalogues(new Set<Id>{ firstFundingOpportunityId });
            Test.stopTest();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM AssessmentQuestionAssignment WHERE FundingOpportunity__c = :firstFundingOpportunityId],
                'The assignments of the first Funding Opportunity are deleted'
            );
            System.assertEquals(
                secondAssignmentCount,
                [SELECT COUNT() FROM AssessmentQuestionAssignment WHERE FundingOpportunity__c = :secondFundingOpportunityId],
                'The assignments of the other Funding Opportunity are kept'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM AssessmentQuestionSet WHERE Id = :templateAssignment.AssessmentQuestionSetId],
                'A section still used by another assignment is kept'
            );
        }
    }
}