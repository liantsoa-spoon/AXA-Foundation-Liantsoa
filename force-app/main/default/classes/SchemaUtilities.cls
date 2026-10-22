/**
 * Small schema helpers
 */
public with sharing class SchemaUtilities {

    // Targeted per-object describe (no Schema.getGlobalDescribe(), which describes the whole org).
    public static Id getRecordTypeId(Schema.SObjectType sObjType, String developerName) {
        Schema.RecordTypeInfo rtInfo = sObjType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName);
        return rtInfo != null ? rtInfo.getRecordTypeId() : null;
    }
}