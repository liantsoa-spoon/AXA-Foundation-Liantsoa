/**
 * @description       : Trigger handler for ApplicationForm.
 * @author            : Ashita Gopaul
 * @last modified on  : 12-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   21-09-2026   AGO      Initial version
 * 1.1   12-10-2026   KRA      Extend BaseTriggerHandler
 **/
public with sharing class ApplicationFormTriggerHandler extends BaseTriggerHandler {

  protected override void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsById) {
    List<ApplicationForm> eoiSubmitted   = new List<ApplicationForm>();
    List<ApplicationForm> fullySubmitted = new List<ApplicationForm>();

    for (ApplicationForm newRecord : (List<ApplicationForm>) newRecords) {
      ApplicationForm oldRecord = (ApplicationForm) oldRecordsById.get(newRecord.Id);
      Boolean stageChanged = newRecord.Stage != oldRecord.Stage;
      if (!stageChanged) {
        continue;
      }

      if (newRecord.Stage == 'EOI Submitted') {
        eoiSubmitted.add(newRecord);
      } else if (newRecord.Stage == 'Submitted') {
        fullySubmitted.add(newRecord);
      }
    }

    if (!eoiSubmitted.isEmpty()) {
      ApplicationFormService.generateEoiPdfs(requeryWithProgramme(eoiSubmitted));
    }
    if (!fullySubmitted.isEmpty()) {
      ApplicationFormService.generateApplicationPdfs(requeryWithProgramme(fullySubmitted));
    }
  }

  private static List<ApplicationForm> requeryWithProgramme(List<ApplicationForm> records) {
    Set<Id> ids = new Map<Id, ApplicationForm>(records).keySet();
    return [
      SELECT
        Id,
        ProgrammeRattache__c
      FROM
        ApplicationForm
      WHERE
        Id IN :ids
      WITH
        USER_MODE
    ];
  }
}