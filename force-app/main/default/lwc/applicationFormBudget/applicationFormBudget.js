/**
 * @description       : Budget block of the application form: its tables and the two amounts computed from them.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 19-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   19-10-2026   LAN      Initial version
 * 1.1   19-10-2026   LAN      Read the messages that name the foundation from Custom Labels
 **/
import { LightningElement, api } from "lwc";
import getBudgetDefinition from "@salesforce/apex/ApplicationFormBudgetController.getBudgetDefinition";
import saveBudgetTables from "@salesforce/apex/ApplicationFormBudgetController.saveBudgetTables";
import requestedAmountLabel from "@salesforce/label/c.ApplicationFormBudgetRequestedAmount";
import loadErrorLabel from "@salesforce/label/c.ApplicationFormBudgetLoadError";

const FORM_LANGUAGE_FRENCH = "FR";
const CURRENCY_CODE = "EUR";
// Roles of a table total, set by ApplicationFormBudgetController.
const TOTAL_ROLE_PROJECT_BUDGET = "totalProjectBudget";
const TOTAL_ROLE_REQUESTED_AMOUNT = "requestedAmount";
const KEY_NAME = "name";
const KEY_YEAR_PREFIX = "year";

const LABELS = {
  en: {
    loading: "Loading",
    totalProjectBudget: "Total project budget (in euros)",
    requestedAmount: requestedAmountLabel,
    loadError: loadErrorLabel
  },
  fr: {
    loading: "Chargement",
    totalProjectBudget: "Budget total du projet (en euros)",
    requestedAmount: requestedAmountLabel,
    loadError: loadErrorLabel
  }
};

function isFilled(value) {
  return String(value ?? "").trim() !== "";
}

function toAmount(value) {
  const amount = Number.parseFloat(value);
  return Number.isFinite(amount) ? amount : 0;
}

/**
 * Budget block of the application form. It loads the tables of the program (and the rows saved for the form), keeps
 * their rows while the candidate moves between the sections, shows the total budget of the project and the amount
 * requested, computed from their tables, and saves everything when the form asks for it:
 * - validate(): true when every mandatory table holds a complete row;
 * - save(applicationFormId, isSubmit): saves the tables; the submission also checks the mandatory tables.
 */
export default class ApplicationFormBudget extends LightningElement {
  @api readOnly = false;

  // [{ sectionId, config, rows: [{ key, values }] }]
  tables = [];
  totalsByQuestionId = {};
  formLanguage;
  isLoading = false;
  hasLoadError = false;
  loadedKey;

  _fundingOpportunityId;
  _applicationFormId;

  @api
  get fundingOpportunityId() {
    return this._fundingOpportunityId;
  }
  set fundingOpportunityId(value) {
    this._fundingOpportunityId = value;
    this.loadIfChanged();
  }

  // Empty for a form not saved yet: the tables are then shown without rows.
  @api
  get applicationFormId() {
    return this._applicationFormId;
  }
  set applicationFormId(value) {
    this._applicationFormId = value;
    this.loadIfChanged();
  }

  get labels() {
    return this.formLanguage === FORM_LANGUAGE_FRENCH ? LABELS.fr : LABELS.en;
  }

  get currencyCode() {
    return CURRENCY_CODE;
  }

  get hasTables() {
    return this.tables.length > 0;
  }

  get totalProjectBudget() {
    return this.getTotalOfRole(TOTAL_ROLE_PROJECT_BUDGET);
  }

  get requestedAmount() {
    return this.getTotalOfRole(TOTAL_ROLE_REQUESTED_AMOUNT);
  }

  get hasTotalProjectBudget() {
    return this.totalProjectBudget !== null;
  }

  get hasRequestedAmount() {
    return this.requestedAmount !== null;
  }

  get hasAmounts() {
    return this.hasTotalProjectBudget || this.hasRequestedAmount;
  }

  // The total of the table of this role, or null when the program has no such table.
  getTotalOfRole(totalRole) {
    const table = this.tables.find((item) => item.config.totalRole === totalRole);
    return table ? this.totalsByQuestionId[table.config.questionId] ?? 0 : null;
  }

  // ===================== LOAD =====================

  // The block reloads only when the program or the form changes, not at every render of the form.
  loadIfChanged() {
    const key = `${this._fundingOpportunityId || ""}|${this._applicationFormId || ""}`;
    if (!this._fundingOpportunityId && !this._applicationFormId) {
      return;
    }
    if (key === this.loadedKey) {
      return;
    }
    this.loadedKey = key;
    this.loadTables();
  }

  async loadTables() {
    this.isLoading = true;
    this.hasLoadError = false;
    try {
      const definition = await getBudgetDefinition({
        fundingOpportunityId: this._fundingOpportunityId,
        applicationFormId: this._applicationFormId
      });
      this.formLanguage = definition?.formLanguage;
      this.tables = (definition?.tables || []).map((table) => ({
        sectionId: table.sectionId,
        config: table.config,
        rows: table.rows || []
      }));
      this.totalsByQuestionId = {};
      this.tables.forEach((table) => {
        this.totalsByQuestionId[table.config.questionId] = this.computeTotal(table);
      });
    } catch (error) {
      this.hasLoadError = true;
    } finally {
      this.isLoading = false;
    }
  }

  // Total of a table as Apex returns its rows: the sum of the years of every row.
  computeTotal(table) {
    return (table.rows || []).reduce((total, row) => {
      const values = row.values || row;
      let rowTotal = 0;
      for (let year = 1; year <= (table.config.numberOfYears || 0); year += 1) {
        rowTotal += toAmount(values[`${KEY_YEAR_PREFIX}${year}`]);
      }
      return total + rowTotal;
    }, 0);
  }

  // ===================== EVENTS =====================

  // The rows are kept here, so the candidate keeps them across the sections; the total feeds the amounts.
  handleTableChange(event) {
    const { questionId, rows, total } = event.detail;
    this.tables = this.tables.map((table) =>
      table.config.questionId === questionId ? { ...table, rows } : table
    );
    this.totalsByQuestionId = { ...this.totalsByQuestionId, [questionId]: total };
    this.dispatchEvent(new CustomEvent("budgetchange"));
  }

  // ===================== PUBLIC METHODS =====================

  // True when every mandatory table holds a complete row: its name and, for a Budget table, an amount.
  @api
  validate() {
    return this.tables.every((table) => !table.config.isMandatory || this.hasCompleteRow(table));
  }

  hasCompleteRow(table) {
    const numberOfYears = table.config.numberOfYears || 0;
    return (table.rows || []).some((row) => {
      const values = row.values || row;
      let hasAmount = numberOfYears === 0;
      for (let year = 1; year <= numberOfYears; year += 1) {
        hasAmount = hasAmount || isFilled(values[`${KEY_YEAR_PREFIX}${year}`]);
      }
      return isFilled(values[KEY_NAME]) && hasAmount;
    });
  }

  // Saves the tables of the form; an Apex error is passed on to the form, which translates it.
  @api
  async save(applicationFormId, isSubmit = false) {
    const formId = applicationFormId || this._applicationFormId;
    if (!formId || !this.hasTables || this.readOnly) {
      return;
    }
    // Set before the call: the form passes the new Id of a form created by this save, which must not reload the
    // tables and lose the rows being saved.
    this._applicationFormId = formId;
    this.loadedKey = `${this._fundingOpportunityId || ""}|${formId}`;
    await saveBudgetTables({
      applicationFormId: formId,
      tablesJson: JSON.stringify(
        this.tables.map((table) => ({
          questionId: table.config.questionId,
          rows: (table.rows || []).map((row) => this.toTextValues(row.values || row))
        }))
      ),
      isSubmit
    });
  }

  // The values are sent as text.
  toTextValues(values) {
    return Object.fromEntries(
      Object.entries(values || {}).map(([key, value]) => [key, value == null ? "" : String(value)])
    );
  }
}