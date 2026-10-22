/**
 * @description       :
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 09-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
import LightningDatatable from "lightning/datatable";
import prequalificationCell from "./prequalificationCell.html";

export default class ApplicationFormTriageTable extends LightningDatatable {
  static customTypes = {
    prequalification: {
      template: prequalificationCell,
      standardCellLayout: true,
      typeAttributes: ["options", "decision"]
    }
  };
}