@isTest
private class FormulairePDFGenerationControllerTest {

    private static void createPdfTemplate() {
        ContentVersion cv = new ContentVersion(
            Title = Label.ApplicationFormPdfTemplateName,
            PathOnClient = Label.ApplicationFormPdfTemplateName + '.docx',
            VersionData = Blob.valueOf('template')
        );
        insert cv;
    }

    private static Id getTemplateContentVersionId() {
        return [SELECT Id FROM ContentVersion WHERE Title = :Label.ApplicationFormPdfTemplateName LIMIT 1].Id;
    }

    private static Id createFundingOpportunity() {
        Program program = new Program(Name = 'Test Program');
        insert program;
        FundingOpportunity fo = new FundingOpportunity(Name = 'Test FO', ProgramId = program.Id);
        insert fo;
        return fo.Id;
    }

    private static Id createApplicationForm(Id fundingOpportunityId) {
        ApplicationForm appForm = new ApplicationForm(UsageType = 'Grantmaking', ProgrammeRattache__c = fundingOpportunityId);
        insert appForm;
        return appForm.Id;
    }

    private static void markAssignmentAsEoi(Id questionId) {
        AssessmentQuestionAssignment assignment = [
            SELECT Id FROM AssessmentQuestionAssignment WHERE AssessmentQuestionId = :questionId LIMIT 1
        ];
        update new AssessmentQuestionAssignment(Id = assignment.Id, EOI__c = true);
    }

    private static Id createSection(String label, Id fundingOpportunityId) {
        AssessmentQuestionSet section = new AssessmentQuestionSet(
            Name = label,
            DeveloperName = label.replace(' ', '_')
        );
        insert section;
        return section.Id;
    }

    // Builds one question + active version + assignment directly (no dependency on
    // AP01_CatalogBuilderController/AP01_QuestionLifecycleService, which belong to a different
    // owner and aren't guaranteed to be present in every org this test deploys to).
    private static Id createQuestion(String name, String questionText, String dataType, Id sectionId,
            Decimal sequence, Id fundingOpportunityId, Boolean isFixed, String objectApiName, String fieldApiName) {
        Id recordTypeId = Schema.SObjectType.AssessmentQuestion.getRecordTypeInfosByDeveloperName()
            .get(isFixed == true ? 'Fixed' : 'Dynamic').getRecordTypeId();

        AssessmentQuestion question = new AssessmentQuestion(
            Name = name,
            DeveloperName = name.replace(' ', '_'),
            DataType = dataType,
            QuestionCategory = 'Demographic',
            RecordTypeId = recordTypeId,
            ObjectAPIName__c = isFixed == true ? objectApiName : null,
            FieldAPIName__c = isFixed == true ? fieldApiName : null,
            Sequence__c = sequence,
            MaximumCharacters__c = 200
        );
        insert question;

        AssessmentQuestionVersion version = new AssessmentQuestionVersion(
            Name = name,
            AssessmentQuestionId = question.Id,
            QuestionText = questionText,
            IsActive = true
        );
        insert version;

        insert new AssessmentQuestionAssignment(
            AssessmentQuestionId = question.Id,
            AssessmentQuestionSetId = sectionId,
            FundingOpportunity__c = fundingOpportunityId
        );

        return question.Id;
    }
    
    private static Id buildFormStructure(Id fundingOpportunityId) {
        Id sectionId = createSection('Section A', fundingOpportunityId);

        createQuestion(
            'Fixed Q', 'What is your phone number?', 'Telephone', sectionId, 1,
            fundingOpportunityId, true, 'Account', 'Phone'
        );

        Id dynamicQuestionId = createQuestion(
            'Dynamic Q', 'Describe your project', 'Text', sectionId, 2,
            fundingOpportunityId, false, null, null
        );

        return dynamicQuestionId;
    }

    @isTest
    static void testGetMergedFormJsonResolvesFixedAndResponseValues() {
        Id fundingOpportunityId = createFundingOpportunity();
        Id appFormId = createApplicationForm(fundingOpportunityId);

        Account acc = new Account(Name = 'Test Organization', Phone = '555-1234');
        insert acc;
        update new ApplicationForm(Id = appFormId, AccountId = acc.Id);

        Assessment assessment = new Assessment(
            Name = 'Test Assessment',
            AssessmentStatus = 'In Progress'
        );
        insert assessment;

        Id dynamicQuestionId = buildFormStructure(fundingOpportunityId);
        Id dynamicVersionId = [SELECT ActiveVersionId FROM AssessmentQuestion WHERE Id = :dynamicQuestionId].ActiveVersionId;

        insert new AssessmentQuestionResponse(
            Name = 'response',
            AssessmentId = assessment.Id,
            AssessmentQuestionId = dynamicVersionId,
            ProjetRattache__c = appFormId,
            ResponseText = 'My project description'

        );

        Test.startTest();
        FormulairePDFGenerationController.FormMetadata formData =
            FormulairePDFGenerationController.getMergedFormJson(appFormId, false);
        Test.stopTest();

        List<FormulairePDFGenerationController.SectionData> sections = formData.sections;
        Assert.areEqual(1, sections.size(), 'Expected exactly one section');
        Assert.areEqual('Section A', sections[0].sectionName, 'Unexpected section name');
        Assert.areEqual(2, sections[0].question.size(), 'Expected two questions in the section');

        FormulairePDFGenerationController.QuestionData fixedQuestion = sections[0].question[0];
        Assert.areEqual('What is your phone number?', fixedQuestion.label, 'Unexpected label for the Fixed question');
        Assert.areEqual('555-1234', fixedQuestion.value, 'Fixed question should resolve its value from the mapped Account field');

        FormulairePDFGenerationController.QuestionData dynamicQuestion = sections[0].question[1];
        Assert.areEqual('Describe your project', dynamicQuestion.label, 'Unexpected label for the Dynamic question');
        Assert.areEqual('My project description', dynamicQuestion.value, 'Dynamic question should resolve its value from the stored response');
    }

    @isTest
    static void testGetMergedFormJsonEoiOnlyFiltersAssignments() {
        Id fundingOpportunityId = createFundingOpportunity();
        Id appFormId = createApplicationForm(fundingOpportunityId);
        buildFormStructure(fundingOpportunityId);
        List<AssessmentQuestionAssignment> sectionAAssignments = [
            SELECT Id, AssessmentQuestionId FROM AssessmentQuestionAssignment
            WHERE FundingOpportunity__c = :fundingOpportunityId AND AssessmentQuestionSet.Name = 'Section A'
        ];
        for (AssessmentQuestionAssignment a : sectionAAssignments) {
            markAssignmentAsEoi(a.AssessmentQuestionId);
        }

        Id sectionId = createSection('Section B', fundingOpportunityId);
        createQuestion(
            'Full Only Q', 'Full form only question', 'Text', sectionId, 1,
            fundingOpportunityId, false, null, null
        );
        // Left with EOI__c = false (the default), so it must be excluded from the EOI-only view.

        Test.startTest();
        FormulairePDFGenerationController.FormMetadata formData =
            FormulairePDFGenerationController.getMergedFormJson(appFormId, true);
        Test.stopTest();

        List<FormulairePDFGenerationController.SectionData> eoiSections = formData.sections;
        Assert.areEqual(1, eoiSections.size(), 'Only the EOI-flagged section should be returned');
        Assert.areEqual('Section A', eoiSections[0].sectionName, 'Unexpected section returned for the EOI-only view');
    }

    @isTest
    static void testGetMergedFormJsonMissingResponseReturnsEmptyValue() {
        Id fundingOpportunityId = createFundingOpportunity();
        Id appFormId = createApplicationForm(fundingOpportunityId);
        buildFormStructure(fundingOpportunityId);

        Test.startTest();
        FormulairePDFGenerationController.FormMetadata formData =
            FormulairePDFGenerationController.getMergedFormJson(appFormId, false);
        Test.stopTest();

        FormulairePDFGenerationController.QuestionData dynamicQuestion = formData.sections[0].question[1];
        Assert.areEqual('', dynamicQuestion.value, 'A question with no stored response and no field mapping should resolve to an empty value');
    }

    @isTest
    static void testGeneratePdfCreatesDocumentGenerationProcess() {
        createPdfTemplate();
        Id fundingOpportunityId = createFundingOpportunity();
        Id appFormId = createApplicationForm(fundingOpportunityId);
        buildFormStructure(fundingOpportunityId);

        Test.startTest();
        Id docGenId = FormulairePDFGenerationController.generatePdf(appFormId, getTemplateContentVersionId(), false);
        Test.stopTest();

        Assert.areNotEqual(null, docGenId, 'Expected a DocumentGenerationProcess Id to be returned');
        DocumentGenerationProcess docGen = [
            SELECT Id, Type, ReferenceObject, DocGenApiVersionType, TokenDataContentDocumentId
            FROM DocumentGenerationProcess
            WHERE Id = :docGenId
        ];
        Assert.areEqual('GenerateAndConvert', docGen.Type, 'Unexpected document generation type');
        Assert.areEqual(appFormId, docGen.ReferenceObject, 'Unexpected reference object');
        Assert.areNotEqual(null, docGen.TokenDataContentDocumentId, 'A token data JSON file should have been uploaded');
    }

    @isTest
    static void testGeneratePdfForEoiUsesEoiTitleAndPrefix() {
        createPdfTemplate();
        Id fundingOpportunityId = createFundingOpportunity();
        Id appFormId = createApplicationForm(fundingOpportunityId);
        buildFormStructure(fundingOpportunityId);

        Test.startTest();
        Id docGenId = FormulairePDFGenerationController.generatePdf(appFormId, getTemplateContentVersionId(), true);
        Test.stopTest();

        DocumentGenerationProcess docGen = [SELECT RequestText FROM DocumentGenerationProcess WHERE Id = :docGenId];
        Assert.isTrue(docGen.RequestText.contains('EOI Form'), 'Expected the EOI title in the request payload: ' + docGen.RequestText);

        ContentVersion tokenFile = [
            SELECT Title FROM ContentVersion WHERE Title LIKE 'TokenData_EOI_%' ORDER BY CreatedDate DESC LIMIT 1
        ];
        Assert.isTrue(tokenFile.Title.startsWith('TokenData_EOI_'), 'Expected the token data file to use the EOI prefix');
    }
}