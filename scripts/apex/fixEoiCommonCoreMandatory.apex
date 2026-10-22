List<AssessmentQuestionAssignment> toUpdate = [
    SELECT Id
    FROM AssessmentQuestionAssignment
    WHERE FundingOpportunity__c = null AND Program__c = null AND EOI__c = true AND IsMandatory__c = false
];
for (AssessmentQuestionAssignment aqa : toUpdate) {
    aqa.IsMandatory__c = true;
}
update toUpdate;
System.debug('Updated ' + toUpdate.size() + ' EOI Common Core assignments to Mandatory.');
