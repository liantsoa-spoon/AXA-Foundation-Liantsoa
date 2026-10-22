/**
 * @description       :
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 21-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue, updateRecord } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { PREQUALIFICATION_OPTIONS } from "c/prequalificationOptions";
import PREQUALIFICATION_FIELD from "@salesforce/schema/ApplicationForm.Prequalification__c";

const LABELS = {
  title: "Pré-qualification",

  feedback: {
    successTitle: "Pré-qualification enregistrée",
    errorTitle: "Une erreur est survenue"
  }
};

export default class ApplicationFormPrequalification extends LightningElement {
  @api recordId;

  labels = LABELS;
  prequalificationOptions = PREQUALIFICATION_OPTIONS;

  @wire(getRecord, { recordId: "$recordId", fields: [PREQUALIFICATION_FIELD] })
  applicationForm;

  get prequalification() {
    return getFieldValue(this.applicationForm.data, PREQUALIFICATION_FIELD);
  }

  handlePrequalificationSelect(event) {
    const option = PREQUALIFICATION_OPTIONS.find(
      candidate => candidate.value === event.detail.value
    );
    updateRecord({
      fields: {
        Id: this.recordId,
        Prequalification__c: event.detail.value
      }
    })
      .then(() => this.notifySuccess(option.label))
      .catch(error => this.notifyError(error));
  }

  notifySuccess(label) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: LABELS.feedback.successTitle,
        message: label,
        variant: "success"
      })
    );
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