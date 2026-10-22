/**
 * @description       :
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 23-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getApplicationFormsToReview from "@salesforce/apex/ApplicationFormEoiReviewController.getApplicationFormsToReview";
import updateStage from "@salesforce/apex/ApplicationFormEoiReviewController.updateStage";

const LABELS = {
  title: "Qualification des expressions d'intérêt",

  selection: {
    suffix: "candidats sélectionnés"
  },

  pagination: {
    showing: "Affichage de",
    to: "à",
    of: "sur",
    records: "dossiers",
    page: "Page",
    first: "Premier",
    previous: "Précédent",
    next: "Suivant",
    last: "Dernier"
  },

  filterLabel: "Filtre",
  clearSelection: "Annuler la sélection",

  columnHeaders: {
    contactName: "Nom du candidat",
    partnerName: "Nom du partenaire",
    title: "Titre du projet",
    eoiDecision: "Décision"
  },

  feedback: {
    bulkSuccessTitle: "Mise à jour effectuée",
    bulkSuccessSuffix: "candidatures mises à jour",
    loading: "Chargement",
    emptyState: "Toutes les expressions d'intérêt ont été qualifiées.",
    errorTitle: "Une erreur est survenue"
  }
};

const EOI_OPTIONS = [
  {
    value: "EOI Approved",
    label: "Retenir",
    bulkLabel: "Valider sélectionnés",
    bulkClass: "bulk-action bulk-action_approve",
    iconName: "utility:check",
    tone: "approve",
    iconPath: "M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"
  },
  {
    value: "EOI Not Selected",
    label: "Rejeter",
    bulkLabel: "Rejeter sélectionnés",
    bulkClass: "bulk-action bulk-action_reject",
    iconName: "utility:close",
    tone: "reject",
    iconPath:
      "M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"
  }
];

const PENDING_STAGE = "EOI Submitted";
const ALL_FILTER = "all";
const REVIEWED_FILTER = "reviewed";

const FILTERS = [
  { value: PENDING_STAGE, label: "À traiter" },
  { value: REVIEWED_FILTER, label: "Traitées" },
  { value: ALL_FILTER, label: "Toutes" }
];

const SORTED_FIELDS = { recordUrl: "contactName" };

const COLUMNS = [
  {
    label: LABELS.columnHeaders.contactName,
    fieldName: "recordUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "contactName" } },
    sortable: true
  },
  {
    label: LABELS.columnHeaders.partnerName,
    fieldName: "partnerName",
    type: "text",
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
    label: LABELS.columnHeaders.eoiDecision,
    fieldName: "id",
    type: "eoiDecision",
    typeAttributes: {
      options: EOI_OPTIONS,
      decision: { fieldName: "stage" }
    },
    cellAttributes: { alignment: "center" },
    initialWidth: 120,
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

export default class ApplicationFormEoiReview extends LightningElement {
  @api recordId;
  @api paginationRows = 25;

  labels = LABELS;
  columns = COLUMNS;
  filters = FILTERS;
  eoiOptions = EOI_OPTIONS;

  isLoaded = false;
  applicationForms = [];
  selectedRowIds = [];
  currentFilter = PENDING_STAGE;
  currentPage = 1;
  sortedBy;
  sortDirection = "asc";

  @wire(getApplicationFormsToReview, { fundingOpportunityId: "$recordId" })
  loadApplicationFormsToReview({ data, error }) {
    if (error) {
      this.notifyError(error);
      return;
    }
    if (data) {
      this.applicationForms = data.map(applicationForm => ({
        ...applicationForm,
        recordUrl: `/lightning/r/${applicationForm.id}/view`
      }));
      this.isLoaded = true;
    }
  }

  get visibleApplicationForms() {
    if (this.currentFilter === ALL_FILTER) {
      return this.applicationForms;
    }
    if (this.currentFilter === PENDING_STAGE) {
      return this.applicationForms.filter(
        applicationForm => applicationForm.stage === PENDING_STAGE
      );
    }
    return this.applicationForms.filter(
      applicationForm => applicationForm.stage !== PENDING_STAGE
    );
  }

  get pagedApplicationForms() {
    const firstIndex = (this.currentPage - 1) * this.paginationRows;
    return this.visibleApplicationForms.slice(
      firstIndex,
      firstIndex + this.paginationRows
    );
  }

  get pageCount() {
    return Math.max(
      1,
      Math.ceil(this.visibleApplicationForms.length / this.paginationRows)
    );
  }

  get isFirstPage() {
    return this.currentPage === 1;
  }

  get isLastPage() {
    return this.currentPage === this.pageCount;
  }

  get pageSummary() {
    const firstIndex = (this.currentPage - 1) * this.paginationRows;
    const lastIndex = firstIndex + this.pagedApplicationForms.length;
    return `${firstIndex + 1}-${lastIndex} ${LABELS.pagination.of} ${this.visibleApplicationForms.length}`;
  }

  get pagePosition() {
    return [
      LABELS.pagination.page,
      this.currentPage,
      LABELS.pagination.of,
      this.pageCount
    ].join(" ");
  }

  get selectedRowCount() {
    return this.selectedRowIds.length;
  }

  get selectionSummary() {
    return `${this.selectedRowIds.length} ${LABELS.selection.suffix}`;
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
    this.goToPage(1);
  }

  handleFirstPage() {
    this.goToPage(1);
  }

  handlePreviousPage() {
    this.goToPage(this.currentPage - 1);
  }

  handleNextPage() {
    this.goToPage(this.currentPage + 1);
  }

  handleLastPage() {
    this.goToPage(this.pageCount);
  }

  handleBulkDecision(event) {
    this.applyDecision(
      this.selectedRowIds,
      event.currentTarget.dataset.value
    );
  }

  goToPage(page) {
    this.currentPage = page;
    this.selectedRowIds = [];
  }

  handleClearSelection() {
    this.selectedRowIds = [];
  }

  handleRowSelection(event) {
    this.selectedRowIds = event.detail.selectedRows.map(row => row.id);
  }

  handleEoiDecisionSelect(event) {
    const { recordId, value } = event.detail;
    this.applyDecision(recordId ? [recordId] : this.selectedRowIds, value);
  }

  async applyDecision(applicationFormIds, stage) {
    try {
      await updateStage({ applicationFormIds, stage });
    } catch (error) {
      this.notifyError(error);
      return;
    }
    const reviewedIds = new Set(applicationFormIds);
    this.applicationForms = this.applicationForms.map(applicationForm => {
      return reviewedIds.has(applicationForm.id)
        ? { ...applicationForm, stage }
        : applicationForm;
    });
    this.selectedRowIds = [];
    if (this.currentPage > this.pageCount) {
      this.currentPage = this.pageCount;
    }
    if (applicationFormIds.length > 1) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: LABELS.feedback.bulkSuccessTitle,
          message: `${applicationFormIds.length} ${LABELS.feedback.bulkSuccessSuffix}`,
          variant: "success"
        })
      );
    }
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