/**
 * @description       : Budget or Benefit table of a question, its columns generated from the configuration.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 19-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   16-10-2026   LAN      Initial version
 * 1.1   19-10-2026   LAN      Accept rows as Apex maps and remove the totals row
 * 1.2   19-10-2026   LAN      Load the table of a Budget on its record page, read-only
 **/
import { LightningElement, api } from "lwc";
import getBudgetTable from "@salesforce/apex/ApplicationFormBudgetController.getBudgetTable";

const FORM_LANGUAGE_FRENCH = "FR";
const OBJECT_BENEFIT = "Benefit";
const CURRENCY_CODE = "EUR";
const CURRENCY_SYMBOL = "€";
const COLUMN_KEYS = {
  name: "name",
  fundingStatus: "fundingStatus",
  fundingType: "fundingType",
  yearPrefix: "year",
  amount: "amount",
  validFrom: "validFrom",
  validUntil: "validUntil",
  type: "type",
  description: "description"
};
// SLDS utility classes only: they style the cell itself, never the table of the calendar of a date input placed in
// it, as slds-table_bordered and slds-table_col-bordered would.
const CELL_BORDER = "slds-border_bottom";
const CELL_SEPARATOR = "slds-border_left";

function joinClasses(...classes) {
  return classes.filter(Boolean).join(" ");
}

const CELL_TYPES = {
  text: "text",
  currency: "currency",
  picklist: "picklist",
  date: "date",
  textArea: "textArea"
};
const LABELS = {
  en: {
    itemName: "Item Name",
    fundingStatus: "Secured or Planned",
    fundingType: "Public or Private",
    year: "Year",
    total: "Total",
    percent: "Percentage",
    title: "Title",
    amount: "Amount",
    validFrom: "Valid From",
    validUntil: "Valid Until",
    type: "Type of Counterpart",
    description: "Description",
    addRow: "Add a row",
    deleteRow: "Delete row",
    required: "required",
    selectPlaceholder: "Select an option",
    noValue: "—",
    loading: "Loading",
    loadError: "Unable to load the budget table.",
    emptyState: "No table is configured for this budget."
  },
  fr: {
    itemName: "Poste",
    fundingStatus: "Sécurisé ou prévu",
    fundingType: "Public ou privé",
    year: "Année",
    total: "Total",
    percent: "Pourcentage",
    title: "Intitulé",
    amount: "Montant",
    validFrom: "Valide du",
    validUntil: "Valide jusqu'au",
    type: "Type de contrepartie",
    description: "Description",
    addRow: "Ajouter une ligne",
    deleteRow: "Supprimer la ligne",
    required: "obligatoire",
    selectPlaceholder: "Sélectionnez une option",
    noValue: "—",
    loading: "Chargement",
    loadError: "Impossible de charger le tableau du budget.",
    emptyState: "Aucun tableau n'est configuré pour ce budget."
  }
};

let rowKeySeed = 0;

function buildRowKey() {
  rowKeySeed += 1;
  return `budget-table-row-${rowKeySeed}`;
}

function toAmount(value) {
  const amount = Number.parseFloat(value);
  return Number.isFinite(amount) ? amount : 0;
}

function isFilled(value) {
  return String(value ?? "").trim() !== "";
}

// A table always shows at least one row to fill in. A row is either a state { key, values } or, as Apex returns it,
// the map of its values.
function toRowStates(rows) {
  const filledRows = Array.isArray(rows) && rows.length ? rows : [{ values: {} }];
  return filledRows.map((row) =>
    row.values
      ? { key: row.key || buildRowKey(), values: { ...row.values } }
      : { key: buildRowKey(), values: { ...row } }
  );
}

/**
 * Table of a question of the form. Its columns come from the configuration:
 * - Budget: Item Name, [Secured or Planned], [Public or Private], Year 1 … Year N, [Total], [Percentage];
 * - Benefit: Title, Amount, Valid From, Valid Until, Type of Counterpart, Description.
 * Every change is sent through the tablechange event: { questionId, rows, total }. The component saves nothing.
 */
export default class BudgetTable extends LightningElement {
  // Form: the parent passes config, rows, readOnly and formLanguage. Budget record page: recordId alone, the table
  // loads itself through getBudgetTable and stays read-only.
  @api
  get recordId() {
    return this.budgetId;
  }
  set recordId(value) {
    this.budgetId = value;
    this.loadBudgetTable();
  }

  @api
  get config() {
    return this.tableConfig;
  }
  set config(value) {
    this.tableConfig = value || {};
  }

  @api
  get readOnly() {
    return this.isReadOnlyInput || this.isRecordPage;
  }
  set readOnly(value) {
    this.isReadOnlyInput = value === true;
  }

  @api
  get formLanguage() {
    return this.language;
  }
  set formLanguage(value) {
    this.language = value;
  }

  budgetId;
  tableConfig = {};
  isReadOnlyInput = false;
  language;
  isLoading = false;
  hasTable = true;
  errorMessage;

  // [{ key, values: { <columnKey>: value } }]
  @api
  get rows() {
    return this.rowStates;
  }
  set rows(value) {
    this.rowStates = toRowStates(value);
  }

  rowStates = toRowStates([]);
  isOpen = true;

  get labels() {
    return this.formLanguage === FORM_LANGUAGE_FRENCH ? LABELS.fr : LABELS.en;
  }

  // ===================== BUDGET RECORD PAGE =====================

  get isRecordPage() {
    return Boolean(this.budgetId);
  }

  get isTableVisible() {
    return !this.isLoading && !this.errorMessage && this.hasTable;
  }

  get isEmptyStateVisible() {
    return !this.isLoading && !this.errorMessage && !this.hasTable;
  }

  async loadBudgetTable() {
    if (!this.budgetId) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const definition = await getBudgetTable({ budgetId: this.budgetId });
      const table = definition?.tables?.[0];
      this.language = definition?.formLanguage;
      this.hasTable = Boolean(table);
      this.tableConfig = table?.config || {};
      this.rowStates = toRowStates(table?.rows);
    } catch (error) {
      this.errorMessage = error?.body?.message || this.labels.loadError;
    } finally {
      this.isLoading = false;
    }
  }

  get isEditable() {
    return !this.readOnly;
  }

  get isBenefit() {
    return this.config?.objectApiName === OBJECT_BENEFIT;
  }

  get hasTotal() {
    return !this.isBenefit && this.config?.hasTotal === true;
  }

  get hasPercent() {
    return !this.isBenefit && this.config?.hasPercent === true;
  }

  get currencyCode() {
    return CURRENCY_CODE;
  }

  get sectionClass() {
    return this.isOpen
      ? "slds-accordion__section slds-is-open"
      : "slds-accordion__section";
  }

  get ariaExpanded() {
    return String(this.isOpen);
  }

  get totalHeader() {
    return this.withCurrency(this.labels.total);
  }

  // "Year 1 (€)": the amounts and the total show their currency.
  withCurrency(label) {
    return `${label} (${CURRENCY_SYMBOL})`;
  }

  // ===================== COLUMNS =====================

  get columns() {
    return this.isBenefit ? this.buildBenefitColumns() : this.buildBudgetColumns();
  }

  buildBudgetColumns() {
    const labels = this.labels;
    const options = this.config?.options || {};
    const columns = [
      { key: COLUMN_KEYS.name, label: labels.itemName, type: CELL_TYPES.text, isRequired: true, isWide: true }
    ];
    if (this.config?.hasPicklistSecuredPlanned) {
      columns.push({
        key: COLUMN_KEYS.fundingStatus,
        label: labels.fundingStatus,
        type: CELL_TYPES.picklist,
        options: options.fundingStatus || []
      });
    }
    if (this.config?.hasPicklistPublicPrivate) {
      columns.push({
        key: COLUMN_KEYS.fundingType,
        label: labels.fundingType,
        type: CELL_TYPES.picklist,
        options: options.fundingType || []
      });
    }
    const numberOfYears = Math.max(Number.parseInt(this.config?.numberOfYears, 10) || 0, 0);
    for (let year = 1; year <= numberOfYears; year += 1) {
      columns.push({
        key: `${COLUMN_KEYS.yearPrefix}${year}`,
        label: this.withCurrency(`${labels.year} ${year}`),
        type: CELL_TYPES.currency,
        isYear: true
      });
    }
    return columns;
  }

  buildBenefitColumns() {
    const labels = this.labels;
    const options = this.config?.options || {};
    return [
      { key: COLUMN_KEYS.name, label: labels.title, type: CELL_TYPES.text, isRequired: true, isWide: true },
      { key: COLUMN_KEYS.amount, label: this.withCurrency(labels.amount), type: CELL_TYPES.currency },
      { key: COLUMN_KEYS.validFrom, label: labels.validFrom, type: CELL_TYPES.date },
      { key: COLUMN_KEYS.validUntil, label: labels.validUntil, type: CELL_TYPES.date },
      {
        key: COLUMN_KEYS.type,
        label: labels.type,
        type: CELL_TYPES.picklist,
        options: options.counterpartType || []
      },
      { key: COLUMN_KEYS.description, label: labels.description, type: CELL_TYPES.textArea, isWide: true }
    ];
  }

  get headers() {
    return this.columns.map((column, index) => ({
      key: column.key,
      label: column.label,
      isRequired: column.isRequired === true && this.isEditable,
      cssClass: joinClasses(
        CELL_BORDER,
        index > 0 && CELL_SEPARATOR,
        column.type === CELL_TYPES.currency && "slds-text-align_right",
        column.isWide && "slds-size_1-of-5"
      )
    }));
  }

  // Total, percentage and delete columns: after the generated ones, always separated.
  get trailingHeaderClass() {
    return joinClasses(CELL_BORDER, CELL_SEPARATOR, "slds-text-align_right");
  }

  get trailingCellClass() {
    return joinClasses(CELL_BORDER, CELL_SEPARATOR, "slds-text-align_right");
  }

  get actionHeaderClass() {
    return joinClasses(CELL_BORDER, CELL_SEPARATOR, "slds-cell-shrink");
  }

  get actionCellClass() {
    return joinClasses(CELL_BORDER, CELL_SEPARATOR, "slds-cell-shrink");
  }

  // ===================== TOTALS =====================

  get yearColumns() {
    return this.columns.filter((column) => column.isYear);
  }

  getRowTotal(row) {
    return this.yearColumns.reduce((total, column) => total + toAmount(row.values[column.key]), 0);
  }

  // Total of the table: the sum of the years of every row. Sent to the parent with every change.
  get tableTotal() {
    return this.rowStates.reduce((total, row) => total + this.getRowTotal(row), 0);
  }

  // ===================== VIEW =====================

  get rowViews() {
    const columns = this.columns;
    const grandTotal = this.tableTotal;
    const hasPercentValue = grandTotal > 0;
    return this.rowStates.map((row) => {
      const total = this.getRowTotal(row);
      return {
        key: row.key,
        total,
        percent: hasPercentValue ? total / grandTotal : null,
        hasPercentValue,
        cells: columns.map((column, index) => ({
          key: column.key,
          cssClass: joinClasses(CELL_BORDER, index > 0 && CELL_SEPARATOR),
          label: column.label,
          value: row.values[column.key] ?? "",
          options: column.options,
          isText: column.type === CELL_TYPES.text,
          isCurrency: column.type === CELL_TYPES.currency,
          isPicklist: column.type === CELL_TYPES.picklist,
          isDate: column.type === CELL_TYPES.date,
          isTextArea: column.type === CELL_TYPES.textArea
        }))
      };
    });
  }

  // ===================== VALIDATION =====================

  // At least one row with its name and, for a Budget table, an amount.
  @api
  isComplete() {
    const hasYears = this.yearColumns.length > 0;
    return this.rowStates.some(
      (row) =>
        isFilled(row.values[COLUMN_KEYS.name]) &&
        (!hasYears || this.yearColumns.some((column) => isFilled(row.values[column.key])))
    );
  }

  // ===================== EVENTS =====================

  handleToggle() {
    this.isOpen = !this.isOpen;
  }

  handleCellChange(event) {
    const { rowKey, columnKey } = event.target.dataset;
    const value = event.detail.value ?? "";
    this.updateRows((rows) =>
      rows.map((row) =>
        row.key === rowKey
          ? { ...row, values: { ...row.values, [columnKey]: String(value) } }
          : row
      )
    );
  }

  handleAddRow() {
    this.updateRows((rows) => [...rows, { key: buildRowKey(), values: {} }]);
  }

  // The last row is emptied rather than removed: the table always keeps a row to fill in.
  handleDeleteRow(event) {
    const { rowKey } = event.target.dataset;
    this.updateRows((rows) => {
      const remainingRows = rows.filter((row) => row.key !== rowKey);
      return remainingRows.length ? remainingRows : [{ key: buildRowKey(), values: {} }];
    });
  }

  updateRows(updateRows) {
    this.rowStates = updateRows(this.rowStates);
    this.dispatchEvent(
      new CustomEvent("tablechange", {
        detail: {
          questionId: this.config?.questionId,
          rows: this.rowStates,
          total: this.tableTotal
        }
      })
    );
  }
}