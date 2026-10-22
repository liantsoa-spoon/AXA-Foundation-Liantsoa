/**
 * @description       : Test class for ApplicationFormBudgetController.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 19-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   13-10-2026   LAN      Initial version
 * 1.1   16-10-2026   LAN      One question per table; test getBudgetTable
 * 1.2   16-10-2026   LAN      Test the logic moved from ApplicationFormBudgetService
 * 1.3   19-10-2026   LAN      Test the totalRole of the configuration
 * 1.4   19-10-2026   LAN      Name the tables of the amounts after their Custom Labels
 * 1.5   19-10-2026   LAN      Neutral title for the counterparts test question
 * 1.6   19-10-2026   LAN      Test that an empty table creates no Budget and an emptied one clears it
 **/
@isTest
private class ApplicationFormBudgetController_TEST {
  private static final String TEST_USER_LAST_NAME = 'OrgBudgetControllerUser';
  // The Name of the question, as the Custom Label holds it: the table of the total budget of the project.
  private static final String TOTAL_TITLE = System.Label.BudgetTotalProjectBudgetQuestionName;
  private static final String FUNDER_TITLE = 'Main public/private financial partners of the project';
  private static final String COUNTERPART_TITLE = 'What counterparts would you like to offer?';

  // The counterparts are never saved here: BenefitType does not accept DML in Apex, and a saved Benefit needs one.
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
      Alias = 'orgbctl',
      Email = 'orgbudgetcontroller@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = TEST_USER_LAST_NAME,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = adminProfile.Id,
      TimeZoneSidKey = 'Europe/Paris',
      Username = 'orgbudgetcontroller' + Datetime.now().getTime() + '@testorg.com'
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
      createTable(fundingOpportunity.Id, sectionId, 1, 'Budget', TOTAL_TITLE, 'Budget total', 2, false);
      createTable(
        fundingOpportunity.Id,
        sectionId,
        2,
        'Budget',
        System.Label.BudgetRequestedAmountQuestionName,
        'Budget demandé',
        1,
        false
      );
      createTable(fundingOpportunity.Id, sectionId, 3, 'Budget', FUNDER_TITLE, 'Financeurs', 1, true);
      createTable(fundingOpportunity.Id, sectionId, 4, 'Benefit', COUNTERPART_TITLE, 'Contreparties', null, false);
    }
  }

  private static void createTable(
    Id fundingOpportunityId,
    Id sectionId,
    Integer sequence,
    String objectApiName,
    String title,
    String titleFr,
    Integer numberOfYears,
    Boolean hasPercentAndPicklists
  ) {
    final Id questionId = ApplicationFormCatalogueController.createFormQuestion(
      title.left(80),
      title,
      'TextBlock',
      null,
      null,
      'Help',
      null,
      true,
      null,
      sectionId,
      null,
      sequence,
      fundingOpportunityId,
      false,
      null,
      null,
      false,
      titleFr,
      null
    );
    update new AssessmentQuestion(Id = questionId, ObjectAPIName__c = objectApiName, FieldAPIName__c = 'Name');
    final AssessmentQuestionVersion version = [
      SELECT
        Id
      FROM
        AssessmentQuestionVersion
      WHERE
        AssessmentQuestionId = :questionId
      LIMIT
        1
    ];
    version.NumberOfYears__c = numberOfYears;
    version.HasTotal__c = numberOfYears != null;
    version.HasPercent__c = hasPercentAndPicklists;
    version.HasPicklistSecuredPlanned__c = hasPercentAndPicklists;
    version.HasPicklistPublicPrivate__c = hasPercentAndPicklists;
    update version;
  }

  private static User getTestUser() {
    return [
      SELECT
        Id
      FROM
        User
      WHERE
        LastName = :TEST_USER_LAST_NAME
      LIMIT
        1
    ];
  }

  private static Id getFundingOpportunityId() {
    return [
      SELECT
        Id
      FROM
        FundingOpportunity
      WHERE
        Name = 'Budget FO'
      LIMIT
        1
    ]
    .Id;
  }

  private static ApplicationForm createApplicationForm(String stage) {
    final ApplicationForm applicationForm = new ApplicationForm(
      ReferenceRecordId = getFundingOpportunityId(),
      UsageType = 'Grantmaking',
      Stage = stage
    );
    insert applicationForm;
    return applicationForm;
  }

  private static ApplicationFormBudgetController.BudgetTableWrapper findTable(String title) {
    for (
      ApplicationFormBudgetController.BudgetTableWrapper table : ApplicationFormBudgetController.getBudgetDefinition(
          getFundingOpportunityId(),
          null
        )
        .tables
    ) {
      if (table.config.titleEn == title) {
        return table;
      }
    }
    return null;
  }

  private static Map<String, Object> buildInput(String title, List<Map<String, String>> rows) {
    return new Map<String, Object>{ 'questionId' => findTable(title).config.questionId, 'rows' => rows };
  }

  private static String getErrorCode(AuraHandledException error) {
    return (String) ((Map<String, Object>) JSON.deserializeUntyped(error.getMessage())).get('code');
  }

  // Saves the given rows of one table and returns the code of the error raised, or null.
  private static String saveAndGetErrorCode(
    Id applicationFormId,
    String title,
    List<Map<String, String>> rows,
    Boolean isSubmit
  ) {
    try {
      ApplicationFormBudgetController.saveBudgetTables(
        applicationFormId,
        JSON.serialize(new List<Object>{ buildInput(title, rows) }),
        isSubmit
      );
    } catch (AuraHandledException e) {
      return getErrorCode(e);
    }
    return null;
  }

  @isTest
  static void isBudgetColumn_givenObjectAndFixedFlag_returnsWhetherTheBlockShowsIt() {
    Assert.isTrue(ApplicationFormBudgetController.isBudgetColumn('Budget', false), 'Budget table');
    Assert.isTrue(ApplicationFormBudgetController.isBudgetColumn('Benefit', null), 'Benefit table');
    Assert.isFalse(ApplicationFormBudgetController.isBudgetColumn('Budget', true), 'Fixed question on Budget');
    Assert.isFalse(ApplicationFormBudgetController.isBudgetColumn('Contact', false), 'Other object');
  }

  @isTest
  static void getBudgetDefinition_givenNoId_throwsIdRequired() {
    System.runAs(getTestUser()) {
      String errorCode;

      Test.startTest();
      try {
        ApplicationFormBudgetController.getBudgetDefinition(null, null);
      } catch (AuraHandledException e) {
        errorCode = getErrorCode(e);
      }
      Test.stopTest();

      Assert.areEqual(ApplicationFormBudgetController.ERROR_ID_REQUIRED, errorCode, 'An Id is required');
    }
  }

  @isTest
  static void getBudgetDefinition_givenProgram_returnsTheConfigurationOfItsTables() {
    System.runAs(getTestUser()) {
      Test.startTest();
      final ApplicationFormBudgetController.BudgetDefinitionWrapper definition =
        ApplicationFormBudgetController.getBudgetDefinition(getFundingOpportunityId(), null);
      Test.stopTest();

      Assert.areEqual(4, definition.tables.size(), 'One table per question');
      Assert.isNotNull(definition.formLanguage, 'Language of the form');
      final ApplicationFormBudgetController.BudgetTableConfigWrapper total = definition.tables[0].config;
      Assert.areEqual('Help', total.helpText, 'Help text of the version');
      Assert.areEqual(2, total.numberOfYears, 'Number of years');
      Assert.isTrue(total.hasTotal, 'Total');
      Assert.areEqual(
        ApplicationFormBudgetController.TOTAL_ROLE_PROJECT_BUDGET,
        total.totalRole,
        'Its total is the total budget of the project'
      );
      Assert.areEqual(
        ApplicationFormBudgetController.TOTAL_ROLE_REQUESTED_AMOUNT,
        definition.tables[1].config.totalRole,
        'Its total is the amount requested'
      );
      Assert.isNull(definition.tables[2].config.totalRole, 'The funders fill no amount of the form');
      final ApplicationFormBudgetController.BudgetTableConfigWrapper funders = definition.tables[2].config;
      Assert.isTrue(funders.hasPercent && funders.hasPicklistSecuredPlanned, 'Percentage and picklists');
      Assert.isFalse(funders.options.fundingStatus.isEmpty(), 'Values of the funding status');
      final ApplicationFormBudgetController.BudgetTableConfigWrapper counterparts = definition.tables[3].config;
      Assert.areEqual('Benefit', counterparts.objectApiName, 'Counterparts table');
      Assert.areEqual(0, counterparts.numberOfYears, 'No years for the counterparts');
    }
  }

  @isTest
  static void buildTables_givenFrench_returnsTheFrenchTitles() {
    System.runAs(getTestUser()) {
      Test.startTest();
      final List<ApplicationFormBudgetController.BudgetTableWrapper> tables =
        ApplicationFormBudgetController.buildTables(getFundingOpportunityId(), true);
      Test.stopTest();

      Assert.areEqual('Budget total', tables[0].config.title, 'French title');
      Assert.areEqual(TOTAL_TITLE, tables[0].config.titleEn, 'English title kept for the Budget');
    }
  }

  @isTest
  static void getBudgetDefinition_givenUnknownApplicationForm_throwsFormNotFound() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      final Id deletedApplicationFormId = applicationForm.Id;
      delete applicationForm;
      String errorCode;

      Test.startTest();
      try {
        ApplicationFormBudgetController.getBudgetDefinition(null, deletedApplicationFormId);
      } catch (AuraHandledException e) {
        errorCode = getErrorCode(e);
      }
      Test.stopTest();

      Assert.areEqual(ApplicationFormBudgetController.ERROR_FORM_NOT_FOUND, errorCode, 'The form must be readable');
    }
  }

  @isTest
  static void saveBudgetTables_givenRows_savesOneBudgetPerTableAndReadsThemBack() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      final ApplicationFormBudgetController.BudgetTableWrapper funders = findTable(FUNDER_TITLE);
      final String statusValue = funders.config.options.fundingStatus[0].value;
      final String typeValue = funders.config.options.fundingType[0].value;
      final List<Object> inputs = new List<Object>{
        buildInput(
          TOTAL_TITLE,
          new List<Map<String, String>>{
            new Map<String, String>{ 'name' => 'Salaries', 'year1' => '1000', 'year2' => '500.5' },
            new Map<String, String>{ 'name' => '', 'year1' => '' },
            new Map<String, String>{ 'name' => 'Equipment', 'year2' => '200' }
          }
        ),
        buildInput(
          System.Label.BudgetRequestedAmountQuestionName,
          new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Salaries', 'year1' => '800' } }
        ),
        buildInput(
          FUNDER_TITLE,
          new List<Map<String, String>>{
            new Map<String, String>{
              'name' => 'Region',
              'fundingStatus' => statusValue,
              'fundingType' => typeValue,
              'year1' => '300'
            }
          }
        ),
        new Map<String, Object>{ 'questionId' => null, 'rows' => new List<Map<String, String>>() }
      };

      Test.startTest();
      ApplicationFormBudgetController.saveBudgetTables(applicationForm.Id, JSON.serialize(inputs), false);
      final ApplicationFormBudgetController.BudgetDefinitionWrapper definition =
        ApplicationFormBudgetController.getBudgetDefinition(null, applicationForm.Id);
      Test.stopTest();

      final Map<String, Budget> budgetsByName = new Map<String, Budget>();
      for (Budget tableBudget : [
        SELECT
          Name,
          Amount
        FROM
          Budget
        WHERE
          Project__c = :applicationForm.Id
      ]) {
        budgetsByName.put(tableBudget.Name, tableBudget);
      }
      Assert.areEqual(3, budgetsByName.size(), 'One Budget per Budget table, named after its English title');
      Assert.areEqual(1700.5, budgetsByName.get(TOTAL_TITLE).Amount, 'Total of the project');
      Assert.areEqual(300, budgetsByName.get(FUNDER_TITLE).Amount, 'Total of the funders');
      final ApplicationForm savedForm = [
        SELECT
          RequestedAmount
        FROM
          ApplicationForm
        WHERE
          Id = :applicationForm.Id
      ];
      Assert.areEqual(800, savedForm.RequestedAmount, 'The total requested fills the Application Form');

      final ApplicationFormBudgetController.BudgetTableWrapper savedTotal = definition.tables[0];
      Assert.areEqual(2, savedTotal.rows.size(), 'The empty row is not saved');
      Assert.areEqual('Salaries', savedTotal.rows[0].get('name'), 'Order of the rows');
      Assert.areEqual('500.50', savedTotal.rows[0].get('year2'), 'Amount of year 2');
      final ApplicationFormBudgetController.BudgetTableWrapper savedFunders = definition.tables[2];
      Assert.areEqual(statusValue, savedFunders.rows[0].get('fundingStatus'), 'Funding status');
      Assert.areEqual(typeValue, savedFunders.rows[0].get('fundingType'), 'Funding type');
    }
  }

  @isTest
  static void saveBudgetTables_givenSavedRows_replacesThemInTheSameBudget() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Old', 'year1' => '10' } },
        false
      );

      Test.startTest();
      saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'New', 'year1' => '20' } },
        false
      );
      Test.stopTest();

      final List<Budget> budgets = [
        SELECT
          Amount
        FROM
          Budget
        WHERE
          Project__c = :applicationForm.Id
      ];
      Assert.areEqual(1, budgets.size(), 'The Budget is reused');
      Assert.areEqual(20, budgets[0].Amount, 'Total of the new rows');
      final List<BudgetCategory> categories = [
        SELECT
          Name
        FROM
          BudgetCategory
      ];
      Assert.areEqual(1, categories.size(), 'The rows are replaced');
      Assert.areEqual('New', categories[0].Name, 'New row');
    }
  }

  @isTest
  static void saveBudgetTables_givenEmptyTables_createsNoBudget() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      final List<Map<String, String>> emptyRows = new List<Map<String, String>>{
        new Map<String, String>{ 'name' => ' ', 'year1' => '' }
      };

      Test.startTest();
      ApplicationFormBudgetController.saveBudgetTables(
        applicationForm.Id,
        JSON.serialize(new List<Object>{ buildInput(TOTAL_TITLE, emptyRows), buildInput(FUNDER_TITLE, emptyRows) }),
        false
      );
      Test.stopTest();

      final Integer budgetCount = [
        SELECT
          COUNT()
        FROM
          Budget
        WHERE
          Project__c = :applicationForm.Id
      ];
      final Integer periodCount = [
        SELECT
          COUNT()
        FROM
          BudgetPeriod
      ];
      Assert.areEqual(0, budgetCount, 'No Budget for an empty table');
      Assert.areEqual(0, periodCount, 'No period for an empty table');
    }
  }

  @isTest
  static void saveBudgetTables_givenOneFilledTable_createsOnlyItsBudget() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      final List<Map<String, String>> filledRows = new List<Map<String, String>>{
        new Map<String, String>{ 'name' => 'Staff', 'year1' => '100' }
      };

      Test.startTest();
      ApplicationFormBudgetController.saveBudgetTables(
        applicationForm.Id,
        JSON.serialize(
          new List<Object>{
            buildInput(TOTAL_TITLE, filledRows),
            buildInput(FUNDER_TITLE, new List<Map<String, String>>())
          }
        ),
        false
      );
      Test.stopTest();

      final List<Budget> budgets = [
        SELECT
          Name
        FROM
          Budget
        WHERE
          Project__c = :applicationForm.Id
      ];
      Assert.areEqual(1, budgets.size(), 'Only the filled table has a Budget');
      Assert.areEqual(TOTAL_TITLE, budgets[0].Name, 'Budget of the filled table');
    }
  }

  @isTest
  static void saveBudgetTables_givenEmptiedTable_clearsItsExistingBudget() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Staff', 'year1' => '100' } },
        false
      );

      Test.startTest();
      saveAndGetErrorCode(applicationForm.Id, TOTAL_TITLE, new List<Map<String, String>>(), false);
      Test.stopTest();

      final List<Budget> budgets = [
        SELECT
          Amount
        FROM
          Budget
        WHERE
          Project__c = :applicationForm.Id
      ];
      Assert.areEqual(1, budgets.size(), 'The existing Budget is kept');
      Assert.areEqual(0, budgets[0].Amount, 'Its total is reset');
      final Integer categoryCount = [
        SELECT
          COUNT()
        FROM
          BudgetCategory
      ];
      Assert.areEqual(0, categoryCount, 'Its rows are deleted');
    }
  }

  @isTest
  static void saveBudgetTables_givenInvalidValues_throwsTheErrors() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');

      Test.startTest();
      final String missingName = saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'year1' => '10' } },
        false
      );
      final String invalidAmount = saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Item', 'year1' => 'abc' } },
        false
      );
      final String invalidOption = saveAndGetErrorCode(
        applicationForm.Id,
        FUNDER_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Funder', 'fundingStatus' => 'Other' } },
        false
      );
      final String invalidDate = saveAndGetErrorCode(
        applicationForm.Id,
        COUNTERPART_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Venue', 'validFrom' => 'tomorrow' } },
        false
      );
      final String missingBenefitType = saveAndGetErrorCode(
        applicationForm.Id,
        COUNTERPART_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Venue' } },
        false
      );
      Test.stopTest();

      Assert.areEqual(ApplicationFormBudgetController.ERROR_QUESTION_REQUIRED, missingName, 'A row needs its name');
      Assert.areEqual(ApplicationFormBudgetController.ERROR_INVALID_VALUE, invalidAmount, 'An amount is a number');
      Assert.areEqual(ApplicationFormBudgetController.ERROR_INVALID_VALUE, invalidOption, 'Only the picklist values');
      Assert.areEqual(ApplicationFormBudgetController.ERROR_INVALID_VALUE, invalidDate, 'A date is valid');
      Assert.areEqual(ApplicationFormBudgetController.ERROR_TECHNICAL, missingBenefitType, 'The Benefit Type exists');
    }
  }

  @isTest
  static void saveBudgetTables_givenMandatoryTableAtSubmission_requiresACompleteRow() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      final List<AssessmentQuestionAssignment> assignments = [
        SELECT
          Id,
          AssessmentQuestion.Name
        FROM
          AssessmentQuestionAssignment
        WHERE
          FundingOpportunity__c = :applicationForm.ReferenceRecordId
      ];
      for (AssessmentQuestionAssignment assignment : assignments) {
        assignment.IsMandatory__c = assignment.AssessmentQuestion.Name == TOTAL_TITLE;
      }
      update assignments;

      Test.startTest();
      final String draftError = saveAndGetErrorCode(applicationForm.Id, TOTAL_TITLE, null, false);
      final String noAmountError = saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Item' } },
        true
      );
      final String completeError = saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Item', 'year2' => '5' } },
        true
      );
      Test.stopTest();

      Assert.isNull(draftError, 'A draft is never blocked');
      Assert.areEqual(ApplicationFormBudgetController.ERROR_QUESTION_REQUIRED, noAmountError, 'A row needs an amount');
      Assert.isNull(completeError, 'A complete row is enough');
    }
  }

  @isTest
  static void saveBudgetTables_givenSubmittedForm_throwsAlreadySubmitted() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Submitted');

      Test.startTest();
      final String errorCode = saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Item', 'year1' => '10' } },
        false
      );
      Test.stopTest();

      Assert.areEqual('APPLICATION_ALREADY_SUBMITTED', errorCode, 'A submitted form is locked');
    }
  }

  @isTest
  static void saveBudgetTables_givenInvalidJson_throwsTechnicalError() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      String errorCode;

      Test.startTest();
      try {
        ApplicationFormBudgetController.saveBudgetTables(applicationForm.Id, '{not json', false);
      } catch (AuraHandledException e) {
        errorCode = getErrorCode(e);
      }
      Test.stopTest();

      Assert.areEqual(ApplicationFormBudgetController.ERROR_TECHNICAL, errorCode, 'An unexpected error is technical');
    }
  }

  @isTest
  static void getBudgetTable_givenSavedBudget_returnsItsTable() {
    System.runAs(getTestUser()) {
      final ApplicationForm applicationForm = createApplicationForm('Draft');
      saveAndGetErrorCode(
        applicationForm.Id,
        TOTAL_TITLE,
        new List<Map<String, String>>{ new Map<String, String>{ 'name' => 'Item', 'year1' => '10' } },
        false
      );
      final Budget tableBudget = [
        SELECT
          Id
        FROM
          Budget
        WHERE
          Project__c = :applicationForm.Id
        LIMIT
          1
      ];

      Test.startTest();
      final ApplicationFormBudgetController.BudgetDefinitionWrapper definition =
        ApplicationFormBudgetController.getBudgetTable(tableBudget.Id);
      Test.stopTest();

      Assert.areEqual(1, definition.tables.size(), 'The table of the Budget');
      Assert.areEqual(TOTAL_TITLE, definition.tables[0].config.title, 'Found by the Name of the Budget');
      Assert.areEqual(1, definition.tables[0].rows.size(), 'Its saved row');
    }
  }

  @isTest
  static void getBudgetTable_givenBudgetWithoutFormOrId_returnsNoTableOrThrows() {
    System.runAs(getTestUser()) {
      final Budget tableBudget = new Budget(Name = 'Budget without form');
      insert tableBudget;
      String errorCode;

      Test.startTest();
      final ApplicationFormBudgetController.BudgetDefinitionWrapper definition =
        ApplicationFormBudgetController.getBudgetTable(tableBudget.Id);
      try {
        ApplicationFormBudgetController.getBudgetTable(null);
      } catch (AuraHandledException e) {
        errorCode = getErrorCode(e);
      }
      Test.stopTest();

      Assert.areEqual(0, definition.tables.size(), 'No form, no table');
      Assert.areEqual(ApplicationFormBudgetController.ERROR_ID_REQUIRED, errorCode, 'A Budget is required');
    }
  }
}
