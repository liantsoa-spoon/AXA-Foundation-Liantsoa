/**
 * @description       : Test class for ApplicationFormBudgetService.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 16-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   13-10-2026   LAN      Initial version
 * 1.1   16-10-2026   LAN      One question per table, configured on its version; one Budget per table
 * 1.2   16-10-2026   LAN      Test the queries and the DML only; the logic is tested by the controller
 **/
@isTest
private class ApplicationFormBudgetService_TEST {
  private static final String TABLE_TITLE = 'Total project budget per year (in euros)';

  @testSetup
  static void setupTestData() {
    final Profile adminProfile = [
      SELECT
        Id
      FROM
        Profile
      WHERE
        Name = 'System Administrator'
      LIMIT
        1
    ];
    final User testUser = new User(
      Alias = 'orgbudg',
      Email = 'orgbudget@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'OrgBudgetUser',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = adminProfile.Id,
      TimeZoneSidKey = 'Europe/Paris',
      Username = 'orgbudget' + Datetime.now().getTime() + '@testorg.com'
    );
    insert testUser;

    final List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permissionSet : [
      SELECT
        Id
      FROM
        PermissionSet
      WHERE
        Name IN ('Admin_Access', 'Grantmaking_Manager')
    ]) {
      assignments.add(new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = permissionSet.Id));
    }
    insert assignments;

    System.runAs(testUser) {
      final Program program = new Program(Name = 'Budget Program ' + Math.abs(Crypto.getRandomInteger()));
      insert program;
      final FundingOpportunity fundingOpportunity = new FundingOpportunity(
        Name = 'Budget FO',
        Status = 'Draft',
        ProgramId = program.Id
      );
      insert fundingOpportunity;
      final Id sectionId = ApplicationFormCatalogueController.createSection('Project budget', fundingOpportunity.Id);
      final Id questionId = ApplicationFormCatalogueController.createQuestion(
        TABLE_TITLE,
        TABLE_TITLE,
        'TextBlock',
        null,
        null,
        null,
        null,
        true,
        null,
        sectionId,
        null,
        1,
        fundingOpportunity.Id,
        false,
        null,
        null
      );
      update new AssessmentQuestion(Id = questionId, ObjectAPIName__c = 'Budget', FieldAPIName__c = 'Name');
      insert new ApplicationForm(ReferenceRecordId = fundingOpportunity.Id, UsageType = 'Grantmaking', Stage = 'Draft');
    }
  }

  private static User getTestUser() {
    return [
      SELECT
        Id
      FROM
        User
      WHERE
        LastName = 'OrgBudgetUser'
      LIMIT
        1
    ];
  }

  private static ApplicationForm getApplicationForm() {
    return [
      SELECT
        Id,
        AccountId,
        ReferenceRecordId
      FROM
        ApplicationForm
      LIMIT
        1
    ];
  }

  @isTest
  static void getApplicationForm_givenReadableOrMissingForm_returnsItOrNull() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = getApplicationForm();
      final Id missingId = applicationForm.Id;
      final ApplicationForm found = ApplicationFormBudgetService.getApplicationForm(applicationForm.Id);
      delete applicationForm;

      Test.startTest();
      final ApplicationForm missing = ApplicationFormBudgetService.getApplicationForm(missingId);
      Test.stopTest();

      Assert.areEqual(applicationForm.ReferenceRecordId, found.ReferenceRecordId, 'The readable form');
      Assert.isNull(missing, 'No form');
    }
  }

  @isTest
  static void getOrCreateBudgets_givenNames_createsTheMissingOnesOnly() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = getApplicationForm();
      final Map<String, Budget> createdBudgetsByName = ApplicationFormBudgetService.getOrCreateBudgets(
        applicationForm,
        new Set<String>{ TABLE_TITLE }
      );

      Test.startTest();
      final Map<String, Budget> budgetsByName = ApplicationFormBudgetService.getOrCreateBudgets(
        applicationForm,
        new Set<String>{ TABLE_TITLE, 'Second table' }
      );
      final Budget tableBudget = ApplicationFormBudgetService.getBudget(createdBudgetsByName.get(TABLE_TITLE).Id);
      Test.stopTest();

      Assert.areEqual(createdBudgetsByName.get(TABLE_TITLE).Id, budgetsByName.get(TABLE_TITLE).Id, 'Budget reused');
      Assert.areEqual(2, budgetsByName.size(), 'The missing Budget is created');
      Assert.areEqual(applicationForm.Id, tableBudget.Project__c, 'Linked to the form');
      Assert.isNull(ApplicationFormBudgetService.getBudget(null), 'No Budget');
    }
  }

  @isTest
  static void getOrCreatePeriods_givenNumberOfYears_createsOnePeriodPerYearOnce() {
    System.runAs(getTestUser()) {
      final Id budgetId = ApplicationFormBudgetService.getOrCreateBudgets(
          getApplicationForm(),
          new Set<String>{ TABLE_TITLE }
        )
        .get(TABLE_TITLE)
        .Id;
      final Map<Id, Map<Integer, Id>> firstPeriods = ApplicationFormBudgetService.getOrCreatePeriods(
        new Map<Id, Integer>{ budgetId => 2 }
      );

      Test.startTest();
      final Map<Id, Map<Integer, Id>> periods = ApplicationFormBudgetService.getOrCreatePeriods(
        new Map<Id, Integer>{ budgetId => 3 }
      );
      Test.stopTest();

      Assert.areEqual(firstPeriods.get(budgetId).get(1), periods.get(budgetId).get(1), 'Existing period kept');
      Assert.areEqual(3, periods.get(budgetId).size(), 'One period per year');
      final List<BudgetPeriod> thirdYear = [
        SELECT
          Name
        FROM
          BudgetPeriod
        WHERE
          Id = :periods.get(budgetId).get(3)
      ];
      Assert.areEqual('Year 3', thirdYear[0].Name, 'Named after its year');
    }
  }

  @isTest
  static void replaceCategories_givenRows_replacesTheCategoriesAndTheirValues() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = getApplicationForm();
      final Map<String, Budget> budgetsByName = ApplicationFormBudgetService.getOrCreateBudgets(
        applicationForm,
        new Set<String>{ TABLE_TITLE }
      );
      final Id budgetId = budgetsByName.get(TABLE_TITLE).Id;
      final Id periodId = ApplicationFormBudgetService.getOrCreatePeriods(new Map<Id, Integer>{ budgetId => 1 })
        .get(budgetId)
        .get(1);
      ApplicationFormBudgetService.replaceCategories(
        new Set<Id>{ budgetId },
        new List<BudgetCategory>{ new BudgetCategory(BudgetId = budgetId, Name = 'Old', SequenceNumber = 1) },
        new List<List<BudgetCategoryValue>>{ new List<BudgetCategoryValue>() }
      );

      Test.startTest();
      ApplicationFormBudgetService.replaceCategories(
        new Set<Id>{ budgetId },
        new List<BudgetCategory>{ new BudgetCategory(BudgetId = budgetId, Name = 'New', SequenceNumber = 1) },
        new List<List<BudgetCategoryValue>>{
          new List<BudgetCategoryValue>{ new BudgetCategoryValue(BudgetDivisionId = periodId, Amount = 10) }
        }
      );
      ApplicationFormBudgetService.updateBudgets(new List<Budget>{ new Budget(Id = budgetId, Amount = 10) });
      ApplicationFormBudgetService.updateRequestedAmount(applicationForm.Id, 10);
      Test.stopTest();

      final List<BudgetCategory> categories = ApplicationFormBudgetService.getCategories(new Set<Id>{ budgetId });
      Assert.areEqual(1, categories.size(), 'The rows are replaced');
      Assert.areEqual('New', categories[0].Name, 'New row');
      final Map<Id, List<BudgetCategoryValue>> valuesByCategoryId = ApplicationFormBudgetService.getValuesByCategoryId(
        new Set<Id>{ categories[0].Id }
      );
      Assert.areEqual(10, valuesByCategoryId.get(categories[0].Id)[0].Amount, 'Value of the row');
      Assert.areEqual(1, valuesByCategoryId.get(categories[0].Id)[0].BudgetDivision.SequenceNumber, 'Its year');
      final ApplicationForm savedForm = [
        SELECT
          RequestedAmount
        FROM
          ApplicationForm
        WHERE
          Id = :applicationForm.Id
      ];
      Assert.areEqual(10, savedForm.RequestedAmount, 'Amount requested');
    }
  }

  @isTest
  static void getTableAssignments_givenProgram_returnsItsTablesAndVersions() {
    System.runAs(getTestUser()) {
      final Id fundingOpportunityId = getApplicationForm().ReferenceRecordId;

      Test.startTest();
      final List<AssessmentQuestionAssignment> assignments = ApplicationFormBudgetService.getTableAssignments(
        fundingOpportunityId,
        new Set<String>{ 'Budget' }
      );
      final Map<Id, AssessmentQuestionVersion> versionsByQuestionId =
        ApplicationFormBudgetService.getLatestVersionsByQuestionId(new Set<Id>{ assignments[0].AssessmentQuestionId });
      final Id pillarId = ApplicationFormBudgetService.getPillarId(fundingOpportunityId);
      Test.stopTest();

      Assert.areEqual(1, assignments.size(), 'The table question');
      Assert.areEqual(
        TABLE_TITLE,
        versionsByQuestionId.get(assignments[0].AssessmentQuestionId).QuestionText,
        'Its latest version'
      );
      Assert.isNotNull(pillarId, 'Pillar of the program');
    }
  }

  @isTest
  static void counterparts_givenNoBenefitType_readAndWriteNothing() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = getApplicationForm();

      Test.startTest();
      final Id benefitTypeId = ApplicationFormBudgetService.getCounterpartBenefitTypeId();
      ApplicationFormBudgetService.replaceCounterparts(applicationForm.Id, benefitTypeId, new List<Benefit>());
      final List<Benefit> benefits = ApplicationFormBudgetService.getCounterparts(applicationForm.Id, benefitTypeId);
      final List<Benefit> unknownFormBenefits = ApplicationFormBudgetService.getCounterparts(null, benefitTypeId);
      ApplicationFormBudgetService.replaceCounterparts(null, benefitTypeId, new List<Benefit>());
      Test.stopTest();

      Assert.isNull(benefitTypeId, 'BenefitType does not accept DML in Apex: none in a test');
      Assert.isTrue(benefits.isEmpty(), 'No counterpart');
      Assert.isTrue(unknownFormBenefits.isEmpty(), 'No form, no counterpart');
    }
  }
}