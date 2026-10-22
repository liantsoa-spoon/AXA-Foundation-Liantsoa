/**
 * @description       : Required consent checkbox whose label links to the consented document.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 20-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   20-10-2026   LAN      Initial version
 **/
import { LightningElement, api } from "lwc";

// Every text comes from the parent, in the language it chose: the portal language or the form language.
export default class ConsentCheckbox extends LightningElement {
  @api prefix;
  @api linkLabel;
  @api url;
  @api errorMessage;

  isChecked = false;
  isErrorShown = false;

  @api
  get checked() {
    return this.isChecked;
  }

  @api
  reportValidity() {
    this.isErrorShown = !this.isChecked;
    return this.isChecked;
  }

  handleChange(event) {
    this.isChecked = event.target.checked;
    this.isErrorShown = false;
    this.dispatchEvent(
      new CustomEvent("consentchange", { detail: { checked: this.isChecked } })
    );
  }

  get fieldClasses() {
    return this.isErrorShown
      ? "slds-form-element slds-has-error"
      : "slds-form-element";
  }
}
