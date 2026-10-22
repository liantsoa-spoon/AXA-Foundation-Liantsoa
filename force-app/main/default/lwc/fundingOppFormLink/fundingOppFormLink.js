/**
 * @description       : Loads the portal form URL for a Funding Opportunity and lets users copy it to the clipboard.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 05-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   05-10-2026   KRA      Initial version
 **/
import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import Toast from "lightning/toast";
import getFormURL from "@salesforce/apex/FundingOppFormLinkController.getFormURL";

const COPIED_ICON_DURATION_IN_MILLISECONDS = 2000;

const LABELS = {
  title: "Lien du formulaire",
  formURLField: "Lien d'accès au formulaire",
  copy: "Copier",
  close: "Fermer",

  feedback: {
    loading: "Chargement",
    noFormURL: "Aucun formulaire n'est associé à ce programme.",
    loadErrorTitle: "Le lien n'a pas pu être généré.",
    copyErrorTitle: "Le lien n'a pas pu être copié."
  }
};

export default class FundingOppFormLink extends LightningElement {
  labels = LABELS;
  fundingOpportunityId;
  formURL;
  loadErrorMessage;
  isLoading = true;
  isCopied = false;
  copiedIconTimeoutId;

  @api
  get recordId() {
    return this.fundingOpportunityId;
  }

  set recordId(value) {
    this.fundingOpportunityId = value;
    this.loadFormURL();
  }

  disconnectedCallback() {
    clearTimeout(this.copiedIconTimeoutId);
  }

  get copyIconName() {
    return this.isCopied ? "utility:check" : "utility:copy";
  }

  async loadFormURL() {
    try {
      this.formURL = await getFormURL({
        fundingOpportunityId: this.fundingOpportunityId
      });
    } catch (error) {
      this.loadErrorMessage = error?.body?.message ?? error?.message;
    } finally {
      this.isLoading = false;
    }
  }

  async handleCopyClick() {
    try {
      await navigator.clipboard.writeText(this.formURL);
      this.isCopied = true;
      clearTimeout(this.copiedIconTimeoutId);
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.copiedIconTimeoutId = setTimeout(() => {
        this.isCopied = false;
      }, COPIED_ICON_DURATION_IN_MILLISECONDS);
    } catch (error) {
      Toast.show(
        {
          label: LABELS.feedback.copyErrorTitle,
          message: error?.message,
          variant: "error"
        },
        this
      );
    }
  }

  handleCloseClick() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}