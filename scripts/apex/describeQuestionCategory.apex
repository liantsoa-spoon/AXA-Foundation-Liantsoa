Schema.DescribeFieldResult categoryDescribe =
    AssessmentQuestion.QuestionCategory.getDescribe();

System.debug('--- QuestionCategory picklist values ---');
for (Schema.PicklistEntry entry : categoryDescribe.getPicklistValues()) {
    System.debug(entry.getValue() + ' | active=' + entry.isActive() + ' | default=' + entry.isDefaultValue());
}

System.debug('--- AssessmentQuestion record types ---');
for (Schema.RecordTypeInfo recordTypeInfo :
        AssessmentQuestion.sObjectType.getDescribe().getRecordTypeInfos()) {
    System.debug(
        recordTypeInfo.getDeveloperName()
        + ' | id=' + recordTypeInfo.getRecordTypeId()
        + ' | available=' + recordTypeInfo.isAvailable()
        + ' | master=' + recordTypeInfo.isMaster()
    );
}
