/**
 * @description       : Routes Apex trigger events to the appropriate handler methods.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 13-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   12-10-2026   KRA      Initial version
 **/
public virtual inherited sharing class BaseTriggerHandler {
  @TestVisible
  private static final Map<String, Integer> recursionDepthsByObjectAndTriggerOperation = new Map<String, Integer>();

  private static final Map<Id, Set<String>> bypassedObjectNamesByUserId = new Map<Id, Set<String>>();
  private static final Map<Id, Set<String>> bypassedObjectsAndTriggerOperationsByUserId = new Map<Id, Set<String>>();

  public void run() {
    run(Trigger.operationType, Trigger.new, Trigger.old, Trigger.oldMap);
  }

  @TestVisible
  private void run(
    TriggerOperation triggerOperation,
    List<SObject> newRecords,
    List<SObject> oldRecords,
    Map<Id, SObject> oldRecordsById
  ) {
    if (triggerOperation == null) {
      throw new TriggerHandlerException('BaseTriggerHandler.run() can only be called during trigger execution.');
    }

    final String objectName = String.valueOf((newRecords ?? oldRecords)[0].getSObjectType());
    final String objectAndTriggerOperation = objectName + ':' + triggerOperation;
    if (isBypassed(objectName, objectAndTriggerOperation)) {
      return;
    }

    final Integer recursionDepth =
      (recursionDepthsByObjectAndTriggerOperation.get(objectAndTriggerOperation) ?? 0) + 1;
    final Integer maxRecursionDepth = getMaxRecursionDepth();
    if (maxRecursionDepth != null && recursionDepth > maxRecursionDepth) {
      throw new TriggerHandlerException(
        'Trigger recursion limit of ' + maxRecursionDepth + ' exceeded for ' + objectAndTriggerOperation + '.'
      );
    }

    recursionDepthsByObjectAndTriggerOperation.put(objectAndTriggerOperation, recursionDepth);
    try {
      switch on triggerOperation {
        when BEFORE_INSERT {
          beforeInsert(newRecords);
        }
        when BEFORE_UPDATE {
          beforeUpdate(newRecords, oldRecordsById);
        }
        when BEFORE_DELETE {
          beforeDelete(oldRecords);
        }
        when AFTER_INSERT {
          afterInsert(newRecords);
        }
        when AFTER_UPDATE {
          afterUpdate(newRecords, oldRecordsById);
        }
        when AFTER_DELETE {
          afterDelete(oldRecords);
        }
        when AFTER_UNDELETE {
          afterUndelete(newRecords);
        }
      }
    } finally {
      recursionDepthsByObjectAndTriggerOperation.put(objectAndTriggerOperation, recursionDepth - 1);
    }
  }

  protected virtual Integer getMaxRecursionDepth() {
    return null;
  }

  protected virtual void beforeInsert(List<SObject> newRecords) {}

  protected virtual void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsById) {}

  protected virtual void beforeDelete(List<SObject> oldRecords) {}

  protected virtual void afterInsert(List<SObject> newRecords) {}

  protected virtual void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsById) {}

  protected virtual void afterDelete(List<SObject> oldRecords) {}

  protected virtual void afterUndelete(List<SObject> newRecords) {}

  private static Boolean isBypassed(String objectName, String objectAndTriggerOperation) {
    final Bypass__c bypass = Bypass__c.getInstance();
    if (bypass.AllApexTriggers__c) {
      return true;
    }

    final Id userId = UserInfo.getUserId();
    return getBypassedObjectNames(bypass, userId).contains(objectName.toLowerCase())
      || getBypassedObjectsAndTriggerOperations(bypass, userId).contains(objectAndTriggerOperation.toLowerCase());
  }

  private static Set<String> getBypassedObjectNames(Bypass__c bypass, Id userId) {
    Set<String> bypassedObjectNames = bypassedObjectNamesByUserId.get(userId);
    if (bypassedObjectNames != null) {
      return bypassedObjectNames;
    }

    final List<String> objectNames = splitSemicolonSeparatedEntries(bypass.ApexTriggersByObject__c);
    validateObjectNames(objectNames, Bypass__c.ApexTriggersByObject__c);

    bypassedObjectNames = new Set<String>();
    for (String objectName : objectNames) {
      bypassedObjectNames.add(objectName.toLowerCase());
    }
    bypassedObjectNamesByUserId.put(userId, bypassedObjectNames);
    return bypassedObjectNames;
  }

  private static Set<String> getBypassedObjectsAndTriggerOperations(Bypass__c bypass, Id userId) {
    Set<String> bypassedObjectsAndTriggerOperations = bypassedObjectsAndTriggerOperationsByUserId.get(userId);
    if (bypassedObjectsAndTriggerOperations != null) {
      return bypassedObjectsAndTriggerOperations;
    }

    final Set<String> triggerOperationNames = new Set<String>();
    for (TriggerOperation triggerOperation : TriggerOperation.values()) {
      triggerOperationNames.add(triggerOperation.name());
    }

    final Schema.SObjectField bypassField = Bypass__c.ApexTriggersByObjectAndContext__c;
    bypassedObjectsAndTriggerOperations = new Set<String>();
    final List<String> objectNames = new List<String>();
    for (String objectAndTriggerOperation : splitSemicolonSeparatedEntries(bypass.ApexTriggersByObjectAndContext__c)) {
      final List<String> objectNameAndTriggerOperationName = objectAndTriggerOperation.split(':');
      if (
        objectNameAndTriggerOperationName.size() != 2
        || !triggerOperationNames.contains(objectNameAndTriggerOperationName[1].toUpperCase())
      ) {
        throw new TriggerHandlerException(
          'Invalid entry \'' + objectAndTriggerOperation + '\' in Bypass__c.' + bypassField + '.'
        );
      }

      objectNames.add(objectNameAndTriggerOperationName[0]);
      bypassedObjectsAndTriggerOperations.add(objectAndTriggerOperation.toLowerCase());
    }
    validateObjectNames(objectNames, bypassField);

    bypassedObjectsAndTriggerOperationsByUserId.put(userId, bypassedObjectsAndTriggerOperations);
    return bypassedObjectsAndTriggerOperations;
  }

  private static List<String> splitSemicolonSeparatedEntries(String semicolonSeparatedEntries) {
    final List<String> entries = new List<String>();
    if (String.isBlank(semicolonSeparatedEntries)) {
      return entries;
    }

    for (String entry : semicolonSeparatedEntries.split(';')) {
      final String entryWithoutWhitespace = entry.deleteWhitespace();
      if (entryWithoutWhitespace.length() > 0) {
        entries.add(entryWithoutWhitespace);
      }
    }
    return entries;
  }

  private static void validateObjectNames(List<String> objectNames, Schema.SObjectField bypassField) {
    if (objectNames.isEmpty()) {
      return;
    }

    try {
      Schema.describeSObjects(objectNames, SObjectDescribeOptions.DEFERRED);
    } catch (InvalidParameterValueException unknownObjectException) {
      throw new TriggerHandlerException(
        'Bypass__c.' + bypassField + ' lists an unknown object. ' + unknownObjectException.getMessage()
      );
    }
  }

  public class TriggerHandlerException extends Exception {}
}