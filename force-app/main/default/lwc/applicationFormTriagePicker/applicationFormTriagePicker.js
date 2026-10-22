/**
 * @description       :
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 17-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
import { LightningElement, api } from "lwc";

export default class ApplicationFormTriagePicker extends LightningElement {
  @api recordId;
  @api options;
  @api prequalification;

  get decidedOption() {
    return this.options?.find(
      option => option.value === this.prequalification
    );
  }

  get availableOptions() {
    return this.decidedOption
      ? this.options.filter(option => option.value !== this.prequalification)
      : this.options;
  }

  handleOptionClick(event) {
    this.dispatchEvent(
      new CustomEvent("prequalificationselect", {
        detail: {
          recordId: this.recordId,
          prequalification: event.currentTarget.dataset.value
        },
        bubbles: true,
        composed: true
      })
    );
  }
}