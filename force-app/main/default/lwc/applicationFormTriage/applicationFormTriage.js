/**
 * @description       :
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 09-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import CURRENCY from "@salesforce/i18n/currency";
import { PREQUALIFICATION_OPTIONS } from "c/prequalificationOptions";
import { loadStyle } from "lightning/platformResourceLoader";
import MODAL_WIDTH from "@salesforce/resourceUrl/ApplicationFormTriageModalWidth";
import getTriageViewModel from "@salesforce/apex/ApplicationFormTriageController.getTriageViewModel";
import updatePrequalification from "@salesforce/apex/ApplicationFormTriageController.updatePrequalification";

const LABELS = {
  title: "Pré-qualification des candidatures",

  fundingOpportunity: {
    sectionTitle: "Opportunité de financement",
    minimumAmount: "Montant minimum",
    maximumAmount: "Montant maximum",
    closingDate: "Clôture"
  },

  applicationForms: {
    sectionTitle: "Candidatures"
  },

  selection: {
    separator: "sur",
    suffix: "sélectionnées"
  },

  filterLabel: "Filtre",
  clearSelection: "Annuler la sélection",
  close: "Fermer",

  columnHeaders: {
    contactName: "Candidat",
    title: "Objet du projet",
    accountName: "Organisation",
    requestedAmount: "Montant demandé",
    submissionDate: "Reçue le",
    prequalification: "Pré-qualification"
  },

  feedback: {
    loading: "Chargement",
    emptyState: "Toutes les candidatures ont été qualifiées.",
    errorTitle: "Une erreur est survenue"
  }
};

const SORTED_FIELDS = { recordUrl: "candidateLabel" };

const PENDING_FILTER = "pending";
const REVIEWED_FILTER = "reviewed";
const ALL_FILTER = "all";

const FILTERS = [
  { value: PENDING_FILTER, label: "À trier" },
  { value: REVIEWED_FILTER, label: "Triées" },
  { value: ALL_FILTER, label: "Toutes" }
];

const COLUMNS = [
  {
    label: LABELS.columnHeaders.contactName,
    fieldName: "recordUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "candidateLabel" } },
    initialWidth: 180,
    sortable: true
  },
  {
    label: LABELS.columnHeaders.title,
    fieldName: "title",
    type: "text",
    sortable: true,
    wrapText: true
  },
  {
    label: LABELS.columnHeaders.accountName,
    fieldName: "accountName",
    type: "text",
    initialWidth: 180,
    sortable: true
  },
  {
    label: LABELS.columnHeaders.requestedAmount,
    fieldName: "requestedAmount",
    type: "currency",
    typeAttributes: { currencyCode: CURRENCY },
    sortable: true
  },
  {
    label: LABELS.columnHeaders.submissionDate,
    fieldName: "submissionDate",
    type: "date-local",
    typeAttributes: { day: "2-digit", month: "2-digit", year: "numeric" },
    sortable: true
  },
  {
    label: LABELS.columnHeaders.prequalification,
    fieldName: "id",
    type: "prequalification",
    typeAttributes: {
      options: PREQUALIFICATION_OPTIONS,
      decision: { fieldName: "prequalification" }
    },
    cellAttributes: { alignment: "center" },
    fixedWidth: 180,
    hideDefaultActions: true
  }
];

const textCollator = new Intl.Collator(undefined, {
  numeric: true,
  sensitivity: "base"
});

const createFieldComparator = (fieldName, sortDirection) => {
  const directionMultiplier = sortDirection === "asc" ? 1 : -1;
  return (firstRow, secondRow) => {
    const firstValue = firstRow[fieldName];
    const secondValue = secondRow[fieldName];
    if (firstValue === secondValue) {
      return 0;
    }
    if (firstValue === null || firstValue === undefined) {
      return 1;
    }
    if (secondValue === null || secondValue === undefined) {
      return -1;
    }
    return (
      directionMultiplier *
      (typeof firstValue === "string"
        ? textCollator.compare(firstValue, secondValue)
        : firstValue - secondValue)
    );
  };
};

export default class ApplicationFormTriage extends LightningElement {
  _recordId;

  @api
  set recordId(value) {
    this._recordId = value;
  }

  get recordId() {
    return this._recordId;
  }

  labels = LABELS;
  columns = COLUMNS;
  filters = FILTERS;
  currencyCode = CURRENCY;
  currentFilter = PENDING_FILTER;
  prequalificationOptions = PREQUALIFICATION_OPTIONS;

  fundingOpportunity;
  applicationForms = [];
  selectedRowIds = [];
  sortedBy;
  sortDirection = "asc";

  @wire(getTriageViewModel, { fundingOpportunityId: "$_recordId" })
  loadTriageViewModel({ data, error }) {
    if (error) {
      this.notifyError(error);
      return;
    }
    if (data) {
      this.fundingOpportunity = data.fundingOpportunity;
      this.applicationForms = data.applicationForms.map(applicationForm => ({
        ...applicationForm,
        candidateLabel: applicationForm.contactName ?? applicationForm.reference,
        recordUrl: `/lightning/r/${applicationForm.id}/view`
      }));
    }
  }

  connectedCallback() {
    loadStyle(this, MODAL_WIDTH).catch(error => this.notifyError(error));
  }

  get visibleApplicationForms() {
    if (this.currentFilter === ALL_FILTER) {
      return this.applicationForms;
    }
    if (this.currentFilter === PENDING_FILTER) {
      return this.applicationForms.filter(
        applicationForm => !applicationForm.prequalification
      );
    }
    return this.applicationForms.filter(
      applicationForm => applicationForm.prequalification
    );
  }

  get selectedRowCount() {
    return this.selectedRowIds.length;
  }

  get selectionSummary() {
    return [
      this.selectedRowIds.length,
      LABELS.selection.separator,
      this.visibleApplicationForms.length,
      LABELS.selection.suffix
    ].join(" ");
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortDirection = event.detail.sortDirection;
    this.applicationForms = [...this.applicationForms].sort(
      createFieldComparator(
        SORTED_FIELDS[this.sortedBy] ?? this.sortedBy,
        this.sortDirection
      )
    );
  }

  handleFilterChange(event) {
    this.currentFilter = event.detail.value;
    this.selectedRowIds = [];
  }

  handleClearSelection() {
    this.selectedRowIds = [];
  }

  handleRowSelection(event) {
    this.selectedRowIds = event.detail.selectedRows.map(row => row.id);
  }

  handlePrequalificationSelect(event) {
    const { recordId, value } = event.detail;
    this.applyTriage(
      recordId ? [recordId] : this.selectedRowIds,
      value
    );
  }

  async applyTriage(applicationFormIds, prequalification) {
    try {
      await updatePrequalification({ applicationFormIds, prequalification });
    } catch (error) {
      this.notifyError(error);
      return;
    }
    const prequalifiedIds = new Set(applicationFormIds);
    this.applicationForms = this.applicationForms.map(applicationForm => {
      return prequalifiedIds.has(applicationForm.id)
        ? { ...applicationForm, prequalification }
        : applicationForm;
    });
    this.selectedRowIds = [];
  }

  notifyError(error) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: LABELS.feedback.errorTitle,
        message: error.body?.message ?? error.message,
        variant: "error"
      })
    );
  }
}