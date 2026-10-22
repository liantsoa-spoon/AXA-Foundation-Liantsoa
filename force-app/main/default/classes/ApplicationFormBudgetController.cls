/**
 * @description       : Serves, checks and saves the budget tables of the candidate-facing application form.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 19-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   13-10-2026   LAN      Initial version
 * 1.1   16-10-2026   LAN      Add getBudgetTable, read by the budgetTable component on the Budget record page
 * 1.2   16-10-2026   LAN      Hold the wrappers and the logic; ApplicationFormBudgetService only reads and writes
 * 1.3   19-10-2026   LAN      Add totalRole to the configuration: the amount of the form a table total fills
 * 1.4   19-10-2026   LAN      Find the two tables of the amounts by the Name of their question, held in Custom Labels
 * 1.5   19-10-2026   LAN      Create no Budget for an empty table; an emptied table only clears its existing Budget
 **/
public with sharing class ApplicationFormBudgetController {
  public static final String OBJECT_BUDGET = 'Budget';
  public static final String OBJECT_BENEFIT = 'Benefit';
  @TestVisible
  private static final String TOTAL_ROLE_PROJECT_BUDGET = 'totalProjectBudget';
  @TestVisible
  private static final String TOTAL_ROLE_REQUESTED_AMOUNT = 'requestedAmount';
  @TestVisible
  private static final String ERROR_ID_REQUIRED = 'ID_REQUIRED';
  @TestVisible
  private static final String ERROR_FORM_NOT_FOUND = 'APPLICATION_FORM_NOT_FOUND';
  @TestVisible
  private static final String ERROR_QUESTION_REQUIRED = 'QUESTION_REQUIRED';
  @TestVisible
  private static final String ERROR_INVALID_VALUE = 'INVALID_VALUE';
  @TestVisible
  private static final String ERROR_TECHNICAL = 'TECHNICAL_ERROR';
  private static final String FIXED_RECORD_TYPE = 'Fixed';
  private static final String LANGUAGE_FRENCH = 'FR';
  private static final Integer NAME_MAX_LENGTH = 80;
  private static final Set<String> TABLE_OBJECT_API_NAMES = new Set<String>{ OBJECT_BUDGET, OBJECT_BENEFIT };

  @TestVisible
  private static final String KEY_NAME = 'name';
  @TestVisible
  private static final String KEY_FUNDING_STATUS = 'fundingStatus';
  @TestVisible
  private static final String KEY_FUNDING_TYPE = 'fundingType';
  @TestVisible
  private static final String KEY_YEAR_PREFIX = 'year';
  @TestVisible
  private static final String KEY_AMOUNT = 'amount';
  @TestVisible
  private static final String KEY_VALID_FROM = 'validFrom';
  @TestVisible
  private static final String KEY_VALID_UNTIL = 'validUntil';
  @TestVisible
  private static final String KEY_TYPE = 'type';
  @TestVisible
  private static final String KEY_DESCRIPTION = 'description';

  // ===================== WRAPPERS =====================

  public class BudgetDefinitionWrapper {
    @AuraEnabled
    public List<BudgetTableWrapper> tables;
    // EN or FR: the language of the form.
    @AuraEnabled
    public String formLanguage;
  }

  public class BudgetTableWrapper {
    @AuraEnabled
    public Id sectionId;
    @AuraEnabled
    public BudgetTableConfigWrapper config;
    // One map per row: the value of each cell, keyed by the keys of the columns.
    @AuraEnabled
    public List<Map<String, String>> rows;
  }

  public class BudgetTableConfigWrapper {
    @AuraEnabled
    public Id questionId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String helpText;
    @AuraEnabled
    public Boolean isMandatory;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public Integer numberOfYears;
    @AuraEnabled
    public Boolean hasTotal;
    @AuraEnabled
    public Boolean hasPercent;
    @AuraEnabled
    public Boolean hasPicklistSecuredPlanned;
    @AuraEnabled
    public Boolean hasPicklistPublicPrivate;
    @AuraEnabled
    public OptionsWrapper options;
    // totalProjectBudget, requestedAmount or null: the amount of the form the total of this table fills.
    @AuraEnabled
    public String totalRole;
    // English title: the Name of the Budget of the table.
    public String titleEn;
  }

  public class OptionsWrapper {
    @AuraEnabled
    public List<OptionWrapper> fundingStatus;
    @AuraEnabled
    public List<OptionWrapper> fundingType;
    @AuraEnabled
    public List<OptionWrapper> counterpartType;
  }

  public class OptionWrapper {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public OptionWrapper(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class BudgetTableInput {
    public Id questionId;
    public List<Map<String, String>> rows;
  }

  // ===================== ENTRY POINTS =====================
  public static Boolean isBudgetColumn(String objectApiName, Boolean isFixed) {
    return isFixed != true && TABLE_OBJECT_API_NAMES.contains(objectApiName);
  }


  @AuraEnabled
  public static BudgetDefinitionWrapper getBudgetDefinition(Id fundingOpportunityId, Id applicationFormId) {
    try {
      if (fundingOpportunityId == null && applicationFormId == null) {
        throw buildError(ERROR_ID_REQUIRED, null, 'A Funding Opportunity or Application Form Id is required.');
      }
      Id resolvedFundingOpportunityId = fundingOpportunityId;
      if (applicationFormId != null) {
        final ApplicationForm applicationForm = getReadableApplicationForm(applicationFormId);
        resolvedFundingOpportunityId = resolvedFundingOpportunityId ?? applicationForm.ReferenceRecordId;
      }
      final BudgetDefinitionWrapper definition = new BudgetDefinitionWrapper();
      definition.formLanguage = FormLanguageService.getFormLanguage(resolvedFundingOpportunityId);
      definition.tables = buildTables(resolvedFundingOpportunityId, definition.formLanguage == LANGUAGE_FRENCH);
      if (applicationFormId != null) {
        fillBudgetRows(definition.tables, applicationFormId);
        fillBenefitRows(definition.tables, applicationFormId);
      }
      return definition;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw wrapException('Unable to load the budget tables', e);
    }
  }


  @AuraEnabled
  public static BudgetDefinitionWrapper getBudgetTable(Id budgetId) {
    try {
      if (budgetId == null) {
        throw buildError(ERROR_ID_REQUIRED, null, 'A Budget Id is required.');
      }
      final BudgetDefinitionWrapper definition = new BudgetDefinitionWrapper();
      definition.formLanguage = FormLanguageService.getFormLanguage(null);
      definition.tables = new List<BudgetTableWrapper>();
      final Budget tableBudget = ApplicationFormBudgetService.getBudget(budgetId);
      if (tableBudget?.Project__c == null) {
        return definition;
      }
      final Boolean isFrench = definition.formLanguage == LANGUAGE_FRENCH;
      for (BudgetTableWrapper table : buildTables(tableBudget.Project__r.ReferenceRecordId, isFrench)) {
        if (table.config.objectApiName == OBJECT_BUDGET && getBudgetName(table) == tableBudget.Name) {
          definition.tables.add(table);
          break;
        }
      }
      fillBudgetRows(definition.tables, tableBudget.Project__c);
      return definition;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw wrapException('Unable to load the budget table', e);
    }
  }

  // tablesJson: [{ questionId, rows: [{ <key>: <value> }] }], the values sent as text. isSubmit: the mandatory
  @AuraEnabled
  public static void saveBudgetTables(Id applicationFormId, String tablesJson, Boolean isSubmit) {
    try {
      ApplicationFormController.ensureCanEditApplicationForm(applicationFormId);
      saveTables(applicationFormId, tablesJson, isSubmit == true);
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw wrapException('Unable to save the budget tables', e);
    }
  }

  // ===================== DEFINITION =====================

  // The budget belongs to the full application: the EOI questions are never read.
  @TestVisible
  private static List<BudgetTableWrapper> buildTables(Id fundingOpportunityId, Boolean isFrench) {
    final List<BudgetTableWrapper> tables = new List<BudgetTableWrapper>();
    if (fundingOpportunityId == null) {
      return tables;
    }
    final List<AssessmentQuestionAssignment> assignments = ApplicationFormBudgetService.getTableAssignments(
      fundingOpportunityId,
      TABLE_OBJECT_API_NAMES
    );
    final Set<Id> questionIds = new Set<Id>();
    for (AssessmentQuestionAssignment assignment : assignments) {
      questionIds.add(assignment.AssessmentQuestionId);
    }
    final Map<Id, AssessmentQuestionVersion> versionsByQuestionId =
      ApplicationFormBudgetService.getLatestVersionsByQuestionId(questionIds);
    final OptionsWrapper options = buildOptions();

    for (AssessmentQuestionAssignment assignment : assignments) {
      final AssessmentQuestionVersion version = versionsByQuestionId.get(assignment.AssessmentQuestionId);
      if (assignment.AssessmentQuestion.RecordType?.DeveloperName == FIXED_RECORD_TYPE || version == null) {
        continue;
      }
      final BudgetTableWrapper table = new BudgetTableWrapper();
      table.sectionId = assignment.AssessmentQuestionSetId;
      table.config = buildConfig(assignment, version, isFrench, options);
      table.rows = new List<Map<String, String>>();
      tables.add(table);
    }
    return tables;
  }

  private static BudgetTableConfigWrapper buildConfig(
    AssessmentQuestionAssignment assignment,
    AssessmentQuestionVersion version,
    Boolean isFrench,
    OptionsWrapper options
  ) {
    final BudgetTableConfigWrapper config = new BudgetTableConfigWrapper();
    config.questionId = assignment.AssessmentQuestionId;
    config.titleEn = version.QuestionText;
    config.title = isFrench == true && String.isNotBlank(version.QuestionTextFR__c)
      ? version.QuestionTextFR__c
      : version.QuestionText;
    config.helpText = version.HelpText;
    config.isMandatory = assignment.IsMandatory__c == true;
    config.objectApiName = assignment.AssessmentQuestion.ObjectAPIName__c;
    final Boolean isBudget = config.objectApiName == OBJECT_BUDGET;
    config.numberOfYears = isBudget && version.NumberOfYears__c != null ? version.NumberOfYears__c.intValue() : 0;
    config.hasTotal = isBudget && version.HasTotal__c;
    config.hasPercent = isBudget && version.HasPercent__c;
    config.hasPicklistSecuredPlanned = isBudget && version.HasPicklistSecuredPlanned__c;
    config.hasPicklistPublicPrivate = isBudget && version.HasPicklistPublicPrivate__c;
    config.options = options;
    final String questionName = assignment.AssessmentQuestion.Name;
    if (isBudget && questionName == System.Label.BudgetTotalProjectBudgetQuestionName) {
      config.totalRole = TOTAL_ROLE_PROJECT_BUDGET;
    } else if (isBudget && questionName == System.Label.BudgetRequestedAmountQuestionName) {
      config.totalRole = TOTAL_ROLE_REQUESTED_AMOUNT;
    }
    return config;
  }

  // The active values of the picklists of the tables, with their labels in the language of the user.
  private static OptionsWrapper buildOptions() {
    final OptionsWrapper options = new OptionsWrapper();
    options.fundingStatus = toOptions(BudgetCategoryValue.FundingStatus__c.getDescribe().getPicklistValues());
    options.fundingType = toOptions(BudgetCategoryValue.FundingType__c.getDescribe().getPicklistValues());
    options.counterpartType = toOptions(Benefit.Type__c.getDescribe().getPicklistValues());
    return options;
  }

  private static List<OptionWrapper> toOptions(List<Schema.PicklistEntry> entries) {
    final List<OptionWrapper> options = new List<OptionWrapper>();
    for (Schema.PicklistEntry entry : entries) {
      if (entry.isActive()) {
        options.add(new OptionWrapper(entry.getLabel(), entry.getValue()));
      }
    }
    return options;
  }

  private static String getBudgetName(BudgetTableWrapper table) {
    final String titleEn = String.isBlank(table.config.titleEn)
      ? String.valueOf(table.config.questionId)
      : table.config.titleEn;
    return titleEn.left(NAME_MAX_LENGTH);
  }

  // ===================== READ =====================

  private static void fillBudgetRows(List<BudgetTableWrapper> tables, Id applicationFormId) {
    final Map<String, BudgetTableWrapper> tablesByBudgetName = new Map<String, BudgetTableWrapper>();
    for (BudgetTableWrapper table : tables) {
      if (table.config.objectApiName == OBJECT_BUDGET) {
        tablesByBudgetName.put(getBudgetName(table), table);
      }
    }
    if (tablesByBudgetName.isEmpty()) {
      return;
    }
    final Map<String, Budget> budgetsByName = ApplicationFormBudgetService.getBudgetsByName(
      applicationFormId,
      tablesByBudgetName.keySet()
    );
    final Map<Id, BudgetTableWrapper> tablesByBudgetId = new Map<Id, BudgetTableWrapper>();
    for (String budgetName : budgetsByName.keySet()) {
      tablesByBudgetId.put(budgetsByName.get(budgetName).Id, tablesByBudgetName.get(budgetName));
    }
    if (tablesByBudgetId.isEmpty()) {
      return;
    }
    final List<BudgetCategory> categories = ApplicationFormBudgetService.getCategories(tablesByBudgetId.keySet());
    final Map<Id, List<BudgetCategoryValue>> valuesByCategoryId = ApplicationFormBudgetService.getValuesByCategoryId(
      new Map<Id, BudgetCategory>(categories).keySet()
    );
    for (BudgetCategory category : categories) {
      final Map<String, String> valuesByKey = new Map<String, String>{ KEY_NAME => category.Name };
      for (BudgetCategoryValue value : valuesByCategoryId.get(category.Id) ?? new List<BudgetCategoryValue>()) {
        final Decimal periodSequence = value.BudgetDivision?.SequenceNumber;
        if (periodSequence == null) {
          valuesByKey.put(KEY_FUNDING_STATUS, value.FundingStatus__c);
          valuesByKey.put(KEY_FUNDING_TYPE, value.FundingType__c);
        } else {
          valuesByKey.put(KEY_YEAR_PREFIX + periodSequence.intValue(), toText(value.Amount));
        }
      }
      tablesByBudgetId.get(category.BudgetId).rows.add(valuesByKey);
    }
  }

  // The counterparts of the Application Form, in their creation order: one counterparts table per form.
  private static void fillBenefitRows(List<BudgetTableWrapper> tables, Id applicationFormId) {
    BudgetTableWrapper benefitTable;
    for (BudgetTableWrapper table : tables) {
      if (table.config.objectApiName == OBJECT_BENEFIT) {
        benefitTable = table;
        break;
      }
    }
    final Id benefitTypeId = benefitTable == null ? null : ApplicationFormBudgetService.getCounterpartBenefitTypeId();
    if (benefitTypeId == null) {
      return;
    }
    for (Benefit benefit : ApplicationFormBudgetService.getCounterparts(applicationFormId, benefitTypeId)) {
      benefitTable.rows.add(
        new Map<String, String>{
          KEY_NAME => benefit.Name,
          KEY_AMOUNT => toText(benefit.MaxBenefitAmount),
          KEY_VALID_FROM => toText(benefit.ValidFrom__c),
          KEY_VALID_UNTIL => toText(benefit.ValidUntil__c),
          KEY_TYPE => benefit.Type__c,
          KEY_DESCRIPTION => benefit.Description
        }
      );
    }
  }

  // ===================== SAVE =====================

  private static void saveTables(Id applicationFormId, String tablesJson, Boolean isSubmit) {
    if (String.isBlank(tablesJson) && !isSubmit) {
      return;
    }
    final List<BudgetTableInput> inputs = String.isBlank(tablesJson)
      ? new List<BudgetTableInput>()
      : (List<BudgetTableInput>) JSON.deserialize(tablesJson, List<BudgetTableInput>.class);
    final ApplicationForm appForm = ApplicationFormBudgetService.getApplicationForm(applicationFormId);
    final Map<Id, BudgetTableWrapper> tablesByQuestionId = new Map<Id, BudgetTableWrapper>();
    for (BudgetTableWrapper table : buildTables(appForm.ReferenceRecordId, false)) {
      tablesByQuestionId.put(table.config.questionId, table);
    }
    final Map<Id, List<Map<String, String>>> rowsByQuestionId = new Map<Id, List<Map<String, String>>>();
    for (BudgetTableInput input : inputs ?? new List<BudgetTableInput>()) {
      if (input != null && tablesByQuestionId.containsKey(input.questionId)) {
        rowsByQuestionId.put(input.questionId, removeEmptyRows(input.rows));
      }
    }
    if (isSubmit) {
      validateMandatoryTables(tablesByQuestionId.values(), rowsByQuestionId);
    }
    final Map<Id, List<Map<String, String>>> budgetRowsByQuestionId = new Map<Id, List<Map<String, String>>>();
    for (Id questionId : rowsByQuestionId.keySet()) {
      final BudgetTableWrapper table = tablesByQuestionId.get(questionId);
      validateRows(table, rowsByQuestionId.get(questionId));
      if (table.config.objectApiName == OBJECT_BENEFIT) {
        saveBenefitRows(appForm, rowsByQuestionId.get(questionId));
      } else {
        budgetRowsByQuestionId.put(questionId, rowsByQuestionId.get(questionId));
      }
    }
    saveBudgetRows(appForm, tablesByQuestionId, budgetRowsByQuestionId);
  }

  // One Budget per table, found by its Name: its periods are kept, its rows replaced, its Amount is its total.
  // An empty table creates no Budget; it only clears the Budget it already has.
  private static void saveBudgetRows(
    ApplicationForm appForm,
    Map<Id, BudgetTableWrapper> tablesByQuestionId,
    Map<Id, List<Map<String, String>>> rowsByQuestionId
  ) {
    if (rowsByQuestionId.isEmpty()) {
      return;
    }
    final Set<String> budgetNames = new Set<String>();
    for (Id questionId : rowsByQuestionId.keySet()) {
      budgetNames.add(getBudgetName(tablesByQuestionId.get(questionId)));
    }
    final Map<String, Budget> existingBudgetsByName = ApplicationFormBudgetService.getBudgetsByName(
      appForm.Id,
      budgetNames
    );
    final Map<String, BudgetTableWrapper> tablesByBudgetName = new Map<String, BudgetTableWrapper>();
    for (Id questionId : rowsByQuestionId.keySet()) {
      final BudgetTableWrapper table = tablesByQuestionId.get(questionId);
      final String budgetName = getBudgetName(table);
      final Boolean hasRows = !rowsByQuestionId.get(questionId).isEmpty();
      if (hasRows || existingBudgetsByName.containsKey(budgetName)) {
        tablesByBudgetName.put(budgetName, table);
      }
    }
    if (tablesByBudgetName.isEmpty()) {
      return;
    }
    final Map<String, Budget> budgetsByName = ApplicationFormBudgetService.getOrCreateBudgets(
      appForm,
      tablesByBudgetName.keySet()
    );
    final Map<Id, Integer> numberOfYearsByBudgetId = new Map<Id, Integer>();
    for (String budgetName : tablesByBudgetName.keySet()) {
      numberOfYearsByBudgetId.put(
        budgetsByName.get(budgetName).Id,
        tablesByBudgetName.get(budgetName).config.numberOfYears
      );
    }
    final Map<Id, Map<Integer, Id>> periodIdsByYearByBudgetId =
      ApplicationFormBudgetService.getOrCreatePeriods(numberOfYearsByBudgetId);

    // Each row becomes a category, and its cells the values of that category, in the same order.
    final List<BudgetCategory> categories = new List<BudgetCategory>();
    final List<List<BudgetCategoryValue>> valuesByRow = new List<List<BudgetCategoryValue>>();
    final List<Budget> budgetTotals = new List<Budget>();
    Decimal requestedAmount;
    for (String budgetName : tablesByBudgetName.keySet()) {
      final BudgetTableWrapper table = tablesByBudgetName.get(budgetName);
      final Id budgetId = budgetsByName.get(budgetName).Id;
      Decimal total = 0;
      Integer sequenceNumber = 0;
      for (Map<String, String> valuesByKey : rowsByQuestionId.get(table.config.questionId)) {
        sequenceNumber += 1;
        categories.add(
          new BudgetCategory(
            BudgetId = budgetId,
            Name = valuesByKey.get(KEY_NAME).trim().left(NAME_MAX_LENGTH),
            SequenceNumber = sequenceNumber
          )
        );
        final List<BudgetCategoryValue> values = buildCategoryValues(
          valuesByKey,
          table.config.numberOfYears,
          periodIdsByYearByBudgetId.get(budgetId)
        );
        for (BudgetCategoryValue value : values) {
          total += value.Amount ?? 0;
        }
        valuesByRow.add(values);
      }
      budgetTotals.add(new Budget(Id = budgetId, Amount = total));
      if (table.config.totalRole == TOTAL_ROLE_REQUESTED_AMOUNT) {
        requestedAmount = total;
      }
    }
    ApplicationFormBudgetService.replaceCategories(numberOfYearsByBudgetId.keySet(), categories, valuesByRow);
    ApplicationFormBudgetService.updateBudgets(budgetTotals);
    if (requestedAmount != null) {
      ApplicationFormBudgetService.updateRequestedAmount(appForm.Id, requestedAmount);
    }
  }

  // The values of a row: one per filled year, and one without period for the funding status and type.
  private static List<BudgetCategoryValue> buildCategoryValues(
    Map<String, String> valuesByKey,
    Integer numberOfYears,
    Map<Integer, Id> periodIdsByYear
  ) {
    final List<BudgetCategoryValue> values = new List<BudgetCategoryValue>();
    for (Integer year = 1; year <= numberOfYears; year++) {
      final Decimal amount = toDecimal(valuesByKey.get(KEY_YEAR_PREFIX + year));
      if (amount != null) {
        values.add(new BudgetCategoryValue(BudgetDivisionId = periodIdsByYear.get(year), Amount = amount));
      }
    }
    final String fundingStatus = toText(valuesByKey.get(KEY_FUNDING_STATUS));
    final String fundingType = toText(valuesByKey.get(KEY_FUNDING_TYPE));
    if (fundingStatus != null || fundingType != null) {
      values.add(new BudgetCategoryValue(FundingStatus__c = fundingStatus, FundingType__c = fundingType));
    }
    return values;
  }

  // The counterparts are replaced: one Benefit per filled row.
  private static void saveBenefitRows(ApplicationForm appForm, List<Map<String, String>> rows) {
    final Id benefitTypeId = ApplicationFormBudgetService.getCounterpartBenefitTypeId();
    if (benefitTypeId == null) {
      throw buildError(
        ERROR_TECHNICAL,
        null,
        'The Benefit Type "' + ApplicationFormBudgetService.COUNTERPART_BENEFIT_TYPE_NAME + '" does not exist.'
      );
    }
    // A Benefit requires its Program (the pillar): the one of the Funding Opportunity of the form.
    final Id pillarId = ApplicationFormBudgetService.getPillarId(appForm.ReferenceRecordId);
    final List<Benefit> benefits = new List<Benefit>();
    for (Map<String, String> valuesByKey : rows) {
      benefits.add(
        new Benefit(
          BenefitTypeId = benefitTypeId,
          Project__c = appForm.Id,
          ProgramId = pillarId,
          Name = valuesByKey.get(KEY_NAME).trim(),
          MaxBenefitAmount = toDecimal(valuesByKey.get(KEY_AMOUNT)),
          ValidFrom__c = toDate(valuesByKey.get(KEY_VALID_FROM)),
          ValidUntil__c = toDate(valuesByKey.get(KEY_VALID_UNTIL)),
          Type__c = toText(valuesByKey.get(KEY_TYPE)),
          Description = toText(valuesByKey.get(KEY_DESCRIPTION))
        )
      );
    }
    ApplicationFormBudgetService.replaceCounterparts(appForm.Id, benefitTypeId, benefits);
  }

  // ===================== VALIDATION =====================

  private static List<Map<String, String>> removeEmptyRows(List<Map<String, String>> rows) {
    final List<Map<String, String>> filledRows = new List<Map<String, String>>();
    for (Map<String, String> row : rows ?? new List<Map<String, String>>()) {
      if (row == null) {
        continue;
      }
      for (String value : row.values()) {
        if (String.isNotBlank(value)) {
          filledRows.add(row);
          break;
        }
      }
    }
    return filledRows;
  }

  // A mandatory table needs at least one complete row: its name and, for a Budget table, at least one amount.
  private static void validateMandatoryTables(
    List<BudgetTableWrapper> tables,
    Map<Id, List<Map<String, String>>> rowsByQuestionId
  ) {
    for (BudgetTableWrapper table : tables) {
      final List<Map<String, String>> rows = rowsByQuestionId.get(table.config.questionId) ??
        new List<Map<String, String>>();
      if (table.config.isMandatory && !hasCompleteRow(table, rows)) {
        throw buildError(
          ERROR_QUESTION_REQUIRED,
          new List<String>{ table.config.title },
          '"' + table.config.title + '" requires at least one complete row.'
        );
      }
    }
  }

  private static Boolean hasCompleteRow(BudgetTableWrapper table, List<Map<String, String>> rows) {
    for (Map<String, String> row : rows) {
      Boolean hasAmount = table.config.numberOfYears == 0;
      for (Integer year = 1; year <= table.config.numberOfYears; year++) {
        hasAmount = hasAmount || String.isNotBlank(row.get(KEY_YEAR_PREFIX + year));
      }
      if (String.isNotBlank(row.get(KEY_NAME)) && hasAmount) {
        return true;
      }
    }
    return false;
  }

  private static void validateRows(BudgetTableWrapper table, List<Map<String, String>> rows) {
    final BudgetTableConfigWrapper config = table.config;
    for (Map<String, String> row : rows) {
      if (String.isBlank(row.get(KEY_NAME))) {
        throw buildError(
          ERROR_QUESTION_REQUIRED,
          new List<String>{ config.title },
          'Every row of "' + config.title + '" requires its name.'
        );
      }
      if (config.objectApiName == OBJECT_BENEFIT) {
        validateNumber(config, row.get(KEY_AMOUNT));
        validateDate(config, row.get(KEY_VALID_FROM));
        validateDate(config, row.get(KEY_VALID_UNTIL));
        validateOption(config, config.options.counterpartType, row.get(KEY_TYPE));
        continue;
      }
      for (Integer year = 1; year <= config.numberOfYears; year++) {
        validateNumber(config, row.get(KEY_YEAR_PREFIX + year));
      }
      if (config.hasPicklistSecuredPlanned) {
        validateOption(config, config.options.fundingStatus, row.get(KEY_FUNDING_STATUS));
      }
      if (config.hasPicklistPublicPrivate) {
        validateOption(config, config.options.fundingType, row.get(KEY_FUNDING_TYPE));
      }
    }
  }

  private static void validateNumber(BudgetTableConfigWrapper config, String value) {
    try {
      toDecimal(value);
    } catch (TypeException e) {
      throw buildInvalidValueError(config);
    }
  }

  private static void validateDate(BudgetTableConfigWrapper config, String value) {
    try {
      toDate(value);
    } catch (TypeException e) {
      throw buildInvalidValueError(config);
    }
  }

  private static void validateOption(BudgetTableConfigWrapper config, List<OptionWrapper> options, String value) {
    if (String.isBlank(value)) {
      return;
    }
    for (OptionWrapper option : options) {
      if (option.value == value) {
        return;
      }
    }
    throw buildInvalidValueError(config);
  }

  // ===================== HELPERS =====================

  // The budget is read in user mode: the user must be able to read the Application Form.
  private static ApplicationForm getReadableApplicationForm(Id applicationFormId) {
    final ApplicationForm applicationForm = ApplicationFormBudgetService.getApplicationForm(applicationFormId);
    if (applicationForm == null) {
      throw buildError(ERROR_FORM_NOT_FOUND, null, 'The Application Form could not be found.');
    }
    return applicationForm;
  }

  private static Decimal toDecimal(String value) {
    return String.isBlank(value) ? null : Decimal.valueOf(value.trim());
  }

  private static Date toDate(String value) {
    return String.isBlank(value) ? null : Date.valueOf(value.trim());
  }

  private static String toText(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof String) {
      return String.isBlank((String) value) ? null : (String) value;
    }
    if (value instanceof Date) {
      return String.valueOf(value);
    }
    return value instanceof Decimal ? ((Decimal) value).toPlainString() : String.valueOf(value);
  }

  private static AuraHandledException buildInvalidValueError(BudgetTableConfigWrapper config) {
    return buildError(
      ERROR_INVALID_VALUE,
      new List<String>{ config.title },
      'A value of "' + config.title + '" is not valid.'
    );
  }

  private static AuraHandledException buildError(String code, List<String> params, String detail) {
    final String message = JSON.serialize(
      new Map<String, Object>{ 'code' => code, 'params' => params ?? new List<String>(), 'detail' => detail }
    );
    final AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }

  private static AuraHandledException wrapException(String context, Exception e) {
    final String detail = context + ': ' + e.getMessage();
    System.debug(LoggingLevel.ERROR, detail + '\n' + e.getStackTraceString());
    return buildError(ERROR_TECHNICAL, null, detail);
  }
}