/**
 * @description       : Test class for FundingOpportunityTriggerHandler.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 12-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   LAN      Initial version
 * 1.1   02-10-2026   LAN      Test that only a Draft Funding Opportunity without Application Form can be deleted
 * 1.2   05-10-2026   LAN      Run every test as the AXA admin user created in the testSetup
 * 1.3   12-10-2026   KRA      Name the delete tests after BaseTriggerHandler.beforeDelete
 **/
@isTest
private class FundingOpportunityTriggerHandler_TEST {

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


  // QuestionCategory est obligatoire mais ses valeurs évoluent avec le paramétrage : on prend
  // la première valeur active plutôt que d'en figer une dans le test.
  private static String getQuestionCategory() {
    for (Schema.PicklistEntry entry : AssessmentQuestion.QuestionCategory.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        return entry.getValue();
      }
    }
    return null;
  }

  // Une validation de l'org impose un pilier (Program) pour créer un programme (FundingOpportunity).
  private static Program createProgram() {
    Program program = new Program(Name = 'Pilier Test ' + String.valueOf(Math.abs(Crypto.getRandomInteger())));
    insert program;
    return program;
  }

  private static AssessmentQuestionSet createTemplateSection(String name) {
    AssessmentQuestionSet section = new AssessmentQuestionSet(
      Name = name,
      DeveloperName = 'Tpl' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
    );
    insert section;
    return section;
  }

  private static void createTemplateQuestion(
    AssessmentQuestionSet section,
    String questionName,
    Id programId,
    Boolean isEoi
  ) {
    AssessmentQuestion question = new AssessmentQuestion(
      Name = questionName,
      DeveloperName = 'Tpl' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
      DataType = 'Text',
      QuestionCategory = getQuestionCategory(),
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

    insert new AssessmentQuestionAssignment(
      AssessmentQuestionId = question.Id,
      AssessmentQuestionSetId = section.Id,
      Program__c = programId,
      EOI__c = isEoi,
      IsMandatory__c = true
    );
  }

  private static List<AssessmentQuestionAssignment> getClonedAssignments(Id fundingOpportunityId) {
    return [
      SELECT
        Id,
        EOI__c,
        IsMandatory__c,
        AssessmentQuestionId,
        AssessmentQuestionSetId,
        AssessmentQuestion.Name,
        AssessmentQuestionSet.Name
      FROM
        AssessmentQuestionAssignment
      WHERE
        FundingOpportunity__c = :fundingOpportunityId
    ];
  }

  private static Set<String> getClonedQuestionNames(Id fundingOpportunityId) {
    Set<String> questionNames = new Set<String>();
    for (AssessmentQuestionAssignment assignment : getClonedAssignments(fundingOpportunityId)) {
      questionNames.add(assignment.AssessmentQuestion.Name);
    }
    return questionNames;
  }

  @isTest
  static void clonesCommonCoreAndPillarTemplatesOnly() {
    System.runAs(getTestUser()) {
      List<Program> programs = new List<Program>{
        new Program(Name = 'Pilier Cible'),
        new Program(Name = 'Pilier Autre')
      };
      insert programs;

      createTemplateQuestion(createTemplateSection('Socle Commun'), 'Question Socle', null, false);
      createTemplateQuestion(createTemplateSection('Pilier Cible'), 'Question Pilier', programs[0].Id, false);
      createTemplateQuestion(createTemplateSection('Pilier Autre'), 'Question Hors Pilier', programs[1].Id, false);

      Test.startTest();
      FundingOpportunity fundingOpportunity = new FundingOpportunity(
        Name = 'FO Pilier Cible',
        ProgramId = programs[0].Id
      );
      insert fundingOpportunity;
      Test.stopTest();

      Set<String> clonedQuestionNames = getClonedQuestionNames(fundingOpportunity.Id);
      System.assertEquals(
        2,
        clonedQuestionNames.size(),
        'Seuls le socle commun et le pilier de la FO doivent être clonés'
      );
      System.assert(clonedQuestionNames.contains('Question Socle'), 'Le socle commun doit être cloné');
      System.assert(clonedQuestionNames.contains('Question Pilier'), 'Le pilier de la FO doit être cloné');
      System.assert(!clonedQuestionNames.contains('Question Hors Pilier'), 'Un autre pilier ne doit pas être cloné');
    }
  }

  @isTest
  static void clonesEoiTemplatesAsDraftVersions() {
    System.runAs(getTestUser()) {
      AssessmentQuestionSet section = createTemplateSection('Section EOI');
      createTemplateQuestion(section, 'Question EOI', null, true);

      Test.startTest();
      FundingOpportunity fundingOpportunity = new FundingOpportunity(
        Name = 'FO EOI',
        ProgramId = createProgram().Id,
        RecordTypeId = FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS.Id
      );
      insert fundingOpportunity;
      Test.stopTest();

      List<AssessmentQuestionAssignment> clonedAssignments = getClonedAssignments(fundingOpportunity.Id);
      System.assertEquals(1, clonedAssignments.size(), 'La question EOI doit être clonée sur la FO');
      System.assertEquals(true, clonedAssignments[0].EOI__c, 'Le marqueur EOI doit être repris sur le clone');

      List<AssessmentQuestionVersion> clonedVersions = [
        SELECT
          IsActive,
          QuestionText
        FROM
          AssessmentQuestionVersion
        WHERE
          AssessmentQuestionId = :clonedAssignments[0].AssessmentQuestionId
      ];
      System.assertEquals(1, clonedVersions.size(), 'Le clone doit avoir exactement une version');
      System.assertEquals(true, clonedVersions[0].IsActive, 'La version clonée doit être active');
      System.assertEquals('Question EOI ?', clonedVersions[0].QuestionText, 'Le texte de la question doit être repris');
    }
  }

  @isTest
  static void clonesTemplatesForEveryFundingOpportunityOfTheBatch() {
    System.runAs(getTestUser()) {
      AssessmentQuestionSet section = createTemplateSection('Socle Commun');
      createTemplateQuestion(section, 'Question A', null, false);
      createTemplateQuestion(section, 'Question B', null, false);

      Test.startTest();
      List<FundingOpportunity> fundingOpportunities = new List<FundingOpportunity>{
        new FundingOpportunity(Name = 'FO Lot 1', Status = 'Draft', ProgramId = createProgram().Id),
        new FundingOpportunity(Name = 'FO Lot 2', Status = 'Draft', ProgramId = createProgram().Id),
        new FundingOpportunity(Name = 'FO Lot 3', Status = 'Draft', ProgramId = createProgram().Id)
      };
      insert fundingOpportunities;
      Test.stopTest();

      for (FundingOpportunity fundingOpportunity : fundingOpportunities) {
        System.assertEquals(
          new Set<String>{ 'Question A', 'Question B' },
          getClonedQuestionNames(fundingOpportunity.Id),
          'Chaque FO du lot doit recevoir la totalité du socle commun'
        );
      }

      Set<Id> clonedSectionIds = new Set<Id>();
      for (AssessmentQuestionAssignment assignment : [
        SELECT
          AssessmentQuestionSetId
        FROM
          AssessmentQuestionAssignment
        WHERE
          FundingOpportunity__c IN :fundingOpportunities
      ]) {
        clonedSectionIds.add(assignment.AssessmentQuestionSetId);
      }
      System.assertEquals(3, clonedSectionIds.size(), 'Chaque FO doit avoir sa propre section clonée');
    }
  }

  @isTest
  static void doesNothingWhenNoTemplateIsAvailable() {
    System.runAs(getTestUser()) {
      Test.startTest();
      FundingOpportunity fundingOpportunity = new FundingOpportunity(Name = 'FO Sans Catalogue', Status = 'Draft', ProgramId = createProgram().Id);
      insert fundingOpportunity;
      Test.stopTest();

      System.assertEquals(0, getClonedAssignments(fundingOpportunity.Id).size(), 'Aucun clone ne doit être créé');
    }
  }

  // Une version active est désactivée avant la suppression, ce qui l'archive : une version
  // archivée ne peut pas être supprimée, donc la version et sa question subsistent sans assignment.
  @isTest
  static void beforeDelete_givenClonedCatalogue_deletesCloneButKeepsArchivedVersions() {
    System.runAs(getTestUser()) {
      final AssessmentQuestionSet templateSection = createTemplateSection('Socle Commun');
      createTemplateQuestion(templateSection, 'Question Socle', null, false);

      final FundingOpportunity fundingOpportunity = new FundingOpportunity(Name = 'FO A Supprimer', ProgramId = createProgram().Id);
      insert fundingOpportunity;
      setDraftStatus(new List<FundingOpportunity>{ fundingOpportunity });

      final List<AssessmentQuestionAssignment> clonedAssignments = getClonedAssignments(fundingOpportunity.Id);
      System.assertEquals(1, clonedAssignments.size(), 'Le catalogue doit être cloné avant la suppression');
      final Id clonedQuestionId = clonedAssignments[0].AssessmentQuestionId;
      final Id clonedSectionId = clonedAssignments[0].AssessmentQuestionSetId;
      final Id clonedVersionId = [
        SELECT
          Id
        FROM
          AssessmentQuestionVersion
        WHERE
          AssessmentQuestionId = :clonedQuestionId
      ][0].Id;

      final Assessment assessment = new Assessment(
        Name = 'Assessment Test',
        AssessmentStatus = 'In Progress'
      );
      insert assessment;
      insert new AssessmentQuestionResponse(
        Name = 'Response Test',
        AssessmentId = assessment.Id,
        AssessmentQuestionId = clonedVersionId,
        ResponseText = 'Réponse'
      );

      Test.startTest();
      delete fundingOpportunity;
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM AssessmentQuestionAssignment WHERE AssessmentQuestionId = :clonedQuestionId],
        'Les assignments clonés doivent être supprimés'
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM AssessmentQuestionResponse WHERE AssessmentQuestionId = :clonedVersionId],
        'Les réponses doivent être supprimées'
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM AssessmentQuestionSet WHERE Id = :clonedSectionId],
        'La section clonée doit être supprimée'
      );

      final List<AssessmentQuestionVersion> remainingVersions = [
        SELECT
          IsActive
        FROM
          AssessmentQuestionVersion
        WHERE
          Id = :clonedVersionId
      ];
      System.assertEquals(1, remainingVersions.size(), 'Une version archivée ne peut pas être supprimée');
      System.assertEquals(false, remainingVersions[0].IsActive, 'La version doit avoir été désactivée');
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AssessmentQuestion WHERE Id = :clonedQuestionId],
        'La question dont la version n\'est pas en Draft subsiste sans assignment'
      );

      System.assertEquals(
        1,
        [SELECT COUNT() FROM AssessmentQuestionSet WHERE Id = :templateSection.Id],
        'Le template ne doit pas être supprimé'
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AssessmentQuestionAssignment WHERE FundingOpportunity__c = NULL],
        'L\'assignment du template doit être conservé'
      );
    }
  }

  @isTest
  static void beforeDelete_givenQuestionStillAssigned_keepsQuestionAndVersionActive() {
    System.runAs(getTestUser()) {
      createTemplateQuestion(createTemplateSection('Socle Commun'), 'Question Socle', null, false);

      final FundingOpportunity fundingOpportunity = new FundingOpportunity(Name = 'FO Question Partagee', ProgramId = createProgram().Id);
      insert fundingOpportunity;
      setDraftStatus(new List<FundingOpportunity>{ fundingOpportunity });

      final AssessmentQuestionAssignment clonedAssignment = getClonedAssignments(fundingOpportunity.Id)[0];
      final Id clonedQuestionId = clonedAssignment.AssessmentQuestionId;
      insert new AssessmentQuestionAssignment(
        AssessmentQuestionId = clonedQuestionId,
        AssessmentQuestionSetId = createTemplateSection('Autre Section').Id,
        IsMandatory__c = true
      );

      Test.startTest();
      delete fundingOpportunity;
      Test.stopTest();

      System.assertEquals(
        1,
        [SELECT COUNT() FROM AssessmentQuestion WHERE Id = :clonedQuestionId],
        'Une question encore assignée ailleurs ne doit pas être supprimée'
      );
      System.assertEquals(
        true,
        [SELECT IsActive FROM AssessmentQuestionVersion WHERE AssessmentQuestionId = :clonedQuestionId][0].IsActive,
        'La version d\'une question encore assignée ne doit pas être désactivée'
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM AssessmentQuestionSet WHERE Id = :clonedAssignment.AssessmentQuestionSetId],
        'La section clonée, devenue vide, doit être supprimée'
      );
    }
  }

  @isTest
  static void beforeDelete_givenSeveralFundingOpportunities_deletesAssignmentsAndSectionsInBulk() {
    System.runAs(getTestUser()) {
      createTemplateQuestion(createTemplateSection('Socle Commun'), 'Question Socle', null, false);

      final List<FundingOpportunity> fundingOpportunities = new List<FundingOpportunity>{
        new FundingOpportunity(Name = 'FO Lot 1', ProgramId = createProgram().Id),
        new FundingOpportunity(Name = 'FO Lot 2', ProgramId = createProgram().Id),
        new FundingOpportunity(Name = 'FO Lot 3', ProgramId = createProgram().Id)
      };
      insert fundingOpportunities;
      setDraftStatus(fundingOpportunities);

      Test.startTest();
      delete fundingOpportunities;
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM AssessmentQuestionAssignment WHERE FundingOpportunity__c != NULL],
        'Aucun assignment cloné ne doit subsister'
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AssessmentQuestionSet],
        'Seule la section du template doit subsister'
      );
    }
  }

  @isTest
  static void beforeDelete_givenNoCatalogue_doesNothing() {
    System.runAs(getTestUser()) {
      final FundingOpportunity fundingOpportunity = new FundingOpportunity(Name = 'FO Sans Catalogue', ProgramId = createProgram().Id);
      insert fundingOpportunity;
      setDraftStatus(new List<FundingOpportunity>{ fundingOpportunity });

      Test.startTest();
      delete fundingOpportunity;
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM FundingOpportunity WHERE Id = :fundingOpportunity.Id],
        'La suppression doit aboutir sans catalogue'
      );
    }
  }

  private static FundingOpportunity createFundingOpportunityWithStatus(final String status) {
    final FundingOpportunity fundingOpportunity = new FundingOpportunity(
      Name = 'FO ' + status,
      ProgramId = createProgram().Id
    );
    insert fundingOpportunity;
    update new FundingOpportunity(Id = fundingOpportunity.Id, Status = status);
    return fundingOpportunity;
  }

  private static void createApplicationForm(final Id fundingOpportunityId) {
    insert new ApplicationForm(
      ReferenceRecordId = fundingOpportunityId,
      ProgrammeRattache__c = fundingOpportunityId,
      UsageType = 'Grantmaking'
    );
  }

  // The status is set by an update: a Funding Opportunity inserted with a status does not
  // necessarily keep it in this org, so the tests that rely on Draft set it explicitly afterwards.
  private static void setDraftStatus(final List<FundingOpportunity> fundingOpportunities) {
    final List<FundingOpportunity> fundingOpportunitiesToUpdate = new List<FundingOpportunity>();
    for (FundingOpportunity fundingOpportunity : fundingOpportunities) {
      fundingOpportunitiesToUpdate.add(new FundingOpportunity(Id = fundingOpportunity.Id, Status = 'Draft'));
    }
    update fundingOpportunitiesToUpdate;
  }

  @isTest
  static void beforeDelete_givenNonDraftWithApplicationForm_blocksTheDeletion() {
    System.runAs(getTestUser()) {
      createTemplateQuestion(createTemplateSection('Socle Commun'), 'Question Socle', null, false);
      final FundingOpportunity fundingOpportunity = createFundingOpportunityWithStatus('Published');
      createApplicationForm(fundingOpportunity.Id);

      Test.startTest();
      final Database.DeleteResult result = Database.delete(fundingOpportunity, false);
      Test.stopTest();

      System.assertEquals(false, result.isSuccess(), 'A non-Draft Funding Opportunity with a form cannot be deleted');
      System.assert(
        result.getErrors()[0].getMessage().contains('Only a Funding Opportunity in Draft status'),
        result.getErrors()[0].getMessage()
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM FundingOpportunity WHERE Id = :fundingOpportunity.Id],
        'The Funding Opportunity must still exist'
      );
      System.assertEquals(
        1,
        getClonedAssignments(fundingOpportunity.Id).size(),
        'Its cloned catalogue must stay untouched'
      );
    }
  }

  @isTest
  static void beforeDelete_givenNonDraftWithoutApplicationForm_blocksTheDeletion() {
    System.runAs(getTestUser()) {
      createTemplateQuestion(createTemplateSection('Socle Commun'), 'Question Socle', null, false);
      final FundingOpportunity fundingOpportunity = createFundingOpportunityWithStatus('Published');

      Test.startTest();
      final Database.DeleteResult result = Database.delete(fundingOpportunity, false);
      Test.stopTest();

      System.assertEquals(false, result.isSuccess(), 'A non-Draft Funding Opportunity cannot be deleted');
      System.assert(
        result.getErrors()[0].getMessage().contains('Only a Funding Opportunity in Draft status'),
        result.getErrors()[0].getMessage()
      );
      System.assertEquals(
        1,
        getClonedAssignments(fundingOpportunity.Id).size(),
        'Its cloned catalogue must stay untouched'
      );
    }
  }

  @isTest
  static void beforeDelete_givenDraftWithApplicationForm_blocksTheDeletion() {
    System.runAs(getTestUser()) {
      createTemplateQuestion(createTemplateSection('Socle Commun'), 'Question Socle', null, false);
      final FundingOpportunity fundingOpportunity = createFundingOpportunityWithStatus('Draft');
      createApplicationForm(fundingOpportunity.Id);

      Test.startTest();
      final Database.DeleteResult result = Database.delete(fundingOpportunity, false);
      Test.stopTest();

      System.assertEquals(false, result.isSuccess(), 'A Draft Funding Opportunity with a form cannot be deleted');
      System.assert(
        result.getErrors()[0].getMessage().contains('Application Forms attached'),
        result.getErrors()[0].getMessage()
      );
      System.assertEquals(
        1,
        getClonedAssignments(fundingOpportunity.Id).size(),
        'Its cloned catalogue must stay untouched'
      );
    }
  }

  @isTest
  static void beforeDelete_givenDraftWithoutApplicationForm_deletesTheFundingOpportunity() {
    System.runAs(getTestUser()) {
      createTemplateQuestion(createTemplateSection('Socle Commun'), 'Question Socle', null, false);
      final FundingOpportunity fundingOpportunity = createFundingOpportunityWithStatus('Draft');

      Test.startTest();
      delete fundingOpportunity;
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM FundingOpportunity WHERE Id = :fundingOpportunity.Id],
        'A Draft Funding Opportunity without any form can be deleted'
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM AssessmentQuestionAssignment WHERE FundingOpportunity__c != NULL],
        'Its cloned catalogue must be deleted with it'
      );
    }
  }

  @isTest
  static void beforeDelete_givenMixedBatch_deletesOnlyTheDraftWithoutApplicationForm() {
    System.runAs(getTestUser()) {
      final FundingOpportunity draftWithFormFundingOpportunity = createFundingOpportunityWithStatus('Draft');
      createApplicationForm(draftWithFormFundingOpportunity.Id);
      final FundingOpportunity draftFundingOpportunity = createFundingOpportunityWithStatus('Draft');
      final FundingOpportunity closedFundingOpportunity = createFundingOpportunityWithStatus('Closed');

      Test.startTest();
      final List<Database.DeleteResult> results = Database.delete(
        new List<FundingOpportunity>{
          draftWithFormFundingOpportunity,
          draftFundingOpportunity,
          closedFundingOpportunity
        },
        false
      );
      Test.stopTest();

      System.assertEquals(false, results[0].isSuccess(), 'Draft with a form must be blocked');
      System.assertEquals(true, results[1].isSuccess(), 'Draft without a form must be deleted');
      System.assertEquals(false, results[2].isSuccess(), 'A non-Draft Funding Opportunity must be blocked');
    }
  }

  @isTest
  static void deleteClonedCatalogues_givenNullOrEmptyIds_doesNothing() {
    System.runAs(getTestUser()) {
      // runAs itself consumes DML statements: the count is compared before and after the calls.
      final Integer dmlStatementsBefore = Limits.getDmlStatements();

      ApplicationFormCatalogueQueryService.deleteClonedCatalogues(null);
      ApplicationFormCatalogueQueryService.deleteClonedCatalogues(new Set<Id>());

      System.assertEquals(dmlStatementsBefore, Limits.getDmlStatements(), 'Aucune DML ne doit être exécutée');
    }
  }
}