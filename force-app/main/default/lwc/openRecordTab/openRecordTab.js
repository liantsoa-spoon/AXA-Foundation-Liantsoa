/**
 * @description       : Flow action that opens a record in a console tab or subtab, or on its page outside a console.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 01-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   KRA      Initial version
 **/
import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { IsConsoleNavigation, getFocusedTabInfo, openSubtab, openTab } from "lightning/platformWorkspaceApi";

export default class OpenRecordTab extends NavigationMixin(LightningElement) {
  @api recordId;
  @api isSubtab;
  @api hasFocus;

  @wire(IsConsoleNavigation) isConsoleNavigation;

  @api
  async invoke() {
    if (!this.recordId) {
      throw new Error("A record Id is required.");
    }
    if (!this.isConsoleNavigation) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: { recordId: this.recordId, actionName: "view" }
      });
      return;
    }

    const tabSettings = { recordId: this.recordId, focus: this.hasFocus !== false };
    if (this.isSubtab) {
      const focusedTab = await getFocusedTabInfo();
      await openSubtab(focusedTab.isSubtab ? focusedTab.parentTabId : focusedTab.tabId, tabSettings);
    } else {
      await openTab(tabSettings);
    }
  }
}