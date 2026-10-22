import { LightningElement, api, track } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getOverview from "@salesforce/apex/ApplicationResultEmailController.getOverview";
import sendResults from "@salesforce/apex/ApplicationResultEmailController.sendResults";

const VIEW = { SELECT: "select", CONFIRM: "confirm", RESULT: "result" };

const LABELS = {
  title: "Communiquer les résultats de candidature",
  total: "Candidats",
  accepted: "Acceptés",
  rejected: "Rejetés",
  notified: "Notifiés",
  search: "Rechercher (nom, organisation, e-mail)",
  selectAll: "Tout sélectionner",
  sendSelected: "Envoyer les résultats",
  sentOn: "Envoyé le",
  pending: "En attente",
  failed: "Échec",
  missingEmail: "E-mail manquant",
  empty: "Aucun candidat dans cette section.",
  noDecision:
    "Aucun projet n'est au statut Validé ou Rejeté pour ce programme : il n'y a rien à communiquer."
};

const dateFormat = new Intl.DateTimeFormat("fr-FR", {
  dateStyle: "short",
  timeStyle: "short"
});

export default class ApplicationResultCommunication extends LightningElement {
  _recordId;
  hasRequestedLoad = false;

  // Quick actions receive recordId AFTER connectedCallback, so the first load is triggered from the setter.
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value;
    if (value && !this.hasRequestedLoad) {
      this.hasRequestedLoad = true;
      this.load();
    }
  }

  labels = LABELS;
  @track overview;
  @track summary;
  view = VIEW.SELECT;
  isBusy = true;
  loadError;
  selected = new Set();
  acceptedSearch = "";
  rejectedSearch = "";
  showAcceptedPreview = false;
  showRejectedPreview = false;

  // ------------------------------------------------------------ lifecycle


  async load() {
    this.isBusy = true;
    this.loadError = undefined;
    try {
      this.overview = await getOverview({ fundingOpportunityId: this.recordId });
      // Drop selections that are no longer valid (e.g. just sent).
      const selectableIds = new Set(this.allRows.filter((r) => r.selectable).map((r) => r.id));
      this.selected = new Set([...this.selected].filter((id) => selectableIds.has(id)));
    } catch (error) {
      this.loadError = this.messageOf(error);
    } finally {
      this.isBusy = false;
    }
  }

  // ---------------------------------------------------------------- rows

  get allRows() {
    return (this.overview?.candidates ?? []).map((c) => this.toRow(c));
  }

  toRow(candidate) {
    const hasEmail = !!candidate.email;
    const selectable = !candidate.isNotified && hasEmail;
    const latestFailure = candidate.errorLog?.split(" | ")[0];
    let statusLabel = LABELS.pending;
    let statusClass = "badge badge_pending";
    if (candidate.isNotified) {
      statusLabel = `${LABELS.sentOn} ${dateFormat.format(new Date(candidate.sentDate))}`;
      statusClass = "badge badge_sent";
    } else if (!hasEmail) {
      statusLabel = LABELS.missingEmail;
      statusClass = "badge badge_failed";
    } else if (latestFailure) {
      statusLabel = latestFailure.replace(/^[[^]]*]s*/, "").substring(0, 120);
      statusClass = "badge badge_failed";
    }
    return {
      ...candidate,
      selectable,
      notSelectable: !selectable,
      isSelected: this.selected.has(candidate.id),
      rowClass: selectable ? "" : "arc-row_locked",
      errorTitle: candidate.errorLog || "",
      statusLabel,
      statusClass,
      stageClass: candidate.isAccepted ? "arc-stage arc-stage_accepted" : "arc-stage arc-stage_rejected",
      hasFailed: !candidate.isNotified && !!latestFailure
    };
  }

  rowsOf(isAccepted, search) {
    const term = search.trim().toLowerCase();
    return this.allRows.filter(
      (r) =>
        r.isAccepted === isAccepted &&
        (!term ||
          [r.projectName, r.candidateName, r.organisationName, r.email, r.stageLabel]
            .filter(Boolean)
            .some((value) => value.toLowerCase().includes(term)))
    );
  }

  get acceptedRows() {
    return this.rowsOf(true, this.acceptedSearch);
  }
  get rejectedRows() {
    return this.rowsOf(false, this.rejectedSearch);
  }

  pendingIds(isAccepted) {
    return this.allRows.filter((r) => r.isAccepted === isAccepted && r.selectable).map((r) => r.id);
  }

  // ----------------------------------------------------------- dashboard

  get programmeName() {
    return this.overview?.programmeName ?? "";
  }
  get hasCandidates() {
    return (this.overview?.totalCandidates ?? 0) > 0;
  }
  get acceptedPendingCount() {
    return this.pendingIds(true).length;
  }
  get rejectedPendingCount() {
    return this.pendingIds(false).length;
  }
  get failedCount() {
    return this.allRows.filter((r) => r.hasFailed && r.selectable).length;
  }
  get retryLabel() {
    return `Réessayer les échecs (${this.failedCount})`;
  }
  get selectedCount() {
    return this.selected.size;
  }

  get acceptedAllChecked() {
    return this.sectionAllChecked(this.acceptedRows);
  }
  get rejectedAllChecked() {
    return this.sectionAllChecked(this.rejectedRows);
  }
  get acceptedNoneSelectable() {
    return !this.acceptedRows.some((r) => r.selectable);
  }
  get rejectedNoneSelectable() {
    return !this.rejectedRows.some((r) => r.selectable);
  }
  /** "Select all" covers the rows currently shown (after search) that can still be notified. */
  sectionAllChecked(rows) {
    const ids = rows.filter((r) => r.selectable).map((r) => r.id);
    return ids.length > 0 && ids.every((id) => this.selected.has(id));
  }

  // --------------------------------------------------------- button state

  get isSelectView() {
    return this.view === VIEW.SELECT;
  }
  get isConfirmView() {
    return this.view === VIEW.CONFIRM;
  }
  get isResultView() {
    return this.view === VIEW.RESULT;
  }
  get disableSendAccepted() {
    return this.isBusy || this.acceptedPendingCount === 0;
  }
  get disableSendRejected() {
    return this.isBusy || this.rejectedPendingCount === 0;
  }
  get disableSendSelected() {
    return this.isBusy || this.selectedCount === 0;
  }
  get disableRetry() {
    return this.isBusy || this.failedCount === 0;
  }
  get showError() {
    return !!this.loadError;
  }
  get showContent() {
    return !this.loadError && this.overview;
  }
  get showEmptyDecision() {
    return this.showContent && !this.hasCandidates;
  }
  get showCandidates() {
    return this.showContent && this.hasCandidates;
  }

  // ------------------------------------------------ selection / search UI

  handleRowToggle(event) {
    const next = new Set(this.selected);
    if (event.target.checked) {
      next.add(event.target.dataset.id);
    } else {
      next.delete(event.target.dataset.id);
    }
    this.selected = next;
  }

  handleSelectAll(event) {
    const rows = event.target.dataset.section === "accepted" ? this.acceptedRows : this.rejectedRows;
    const next = new Set(this.selected);
    rows
      .filter((r) => r.selectable)
      .forEach((r) => (event.target.checked ? next.add(r.id) : next.delete(r.id)));
    this.selected = next;
  }

  handleAcceptedSearch(event) {
    this.acceptedSearch = event.target.value ?? "";
  }
  handleRejectedSearch(event) {
    this.rejectedSearch = event.target.value ?? "";
  }
  toggleAcceptedPreview() {
    this.showAcceptedPreview = !this.showAcceptedPreview;
  }
  toggleRejectedPreview() {
    this.showRejectedPreview = !this.showRejectedPreview;
  }

  // ------------------------------------------------------- send workflow

  handleSendAllAccepted() {
    this.selected = new Set(this.pendingIds(true));
    this.openConfirm();
  }
  handleSendAllRejected() {
    this.selected = new Set(this.pendingIds(false));
    this.openConfirm();
  }
  handleSendSelected() {
    this.openConfirm();
  }
  handleRetryFailed() {
    this.selected = new Set(this.allRows.filter((r) => r.hasFailed && r.selectable).map((r) => r.id));
    this.openConfirm();
  }

  openConfirm() {
    if (this.selected.size === 0) {
      return;
    }
    this.view = VIEW.CONFIRM;
  }

  handleCancelConfirm() {
    this.view = VIEW.SELECT;
  }

  get confirmRows() {
    return this.allRows.filter((r) => this.selected.has(r.id));
  }
  get confirmAcceptedCount() {
    return this.confirmRows.filter((r) => r.isAccepted).length;
  }
  get confirmRejectedCount() {
    return this.confirmRows.filter((r) => !r.isAccepted).length;
  }
  get confirmHasAccepted() {
    return this.confirmAcceptedCount > 0;
  }
  get confirmHasRejected() {
    return this.confirmRejectedCount > 0;
  }
  get confirmTitle() {
    return `${this.selected.size} e-mail(s) vont être envoyés`;
  }
  get tooManySelected() {
    return this.selected.size > (this.overview?.maxRecipientsPerRequest ?? Infinity);
  }
  get tooManyMessage() {
    return `Maximum ${this.overview?.maxRecipientsPerRequest} candidats par envoi : réduisez la sélection.`;
  }
  get disableConfirm() {
    return this.isBusy || this.tooManySelected;
  }

  async handleConfirmSend() {
    if (this.isBusy || this.tooManySelected) {
      return; // guards against double click
    }
    this.isBusy = true;
    try {
      this.summary = await sendResults({
        fundingOpportunityId: this.recordId,
        applicationFormIds: [...this.selected]
      });
      this.selected = new Set();
      this.view = VIEW.RESULT;
      if (this.summary.failedCount > 0) {
        this.toast(
          "Certains envois ont échoué",
          `${this.summary.failedCount} e-mail(s) en échec. Consultez le détail et réessayez.`,
          "error"
        );
      }
      await this.load();
    } catch (error) {
      this.view = VIEW.SELECT;
      this.toast("Envoi impossible", this.messageOf(error), "error");
      await this.load(); // state may have changed server side
    } finally {
      this.isBusy = false;
    }
  }

  // -------------------------------------------------------------- result

  get successMessage() {
    const when = this.summary?.completedAt
      ? dateFormat.format(new Date(this.summary.completedAt))
      : "";
    return `${this.summary?.sentCount ?? 0} e-mail(s) envoyé(s) avec succès le ${when}`;
  }
  get hasSent() {
    return (this.summary?.sentCount ?? 0) > 0;
  }
  get hasFailures() {
    return (this.summary?.failedCount ?? 0) > 0;
  }
  get hasSkipped() {
    return (this.summary?.skippedCount ?? 0) > 0;
  }
  get hasWarnings() {
    return (this.summary?.warnings?.length ?? 0) > 0;
  }
  get failedOutcomes() {
    return (this.summary?.outcomes ?? []).filter((o) => o.status === "FAILED");
  }
  get skippedOutcomes() {
    return (this.summary?.outcomes ?? []).filter((o) => o.status === "SKIPPED");
  }
  get failureTitle() {
    return `${this.summary?.failedCount} e-mail(s) en échec`;
  }
  get skippedTitle() {
    return `${this.summary?.skippedCount} candidat(s) ignoré(s) (déjà notifiés ou non éligibles)`;
  }

  handleBackToList() {
    this.view = VIEW.SELECT;
    this.summary = undefined;
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  handleReload() {
    this.load();
  }

  // ------------------------------------------------------------- helpers

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: "sticky" }));
  }

  messageOf(error) {
    return error?.body?.message ?? error?.message ?? "Erreur inconnue.";
  }
}