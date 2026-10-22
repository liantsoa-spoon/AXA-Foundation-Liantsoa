import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getOrganizationId from "@salesforce/apex/OrganizationRedirectController.getOrganizationId";

export default class OrganizationRedirect extends NavigationMixin(LightningElement) {
  isLoading = true;
  errorMessage;

  connectedCallback() {
    this.redirectToOrganization();
  }

  async redirectToOrganization() {
    try {
      const organizationId = await getOrganizationId();
      if (!organizationId) {
        this.errorMessage =
          "Aucune organisation n'est associée à votre compte.";
        this.isLoading = false;
        return;
      }

      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: organizationId,
          objectApiName: "Account",
          actionName: "view"
        }
      });
    } catch (error) {
      this.errorMessage = "Une erreur est survenue. Veuillez réessayer.";
      this.isLoading = false;
    }
  }
}