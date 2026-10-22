/**
 * @description       : Test class for ApplicationFormEoiReviewController.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 22-10-2026
 * @last modified by  : Liantsoa Andrianilana
 **/
@IsTest
private class ApplicationFormEoiReviewController_TEST {
  private static final String STAGE_DRAFT = 'Draft';
  private static final String STAGE_EOI_DRAFT = 'EOI Draft';
  private static final String STAGE_SUBMITTED = 'Submitted';
  private static final String STAGE_EOI_SUBMITTED = 'EOI Submitted';
  private static final String STAGE_EOI_APPROVED = 'EOI Approved';
  private static final String STAGE_EOI_NOT_SELECTED = 'EOI Not Selected';
  private static final String USAGE_TYPE_GRANTMAKING = 'Grantmaking';

  private static final String REVIEWED_PROGRAM = 'Reviewed Program';
  private static final String OTHER_PROGRAM = 'Other Program';
  private static final String ALPHA_PARTNER = 'Alpha Partner';
  private static final String BETA_PARTNER = 'Beta Partner';

  private static User getTestUser() {
    return [SELECT Id FROM User WHERE LastName = 'orgAdminUser' LIMIT 1];
  }

  @TestSetup
  // static void createApplicationFormsAcrossStages() {
  //   // Create user with System Administrator profile
  //   Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
  //   User testUser = new User(
  //     Alias = 'orgadmin',
  //     Email = 'orgadmin@testorg.com',
  //     EmailEncodingKey = 'UTF-8',
  //     LastName = 'orgAdminUser',
  //     LanguageLocaleKey = 'en_US',
  //     LocaleSidKey = 'en_US',
  //     ProfileId = p.Id,
  //     TimeZoneSidKey = 'America/Los_Angeles',
  //     Username = 'orgadmin' + DateTime.now().getTime() + '@testorg.com'
  //   );
  //   insert testUser;

  //   // Query both Permission Sets (by API Name or Label)
  //   List<PermissionSet> psList = [
  //     SELECT Id
  //     FROM PermissionSet
  //     WHERE Name IN ('Admin_Access', 'Grantmaking_Manager')
  //        OR Label IN ('Admin Access', 'Grantmaking Manager')
  //   ];

  //   // Assign permission sets to the test user
  //   List<PermissionSetAssignment> psaList = new List<PermissionSetAssignment>();
  //   for (PermissionSet ps : psList) {
  //     psaList.add(new PermissionSetAssignment(
  //       AssigneeId = testUser.Id,
  //       PermissionSetId = ps.Id
  //     ));
  //   }
  //   insert psaList;

  //   final List<Account> partners = new List<Account>{
  //     new Account(Name = ALPHA_PARTNER,LegalName__c = ALPHA_PARTNER,LegalForm__c='Nonprofit / association',TIN__c='123456789'),
  //     new Account(Name = BETA_PARTNER,LegalName__c = BETA_PARTNER,LegalForm__c='Nonprofit / association',TIN__c='987654321')
  //   };
  //   insert partners;

  //   final List<Contact> applicants = new List<Contact>{
  //     new Contact(LastName = 'Alpha Applicant', AccountId = partners[0].Id),
  //     new Contact(LastName = 'Beta Applicant', AccountId = partners[1].Id),
  //     new Contact(LastName = 'Unaffiliated Applicant')
  //   };
  //   insert applicants;

  //   TestDataFactory.createPillar('Test Pillar');
  //   final Program pillar = [SELECT Id FROM Program WHERE Name = 'Test Pillar' LIMIT 1];

  //   final List<FundingOpportunity> programs = new List<FundingOpportunity>{
  //     TestDataFactory.buildFundingOpportunity(REVIEWED_PROGRAM,'',pillar.Id),
  //     TestDataFactory.buildFundingOpportunity(OTHER_PROGRAM,'',pillar.Id)
  //   };
  //   insert programs;

  //   // final List<FundingOpportunity> programs = new List<FundingOpportunity>{
  //   //   new FundingOpportunity(Name = REVIEWED_PROGRAM),
  //   //   new FundingOpportunity(Name = OTHER_PROGRAM)
  //   // };
  //   // insert programs;

  //   insert new List<ApplicationForm>{
  //     buildApplicationForm('Alpha approved', STAGE_EOI_APPROVED, programs[0].Id, applicants[0].Id),
  //     buildApplicationForm(
  //       'Beta EOI submitted',
  //       STAGE_EOI_SUBMITTED,
  //       programs[0].Id,
  //       applicants[1].Id
  //     ),
  //     buildApplicationForm(
  //       'Unaffiliated not selected',
  //       STAGE_EOI_NOT_SELECTED,
  //       programs[0].Id,
  //       applicants[2].Id
  //     ),
  //     buildApplicationForm('Still a draft', STAGE_DRAFT, programs[0].Id, applicants[0].Id),
  //     buildApplicationForm('Still an EOI draft', STAGE_EOI_DRAFT, programs[0].Id, applicants[0].Id),
  //     buildApplicationForm(
  //       'Past the expression of interest',
  //       STAGE_SUBMITTED,
  //       programs[0].Id,
  //       applicants[0].Id
  //     ),
  //     buildApplicationForm(
  //       'Belongs elsewhere',
  //       STAGE_EOI_SUBMITTED,
  //       programs[1].Id,
  //       applicants[0].Id
  //     )
  //   };
  // }

  static void createApplicationFormsAcrossStages() {
    // 1. Create setup objects inside System.runAs block to avoid MIXED_DML_OPERATION
    User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    User testUser;

    System.runAs(runningUser) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        testUser = new User(
            Alias = 'orgadmin',
            Email = 'orgadmin@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'orgAdminUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'orgadmin' + DateTime.now().getTime() + '@testorg.com'
        );
        insert testUser;

        // Query both Permission Sets
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

    // 2. Non-Setup DML Operations (Accounts, Contacts, Custom Objects) now run safely
    final List<Account> partners = new List<Account>{
        new Account(Name = ALPHA_PARTNER, LegalName__c = ALPHA_PARTNER, LegalForm__c = 'Nonprofit / association', TIN__c = '123456789'),
        new Account(Name = BETA_PARTNER, LegalName__c = BETA_PARTNER, LegalForm__c = 'Nonprofit / association', TIN__c = '987654321')
    };
    insert partners;

    final List<Contact> applicants = new List<Contact>{
        new Contact(FirstName = 'Alpha', LastName = 'Applicant', AccountId = partners[0].Id),
        new Contact(FirstName = 'Beta', LastName = 'Applicant', AccountId = partners[1].Id),
        new Contact(FirstName = 'Unaffiliated', LastName = 'Applicant')
    };
    insert applicants;

    TestDataFactory.createPillar('Test Pillar');
    final Program pillar = [SELECT Id FROM Program WHERE Name = 'Test Pillar' LIMIT 1];

    final List<FundingOpportunity> programs = new List<FundingOpportunity>{
        TestDataFactory.buildFundingOpportunity(REVIEWED_PROGRAM, 'CallForProjects', pillar.Id),
        TestDataFactory.buildFundingOpportunity(OTHER_PROGRAM, 'CallForProjects', pillar.Id)
    };
    insert programs;

    insert new List<ApplicationForm>{
        buildApplicationForm('Alpha approved', STAGE_EOI_APPROVED, programs[0].Id, applicants[0].Id),
        buildApplicationForm('Beta EOI submitted', STAGE_EOI_SUBMITTED, programs[0].Id, applicants[1].Id),
        buildApplicationForm('Unaffiliated not selected', STAGE_EOI_NOT_SELECTED, programs[0].Id, applicants[2].Id),
        buildApplicationForm('Still a draft', STAGE_DRAFT, programs[0].Id, applicants[0].Id),
        buildApplicationForm('Still an EOI draft', STAGE_EOI_DRAFT, programs[0].Id, applicants[0].Id),
        buildApplicationForm('Past the expression of interest', STAGE_SUBMITTED, programs[0].Id, applicants[0].Id),
        buildApplicationForm('Belongs elsewhere', STAGE_EOI_SUBMITTED, programs[1].Id, applicants[0].Id)
    };
}

  @IsTest
  static void getApplicationFormsToReviewKeepsOnlyReviewableStages() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    final Id fundingOpportunityId = getProgramId(REVIEWED_PROGRAM);

    Test.startTest();
    final List<ApplicationFormEoiReviewController.ApplicationFormViewModel> viewModels =
      ApplicationFormEoiReviewController.getApplicationFormsToReview(fundingOpportunityId);
    Test.stopTest();

    final Set<String> stages = new Set<String>();
    for (ApplicationFormEoiReviewController.ApplicationFormViewModel viewModel : viewModels) {
      stages.add(viewModel.stage);
    }
    Assert.areEqual(3, viewModels.size());
    Assert.areEqual(
      new Set<String>{ STAGE_EOI_SUBMITTED, STAGE_EOI_APPROVED, STAGE_EOI_NOT_SELECTED },
      stages
    );
    Assert.isNull(findByTitle(viewModels, 'Past the expression of interest'));
    }
  }

  @IsTest
  static void getApplicationFormsToReviewIgnoresOtherFundingOpportunities() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    final Id fundingOpportunityId = getProgramId(REVIEWED_PROGRAM);

    Test.startTest();
    final List<ApplicationFormEoiReviewController.ApplicationFormViewModel> viewModels =
      ApplicationFormEoiReviewController.getApplicationFormsToReview(fundingOpportunityId);
    Test.stopTest();

    Assert.isNull(findByTitle(viewModels, 'Belongs elsewhere'));
    }
  }

  @IsTest
  static void getApplicationFormsToReviewOrdersPartnersWithUnaffiliatedLast() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    final Id fundingOpportunityId = getProgramId(REVIEWED_PROGRAM);

    Test.startTest();
    final List<ApplicationFormEoiReviewController.ApplicationFormViewModel> viewModels =
      ApplicationFormEoiReviewController.getApplicationFormsToReview(fundingOpportunityId);
    Test.stopTest();

    Assert.areEqual(ALPHA_PARTNER, viewModels[0].partnerName);
    Assert.areEqual(BETA_PARTNER, viewModels[1].partnerName);
    Assert.isNull(viewModels[2].partnerName);
    }
  }

  @IsTest
  static void getApplicationFormsToReviewMapsEveryDisplayedField() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    final Id fundingOpportunityId = getProgramId(REVIEWED_PROGRAM);
    final ApplicationForm expectedApplicationForm = [
      SELECT
        Id,
        Name,
        Contact.Name
      FROM
        ApplicationForm
      WHERE
        Title = 'Alpha approved'
      LIMIT
        1
    ];

    Test.startTest();
    final List<ApplicationFormEoiReviewController.ApplicationFormViewModel> viewModels =
      ApplicationFormEoiReviewController.getApplicationFormsToReview(fundingOpportunityId);
    Test.stopTest();

    final ApplicationFormEoiReviewController.ApplicationFormViewModel viewModel = findByTitle(
      viewModels,
      'Alpha approved'
    );
    Assert.areEqual(expectedApplicationForm.Id, viewModel.id);
    Assert.areEqual(expectedApplicationForm.Name, viewModel.reference);
    Assert.areEqual(expectedApplicationForm.Contact.Name, viewModel.contactName);
    Assert.areEqual(ALPHA_PARTNER, viewModel.partnerName);
    Assert.areEqual(STAGE_EOI_APPROVED, viewModel.stage);
    }
  }

  @IsTest
  static void getApplicationFormsToReviewLeavesApplicantEmptyWhenUnlinked() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    final Id fundingOpportunityId = getProgramId(REVIEWED_PROGRAM);
    insert buildApplicationForm(
      'Without an applicant',
      STAGE_EOI_SUBMITTED,
      fundingOpportunityId,
      null
    );

    Test.startTest();
    final List<ApplicationFormEoiReviewController.ApplicationFormViewModel> viewModels =
      ApplicationFormEoiReviewController.getApplicationFormsToReview(fundingOpportunityId);
    Test.stopTest();

    final ApplicationFormEoiReviewController.ApplicationFormViewModel viewModel = findByTitle(
      viewModels,
      'Without an applicant'
    );
    Assert.isNotNull(viewModel);
    Assert.isNull(viewModel.contactName);
    Assert.isNull(viewModel.partnerName);
    }
  }

  @IsTest
  static void getApplicationFormsToReviewReturnsNothingWithoutMatchingForms() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    final Program pillar = [SELECT Id FROM Program WHERE Name = 'Test Pillar' LIMIT 1];

    final FundingOpportunity programWithoutForms = TestDataFactory.buildFundingOpportunity('Empty Program', 'CallForProjects', pillar.Id);
    insert programWithoutForms;

    Test.startTest();
    final List<ApplicationFormEoiReviewController.ApplicationFormViewModel> viewModels =
      ApplicationFormEoiReviewController.getApplicationFormsToReview(programWithoutForms.Id);
    Test.stopTest();

    Assert.isTrue(viewModels.isEmpty());
    }
  }

  @IsTest
  static void updateStageAppliesTheStageToEveryForm() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    final Id fundingOpportunityId = getProgramId(REVIEWED_PROGRAM);
    final List<Id> applicationFormIds = new List<Id>(
      new Map<Id, ApplicationForm>([
        SELECT
          Id
        FROM
          ApplicationForm
        WHERE
          ReferenceRecordId = :fundingOpportunityId
          AND Stage IN (:STAGE_EOI_SUBMITTED, :STAGE_EOI_NOT_SELECTED)
      ]).keySet()
    );

    Test.startTest();
    ApplicationFormEoiReviewController.updateStage(applicationFormIds, STAGE_EOI_APPROVED);
    Test.stopTest();

    Assert.areEqual(2, applicationFormIds.size());
    Assert.areEqual(
      applicationFormIds.size(),
      [
        SELECT
          COUNT()
        FROM
          ApplicationForm
        WHERE
          Id IN :applicationFormIds
          AND Stage = :STAGE_EOI_APPROVED
      ]
    );
    }
  }

  @IsTest
  static void updateStageAcceptsAnEmptyList() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    Test.startTest();
    ApplicationFormEoiReviewController.updateStage(new List<Id>(), STAGE_EOI_APPROVED);
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT
          COUNT()
        FROM
          ApplicationForm
        WHERE
          Stage = :STAGE_EOI_APPROVED
      ]
    );
    }
  }

  @IsTest
  static void updateStageRejectsAnUnknownStage() {
    User testUser = getTestUser();
    System.runAs(testUser) {
    final List<Id> applicationFormIds = new List<Id>{ getApplicationFormId('Beta EOI submitted') };

    Test.startTest();
    try {
      ApplicationFormEoiReviewController.updateStage(applicationFormIds, 'Preselected');
      Assert.fail('Expected the stage update to be rejected.');
    } catch (DmlException caughtException) {
      Assert.areEqual(
        StatusCode.INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST,
        caughtException.getDmlType(0)
      );
    }
    Test.stopTest();
    }
  }

  private static ApplicationForm buildApplicationForm(
    String title,
    String stage,
    Id fundingOpportunityId,
    Id contactId
  ) {
    return new ApplicationForm(
      Title = title,
      Stage = stage,
      UsageType = USAGE_TYPE_GRANTMAKING,
      ReferenceRecordId = fundingOpportunityId,
      ContactId = contactId
    );
  }

  private static Id getProgramId(String name) {
    return [
      SELECT
        Id
      FROM
        FundingOpportunity
      WHERE
        Name = :name
      LIMIT
        1
    ].Id;
  }

  private static Id getApplicationFormId(String title) {
    return [
      SELECT
        Id
      FROM
        ApplicationForm
      WHERE
        Title = :title
      LIMIT
        1
    ].Id;
  }

  private static ApplicationFormEoiReviewController.ApplicationFormViewModel findByTitle(
    List<ApplicationFormEoiReviewController.ApplicationFormViewModel> viewModels,
    String title
  ) {
    for (ApplicationFormEoiReviewController.ApplicationFormViewModel viewModel : viewModels) {
      if (viewModel.title == title) {
        return viewModel;
      }
    }
    return null;
  }
}