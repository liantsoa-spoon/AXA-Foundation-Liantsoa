trigger FundingOpportunityTrigger on FundingOpportunity (after insert, before delete) {
    if (Trigger.isAfter && Trigger.isInsert) {
        FundingOpportunityTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isDelete) {
        FundingOpportunityTriggerHandler.handleBeforeDelete(Trigger.old);
    }
}
