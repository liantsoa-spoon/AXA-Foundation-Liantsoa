/**
 * @description       : Portal self-registration form, from the legal name check to the account creation.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 20-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   24-09-2026   KRA      Initial version
 * 1.1   20-10-2026   LAN      Replace the terms checkbox with the data acceptance policy and its document link
 * 1.2   20-10-2026   LAN      Show the data acceptance policy through the consentCheckbox component
 **/
import { LightningElement, api, wire } from "lwc";
import lang from "@salesforce/i18n/lang";

import checkOrganizationExists from "@salesforce/apex/PortalRegistrationController.checkOrganizationExists";
import getDataAcceptanceDocument from "@salesforce/apex/PortalRegistrationController.getDataAcceptanceDocument";
import getRegistrationPicklists from "@salesforce/apex/PortalRegistrationController.getRegistrationPicklists";
import registerCandidate from "@salesforce/apex/PortalRegistrationController.registerCandidate";
import suggestOrganizations from "@salesforce/apex/PortalRegistrationController.suggestOrganizations";

import title from "@salesforce/label/c.PortalRegistration_Title";
import createOrganization from "@salesforce/label/c.PortalRegistration_CreateOrganization";
import submit from "@salesforce/label/c.PortalRegistration_Submit";
import changeOrganization from "@salesforce/label/c.PortalRegistration_ChangeOrganization";
import dataAcceptance from "@salesforce/label/c.PortalRegistration_DataAcceptance";
import dataAcceptanceLink from "@salesforce/label/c.PortalRegistration_DataAcceptanceLink";
import search from "@salesforce/label/c.PortalRegistration_Search";

import sectionIdentity from "@salesforce/label/c.PortalRegistration_SectionIdentity";
import sectionOrganizationDetails from "@salesforce/label/c.PortalRegistration_SectionOrganizationDetails";
import sectionLegalRepresentative from "@salesforce/label/c.PortalRegistration_SectionLegalRepresentative";

import introduction from "@salesforce/label/c.PortalRegistration_Introduction";
import organizationMissing from "@salesforce/label/c.PortalRegistration_OrganizationMissing";
import organizationUnknown from "@salesforce/label/c.PortalRegistration_OrganizationUnknown";
import blockedTitle from "@salesforce/label/c.PortalRegistration_BlockedTitle";
import blockedMessage from "@salesforce/label/c.PortalRegistration_BlockedMessage";
import blockedContactName from "@salesforce/label/c.PortalRegistration_BlockedContactName";
import confirmationTitle from "@salesforce/label/c.PortalRegistration_ConfirmationTitle";
import confirmationMessage from "@salesforce/label/c.PortalRegistration_ConfirmationMessage";
import footerNoteParagraph1 from "@salesforce/label/c.PortalRegistration_FooterNoteParagraph1";
import footerNoteParagraph2 from "@salesforce/label/c.PortalRegistration_FooterNoteParagraph2";
import footerNoteParagraph3 from "@salesforce/label/c.PortalRegistration_FooterNoteParagraph3";

import errorLegalNameRequired from "@salesforce/label/c.PortalRegistration_ErrorLegalNameRequired";
import errorMissingData from "@salesforce/label/c.PortalRegistration_ErrorMissingData";
import errorInvalidEmail from "@salesforce/label/c.PortalRegistration_ErrorInvalidEmail";
import errorDataAcceptanceNotAccepted from "@salesforce/label/c.PortalRegistration_ErrorDataAcceptanceNotAccepted";
import errorOrganizationAlreadyHasContact from "@salesforce/label/c.PortalRegistration_ErrorOrganizationAlreadyHasContact";
import errorOrganizationDetailsRequired from "@salesforce/label/c.PortalRegistration_ErrorOrganizationDetailsRequired";
import errorEmailAlreadyRegistered from "@salesforce/label/c.PortalRegistration_ErrorEmailAlreadyRegistered";
import errorEmailBelongsToAnotherOrganization from "@salesforce/label/c.PortalRegistration_ErrorEmailBelongsToAnotherOrganization";
import errorPortalUserCreationFailed from "@salesforce/label/c.PortalRegistration_ErrorPortalUserCreationFailed";
import errorInvalidInput from "@salesforce/label/c.PortalRegistration_ErrorInvalidInput";
import errorDuplicateOrganization from "@salesforce/label/c.PortalRegistration_ErrorDuplicateOrganization";
import errorDuplicateContact from "@salesforce/label/c.PortalRegistration_ErrorDuplicateContact";import errorUnexpected from "@salesforce/label/c.PortalRegistration_ErrorUnexpected";
import legalRepresentativeHelp from "@salesforce/label/c.PortalRegistration_LegalRepresentativeHelp";

const STEPS = {
  organization: "organization",
  candidate: "candidate",
  confirmed: "confirmed"
};

const isFrench = lang ? lang.toLowerCase().startsWith("fr") : false;

const FIELD_LABELS = {
  fr: {
    legalName: "Raison sociale",
    salutation: "Civilité",
    firstName: "Prénom",
    lastName: "Nom",
    title: "Fonction",
    birthdate: "Date de naissance",
    phone: "Téléphone",
    email: "Adresse email",
    name: "Nom de l'organisation",
    legalForm: "Statut juridique",
    otherLegalForm: "Précisez le statut juridique",
    identificationNumber: "Numéro d'identification officiel",
    taxIdentificationNumber: "Identifiant fiscal international",
    foundingDate: "Date de création",
    country: "Pays d'enregistrement administratif",
    street: "Adresse",
    postalCode: "Code postal",
    foundingBackground: "Contexte de création",
    description: "Présentation de l'organisation",
    keyDates: "Dates clés",
    objectives: "Objectifs",
    mainActivities: "Principales activités",
    authorizedToIssueTaxReceipts: "Habilité à délivrer un reçu fiscal",
    keyFigures: "Chiffres clés",
    website: "Site internet"
  },
  en: {
    legalName: "Legal Name",
    salutation: "Salutation",
    firstName: "First Name",
    lastName: "Last Name",
    title: "Title / Function",
    birthdate: "Date of Birth",
    phone: "Phone Number",
    email: "Email Address",
    name: "Organization Name",
    legalForm: "Legal Form",
    otherLegalForm: "Specify the Legal Form",
    identificationNumber: "Official Identification Number",
    taxIdentificationNumber: "Tax Identification Number",
    foundingDate: "Founding Date",
    country: "Country of Registration",
    street: "Address",
    postalCode: "Postal Code",
    foundingBackground: "Founding Background",
    description: "Organization Overview",
    keyDates: "Key Dates",
    objectives: "Objectives",
    mainActivities: "Main Activities",
    authorizedToIssueTaxReceipts: "Authorized to Issue Tax Receipts",
    keyFigures: "Key Figures",
    website: "Website"
  }
};

const FIELD_HELP = {
  fr: {
    legalName:
      "Nom officiel et juridique qui permet d'identifier l'organisation dans tous ses actes administratifs.",
    identificationNumber:
      "Si votre organisation française possède un numéro SIREN, renseignez ses 9 chiffres.",
    taxIdentificationNumber:
      "Renseignez le numéro d'identification fiscale (NIF/TIN) attribué à l'organisation par l'administration fiscale de son pays de résidence ou d'enregistrement."
  },
  en: {
    legalName:
      "Official legal name that identifies the organization in all its administrative documents.",
    identificationNumber:
      "If your French organization has a SIREN number, enter its 9 digits.",
    taxIdentificationNumber:
      "Enter the tax identification number (TIN) assigned to the organization by the tax authority of its country of residence or registration."
  }
};

const FIELD_ERRORS = {
  fr: {
    country: "Sélectionnez un pays dans la liste."
  },
  en: {
    country: "Select a country from the list."
  }
};

const OTHER_LEGAL_FORM = "Other (please specify)";
const FRANCE = "France";

const MINIMUM_SEARCH_LENGTH = 3;
const SEARCH_DELAY = 300;

const LABELS = {
  title,
  createOrganization,
  submit,
  changeOrganization,
  dataAcceptance,
  dataAcceptanceLink,
  search,

  sections: {
    identity: sectionIdentity,
    organizationDetails: sectionOrganizationDetails,
    legalRepresentative: sectionLegalRepresentative
  },

  fields: isFrench ? FIELD_LABELS.fr : FIELD_LABELS.en,
  fieldHelp: isFrench ? FIELD_HELP.fr : FIELD_HELP.en,
  fieldErrors: isFrench ? FIELD_ERRORS.fr : FIELD_ERRORS.en,

  feedback: {
    introduction,
    organizationMissing,
    organizationUnknown,
    blockedTitle,
    blockedMessage,
    blockedContactName,
    confirmationTitle,
    confirmationMessage,
    footerNoteParagraph1,
    footerNoteParagraph2,
    footerNoteParagraph3,
    legalRepresentativeHelp
  },

  errors: {
    LEGAL_NAME_REQUIRED: errorLegalNameRequired,
    MISSING_DATA: errorMissingData,
    INVALID_EMAIL: errorInvalidEmail,
    DATA_ACCEPTANCE_NOT_ACCEPTED: errorDataAcceptanceNotAccepted,
    ORGANIZATION_ALREADY_HAS_CONTACT: errorOrganizationAlreadyHasContact,
    ORGANIZATION_DETAILS_REQUIRED: errorOrganizationDetailsRequired,
    EMAIL_ALREADY_REGISTERED: errorEmailAlreadyRegistered,
    EMAIL_BELONGS_TO_ANOTHER_ORGANIZATION: errorEmailBelongsToAnotherOrganization,
    PORTAL_USER_CREATION_FAILED: errorPortalUserCreationFailed,
    INVALID_INPUT: errorInvalidInput,
    DUPLICATE_ORGANIZATION: errorDuplicateOrganization,
    DUPLICATE_CONTACT: errorDuplicateContact,
    UNEXPECTED_ERROR: errorUnexpected
  }
};

// Lets "Ile" find "Île" and "cote" find "Côte".
const normalizeForSearch = (text) =>
  text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .trim();

const EMPTY_PERSON = {
  salutation: "",
  firstName: "",
  lastName: "",
  title: "",
  birthdate: null,
  phone: "",
  email: ""
};

export default class PortalRegistration extends LightningElement {
  // Unused: the document URL now comes from the AuthorizationFormText. Kept because the published
  // Experience Cloud page still declares it, and the platform refuses to remove its targetConfig.
  @api termsUrl;

  labels = LABELS;
  step = STEPS.organization;
  legalName = "";
  legalNameError;
  suggestions = [];
  candidate = { ...EMPTY_PERSON };
  organization = { legalRepresentative: { ...EMPTY_PERSON } };
  hasAcceptedDataAcceptance = false;
  isBusy = false;
  errorMessage;
  operationalContactName;
  hasSearched = false;
  organizationExists = false;
  countrySearchText = "";
  isCountryListOpen = false;
  countryError;

  searchTimeout;

  @wire(getRegistrationPicklists)
  options;

  // The text follows the portal language, so the candidate opens the policy document in their own language.
  @wire(getDataAcceptanceDocument, { language: lang })
  dataAcceptanceDocument;

  disconnectedCallback() {
    clearTimeout(this.searchTimeout);
  }

  handleLegalNameChange(event) {
    this.legalName = event.target.value.toUpperCase();
    event.target.value = this.legalName;
    this.legalNameError = undefined;
    this.hasSearched = false;
    this.organizationExists = false;
    this.operationalContactName = undefined;
    clearTimeout(this.searchTimeout);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimeout = setTimeout(() => this.loadSuggestions(), SEARCH_DELAY);
  }

  handleSuggestionSelect(event) {
    this.legalName = event.currentTarget.dataset.value;
    this.suggestions = [];
    this.template.querySelector("input.slds-combobox__input").value =
      this.legalName;
  }

  handleLegalNameBlur() {
    this.suggestions = [];
  }

  handleCandidateChange(event) {
    this.candidate = {
      ...this.candidate,
      [event.detail.name]: event.detail.value
    };
  }

  handleOrganizationChange(event) {
    this.organization = {
      ...this.organization,
      [event.target.name]: event.target.value
    };
  }

  handleCountryInput(event) {
    this.countrySearchText = event.target.value;
    const searchText = normalizeForSearch(this.countrySearchText);
    this.organization = {
      ...this.organization,
      country: this.countryOptions.find(
        (option) => normalizeForSearch(option.label) === searchText
      )?.value
    };
    this.isCountryListOpen = true;
    this.countryError = undefined;
  }

  handleCountryFocus() {
    this.isCountryListOpen = true;
  }

  handleCountryBlur() {
    this.isCountryListOpen = false;
  }

  handleCountrySelect(event) {
    const { value, label } = event.currentTarget.dataset;
    this.organization = { ...this.organization, country: value };
    this.countrySearchText = label;
    this.isCountryListOpen = false;
    this.countryError = undefined;
  }

  handleLegalRepresentativeChange(event) {
    this.organization = {
      ...this.organization,
      legalRepresentative: {
        ...this.organization.legalRepresentative,
        [event.detail.name]: event.detail.value
      }
    };
  }

  handleDataAcceptanceChange(event) {
    this.hasAcceptedDataAcceptance = event.detail.checked;
  }

  handleChangeOrganization() {
    this.step = STEPS.organization;
    this.legalNameError = undefined;
    this.errorMessage = undefined;
    this.operationalContactName = undefined;
    this.hasSearched = false;
    this.organizationExists = false;
  }

  async handleSearch() {
    this.errorMessage = undefined;
    if (!this.legalName.trim()) {
      this.legalNameError = LABELS.errors.LEGAL_NAME_REQUIRED;
      return;
    }

    this.suggestions = [];
    this.isBusy = true;
    try {
      const result = await checkOrganizationExists({
        legalNameInput: this.legalName
      });
      this.operationalContactName = result.operationalContactName;
      this.organizationExists = result.exists;
      this.hasSearched = true;
      if (!result.exists) {
        this.organization = { ...this.organization, name: this.legalName };
      }
    } catch (error) {
      this.errorMessage = this.translateError(error);
    } finally {
      this.isBusy = false;
    }
  }

  handleCreateOrganization() {
    this.step = STEPS.candidate;
  }

  async handleSubmit() {
    this.errorMessage = undefined;
    if (!this.reportValidity()) {
      return;
    }

    this.isBusy = true;
    try {
      await registerCandidate({
        legalNameInput: this.legalName,
        candidateInput: this.candidate,
        organizationInput: this.organization,
        dataAcceptanceFormTextId: this.dataAcceptanceDocument.data?.formTextId
      });
      this.step = STEPS.confirmed;
    } catch (error) {
      this.errorMessage = this.translateError(error);
    } finally {
      this.isBusy = false;
    }
  }

  async loadSuggestions() {
    if (this.legalName.trim().length < MINIMUM_SEARCH_LENGTH) {
      this.suggestions = [];
      return;
    }
    try {
      this.suggestions = await suggestOrganizations({
        legalNameInput: this.legalName
      });
    } catch {
      this.suggestions = [];
    }
  }

  reportValidity() {
    const isPersonFieldsValid = [
      ...this.template.querySelectorAll("c-contact-details-container")
    ].reduce((isValid, fields) => fields.reportValidity() && isValid, true);
    const isOtherFieldsValid = [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-combobox, lightning-textarea"
      )
    ].reduce((isValid, field) => field.reportValidity() && isValid, true);
    const isCountryValid = Boolean(this.organization.country);
    if (!isCountryValid) {
      this.countryError = LABELS.fieldErrors.country;
    }
    const isDataAcceptanceValid = this.template
      .querySelector("c-consent-checkbox")
      .reportValidity();
    return (
      isPersonFieldsValid &&
      isOtherFieldsValid &&
      isCountryValid &&
      isDataAcceptanceValid
    );
  }

  translateError(error) {
    return (
      LABELS.errors[error?.body?.message] ?? LABELS.errors.UNEXPECTED_ERROR
    );
  }

  get isOrganizationStep() {
    return this.step === STEPS.organization;
  }

  get showBlockedMessage() {
    return this.hasSearched && this.organizationExists;
  }

  get showCreateOrganizationSection() {
    return this.hasSearched && !this.organizationExists;
  }

  get isCandidateStep() {
    return this.step === STEPS.candidate;
  }

  get isConfirmed() {
    return this.step === STEPS.confirmed;
  }

  get legalNameFieldClasses() {
    return this.legalNameError
      ? "slds-form-element slds-has-error"
      : "slds-form-element";
  }

  get hasSuggestions() {
    return this.suggestions.length > 0;
  }

  get comboboxClasses() {
    return this.hasSuggestions
      ? "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open"
      : "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click";
  }

  get salutationOptions() {
    return this.options.data?.salutations ?? [];
  }

  get legalFormOptions() {
    return this.options.data?.legalForms ?? [];
  }

  get isOtherLegalForm() {
    return this.organization.legalForm === OTHER_LEGAL_FORM;
  }

  get countryOptions() {
    return this.options.data?.countries ?? [];
  }

  get countrySuggestions() {
    if (!this.isCountryListOpen) {
      return [];
    }
    const searchText = normalizeForSearch(this.countrySearchText);
    return this.countryOptions.filter((option) =>
      normalizeForSearch(option.label).includes(searchText)
    );
  }

  get hasCountrySuggestions() {
    return this.countrySuggestions.length > 0;
  }

  get countryComboboxClasses() {
    return this.hasCountrySuggestions
      ? "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open"
      : "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click";
  }

  get countryFieldClasses() {
    return this.countryError
      ? "slds-form-element slds-has-error"
      : "slds-form-element";
  }

  get isIdentificationNumberRequired() {
    return this.organization.country === FRANCE;
  }

  get isTaxIdentificationNumberRequired() {
    return (
      Boolean(this.organization.country) &&
      this.organization.country !== FRANCE
    );
  }

  get taxReceiptOptions() {
    return this.options.data?.authorizedToIssueTaxReceipts ?? [];
  }

  get dataAcceptanceUrl() {
    return this.dataAcceptanceDocument?.data?.url;
  }

}