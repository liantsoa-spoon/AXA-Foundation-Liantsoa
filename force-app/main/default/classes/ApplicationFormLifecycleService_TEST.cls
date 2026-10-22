/**
 * @description       : Test class for ApplicationFormLifecycleService
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 08-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   08-10-2026   KRA      Initial version
 **/
@IsTest
private class ApplicationFormLifecycleService_TEST {
  private static final String RECORD_TYPE_FIXED = 'Fixed';

  @TestSetup
  static void setup() {
    TestDataFactory.createAdminUser(new List<String>{ 'AXA_Foundation_Admin', 'GrantmakingManager' });
  }

  @IsTest
  static void purgeOrphanedDraftQuestions_givenNoQuestionIds_deletesNothing() {
    TestDataFactory.createAssessmentQuestion('Question');

    Test.startTest();
    ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(null);
    ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(new Set<Id>());
    Test.stopTest();

    Assert.areEqual(1, countQuestions());
  }

  @IsTest
  static void purgeOrphanedDraftQuestions_givenOrphanDraftQuestion_deletesQuestionAndVersions() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id questionId = TestDataFactory.createAssessmentQuestion('Question').Id;
      insertVersion(questionId, 'First draft', false);
      insertVersion(questionId, 'Second draft', false);

      Test.startTest();
      ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(new Set<Id>{ questionId });
      Test.stopTest();

      Assert.areEqual(0, countQuestions());
      Assert.areEqual(0, countVersions());
    }
  }

  @IsTest
  static void purgeOrphanedDraftQuestions_givenOrphanQuestionWithoutVersion_deletesQuestion() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id questionId = TestDataFactory.createAssessmentQuestion('Question').Id;

      Test.startTest();
      ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(new Set<Id>{ questionId });
      Test.stopTest();

      Assert.areEqual(0, countQuestions());
    }
  }

  @IsTest
  static void purgeOrphanedDraftQuestions_givenAssignedQuestion_keepsIt() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id questionId = TestDataFactory.createAssessmentQuestion('Question').Id;
      insertVersion(questionId, 'Draft', false);
      TestDataFactory.createAssessmentQuestionAssignment(
        questionId,
        TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
        null,
        null,
        false
      );

      Test.startTest();
      ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(new Set<Id>{ questionId });
      Test.stopTest();

      Assert.areEqual(1, countQuestions());
      Assert.areEqual(1, countVersions());
    }
  }

  @IsTest
  static void purgeOrphanedDraftQuestions_givenOrphanQuestionWithActiveVersion_keepsIt() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id questionId = TestDataFactory.createAssessmentQuestion('Question').Id;
      insertVersion(questionId, 'Draft', false);
      insertVersion(questionId, 'Active', true);

      Test.startTest();
      ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(new Set<Id>{ questionId });
      Test.stopTest();

      Assert.areEqual(1, countQuestions());
      Assert.areEqual(2, countVersions());
    }
  }

  @IsTest
  static void updateMandatoryStatus_givenFalse_marksQuestionOptional() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id questionId = TestDataFactory.createAssessmentQuestion('Question').Id;
      final Id questionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        questionId,
        TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
        null,
        null,
        false
      ).Id;

      Test.startTest();
      ApplicationFormLifecycleService.updateMandatoryStatus(questionId, false);
      Test.stopTest();

      Assert.isFalse(queryIsMandatory(questionAssignmentId));
    }
  }

  @IsTest
  static void updateMandatoryStatus_givenNull_marksQuestionMandatory() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id questionId = TestDataFactory.createAssessmentQuestion('Question').Id;
      final Id questionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        questionId,
        TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
        null,
        null,
        false
      ).Id;
      update new AssessmentQuestionAssignment(Id = questionAssignmentId, IsMandatory__c = false);

      Test.startTest();
      ApplicationFormLifecycleService.updateMandatoryStatus(questionId, null);
      Test.stopTest();

      Assert.isTrue(queryIsMandatory(questionAssignmentId));
    }
  }

  @IsTest
  static void updateMandatoryStatus_givenUnassignedQuestion_keepsOtherAssignmentsUnchanged() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id otherQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Assigned').Id,
        TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
        null,
        null,
        false
      ).Id;
      final Id unassignedQuestionId = TestDataFactory.createAssessmentQuestion('Unassigned').Id;

      Test.startTest();
      ApplicationFormLifecycleService.updateMandatoryStatus(unassignedQuestionId, false);
      Test.stopTest();

      Assert.isTrue(queryIsMandatory(otherQuestionAssignmentId));
    }
  }

  @IsTest
  static void serializeTableColumns_givenNoTable_returnsNull() {
    final ApplicationFormCatalogueController.ColumnWrapper column =
      new ApplicationFormCatalogueController.ColumnWrapper();
    column.label = 'Amount';
    final List<ApplicationFormCatalogueController.ColumnWrapper> columns =
      new List<ApplicationFormCatalogueController.ColumnWrapper>{ column };

    Assert.isNull(ApplicationFormLifecycleService.serializeTableColumns(false, columns));
    Assert.isNull(ApplicationFormLifecycleService.serializeTableColumns(null, columns));
  }

  @IsTest
  static void serializeTableColumns_givenNoColumns_returnsNull() {
    Assert.isNull(ApplicationFormLifecycleService.serializeTableColumns(true, null));
    Assert.isNull(
      ApplicationFormLifecycleService.serializeTableColumns(
        true,
        new List<ApplicationFormCatalogueController.ColumnWrapper>()
      )
    );
  }

  @IsTest
  static void serializeTableColumns_givenOnlyBlankLabels_returnsNull() {
    final ApplicationFormCatalogueController.ColumnWrapper column =
      new ApplicationFormCatalogueController.ColumnWrapper();
    column.label = ' ';

    Assert.isNull(
      ApplicationFormLifecycleService.serializeTableColumns(
        true,
        new List<ApplicationFormCatalogueController.ColumnWrapper>{ column }
      )
    );
  }

  @IsTest
  static void serializeTableColumns_givenColumns_serializesLabelledColumnsWithDeveloperNames() {
    final ApplicationFormCatalogueController.ColumnWrapper namedColumn =
      new ApplicationFormCatalogueController.ColumnWrapper();
    namedColumn.label = 'Amount';
    namedColumn.developerName = 'TotalAmount';
    final ApplicationFormCatalogueController.ColumnWrapper unnamedColumn =
      new ApplicationFormCatalogueController.ColumnWrapper();
    unnamedColumn.label = 'Start date';

    final List<ApplicationFormCatalogueController.ColumnWrapper> serializedColumns =
      (List<ApplicationFormCatalogueController.ColumnWrapper>) JSON.deserialize(
        ApplicationFormLifecycleService.serializeTableColumns(
          true,
          new List<ApplicationFormCatalogueController.ColumnWrapper>{
            namedColumn,
            unnamedColumn,
            new ApplicationFormCatalogueController.ColumnWrapper()
          }
        ),
        List<ApplicationFormCatalogueController.ColumnWrapper>.class
      );

    Assert.areEqual(2, serializedColumns.size());
    Assert.areEqual('TotalAmount', serializedColumns[0].developerName);
    Assert.areEqual('StartDate', serializedColumns[1].developerName);
  }

  @IsTest
  static void toDeveloperName_givenBlankLabel_returnsGeneratedName() {
    Assert.isTrue(ApplicationFormLifecycleService.toDeveloperName(null).startsWith('Item'));
    Assert.isTrue(ApplicationFormLifecycleService.toDeveloperName(' ').startsWith('Item'));
  }

  @IsTest
  static void toDeveloperName_givenLabel_returnsPascalCase() {
    Assert.areEqual('ProjectBudgetTotal', ApplicationFormLifecycleService.toDeveloperName('project budget (TOTAL)'));
  }

  @IsTest
  static void toDeveloperName_givenLeadingDigit_prefixesWithQ() {
    Assert.areEqual('Q2ndQuestion', ApplicationFormLifecycleService.toDeveloperName('2nd question'));
  }

  @IsTest
  static void toDeveloperName_givenNoAlphanumericCharacter_returnsEmptyString() {
    Assert.areEqual('', ApplicationFormLifecycleService.toDeveloperName('- ?'));
  }

  @IsTest
  static void toDeveloperName_givenLongLabel_truncatesToMaximumLength() {
    final Integer developerNameMaxLength = ApplicationFormLifecycleService.DEVELOPER_NAME_MAX_LENGTH;

    Assert.areEqual(
      developerNameMaxLength,
      ApplicationFormLifecycleService.toDeveloperName('word '.repeat(developerNameMaxLength)).length()
    );
  }

  @IsTest
  static void cloneTemplateQuestionCataloguesToFundingOpportunities_givenNoFundingOpportunityIds_createsNothing() {
    TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Template').Id,
      TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
      null,
      null,
      false
    );

    Test.startTest();
    ApplicationFormLifecycleService.cloneTemplateQuestionCataloguesToFundingOpportunities(null);
    ApplicationFormLifecycleService.cloneTemplateQuestionCataloguesToFundingOpportunities(new Set<Id>());
    Test.stopTest();

    Assert.areEqual(1, countQuestions());
  }

  @IsTest
  static void cloneTemplateQuestionCataloguesToFundingOpportunities_givenUnknownIds_createsNothing() {
    TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Template').Id,
      TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
      null,
      null,
      false
    );
    final Id programId = TestDataFactory.createPillar('Pillar').Id;

    Test.startTest();
    ApplicationFormLifecycleService.cloneTemplateQuestionCataloguesToFundingOpportunities(new Set<Id>{ programId });
    Test.stopTest();

    Assert.areEqual(1, countQuestions());
  }

  @IsTest
  static void cloneTemplateQuestionCataloguesToFundingOpportunities_givenNoTemplates_createsNothing() {
    final Id programId  = TestDataFactory.createPillar('Pillar').Id;
    final Id targetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
      FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
      programId
    ).Id;

    Test.startTest();
    ApplicationFormLifecycleService.cloneTemplateQuestionCataloguesToFundingOpportunities(new Set<Id>{ targetFOId });
    Test.stopTest();

    Assert.areEqual(0, queryClonedQuestionAssignments(targetFOId).size());
  }

  @IsTest
  static void cloneTemplateQuestionCataloguesToFundingOpportunities_givenPrograms_clonesCommonAndOwnProgramTemplates() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final RecordTypeProvider.RecordTypeReference callForProjectsRecordType =
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS;
      final Id firstProgramId   = TestDataFactory.createPillar('First pillar').Id;
      final Id secondProgramId  = TestDataFactory.createPillar('Second pillar').Id;
      final Id emptyProgramId   = TestDataFactory.createPillar('Empty pillar').Id;
      final Id firstProgramFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        firstProgramId
      ).Id;
      final Id emptyProgramFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        emptyProgramId
      ).Id;
      final Id sectionId = TestDataFactory.createAssessmentQuestionSet('Section', 1).Id;
      TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Common').Id,
        sectionId,
        null,
        null,
        false
      );
      TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('First pillar').Id,
        sectionId,
        null,
        firstProgramId,
        false
      );
      TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Second pillar').Id,
        sectionId,
        null,
        secondProgramId,
        false
      );

      Test.startTest();
      ApplicationFormLifecycleService.cloneTemplateQuestionCataloguesToFundingOpportunities(
        new Set<Id>{ firstProgramFOId, emptyProgramFOId }
      );
      Test.stopTest();

      final List<AssessmentQuestionAssignment> firstProgramQuestionAssignments =
        queryClonedQuestionAssignments(firstProgramFOId);
      Assert.areEqual(2, firstProgramQuestionAssignments.size());
      Assert.areEqual('Common', firstProgramQuestionAssignments[0].AssessmentQuestion.Name);
      Assert.areEqual('First pillar', firstProgramQuestionAssignments[1].AssessmentQuestion.Name);

      final List<AssessmentQuestionAssignment> emptyProgramQuestionAssignments =
        queryClonedQuestionAssignments(emptyProgramFOId);
      Assert.areEqual(1, emptyProgramQuestionAssignments.size());
      Assert.areEqual('Common', emptyProgramQuestionAssignments[0].AssessmentQuestion.Name);
    }
  }

  @IsTest
  static void cloneTemplateQuestionCataloguesToFundingOpportunities_givenRecordTypes_clonesEOITemplatesToCallForProjectsOnly() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId = TestDataFactory.createPillar('Pillar').Id;
      final Id callForProjectsFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
        programId
      ).Id;
      final Id directManagementFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT,
        programId
      ).Id;
      final Id sectionId = TestDataFactory.createAssessmentQuestionSet('Section', 1).Id;
      TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Common EOI').Id,
        sectionId,
        null,
        null,
        true
      );
      TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Common full application').Id,
        sectionId,
        null,
        null,
        false
      );
      TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Pillar EOI').Id,
        sectionId,
        null,
        programId,
        true
      );
      TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Pillar full application').Id,
        sectionId,
        null,
        programId,
        false
      );

      Test.startTest();
      ApplicationFormLifecycleService.cloneTemplateQuestionCataloguesToFundingOpportunities(
        new Set<Id>{ callForProjectsFOId, directManagementFOId }
      );
      Test.stopTest();

      Assert.areEqual(4, queryClonedQuestionAssignments(callForProjectsFOId).size());
      final List<AssessmentQuestionAssignment> directManagementQuestionAssignments =
        queryClonedQuestionAssignments(directManagementFOId);
      Assert.areEqual(2, directManagementQuestionAssignments.size());
      Assert.areEqual('Common full application', directManagementQuestionAssignments[0].AssessmentQuestion.Name);
      Assert.areEqual('Pillar full application', directManagementQuestionAssignments[1].AssessmentQuestion.Name);
    }
  }

  @IsTest
  static void queryTemplateQuestionAssignmentIdsByIsEOIByProgramId_givenNoProgramIds_returnsEmptyCommonSets() {
    TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Common EOI').Id,
      TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
      null,
      null,
      true
    );

    Test.startTest();
    final Map<Boolean, Map<Id, Set<Id>>> templateQuestionAssignmentIdsByIsEOIByProgramId =
      ApplicationFormLifecycleService.queryTemplateQuestionAssignmentIdsByIsEOIByProgramId(new Set<Id>());
    Test.stopTest();

    Assert.isTrue(templateQuestionAssignmentIdsByIsEOIByProgramId.get(true).get(null).isEmpty());
    Assert.isTrue(templateQuestionAssignmentIdsByIsEOIByProgramId.get(false).get(null).isEmpty());
  }

  @IsTest
  static void queryTemplateQuestionAssignmentIdsByIsEOIByProgramId_givenProgramIds_splitsTemplatesByEOIAndProgram() {
    final Id programId      = TestDataFactory.createPillar('Pillar').Id;
    final Id emptyProgramId = TestDataFactory.createPillar('Empty pillar').Id;
    final Id sectionId = TestDataFactory.createAssessmentQuestionSet('Section', 1).Id;
    final Id commonEOITemplateQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Common EOI').Id,
      sectionId,
      null,
      null,
      true
    ).Id;
    final Id programEOITemplateQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Pillar EOI').Id,
      sectionId,
      null,
      programId,
      true
    ).Id;
    final Id commonFullApplicationTemplateQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Common full application').Id,
      sectionId,
      null,
      null,
      false
    ).Id;
    final Id programFullApplicationTemplateQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Pillar full application').Id,
      sectionId,
      null,
      programId,
      false
    ).Id;
    TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Other pillar EOI').Id,
      sectionId,
      null,
      TestDataFactory.createPillar('Other pillar').Id,
      true
    );

    Test.startTest();
    final Map<Boolean, Map<Id, Set<Id>>> templateQuestionAssignmentIdsByIsEOIByProgramId =
      ApplicationFormLifecycleService.queryTemplateQuestionAssignmentIdsByIsEOIByProgramId(
        new Set<Id>{ programId, emptyProgramId }
      );
    Test.stopTest();

    final Map<Id, Set<Id>> EOITemplateQuestionAssignmentIdsByProgramId =
      templateQuestionAssignmentIdsByIsEOIByProgramId.get(true);
    final Map<Id, Set<Id>> fullApplicationTemplateQuestionAssignmentIdsByProgramId =
      templateQuestionAssignmentIdsByIsEOIByProgramId.get(false);
    Assert.areEqual(
      new Set<Id>{ commonEOITemplateQuestionAssignmentId },
      EOITemplateQuestionAssignmentIdsByProgramId.get(null)
    );
    Assert.areEqual(
      new Set<Id>{ programEOITemplateQuestionAssignmentId },
      EOITemplateQuestionAssignmentIdsByProgramId.get(programId)
    );
    Assert.isTrue(EOITemplateQuestionAssignmentIdsByProgramId.get(emptyProgramId).isEmpty());
    Assert.areEqual(
      new Set<Id>{ commonFullApplicationTemplateQuestionAssignmentId },
      fullApplicationTemplateQuestionAssignmentIdsByProgramId.get(null)
    );
    Assert.areEqual(
      new Set<Id>{ programFullApplicationTemplateQuestionAssignmentId },
      fullApplicationTemplateQuestionAssignmentIdsByProgramId.get(programId)
    );
    Assert.isTrue(fullApplicationTemplateQuestionAssignmentIdsByProgramId.get(emptyProgramId).isEmpty());
  }

  // ============================== <Clone engine> ==============================

  @IsTest
  static void cloneQuestionCataloguesToFundingOpportunities_givenNoQuestionAssignmentIds_createsNothing() {
    final Id programId  = TestDataFactory.createPillar('Pillar').Id;
    final Id targetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
      FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
      programId
    ).Id;

    Test.startTest();
    ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(null);
    ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(new Map<Id, Set<Id>>());
    ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
      new Map<Id, Set<Id>>{ targetFOId => null }
    );
    ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
      new Map<Id, Set<Id>>{ targetFOId => new Set<Id>() }
    );
    Test.stopTest();

    Assert.areEqual(0, countQuestions());
    Assert.areEqual(0, countSections());
  }

  @IsTest
  static void cloneQuestionCataloguesToFundingOpportunities_givenDeletedQuestionAssignment_createsNothing() {
    final Id programId  = TestDataFactory.createPillar('Pillar').Id;
    final Id targetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
      FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
      programId
    ).Id;
    final Id deletedQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion('Deleted').Id,
      TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
      null,
      null,
      false
    ).Id;
    delete new AssessmentQuestionAssignment(Id = deletedQuestionAssignmentId);

    Test.startTest();
    ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
      new Map<Id, Set<Id>>{ targetFOId => new Set<Id>{ deletedQuestionAssignmentId } }
    );
    Test.stopTest();

    Assert.areEqual(0, queryClonedQuestionAssignments(targetFOId).size());
  }

  @IsTest
  static void cloneQuestionCataloguesToFundingOpportunities_givenSourceQuestions_clonesWholeCatalogue() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final RecordTypeProvider.RecordTypeReference callForProjectsRecordType =
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS;
      final Id programId  = TestDataFactory.createPillar('Pillar').Id;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        programId
      ).Id;
      final Id targetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        programId
      ).Id;
      final Id firstSectionId  = TestDataFactory.createAssessmentQuestionSet('First section', 1).Id;
      final Id secondSectionId = TestDataFactory.createAssessmentQuestionSet('Second section', 2).Id;

      final AssessmentQuestion fixedQuestion = new AssessmentQuestion(
        Name                 = 'A fixed question',
        DeveloperName        = TestDataFactory.buildUniqueDeveloperName('FixedQuestion'),
        DataType             = TestDataFactory.ASSESSMENT_QUESTION_DATA_TYPE_TEXT,
        QuestionCategory     = TestDataFactory.ASSESSMENT_QUESTION_QUESTION_CATEGORY_DEMOGRAPHIC,
        RecordTypeId         =
          new RecordTypeProvider.RecordTypeReference(AssessmentQuestion.SObjectType, RECORD_TYPE_FIXED).Id,
        ObjectAPIName__c     = 'Contact',
        FieldAPIName__c      = 'LastName',
        MaximumCharacters__c = 80,
        Sequence__c          = 3
      );
      insert fixedQuestion;
      final AssessmentQuestionVersion fixedVersion = new AssessmentQuestionVersion(
        Name                  = 'A fixed question',
        AssessmentQuestionId  = fixedQuestion.Id,
        QuestionText          = 'What is your last name?',
        QuestionTextFR__c     = 'Quel est votre nom ?',
        Description           = 'Description',
        ResponseValues        = 'Value',
        ResponseValuesFR__c   = 'Valeur',
        HelpText              = 'Help',
        AdditionalInformation = 'Information',
        IsActive              = true
      );
      insert fixedVersion;
      final AssessmentQuestionAssignment fixedQuestionAssignment = new AssessmentQuestionAssignment(
        AssessmentQuestionId    = fixedQuestion.Id,
        AssessmentQuestionSetId = firstSectionId,
        FundingOpportunity__c   = sourceFOId,
        EOI__c                  = true,
        IsMandatory__c          = false
      );
      insert fixedQuestionAssignment;
      final Id versionlessQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('B versionless question').Id,
        secondSectionId,
        sourceFOId,
        null,
        false
      ).Id;

      Test.startTest();
      ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
        new Map<Id, Set<Id>>{
          targetFOId => new Set<Id>{ fixedQuestionAssignment.Id, versionlessQuestionAssignmentId }
        }
      );
      Test.stopTest();

      final List<AssessmentQuestionAssignment> clonedQuestionAssignments = queryClonedQuestionAssignments(targetFOId);
      Assert.areEqual(2, clonedQuestionAssignments.size());

      final AssessmentQuestionAssignment clonedFixedQuestionAssignment = clonedQuestionAssignments[0];
      final AssessmentQuestionSet clonedFirstSection = clonedFixedQuestionAssignment.AssessmentQuestionSet;
      final AssessmentQuestion clonedFixedQuestion   = clonedFixedQuestionAssignment.AssessmentQuestion;
      final String expectedDeveloperNameSuffix = '_' + targetFOId + '_0';
      Assert.areNotEqual(firstSectionId, clonedFixedQuestionAssignment.AssessmentQuestionSetId);
      Assert.areNotEqual(fixedQuestion.Id, clonedFixedQuestionAssignment.AssessmentQuestionId);
      Assert.isTrue(clonedFixedQuestionAssignment.EOI__c);
      Assert.isFalse(clonedFixedQuestionAssignment.IsMandatory__c);
      Assert.areEqual('First section', clonedFirstSection.Name);
      Assert.areEqual(1, clonedFirstSection.Sequence__c);
      Assert.isTrue(clonedFirstSection.DeveloperName.endsWith(expectedDeveloperNameSuffix));
      Assert.areEqual('A fixed question', clonedFixedQuestion.Name);
      Assert.isTrue(clonedFixedQuestion.DeveloperName.endsWith(expectedDeveloperNameSuffix));
      Assert.areEqual(TestDataFactory.ASSESSMENT_QUESTION_DATA_TYPE_TEXT, clonedFixedQuestion.DataType);
      Assert.areEqual(
        TestDataFactory.ASSESSMENT_QUESTION_QUESTION_CATEGORY_DEMOGRAPHIC,
        clonedFixedQuestion.QuestionCategory
      );
      Assert.areEqual(fixedQuestion.RecordTypeId, clonedFixedQuestion.RecordTypeId);
      Assert.areEqual('Contact', clonedFixedQuestion.ObjectAPIName__c);
      Assert.areEqual('LastName', clonedFixedQuestion.FieldAPIName__c);
      Assert.areEqual(80, clonedFixedQuestion.MaximumCharacters__c);
      Assert.areEqual(3, clonedFixedQuestion.Sequence__c);

      final AssessmentQuestionVersion clonedFixedVersion = queryVersion(clonedFixedQuestion.Id);
      Assert.areEqual(fixedVersion.QuestionText, clonedFixedVersion.QuestionText);
      Assert.areEqual(fixedVersion.QuestionTextFR__c, clonedFixedVersion.QuestionTextFR__c);
      Assert.areEqual(fixedVersion.Description, clonedFixedVersion.Description);
      Assert.areEqual(fixedVersion.ResponseValues, clonedFixedVersion.ResponseValues);
      Assert.areEqual(fixedVersion.ResponseValuesFR__c, clonedFixedVersion.ResponseValuesFR__c);
      Assert.areEqual(fixedVersion.HelpText, clonedFixedVersion.HelpText);
      Assert.areEqual(fixedVersion.AdditionalInformation, clonedFixedVersion.AdditionalInformation);
      Assert.isTrue(clonedFixedVersion.IsActive);

      final AssessmentQuestionAssignment clonedVersionlessQuestionAssignment = clonedQuestionAssignments[1];
      Assert.areEqual('Second section', clonedVersionlessQuestionAssignment.AssessmentQuestionSet.Name);
      Assert.areEqual(2, clonedVersionlessQuestionAssignment.AssessmentQuestionSet.Sequence__c);
      Assert.isTrue(clonedVersionlessQuestionAssignment.IsMandatory__c);
      Assert.areEqual(
        'B versionless question',
        queryVersion(clonedVersionlessQuestionAssignment.AssessmentQuestionId).QuestionText
      );
    }
  }

  @IsTest
  static void cloneQuestionCataloguesToFundingOpportunities_givenSeveralVersions_clonesActiveVersion() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId  = TestDataFactory.createPillar('Pillar').Id;
      final Id targetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
        programId
      ).Id;
      final Id questionId = TestDataFactory.createAssessmentQuestion('Question').Id;
      insertVersion(questionId, 'Active text', true);
      insertVersion(questionId, 'Draft text', false);
      final Id questionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        questionId,
        TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
        null,
        null,
        false
      ).Id;

      Test.startTest();
      ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
        new Map<Id, Set<Id>>{ targetFOId => new Set<Id>{ questionAssignmentId } }
      );
      Test.stopTest();

      Assert.areEqual(
        'Active text',
        queryVersion(queryClonedQuestionAssignments(targetFOId)[0].AssessmentQuestionId).QuestionText
      );
    }
  }

  @IsTest
  static void cloneQuestionCataloguesToFundingOpportunities_givenDuplicateNames_clonesEachSectionAndQuestionOnce() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId  = TestDataFactory.createPillar('Pillar').Id;
      final Id targetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
        programId
      ).Id;
      final Set<Id> questionAssignmentIds = new Set<Id>();
      for (String questionName : new List<String>{ 'Question', 'Question', 'Other question' }) {
        questionAssignmentIds.add(
          TestDataFactory.createAssessmentQuestionAssignment(
            TestDataFactory.createAssessmentQuestion(questionName).Id,
            TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
            null,
            null,
            false
          ).Id
        );
      }

      Test.startTest();
      ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
        new Map<Id, Set<Id>>{ targetFOId => questionAssignmentIds }
      );
      Test.stopTest();

      final List<AssessmentQuestionAssignment> clonedQuestionAssignments = queryClonedQuestionAssignments(targetFOId);
      Assert.areEqual(2, clonedQuestionAssignments.size());
      Assert.areEqual(
        clonedQuestionAssignments[0].AssessmentQuestionSetId,
        clonedQuestionAssignments[1].AssessmentQuestionSetId
      );
    }
  }

  @IsTest
  static void cloneQuestionCataloguesToFundingOpportunities_givenSeveralTargets_clonesOwnQuestionsToEachTarget() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final RecordTypeProvider.RecordTypeReference callForProjectsRecordType =
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS;
      final Id programId = TestDataFactory.createPillar('Pillar').Id;
      final Id firstTargetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        programId
      ).Id;
      final Id secondTargetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        programId
      ).Id;
      final Id emptyTargetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        programId
      ).Id;
      final Id sectionId = TestDataFactory.createAssessmentQuestionSet('Section', 1).Id;
      final Id commonQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Common').Id,
        sectionId,
        null,
        null,
        false
      ).Id;
      final Id specificQuestionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Specific').Id,
        sectionId,
        null,
        null,
        false
      ).Id;

      Test.startTest();
      ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
        new Map<Id, Set<Id>>{
          firstTargetFOId  => new Set<Id>{ commonQuestionAssignmentId },
          secondTargetFOId => new Set<Id>{ commonQuestionAssignmentId, specificQuestionAssignmentId },
          emptyTargetFOId  => null
        }
      );
      Test.stopTest();

      final List<AssessmentQuestionAssignment> firstTargetQuestionAssignments  =
        queryClonedQuestionAssignments(firstTargetFOId);
      final List<AssessmentQuestionAssignment> secondTargetQuestionAssignments =
        queryClonedQuestionAssignments(secondTargetFOId);
      Assert.areEqual(1, firstTargetQuestionAssignments.size());
      Assert.areEqual(2, secondTargetQuestionAssignments.size());
      Assert.areEqual(0, queryClonedQuestionAssignments(emptyTargetFOId).size());
      Assert.areNotEqual(
        firstTargetQuestionAssignments[0].AssessmentQuestionSetId,
        secondTargetQuestionAssignments[0].AssessmentQuestionSetId
      );
    }
  }

  @IsTest
  static void cloneQuestionCataloguesToFundingOpportunities_givenLongNames_keepsDeveloperNamesWithinLimit() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId  = TestDataFactory.createPillar('Pillar').Id;
      final Id targetFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
        programId
      ).Id;
      final String longName = 'Describe the initial situation of the children who benefit from your project '
        + 'and the vulnerabilities you have identified';
      final Id questionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion(longName).Id,
        TestDataFactory.createAssessmentQuestionSet(longName, 1).Id,
        null,
        null,
        false
      ).Id;

      Test.startTest();
      ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
        new Map<Id, Set<Id>>{ targetFOId => new Set<Id>{ questionAssignmentId } }
      );
      Test.stopTest();

      final AssessmentQuestionAssignment clonedQuestionAssignment = queryClonedQuestionAssignments(targetFOId)[0];
      final String questionDeveloperName = clonedQuestionAssignment.AssessmentQuestion.DeveloperName;
      final String sectionDeveloperName  = clonedQuestionAssignment.AssessmentQuestionSet.DeveloperName;
      final Integer developerNameMaxLength     = ApplicationFormLifecycleService.DEVELOPER_NAME_MAX_LENGTH;
      final String expectedDeveloperNameSuffix = '_' + targetFOId + '_0';
      Assert.areEqual(developerNameMaxLength, questionDeveloperName.length());
      Assert.isTrue(questionDeveloperName.endsWith(expectedDeveloperNameSuffix));
      Assert.areEqual(developerNameMaxLength, sectionDeveloperName.length());
      Assert.isTrue(sectionDeveloperName.endsWith(expectedDeveloperNameSuffix));
    }
  }

  @IsTest
  static void cloneQuestionCataloguesToFundingOpportunities_givenInvalidTarget_throwsDmlException() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId = TestDataFactory.createPillar('Pillar').Id;
      final Id questionAssignmentId = TestDataFactory.createAssessmentQuestionAssignment(
        TestDataFactory.createAssessmentQuestion('Question').Id,
        TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
        null,
        null,
        false
      ).Id;

      Test.startTest();
      try {
        ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(
          new Map<Id, Set<Id>>{ programId => new Set<Id>{ questionAssignmentId } }
        );
        Assert.fail('Expected the clone to fail on a target that is not a Funding Opportunity.');
      } catch (DmlException e) {
        Assert.isNotNull(e.getMessage());
      }
      Test.stopTest();
    }
  }

  // ============================== </Clone engine> ==============================

  // ============================== <Helpers> ==============================

  private static void insertVersion(Id questionId, String questionText, Boolean isActive) {
    insert new AssessmentQuestionVersion(
      Name                 = questionText,
      AssessmentQuestionId = questionId,
      QuestionText         = questionText,
      IsActive             = isActive
    );
  }

  private static List<AssessmentQuestionAssignment> queryClonedQuestionAssignments(Id fundingOpportunityId) {
    return [
      SELECT
        EOI__c,
        IsMandatory__c,
        AssessmentQuestionSetId,
        AssessmentQuestionSet.Name,
        AssessmentQuestionSet.DeveloperName,
        AssessmentQuestionSet.Sequence__c,
        AssessmentQuestionId,
        AssessmentQuestion.Name,
        AssessmentQuestion.DeveloperName,
        AssessmentQuestion.DataType,
        AssessmentQuestion.QuestionCategory,
        AssessmentQuestion.ObjectAPIName__c,
        AssessmentQuestion.FieldAPIName__c,
        AssessmentQuestion.MaximumCharacters__c,
        AssessmentQuestion.Sequence__c,
        AssessmentQuestion.RecordTypeId
      FROM
        AssessmentQuestionAssignment
      WHERE
        FundingOpportunity__c = :fundingOpportunityId
      ORDER BY
        AssessmentQuestion.Name
    ];
  }

  private static AssessmentQuestionVersion queryVersion(Id questionId) {
    return [
      SELECT
        QuestionText,
        QuestionTextFR__c,
        Description,
        ResponseValues,
        ResponseValuesFR__c,
        HelpText,
        AdditionalInformation,
        IsActive
      FROM
        AssessmentQuestionVersion
      WHERE
        AssessmentQuestionId = :questionId
    ];
  }

  private static Boolean queryIsMandatory(Id questionAssignmentId) {
    return [
      SELECT
        IsMandatory__c
      FROM
        AssessmentQuestionAssignment
      WHERE
        Id = :questionAssignmentId
    ].IsMandatory__c;
  }

  private static Integer countQuestions() {
    return [
      SELECT
        COUNT()
      FROM
        AssessmentQuestion
    ];
  }

  private static Integer countVersions() {
    return [
      SELECT
        COUNT()
      FROM
        AssessmentQuestionVersion
    ];
  }

  private static Integer countSections() {
    return [
      SELECT
        COUNT()
      FROM
        AssessmentQuestionSet
    ];
  }

  // ============================== </Helpers> ==============================
}