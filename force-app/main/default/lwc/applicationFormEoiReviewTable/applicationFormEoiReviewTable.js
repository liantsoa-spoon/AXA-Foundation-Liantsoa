/**
 * @description       :
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 17-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
import LightningDatatable from "lightning/datatable";
import eoiDecisionCell from "./eoiDecisionCell.html";

export default class ApplicationFormEoiReviewTable extends LightningDatatable {
  static customTypes = {
    eoiDecision: {
      template: eoiDecisionCell,
      standardCellLayout: true,
      typeAttributes: ["options", "decision"]
    }
  };
}