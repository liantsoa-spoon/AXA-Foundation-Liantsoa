import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getContacts from "@salesforce/apex/OrganizationContactsListController.getContacts";

const LABELS = {
  title: "Contacts de l'organisation"
};

export default class OrganizationContactsList extends NavigationMixin(
  LightningElement
) {
  labels = LABELS;
  contacts = [];
  errorMessage;

  @wire(getContacts)
  wiredContacts({ data, error }) {
    if (data) {
      this.contacts = data.map((contact) => this.toViewModel(contact));
      this.errorMessage = undefined;
    } else if (error) {
      this.contacts = [];
      this.errorMessage =
        error?.body?.message ?? "Une erreur est survenue. Veuillez réessayer.";
    }
  }

  toViewModel(contact) {
    return {
      id: contact.id,
      name: contact.name,
      role: contact.role,
      email: contact.email,
      phone: contact.phone,
      initials: this.buildInitials(contact.name),
      detailUrl: `/contact/${contact.id}`,
      emailHref: contact.email ? `mailto:${contact.email}` : undefined,
      phoneHref: contact.phone ? `tel:${contact.phone}` : undefined
    };
  }

  buildInitials(name) {
    if (!name) {
      return "";
    }
    return name
      .split(" ")
      .filter(Boolean)
      .map((part) => part[0].toUpperCase())
      .slice(0, 2)
      .join("");
  }

  get countLabel() {
    return `${this.contacts.length} contact${this.contacts.length === 1 ? "" : "s"}`;
  }

  handleOpenContact(event) {
    event.preventDefault();
    const contactId = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: contactId,
        objectApiName: "Contact",
        actionName: "view"
      }
    });
  }
}