/**
 * @description       : Budget tables of the application form, with row and column totals and percentages.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 13-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   13-10-2026   LAN      Initial version
 **/
import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getBudgetDefinition from "@salesforce/apex/ApplicationFormBudgetController.getBudgetDefinition";
import saveBudgetTables from "@salesforce/apex/ApplicationFormBudgetController.saveBudgetTables";

const FORM_LANGUAGE_FRENCH = "FR";
// Every amount of the budget is in euros.
const CURRENCY_CODE = "EUR";
const CURRENCY_SYMBOL = "€";

const LABELS = {
  en: {
    total: "Total",
    percent: "Percentage",
    addRow: "Add a row",
    deleteRow: "Delete row",
    required: "required",
    selectPlaceholder: "Select an option",
    noValue: "—",
    loading: "Loading",
    missingContext:
      "Set the Application Form Id or the Funding Opportunity Id of the component.",
    noTable: "No budget table is configured for this program.",
    save: "Save",
    saved: "Budget saved.",
    successTitle: "Success",
    errorTitle: "Error",
    unexpectedError: "An unexpected error occurred."
  },
  fr: {
    total: "Total",
    percent: "Pourcentage",
    addRow: "Ajouter une ligne",
    deleteRow: "Supprimer la ligne",
    required: "obligatoire",
    selectPlaceholder: "Sélectionnez une option",
    noValue: "—",
    loading: "Chargement",
    missingContext:
      "Renseignez l'Id de l'Application Form ou de la Funding Opportunity du composant.",
    noTable: "Aucun tableau budget n'est configuré pour ce programme.",
    save: "Enregistrer",
    saved: "Budget enregistré.",
    successTitle: "Succès",
    errorTitle: "Erreur",
    unexpectedError: "Une erreur inattendue est survenue."
  }
};

let rowKeySeed = 0;

function buildBudgetRowKey() {
  rowKeySeed += 1;
  return `budget-row-${rowKeySeed}`;
}

function toAmount(value) {
  const amount = Number.parseFloat(value);
  return Number.isFinite(amount) ? amount : 0;
}

function sumAmounts(values) {
  return values.reduce((total, value) => total + toAmount(value), 0);
}

function toRowStates(rows) {
  return (rows?.length ? rows : [{}]).map((values) => ({
    key: buildBudgetRowKey(),
    values: { ...values }
  }));
}

/**
 * Two modes. Controlled: the tables come from the form, which keeps them across the sections and saves them;
 * every change is sent back through the budgetchange event, with the new rows of the table. Standalone (record
 * page or Experience page, without tables): the component loads the budget of recordId or fundingOpportunityId
 * itself and saves it with its own button.
 */
export default class ApplicationFormBudgetTable extends LightningElement {
  @api readOnly = false;
  // Standalone mode: the Application Form of the record page, or a program without form.
  @api recordId;
  @api fundingOpportunityId;

  // [{ tableKey, title, hasTotal, hasPercent, columns: [...], rows: [{ key, values: { columnKey: value } }] }]
  @api
  get tables() {
    return this.tableStates;
  }
  set tables(value) {
    this.isControlled = true;
    this.tableStates = value || [];
  }

  @api
  get formLanguage() {
    return this.language;
  }
  set formLanguage(value) {
    this.language = value;
  }

  tableStates = [];
  hasLoaded = false;
  // Sections of the accordion: every table is open until the candidate closes it.
  closedTableKeys = [];
  language;
  isControlled = false;
  isLoading = false;
  isSaving = false;

  connectedCallback() {
    if (!this.isControlled && (this.recordId || this.fundingOpportunityId)) {
      this.loadDefinition();
    }
  }

  async loadDefinition() {
    this.isLoading = true;
    try {
      const definition = await getBudgetDefinition({
        fundingOpportunityId: this.fundingOpportunityId,
        applicationFormId: this.recordId
      });
      this.language = definition?.formLanguage;
      this.tableStates = (definition?.tables || []).map((table) => ({
        ...table,
        rows: toRowStates(table.rows)
      }));
    } catch (error) {
      this.showToast(this.labels.errorTitle, this.getErrorMessage(error), "error");
    } finally {
      this.isLoading = false;
      this.hasLoaded = true;
    }
  }

  // Standalone mode only: the reason why no table is shown.
  get emptyMessage() {
    if (this.isControlled || this.isLoading) {
      return null;
    }
    if (!this.recordId && !this.fundingOpportunityId) {
      return this.labels.missingContext;
    }
    return this.hasLoaded && this.tableStates.length === 0 ? this.labels.noTable : null;
  }

  get isStandaloneSaveVisible() {
    return (
      !this.isControlled &&
      Boolean(this.recordId) &&
      this.isEditable &&
      this.tableStates.length > 0
    );
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await saveBudgetTables({
        applicationFormId: this.recordId,
        tablesJson: JSON.stringify(
          this.tableStates.map((table) => ({
            tableKey: table.tableKey,
            rows: table.rows.map((row) => row.values)
          }))
        )
      });
      this.showToast(this.labels.successTitle, this.labels.saved, "success");
      await this.loadDefinition();
    } catch (error) {
      this.showToast(this.labels.errorTitle, this.getErrorMessage(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  // The Apex errors are JSON { code, params, detail }: the English detail is shown while testing the table.
  getErrorMessage(error) {
    const message = error?.body?.message || error?.message;
    try {
      return JSON.parse(message).detail || this.labels.unexpectedError;
    } catch (parseError) {
      return message || this.labels.unexpectedError;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  get labels() {
    return this.language === FORM_LANGUAGE_FRENCH ? LABELS.fr : LABELS.en;
  }

  get currencyCode() {
    return CURRENCY_CODE;
  }

  get totalHeader() {
    return this.withCurrency(this.labels.total);
  }

  // "Year 1 (€)": the amount columns and the total show their currency.
  withCurrency(label) {
    return `${label} (${CURRENCY_SYMBOL})`;
  }

  get isEditable() {
    return !this.readOnly;
  }

  get hasTables() {
    return this.tableStates.length > 0;
  }

  handleSectionToggle(event) {
    const { tableKey } = event.currentTarget.dataset;
    this.closedTableKeys = this.closedTableKeys.includes(tableKey)
      ? this.closedTableKeys.filter((closedKey) => closedKey !== tableKey)
      : [...this.closedTableKeys, tableKey];
  }

  get tableViews() {
    return this.tableStates.map((table) => this.buildTableView(table));
  }

  buildTableView(table) {
    const columns = table.columns || [];
    const amountColumns = columns.filter((column) => column.isAmount);
    const rowTotals = (table.rows || []).map((row) =>
      sumAmounts(amountColumns.map((column) => row.values[column.columnKey]))
    );
    const grandTotal = rowTotals.reduce((total, rowTotal) => total + rowTotal, 0);
    // Percentage of a row: its share of the total of its own table; none while the table totals 0.
    const hasPercent = grandTotal > 0;
    const rows = (table.rows || []).map((row, index) => {
      const total = rowTotals[index];
      return {
        key: row.key,
        total,
        percent: hasPercent ? total / grandTotal : null,
        hasPercent,
        cells: columns.map((column) => ({
          columnKey: column.columnKey,
          label: column.label,
          value: row.values[column.columnKey] ?? "",
          options: column.options,
          isPicklist: column.isPicklist,
          isCurrency: column.isCurrency === true,
          isDate: column.isDate === true,
          isTextArea: column.isTextArea === true
        }))
      };
    });
    const isOpen = !this.closedTableKeys.includes(table.tableKey);
    return {
      ...table,
      sectionClass: isOpen
        ? "slds-accordion__section slds-is-open"
        : "slds-accordion__section",
      ariaExpanded: String(isOpen),
      headers: columns.map((column) => ({
        key: column.columnKey,
        label: column.isCurrency ? this.withCurrency(column.label) : column.label,
        isRequired: column.isMandatory === true && column.isRowName !== true,
        cssClass: column.isCurrency
          ? "slds-text-align_right"
          : column.isRowName
            ? "budget-table__name"
            : ""
      })),
      rows,
      footerCells: columns.map((column, index) => ({
        key: column.columnKey,
        isLabel: index === 0,
        isAmount: index > 0 && column.isAmount,
        total: column.isAmount
          ? sumAmounts(table.rows.map((row) => row.values[column.columnKey]))
          : null
      })),
      grandTotal,
      grandPercent: hasPercent ? 1 : null,
      hasGrandPercent: hasPercent
    };
  }

  handleCellChange(event) {
    const { tableKey, rowKey, columnKey } = event.target.dataset;
    const value = event.detail.value ?? "";
    this.dispatchRows(tableKey, (rows) =>
      rows.map((row) =>
        row.key === rowKey
          ? { ...row, values: { ...row.values, [columnKey]: String(value) } }
          : row
      )
    );
  }

  handleAddRow(event) {
    const { tableKey } = event.target.dataset;
    this.dispatchRows(tableKey, (rows) => [
      ...rows,
      { key: buildBudgetRowKey(), values: {} }
    ]);
  }

  // The last row is emptied rather than removed: the table always keeps a row to fill in.
  handleDeleteRow(event) {
    const { tableKey, rowKey } = event.target.dataset;
    this.dispatchRows(tableKey, (rows) => {
      const remainingRows = rows.filter((row) => row.key !== rowKey);
      return remainingRows.length
        ? remainingRows
        : [{ key: buildBudgetRowKey(), values: {} }];
    });
  }

  dispatchRows(tableKey, updateRows) {
    const table = this.tableStates.find((item) => item.tableKey === tableKey);
    if (!table) {
      return;
    }
    if (!this.isControlled) {
      this.tableStates = this.tableStates.map((item) =>
        item.tableKey === tableKey
          ? { ...item, rows: updateRows(item.rows || []) }
          : item
      );
      return;
    }
    this.dispatchEvent(
      new CustomEvent("budgetchange", {
        detail: { tableKey, rows: updateRows(table.rows || []) }
      })
    );
  }
}
