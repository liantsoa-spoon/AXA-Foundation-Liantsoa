/**
 * @description       : Provides record type IDs from object types and developer names.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 08-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   08-10-2026   KRA      Initial version
 **/
public inherited sharing class RecordTypeProvider {
  private static final Map<Schema.SObjectType, Map<String, Schema.RecordTypeInfo>>
    recordTypeInfosByObjectTypeByDeveloperName = new Map<Schema.SObjectType, Map<String, Schema.RecordTypeInfo>>();

  public class RecordTypeReference {
    public final String DeveloperName;
    private final Schema.SObjectType objectType;
    private Id recordTypeId;

    public RecordTypeReference(Schema.SObjectType objectType, String developerName) {
      if (objectType == null) {
        throw new RecordTypeException('Object type is required.');
      }
      if (String.isBlank(developerName)) {
        throw new RecordTypeException('Record type developer name is required.');
      }

      this.DeveloperName = developerName;
      this.objectType    = objectType;
    }

    public Id Id {
      get {
        if (recordTypeId == null) {
          recordTypeId = getRecordTypeInfo(objectType, DeveloperName).getRecordTypeId();
        }
        return recordTypeId;
      }
    }
  }

  private static Schema.RecordTypeInfo getRecordTypeInfo(Schema.SObjectType objectType, String developerName) {
    Map<String, Schema.RecordTypeInfo> recordTypeInfosByDeveloperName =
      recordTypeInfosByObjectTypeByDeveloperName.get(objectType);
    if (recordTypeInfosByDeveloperName == null) {
      recordTypeInfosByDeveloperName =
        objectType.getDescribe(SObjectDescribeOptions.DEFERRED).getRecordTypeInfosByDeveloperName();
      recordTypeInfosByObjectTypeByDeveloperName.put(objectType, recordTypeInfosByDeveloperName);
    }

    final Schema.RecordTypeInfo recordTypeInfo = recordTypeInfosByDeveloperName.get(developerName);
    if (recordTypeInfo == null) {
      throw new RecordTypeException(
        'No record type with developer name \'' + developerName + '\' was found on ' + objectType + '.'
      );
    }
    return recordTypeInfo;
  }

  public class RecordTypeException extends Exception {}
}