/**
 * @description       : Displays why the program questions cannot be edited while the program is not Active.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 07-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   07-10-2026   KRA      Initial version
 **/
import { LightningElement, api, wire } from "lwc";
import { getFieldValue, getRecord } from "lightning/uiRecordApi";
import FUNDING_OPPORTUNITY_STATUS_FIELD from "@salesforce/schema/FundingOpportunity.Status";

const STATUS_ACTIVE = "Active";

const LABELS = {
  title: "🔒 Questions en lecture seule",
  message:
    "Les questions sont modifiables uniquement lorsque le programme est au statut Actif."
};

export default class ApplicationFormCatalogueReadOnlyNotice extends LightningElement {
  labels = LABELS;

  @api recordId;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [FUNDING_OPPORTUNITY_STATUS_FIELD]
  })
  fundingOpportunity;

  get isReadOnly() {
    const status = getFieldValue(
      this.fundingOpportunity.data,
      FUNDING_OPPORTUNITY_STATUS_FIELD
    );
    return status != null && status !== STATUS_ACTIVE;
  }
}