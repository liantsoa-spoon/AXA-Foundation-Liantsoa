import { LightningElement, api } from "lwc";

export default class ContactDetailsContainer extends LightningElement {
  @api value = {};
  @api salutationOptions = [];
  @api labels = {};
  @api isEveryFieldRequired = false;

  get today() {
    const now = new Date();
    return [
      now.getFullYear(),
      String(now.getMonth() + 1).padStart(2, "0"),
      String(now.getDate()).padStart(2, "0")
    ].join("-");
  }

  handleChange(event) {
    this.dispatchEvent(
      new CustomEvent("fieldchange", {
        detail: {
          name: event.target.name,
          value: event.target.value
        }
      })
    );
  }

  @api
  reportValidity() {
    return [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ].reduce((isValid, field) => field.reportValidity() && isValid, true);
  }
}