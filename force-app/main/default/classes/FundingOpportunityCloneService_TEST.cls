/**
 * @description       : Test class for FundingOpportunityCloneService.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 13-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
@IsTest
private class FundingOpportunityCloneService_TEST {
  @TestSetup
  static void setup() {
    TestDataFactory.createAdminUser(new List<String>{ 'AXA_Foundation_Admin', 'GrantmakingManager' });
  }

  @IsTest
  static void cloneFundingOpportunities_givenNoInputs_throwsIllegalArgumentException() {
    final String expectedMessage = 'Expected at least one Funding Opportunity.';

    assertRejected(null, expectedMessage);
    assertRejected(new List<FundingOpportunityCloneService.CloneInput>(), expectedMessage);
  }

  @IsTest
  static void cloneFundingOpportunities_givenInputWithoutSourceId_throwsIllegalArgumentException() {
    final String expectedMessage = 'Expected each Funding Opportunity with its Id.';
    final FundingOpportunityCloneService.CloneInput inputWithoutFundingOpportunity =
      new FundingOpportunityCloneService.CloneInput();
    final FundingOpportunityCloneService.CloneInput inputWithoutSourceId =
      new FundingOpportunityCloneService.CloneInput();
    inputWithoutSourceId.fundingOpportunity = new FundingOpportunity(Name = 'Cloned program');

    assertRejected(new List<FundingOpportunityCloneService.CloneInput>{ null }, expectedMessage);
    assertRejected(
      new List<FundingOpportunityCloneService.CloneInput>{ inputWithoutFundingOpportunity },
      expectedMessage
    );
    assertRejected(new List<FundingOpportunityCloneService.CloneInput>{ inputWithoutSourceId }, expectedMessage);
  }

  @IsTest
  static void cloneFundingOpportunities_givenUnknownSource_throwsIllegalArgumentException() {
    final Id unknownSourceFOId =
      Id.valueOf(FundingOpportunity.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12));

    assertRejected(
      new List<FundingOpportunityCloneService.CloneInput>{
        buildCloneInput(unknownSourceFOId, FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS)
      },
      'Expected every source Funding Opportunity to exist.'
    );
  }

  @IsTest
  static void cloneFundingOpportunities_givenSource_copiesInputFieldsAndSourceProgram() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId  = TestDataFactory.createPillar('Pillar').Id;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
        programId
      ).Id;
      final FundingOpportunity inputFO = new FundingOpportunity(
        Id                 = sourceFOId,
        RecordTypeId       = FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT.Id,
        Name               = 'Cloned program',
        ProgramCode__c     = 'CODE',
        Description__c     = 'Description',
        StartDate          = Date.today(),
        EndDate            = Date.today().addDays(30),
        Theme__c           = FundingOpportunityConstants.Theme.GLOBAL_CHAIRS,
        Program_Name__c    = 'Education',
        GeographicScope__c = FundingOpportunityConstants.GeographicScope.FRANCE
      );
      final FundingOpportunityCloneService.CloneInput input = new FundingOpportunityCloneService.CloneInput();
      input.fundingOpportunity = inputFO;

      Test.startTest();
      final List<FundingOpportunityCloneService.CloneOutput> outputs =
        FundingOpportunityCloneService.cloneFundingOpportunities(
          new List<FundingOpportunityCloneService.CloneInput>{ input }
        );
      Test.stopTest();

      Assert.areEqual(1, outputs.size());
      final FundingOpportunity clonedFO = [
        SELECT
          RecordTypeId,
          Name,
          ProgramCode__c,
          Description__c,
          StartDate,
          EndDate,
          Theme__c,
          Program_Name__c,
          GeographicScope__c,
          ProgramId
        FROM
          FundingOpportunity
        WHERE
          Id = :outputs[0].clonedFundingOpportunityId
      ];
      Assert.areEqual(inputFO.RecordTypeId, clonedFO.RecordTypeId);
      Assert.areEqual(inputFO.Name, clonedFO.Name);
      Assert.areEqual(inputFO.ProgramCode__c, clonedFO.ProgramCode__c);
      Assert.areEqual(inputFO.Description__c, clonedFO.Description__c);
      Assert.areEqual(inputFO.StartDate, clonedFO.StartDate);
      Assert.areEqual(inputFO.EndDate, clonedFO.EndDate);
      Assert.areEqual(inputFO.Theme__c, clonedFO.Theme__c);
      Assert.areEqual(inputFO.Program_Name__c, clonedFO.Program_Name__c);
      Assert.areEqual(inputFO.GeographicScope__c, clonedFO.GeographicScope__c);
      Assert.areEqual(programId, clonedFO.ProgramId);
      Assert.isTrue(FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled);
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenCallForProjectsToCallForProjects_clonesAllSourceQuestionsOnly() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final RecordTypeProvider.RecordTypeReference callForProjectsRecordType =
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        TestDataFactory.createPillar('Pillar').Id
      ).Id;
      createAttachedQuestion('EOI question', sourceFOId, null, true);
      createAttachedQuestion('Full application question', sourceFOId, null, false);
      createAttachedQuestion('Common template', null, null, false);
      final FundingOpportunityCloneService.CloneInput input = buildCloneInput(sourceFOId, callForProjectsRecordType);

      Test.startTest();
      final Id clonedFOId = cloneFundingOpportunity(input);
      Test.stopTest();

      Assert.areEqual(
        new List<String>{ 'EOI question', 'Full application question' },
        queryClonedQuestionNames(clonedFOId)
      );
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenCallForProjectsToDirectManagement_excludesEOIQuestions() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
        TestDataFactory.createPillar('Pillar').Id
      ).Id;
      createAttachedQuestion('EOI question', sourceFOId, null, true);
      createAttachedQuestion('Full application question', sourceFOId, null, false);
      final FundingOpportunityCloneService.CloneInput input =
        buildCloneInput(sourceFOId, FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT);

      Test.startTest();
      final Id clonedFOId = cloneFundingOpportunity(input);
      Test.stopTest();

      Assert.areEqual(new List<String>{ 'Full application question' }, queryClonedQuestionNames(clonedFOId));
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenDirectManagementToDirectManagement_excludesEOIQuestions() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final RecordTypeProvider.RecordTypeReference directManagementRecordType =
        FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        directManagementRecordType,
        TestDataFactory.createPillar('Pillar').Id
      ).Id;
      createAttachedQuestion('EOI question', sourceFOId, null, true);
      createAttachedQuestion('Full application question', sourceFOId, null, false);
      final FundingOpportunityCloneService.CloneInput input = buildCloneInput(sourceFOId, directManagementRecordType);

      Test.startTest();
      final Id clonedFOId = cloneFundingOpportunity(input);
      Test.stopTest();

      Assert.areEqual(new List<String>{ 'Full application question' }, queryClonedQuestionNames(clonedFOId));
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenDirectManagementToCallForProjects_addsCommonAndProgramEOITemplates() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId = TestDataFactory.createPillar('Pillar').Id;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT,
        programId
      ).Id;
      createAttachedQuestion('Source EOI question', sourceFOId, null, true);
      createAttachedQuestion('Source full application question', sourceFOId, null, false);
      createAttachedQuestion('Common EOI template', null, null, true);
      createAttachedQuestion('Common full application template', null, null, false);
      createAttachedQuestion('Program EOI template', null, programId, true);
      createAttachedQuestion('Other program EOI template', null, TestDataFactory.createPillar('Other').Id, true);
      final FundingOpportunityCloneService.CloneInput input =
        buildCloneInput(sourceFOId, FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS);

      Test.startTest();
      final Id clonedFOId = cloneFundingOpportunity(input);
      Test.stopTest();

      Assert.areEqual(
        new List<String>{ 'Common EOI template', 'Program EOI template', 'Source full application question' },
        queryClonedQuestionNames(clonedFOId)
      );
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenEOIOnlySourceToCallForProjects_addsFullApplicationTemplates() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final RecordTypeProvider.RecordTypeReference callForProjectsRecordType =
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS;
      final Id programId = TestDataFactory.createPillar('Pillar').Id;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        programId
      ).Id;
      createAttachedQuestion('Source EOI question', sourceFOId, null, true);
      createAttachedQuestion('Common EOI template', null, null, true);
      createAttachedQuestion('Common full application template', null, null, false);
      createAttachedQuestion('Program full application template', null, programId, false);
      createAttachedQuestion(
        'Other program full application template',
        null,
        TestDataFactory.createPillar('Other').Id,
        false
      );
      final FundingOpportunityCloneService.CloneInput input = buildCloneInput(sourceFOId, callForProjectsRecordType);

      Test.startTest();
      final Id clonedFOId = cloneFundingOpportunity(input);
      Test.stopTest();

      Assert.areEqual(
        new List<String>{
          'Common full application template',
          'Program full application template',
          'Source EOI question'
        },
        queryClonedQuestionNames(clonedFOId)
      );
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenEOIOnlySourceToDirectManagement_addsFullApplicationTemplatesOnly() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId = TestDataFactory.createPillar('Pillar').Id;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS,
        programId
      ).Id;
      createAttachedQuestion('Source EOI question', sourceFOId, null, true);
      createAttachedQuestion('Common EOI template', null, null, true);
      createAttachedQuestion('Common full application template', null, null, false);
      createAttachedQuestion('Program full application template', null, programId, false);
      final FundingOpportunityCloneService.CloneInput input =
        buildCloneInput(sourceFOId, FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT);

      Test.startTest();
      final Id clonedFOId = cloneFundingOpportunity(input);
      Test.stopTest();

      Assert.areEqual(
        new List<String>{ 'Common full application template', 'Program full application template' },
        queryClonedQuestionNames(clonedFOId)
      );
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenSourceWithoutQuestionsToCallForProjects_addsAllTemplates() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final Id programId = TestDataFactory.createPillar('Pillar').Id;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT,
        programId
      ).Id;
      createAttachedQuestion('Common EOI template', null, null, true);
      createAttachedQuestion('Common full application template', null, null, false);
      createAttachedQuestion('Program EOI template', null, programId, true);
      createAttachedQuestion('Program full application template', null, programId, false);
      final FundingOpportunityCloneService.CloneInput input =
        buildCloneInput(sourceFOId, FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS);

      Test.startTest();
      final Id clonedFOId = cloneFundingOpportunity(input);
      Test.stopTest();

      Assert.areEqual(
        new List<String>{
          'Common EOI template',
          'Common full application template',
          'Program EOI template',
          'Program full application template'
        },
        queryClonedQuestionNames(clonedFOId)
      );
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenSeveralInputs_clonesEachInputInOrder() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final RecordTypeProvider.RecordTypeReference callForProjectsRecordType =
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS;
      final RecordTypeProvider.RecordTypeReference directManagementRecordType =
        FundingOpportunityConstants.RecordTypes.DIRECT_MANAGEMENT;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        TestDataFactory.createPillar('Pillar').Id
      ).Id;
      createAttachedQuestion('EOI question', sourceFOId, null, true);
      createAttachedQuestion('Full application question', sourceFOId, null, false);
      final List<FundingOpportunityCloneService.CloneInput> inputs =
        new List<FundingOpportunityCloneService.CloneInput>{
          buildCloneInput(sourceFOId, callForProjectsRecordType),
          buildCloneInput(sourceFOId, directManagementRecordType)
        };

      Test.startTest();
      final List<FundingOpportunityCloneService.CloneOutput> outputs =
        FundingOpportunityCloneService.cloneFundingOpportunities(inputs);
      Test.stopTest();

      Assert.areEqual(2, outputs.size());
      final Id callForProjectsCloneId  = outputs[0].clonedFundingOpportunityId;
      final Id directManagementCloneId = outputs[1].clonedFundingOpportunityId;
      final Set<Id> clonedFOIds = new Set<Id>{ callForProjectsCloneId, directManagementCloneId };
      final Map<Id, FundingOpportunity> clonedFOById = new Map<Id, FundingOpportunity>([
        SELECT
          RecordTypeId
        FROM
          FundingOpportunity
        WHERE
          Id IN :clonedFOIds
      ]);
      Assert.areEqual(callForProjectsRecordType.Id, clonedFOById.get(callForProjectsCloneId).RecordTypeId);
      Assert.areEqual(directManagementRecordType.Id, clonedFOById.get(directManagementCloneId).RecordTypeId);
      Assert.areEqual(
        new List<String>{ 'EOI question', 'Full application question' },
        queryClonedQuestionNames(callForProjectsCloneId)
      );
      Assert.areEqual(
        new List<String>{ 'Full application question' },
        queryClonedQuestionNames(directManagementCloneId)
      );
    }
  }

  @IsTest
  static void cloneFundingOpportunities_givenInsertFailure_rollsBackAndRestoresSeeding() {
    System.runAs(TestDataFactory.getAdminUser()) {
      final RecordTypeProvider.RecordTypeReference callForProjectsRecordType =
        FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS;
      final Id sourceFOId = TestDataFactory.createFundingOpportunityWithoutCatalogue(
        callForProjectsRecordType,
        TestDataFactory.createPillar('Pillar').Id
      ).Id;
      createAttachedQuestion('Question', sourceFOId, null, false);
      final FundingOpportunityCloneService.CloneInput validInput   =
        buildCloneInput(sourceFOId, callForProjectsRecordType);
      final FundingOpportunityCloneService.CloneInput invalidInput =
        buildCloneInput(sourceFOId, callForProjectsRecordType);
      invalidInput.fundingOpportunity.Name = 'X'.repeat(256);

      Test.startTest();
      try {
        FundingOpportunityCloneService.cloneFundingOpportunities(
          new List<FundingOpportunityCloneService.CloneInput>{ validInput, invalidInput }
        );
        Assert.fail('Expected the clone to fail on a name longer than the field allows.');
      } catch (DmlException e) {
        Assert.isNotNull(e.getMessage());
      }
      Test.stopTest();

      Assert.areEqual(1, countFundingOpportunities());
      Assert.isTrue(FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled);
    }
  }

  // ============================== <Helpers> ==============================

  private static FundingOpportunityCloneService.CloneInput buildCloneInput(
    Id sourceFOId,
    RecordTypeProvider.RecordTypeReference targetRecordType
  ) {
    final FundingOpportunity inputFO =
      TestDataFactory.buildFundingOpportunity('Cloned program', targetRecordType.DeveloperName, null);
    inputFO.Id = sourceFOId;
    final FundingOpportunityCloneService.CloneInput input = new FundingOpportunityCloneService.CloneInput();
    input.fundingOpportunity = inputFO;
    return input;
  }

  private static Id cloneFundingOpportunity(FundingOpportunityCloneService.CloneInput input) {
    return FundingOpportunityCloneService.cloneFundingOpportunities(
      new List<FundingOpportunityCloneService.CloneInput>{ input }
    )[0].clonedFundingOpportunityId;
  }

  private static void createAttachedQuestion(
    String questionName,
    Id fundingOpportunityId,
    Id programId,
    Boolean isEOI
  ) {
    TestDataFactory.createAssessmentQuestionAssignment(
      TestDataFactory.createAssessmentQuestion(questionName).Id,
      TestDataFactory.createAssessmentQuestionSet('Section', 1).Id,
      fundingOpportunityId,
      programId,
      isEOI
    );
  }

  private static void assertRejected(List<FundingOpportunityCloneService.CloneInput> inputs, String expectedMessage) {
    try {
      FundingOpportunityCloneService.cloneFundingOpportunities(inputs);
      Assert.fail('Expected the clone inputs to be rejected.');
    } catch (IllegalArgumentException e) {
      Assert.areEqual(expectedMessage, e.getMessage());
    }
  }

  private static List<String> queryClonedQuestionNames(Id fundingOpportunityId) {
    final List<String> questionNames = new List<String>();
    for (AssessmentQuestionAssignment questionAssignment : [
      SELECT
        AssessmentQuestion.Name
      FROM
        AssessmentQuestionAssignment
      WHERE
        FundingOpportunity__c = :fundingOpportunityId
      ORDER BY
        AssessmentQuestion.Name
    ]) {
      questionNames.add(questionAssignment.AssessmentQuestion.Name);
    }
    return questionNames;
  }

  private static Integer countFundingOpportunities() {
    return [
      SELECT
        COUNT()
      FROM
        FundingOpportunity
    ];
  }

  // ============================== </Helpers> ==============================
}