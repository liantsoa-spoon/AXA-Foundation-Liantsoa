/**
 * @description       :
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 21-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
import { LightningElement, api } from "lwc";

export default class DecisionPicker extends LightningElement {
  @api recordId;
  @api options;
  @api value;

  get displayedOptions() {
    const isDecided = this.options?.some(option => option.value === this.value);
    return this.options?.map(option => {
      const state = !isDecided
        ? "pending"
        : option.value === this.value
          ? "chosen"
          : "muted";
      return { ...option, buttonClass: `decision ${option.tone} ${state}` };
    });
  }

  handleOptionClick(event) {
    this.dispatchEvent(
      new CustomEvent("decisionselect", {
        detail: {
          recordId: this.recordId,
          value: event.currentTarget.dataset.value
        },
        bubbles: true,
        composed: true
      })
    );
  }
}