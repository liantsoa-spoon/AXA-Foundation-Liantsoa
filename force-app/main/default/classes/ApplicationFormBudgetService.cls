/**
 * @description       : Reads and writes the records of the budget tables of the application form.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 19-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   13-10-2026   LAN      Initial version
 * 1.1   16-10-2026   LAN      One question per table, configured on its version; one Budget per table
 * 1.2   16-10-2026   LAN      Keep only the queries and the DML: the logic moves to ApplicationFormBudgetController
 * 1.3   19-10-2026   LAN      Read the Name of the table questions
 * 1.4   19-10-2026   LAN      Read the name of the counterpart Benefit Type from a Custom Label
 **/
public with sharing class ApplicationFormBudgetService {
  // Benefit Type of the counterparts, the master of their Benefit records: to create in each org.
  public static final String COUNTERPART_BENEFIT_TYPE_NAME = System.Label.BudgetCounterpartBenefitTypeName;
  private static final String PERIOD_NAME_PREFIX = 'Year ';

  // ===================== APPLICATION FORM AND BUDGET (USER MODE) =====================

  // Null when the connected user cannot read it.
  public static ApplicationForm getApplicationForm(Id applicationFormId) {
    final List<ApplicationForm> applicationForms = [
      SELECT
        Id,
        AccountId,
        ReferenceRecordId
      FROM
        ApplicationForm
      WHERE
        Id = :applicationFormId
      WITH
        USER_MODE
      LIMIT
        1
    ];
    return applicationForms.isEmpty() ? null : applicationForms[0];
  }

  public static Budget getBudget(Id budgetId) {
    final List<Budget> budgets = [
      SELECT
        Id,
        Name,
        Project__c,
        Project__r.ReferenceRecordId
      FROM
        Budget
      WHERE
        Id = :budgetId
      WITH
        USER_MODE
      LIMIT
        1
    ];
    return budgets.isEmpty() ? null : budgets[0];
  }

  public static Map<String, Budget> getBudgetsByName(Id applicationFormId, Set<String> budgetNames) {
    final Map<String, Budget> budgetsByName = new Map<String, Budget>();
    for (Budget tableBudget : [
      SELECT
        Id,
        Name
      FROM
        Budget
      WHERE
        Project__c = :applicationFormId
        AND Name IN :budgetNames
      WITH
        USER_MODE
    ]) {
      budgetsByName.put(tableBudget.Name, tableBudget);
    }
    return budgetsByName;
  }

  public static Map<String, Budget> getOrCreateBudgets(ApplicationForm appForm, Set<String> budgetNames) {
    final Map<String, Budget> budgetsByName = getBudgetsByName(appForm.Id, budgetNames);
    final List<Budget> newBudgets = new List<Budget>();
    for (String budgetName : budgetNames) {
      if (!budgetsByName.containsKey(budgetName)) {
        final Budget tableBudget = new Budget(
          Name = budgetName,
          Project__c = appForm.Id,
          AccountId = appForm.AccountId
        );
        newBudgets.add(tableBudget);
        budgetsByName.put(budgetName, tableBudget);
      }
    }
    Database.insert(newBudgets, AccessLevel.USER_MODE);
    return budgetsByName;
  }

  public static Map<Id, Map<Integer, Id>> getOrCreatePeriods(Map<Id, Integer> numberOfYearsByBudgetId) {
    final Map<Id, Map<Integer, Id>> periodIdsByYearByBudgetId = new Map<Id, Map<Integer, Id>>();
    for (Id budgetId : numberOfYearsByBudgetId.keySet()) {
      periodIdsByYearByBudgetId.put(budgetId, new Map<Integer, Id>());
    }
    final Set<Id> budgetIds = numberOfYearsByBudgetId.keySet();
    for (BudgetPeriod period : [
      SELECT
        Id,
        BudgetId,
        SequenceNumber
      FROM
        BudgetPeriod
      WHERE
        BudgetId IN :budgetIds
        AND SequenceNumber != null
      WITH
        USER_MODE
    ]) {
      periodIdsByYearByBudgetId.get(period.BudgetId).put(period.SequenceNumber.intValue(), period.Id);
    }

    final List<BudgetPeriod> newPeriods = new List<BudgetPeriod>();
    for (Id budgetId : budgetIds) {
      for (Integer year = 1; year <= numberOfYearsByBudgetId.get(budgetId); year++) {
        if (!periodIdsByYearByBudgetId.get(budgetId).containsKey(year)) {
          newPeriods.add(
            new BudgetPeriod(BudgetId = budgetId, Name = PERIOD_NAME_PREFIX + year, SequenceNumber = year)
          );
        }
      }
    }
    Database.insert(newPeriods, AccessLevel.USER_MODE);
    for (BudgetPeriod period : newPeriods) {
      periodIdsByYearByBudgetId.get(period.BudgetId).put(period.SequenceNumber.intValue(), period.Id);
    }
    return periodIdsByYearByBudgetId;
  }

  public static List<BudgetCategory> getCategories(Set<Id> budgetIds) {
    return [
      SELECT
        Id,
        BudgetId,
        Name
      FROM
        BudgetCategory
      WHERE
        BudgetId IN :budgetIds
      WITH
        USER_MODE
      ORDER BY
        SequenceNumber ASC NULLS LAST
    ];
  }

  public static Map<Id, List<BudgetCategoryValue>> getValuesByCategoryId(Set<Id> categoryIds) {
    final Map<Id, List<BudgetCategoryValue>> valuesByCategoryId = new Map<Id, List<BudgetCategoryValue>>();
    for (BudgetCategoryValue value : [
      SELECT
        BudgetCategoryId,
        Amount,
        FundingStatus__c,
        FundingType__c,
        BudgetDivision.SequenceNumber
      FROM
        BudgetCategoryValue
      WHERE
        BudgetCategoryId IN :categoryIds
      WITH
        USER_MODE
    ]) {
      if (!valuesByCategoryId.containsKey(value.BudgetCategoryId)) {
        valuesByCategoryId.put(value.BudgetCategoryId, new List<BudgetCategoryValue>());
      }
      valuesByCategoryId.get(value.BudgetCategoryId).add(value);
    }
    return valuesByCategoryId;
  }

  public static void replaceCategories(
    Set<Id> budgetIds,
    List<BudgetCategory> categories,
    List<List<BudgetCategoryValue>> valuesByCategory
  ) {
    final List<BudgetCategory> existingCategories = [
      SELECT
        Id
      FROM
        BudgetCategory
      WHERE
        BudgetId IN :budgetIds
      WITH
        USER_MODE
    ];
    Database.delete(existingCategories, AccessLevel.USER_MODE);
    Database.insert(categories, AccessLevel.USER_MODE);

    final List<BudgetCategoryValue> values = new List<BudgetCategoryValue>();
    for (Integer index = 0; index < categories.size(); index++) {
      for (BudgetCategoryValue value : valuesByCategory[index]) {
        value.BudgetCategoryId = categories[index].Id;
        values.add(value);
      }
    }
    Database.insert(values, AccessLevel.USER_MODE);
  }

  public static void updateBudgets(List<Budget> budgets) {
    Database.update(budgets, AccessLevel.USER_MODE);
  }

  public static void updateRequestedAmount(Id applicationFormId, Decimal requestedAmount) {
    Database.update(
      new ApplicationForm(Id = applicationFormId, RequestedAmount = requestedAmount),
      AccessLevel.USER_MODE
    );
  }

  public static List<AssessmentQuestionAssignment> getTableAssignments(
    Id fundingOpportunityId,
    Set<String> objectApiNames
  ) {
    return new CatalogueQueries().getTableAssignments(fundingOpportunityId, objectApiNames);
  }

  public static Map<Id, AssessmentQuestionVersion> getLatestVersionsByQuestionId(Set<Id> questionIds) {
    return new CatalogueQueries().getLatestVersionsByQuestionId(questionIds);
  }

  public static Id getCounterpartBenefitTypeId() {
    return new CatalogueQueries().getCounterpartBenefitTypeId();
  }

  public static Id getPillarId(Id fundingOpportunityId) {
    return new CatalogueQueries().getPillarId(fundingOpportunityId);
  }

  // The form catalogue, the Benefit Type and the pillar are configuration a candidate cannot read.
  private without sharing class CatalogueQueries {
    // The full application questions of the program that target the given objects, in the order of the form.
    List<AssessmentQuestionAssignment> getTableAssignments(Id fundingOpportunityId, Set<String> objectApiNames) {
      return [
        SELECT
          AssessmentQuestionSetId,
          AssessmentQuestionId,
          AssessmentQuestion.Name,
          AssessmentQuestion.ObjectAPIName__c,
          AssessmentQuestion.RecordType.DeveloperName,
          IsMandatory__c
        FROM
          AssessmentQuestionAssignment
        WHERE
          FundingOpportunity__c = :fundingOpportunityId
          AND EOI__c = false
          AND AssessmentQuestion.ObjectAPIName__c IN :objectApiNames
        WITH
          SYSTEM_MODE
        ORDER BY
          AssessmentQuestionSet.Sequence__c ASC NULLS LAST,
          AssessmentQuestion.Sequence__c ASC NULLS LAST
      ];
    }

    // The latest version of each question: its labels and the configuration of its table.
    Map<Id, AssessmentQuestionVersion> getLatestVersionsByQuestionId(Set<Id> questionIds) {
      final Map<Id, AssessmentQuestionVersion> versionsByQuestionId = new Map<Id, AssessmentQuestionVersion>();
      for (AssessmentQuestionVersion version : [
        SELECT
          AssessmentQuestionId,
          QuestionText,
          QuestionTextFR__c,
          HelpText,
          NumberOfYears__c,
          HasTotal__c,
          HasPercent__c,
          HasPicklistSecuredPlanned__c,
          HasPicklistPublicPrivate__c
        FROM
          AssessmentQuestionVersion
        WHERE
          AssessmentQuestionId IN :questionIds
        WITH
          SYSTEM_MODE
        ORDER BY
          CreatedDate DESC
      ]) {
        if (!versionsByQuestionId.containsKey(version.AssessmentQuestionId)) {
          versionsByQuestionId.put(version.AssessmentQuestionId, version);
        }
      }
      return versionsByQuestionId;
    }

    Id getCounterpartBenefitTypeId() {
      final List<BenefitType> benefitTypes = [
        SELECT
          Id
        FROM
          BenefitType
        WHERE
          Name = :COUNTERPART_BENEFIT_TYPE_NAME
        WITH
          SYSTEM_MODE
        LIMIT
          1
      ];
      return benefitTypes.isEmpty() ? null : benefitTypes[0].Id;
    }

    Id getPillarId(Id fundingOpportunityId) {
      final List<FundingOpportunity> fundingOpportunities = [
        SELECT
          ProgramId
        FROM
          FundingOpportunity
        WHERE
          Id = :fundingOpportunityId
        WITH
          SYSTEM_MODE
        LIMIT
          1
      ];
      return fundingOpportunities.isEmpty() ? null : fundingOpportunities[0].ProgramId;
    }
  }


  public static List<Benefit> getCounterparts(Id applicationFormId, Id benefitTypeId) {
    return new CounterpartQueries().getCounterparts(applicationFormId, benefitTypeId);
  }

  public static void replaceCounterparts(Id applicationFormId, Id benefitTypeId, List<Benefit> benefits) {
    new CounterpartQueries().replaceCounterparts(applicationFormId, benefitTypeId, benefits);
  }

  private without sharing class CounterpartQueries {
    List<Benefit> getCounterparts(Id applicationFormId, Id benefitTypeId) {
      if (getApplicationForm(applicationFormId) == null) {
        return new List<Benefit>();
      }
      return [
        SELECT
          Name,
          MaxBenefitAmount,
          ValidFrom__c,
          ValidUntil__c,
          Type__c,
          Description
        FROM
          Benefit
        WHERE
          Project__c = :applicationFormId
          AND BenefitTypeId = :benefitTypeId
        WITH
          SYSTEM_MODE
        ORDER BY
          CreatedDate ASC,
          Id ASC
      ];
    }

    void replaceCounterparts(Id applicationFormId, Id benefitTypeId, List<Benefit> benefits) {
      if (getApplicationForm(applicationFormId) == null) {
        return;
      }
      final List<Benefit> existingBenefits = [
        SELECT
          Id
        FROM
          Benefit
        WHERE
          Project__c = :applicationFormId
          AND BenefitTypeId = :benefitTypeId
        WITH
          SYSTEM_MODE
      ];
      Database.delete(existingBenefits, AccessLevel.SYSTEM_MODE);
      Database.insert(benefits, AccessLevel.SYSTEM_MODE);
    }
  }
}