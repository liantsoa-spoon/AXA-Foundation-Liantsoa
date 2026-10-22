import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import createContact from "@salesforce/apex/PortalContactCreationController.createContact";
import getRoleOptions from "@salesforce/apex/PortalContactCreationController.getRoleOptions";

import title from "@salesforce/label/c.PortalContactCreation_Title";
import createContactLabel from "@salesforce/label/c.PortalContactCreation_CreateContact";
import contactCreated from "@salesforce/label/c.PortalContactCreation_ContactCreated";
import roleLimitInfo from "@salesforce/label/c.PortalContactCreation_RoleLimitInfo";
import multiRoleInfo from "@salesforce/label/c.PortalContactCreation_MultiRoleInfo";
import contactSupport from "@salesforce/label/c.PortalContactCreation_ContactSupport";

import errorNotOperationalContact from "@salesforce/label/c.PortalContactCreation_ErrorNotOperationalContact";
import errorRoleAlreadyAssigned from "@salesforce/label/c.PortalContactCreation_ErrorRoleAlreadyAssigned";
import errorRoleLimitReached from "@salesforce/label/c.PortalContactCreation_ErrorRoleLimitReached";
import errorPortalUserCreationFailed from "@salesforce/label/c.PortalRegistration_ErrorPortalUserCreationFailed";
import errorInvalidInput from "@salesforce/label/c.PortalRegistration_ErrorInvalidInput";
import errorMissingData from "@salesforce/label/c.PortalRegistration_ErrorMissingData";
import errorInvalidEmail from "@salesforce/label/c.PortalRegistration_ErrorInvalidEmail";
import errorEmailAlreadyRegistered from "@salesforce/label/c.PortalRegistration_ErrorEmailAlreadyRegistered";
import errorEmailBelongsToAnotherOrganization from "@salesforce/label/c.PortalRegistration_ErrorEmailBelongsToAnotherOrganization";
import errorUnexpected from "@salesforce/label/c.PortalRegistration_ErrorUnexpected";

const LABELS = {
  title,
  createContact: createContactLabel,

  fields: {
    firstName: "Prénom",
    lastName: "Nom",
    email: "Addresse Mail",
    phone: "Telephone",
    role: "Role"
  },

  feedback: {
    contactCreated,
    roleLimitInfo,
    multiRoleInfo,
    contactSupport
  },

  errors: {
    NOT_OPERATIONAL_CONTACT: errorNotOperationalContact,
    MISSING_DATA: errorMissingData,
    INVALID_EMAIL: errorInvalidEmail,
    ROLE_ALREADY_ASSIGNED: errorRoleAlreadyAssigned,
    ROLE_LIMIT_REACHED: errorRoleLimitReached,
    EMAIL_ALREADY_REGISTERED: errorEmailAlreadyRegistered,
    EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION: errorEmailBelongsToAnotherOrganization,
    PORTAL_USER_CREATION_FAILED: errorPortalUserCreationFailed,
    INVALID_INPUT: errorInvalidInput,
    UNEXPECTED_ERROR: errorUnexpected
  }
};

const RELOAD_DELAY_MS = 1500;

const EMPTY_CONTACT = {
  firstName: "",
  lastName: "",
  email: "",
  phone: "",
  role: ""
};

export default class PortalContactCreation extends LightningElement {
  labels = LABELS;
  contact = { ...EMPTY_CONTACT };
  isBusy = false;
  errorMessage;
  showSuccessMessage = false;
  roleOptions = [];

  connectedCallback() {
    this.loadRoleOptions();
  }

  async loadRoleOptions() {
    try {
      const options = await getRoleOptions();
      this.roleOptions = (options ?? []).map((option) => ({
        label: option.label,
        value: option.value
      }));
    } catch (error) {
      this.errorMessage = this.translateError(error);
    }
  }

  handleFieldChange(event) {
    this.contact = {
      ...this.contact,
      [event.target.name]: event.target.value
    };
  }

  async handleCreateContact() {
    this.errorMessage = undefined;
    this.showSuccessMessage = false;
    if (!this.reportValidity()) {
      return;
    }

    this.isBusy = true;
    try {
      await createContact({
        firstName: this.contact.firstName,
        lastName: this.contact.lastName,
        email: this.contact.email,
        phone: this.contact.phone,
        role: this.contact.role
      });
      this.dispatchEvent(
        new ShowToastEvent({
          message: LABELS.feedback.contactCreated,
          variant: "success"
        })
      );
      // Keep the spinner up and give the toast a moment to show before the reload.
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => window.location.reload(), RELOAD_DELAY_MS);
    } catch (error) {
      this.errorMessage = this.translateError(error);
      this.isBusy = false;
    }
  }

  reportValidity() {
    return [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ].reduce((isValid, field) => field.reportValidity() && isValid, true);
  }

  translateError(error) {
    return (
      LABELS.errors[error?.body?.message] ?? LABELS.errors.UNEXPECTED_ERROR
    );
  }
}