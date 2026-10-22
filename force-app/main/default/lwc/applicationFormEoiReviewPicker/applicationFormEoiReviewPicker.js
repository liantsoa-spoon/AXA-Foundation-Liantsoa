/**
 * @description       :
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 21-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
import { LightningElement, api } from "lwc";

export default class ApplicationFormEoiReviewPicker extends LightningElement {
  @api recordId;
  @api options;
  @api stage;

  get displayedOptions() {
    const isDecided = this.options?.some(option => option.value === this.stage);
    return this.options?.map(option => {
      const state = !isDecided
        ? "pending"
        : option.value === this.stage
          ? "chosen"
          : "muted";
      return { ...option, buttonClass: `decision ${option.tone} ${state}` };
    });
  }

  handleOptionClick(event) {
    this.dispatchEvent(
      new CustomEvent("eoidecisionselect", {
        detail: {
          recordId: this.recordId,
          stage: event.currentTarget.dataset.value
        },
        bubbles: true,
        composed: true
      })
    );
  }
}