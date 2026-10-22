/**
 * @description       : Test class for BaseTriggerHandler
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 13-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   12-10-2026   KRA      Initial version
 **/
@IsTest
private class BaseTriggerHandler_TEST {
  @IsTest
  static void run_calledOutsideTriggerExecution_throwsTriggerHandlerException() {
    try {
      new BaseTriggerHandler().run();
      Assert.fail('Expected a TriggerHandlerException outside a trigger.');
    } catch (BaseTriggerHandler.TriggerHandlerException triggerHandlerException) {
      Assert.areEqual(
        'BaseTriggerHandler.run() can only be called during trigger execution.',
        triggerHandlerException.getMessage()
      );
    }
  }

  @IsTest
  static void run_givenEachTriggerOperation_callsCorrespondingTriggerOperationMethod() {
    final Map<TriggerOperation, String> methodNamesByTriggerOperation = new Map<TriggerOperation, String>{
      TriggerOperation.BEFORE_INSERT  => 'beforeInsert',
      TriggerOperation.BEFORE_UPDATE  => 'beforeUpdate',
      TriggerOperation.BEFORE_DELETE  => 'beforeDelete',
      TriggerOperation.AFTER_INSERT   => 'afterInsert',
      TriggerOperation.AFTER_UPDATE   => 'afterUpdate',
      TriggerOperation.AFTER_DELETE   => 'afterDelete',
      TriggerOperation.AFTER_UNDELETE => 'afterUndelete'
    };

    for (TriggerOperation triggerOperation : methodNamesByTriggerOperation.keySet()) {
      final RecordingTriggerHandler handler = new RecordingTriggerHandler();
      runHandlerOnAccounts(handler, triggerOperation);

      Assert.areEqual(
        new List<String>{ methodNamesByTriggerOperation.get(triggerOperation) },
        handler.calledTriggerOperationMethodNames,
        'Unexpected trigger operation methods for ' + triggerOperation + '.'
      );
    }
  }

  @IsTest
  static void run_givenBaseHandler_runsEveryTriggerOperationAndRestoresRecursionDepth() {
    for (TriggerOperation triggerOperation : TriggerOperation.values()) {
      runHandlerOnAccounts(new BaseTriggerHandler(), triggerOperation);

      Assert.areEqual(0, getAccountRecursionDepth(triggerOperation));
    }
  }

  @IsTest
  static void run_givenAllApexTriggers_skipsTriggerOperationMethod() {
    insert new Bypass__c(
      SetupOwnerId       = UserInfo.getUserId(),
      AllApexTriggers__c = true
    );
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();

    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);

    Assert.isTrue(handler.calledTriggerOperationMethodNames.isEmpty());
  }

  @IsTest
  static void run_givenObjectWithOtherCaseAndSpacesInApexTriggersByObject_skipsEveryTriggerOperationMethod() {
    insert new Bypass__c(
      SetupOwnerId            = UserInfo.getUserId(),
      ApexTriggersByObject__c = 'Contact; account'
    );
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();

    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);
    runHandlerOnAccounts(handler, TriggerOperation.AFTER_INSERT);

    Assert.isTrue(handler.calledTriggerOperationMethodNames.isEmpty());
  }

  @IsTest
  static void run_givenOtherObjectInApexTriggersByObject_callsTriggerOperationMethod() {
    insert new Bypass__c(
      SetupOwnerId            = UserInfo.getUserId(),
      ApexTriggersByObject__c = 'Contact'
    );
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();

    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);

    Assert.areEqual(new List<String>{ 'beforeInsert' }, handler.calledTriggerOperationMethodNames);
  }

  @IsTest
  static void run_givenObjectAndContextWithOtherCaseAndSpacesInApexTriggersByObjectAndContext_skipsOnlyThatTriggerOperationMethod() {
    insert new Bypass__c(
      SetupOwnerId                      = UserInfo.getUserId(),
      ApexTriggersByObjectAndContext__c = ' account : after_insert ;'
    );
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();

    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);
    runHandlerOnAccounts(handler, TriggerOperation.AFTER_INSERT);

    Assert.areEqual(new List<String>{ 'beforeInsert' }, handler.calledTriggerOperationMethodNames);
  }

  @IsTest
  static void run_givenUnknownObjectInApexTriggersByObject_throwsTriggerHandlerException() {
    insert new Bypass__c(
      SetupOwnerId            = UserInfo.getUserId(),
      ApexTriggersByObject__c = 'Acount'
    );

    try {
      runHandlerOnAccounts(new RecordingTriggerHandler(), TriggerOperation.BEFORE_INSERT);
      Assert.fail('Expected a TriggerHandlerException for an unknown object.');
    } catch (BaseTriggerHandler.TriggerHandlerException triggerHandlerException) {
      Assert.isTrue(
        triggerHandlerException.getMessage().startsWith('Bypass__c.ApexTriggersByObject__c lists an unknown object.'),
        triggerHandlerException.getMessage()
      );
    }
  }

  @IsTest
  static void run_givenUnknownObjectInApexTriggersByObjectAndContext_throwsTriggerHandlerException() {
    insert new Bypass__c(
      SetupOwnerId                      = UserInfo.getUserId(),
      ApexTriggersByObjectAndContext__c = 'Acount:AFTER_INSERT'
    );

    try {
      runHandlerOnAccounts(new RecordingTriggerHandler(), TriggerOperation.BEFORE_INSERT);
      Assert.fail('Expected a TriggerHandlerException for an unknown object.');
    } catch (BaseTriggerHandler.TriggerHandlerException triggerHandlerException) {
      Assert.isTrue(
        triggerHandlerException.getMessage()
          .startsWith('Bypass__c.ApexTriggersByObjectAndContext__c lists an unknown object.'),
        triggerHandlerException.getMessage()
      );
    }
  }

  @IsTest
  static void run_givenEntryWithoutContextInApexTriggersByObjectAndContext_throwsTriggerHandlerException() {
    insert new Bypass__c(
      SetupOwnerId                      = UserInfo.getUserId(),
      ApexTriggersByObjectAndContext__c = 'Account'
    );

    try {
      runHandlerOnAccounts(new RecordingTriggerHandler(), TriggerOperation.BEFORE_INSERT);
      Assert.fail('Expected a TriggerHandlerException for an entry without context.');
    } catch (BaseTriggerHandler.TriggerHandlerException triggerHandlerException) {
      Assert.areEqual(
        'Invalid entry \'Account\' in Bypass__c.ApexTriggersByObjectAndContext__c.',
        triggerHandlerException.getMessage()
      );
    }
  }

  @IsTest
  static void run_givenUnknownContextInApexTriggersByObjectAndContext_throwsTriggerHandlerException() {
    insert new Bypass__c(
      SetupOwnerId                      = UserInfo.getUserId(),
      ApexTriggersByObjectAndContext__c = 'Account:AFTER_SAVE'
    );

    try {
      runHandlerOnAccounts(new RecordingTriggerHandler(), TriggerOperation.BEFORE_INSERT);
      Assert.fail('Expected a TriggerHandlerException for an unknown context.');
    } catch (BaseTriggerHandler.TriggerHandlerException triggerHandlerException) {
      Assert.areEqual(
        'Invalid entry \'Account:AFTER_SAVE\' in Bypass__c.ApexTriggersByObjectAndContext__c.',
        triggerHandlerException.getMessage()
      );
    }
  }

  @IsTest
  static void run_givenSequentialRunsWithMaxRecursionDepthOne_callsTriggerOperationMethodEachTime() {
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();
    handler.maxRecursionDepth = 1;

    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);
    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);

    Assert.areEqual(new List<String>{ 'beforeInsert', 'beforeInsert' }, handler.calledTriggerOperationMethodNames);
  }

  @IsTest
  static void run_givenNestedRunAtMaxRecursionDepth_callsTriggerOperationMethodTwiceAndRestoresRecursionDepth() {
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();
    handler.maxRecursionDepth   = 2;
    handler.remainingNestedRuns = 1;

    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);

    Assert.areEqual(new List<String>{ 'beforeInsert', 'beforeInsert' }, handler.calledTriggerOperationMethodNames);
    Assert.areEqual(0, getAccountRecursionDepth(TriggerOperation.BEFORE_INSERT));
  }

  @IsTest
  static void run_givenNestedRunAboveMaxRecursionDepth_throwsTriggerHandlerException() {
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();
    handler.maxRecursionDepth   = 1;
    handler.remainingNestedRuns = 1;

    try {
      runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);
      Assert.fail('Expected a TriggerHandlerException above the maximum recursion depth.');
    } catch (BaseTriggerHandler.TriggerHandlerException triggerHandlerException) {
      Assert.areEqual(
        'Trigger recursion limit of 1 exceeded for Account:BEFORE_INSERT.',
        triggerHandlerException.getMessage()
      );
    }
    Assert.areEqual(0, getAccountRecursionDepth(TriggerOperation.BEFORE_INSERT));
  }

  @IsTest
  static void run_givenNestedRunOnOtherTriggerOperation_countsRecursionDepthSeparately() {
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();
    handler.maxRecursionDepth      = 1;
    handler.remainingNestedRuns    = 1;
    handler.nestedTriggerOperation = TriggerOperation.AFTER_INSERT;

    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);

    Assert.areEqual(new List<String>{ 'beforeInsert', 'afterInsert' }, handler.calledTriggerOperationMethodNames);
  }

  @IsTest
  static void run_givenNoMaxRecursionDepth_allowsNestedRuns() {
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();
    handler.remainingNestedRuns = 3;

    runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);

    Assert.areEqual(4, handler.calledTriggerOperationMethodNames.size());
  }

  @IsTest
  static void run_givenFailingTriggerOperationMethod_restoresRecursionDepth() {
    final RecordingTriggerHandler handler = new RecordingTriggerHandler();
    handler.isTriggerOperationMethodThrowingException = true;

    try {
      runHandlerOnAccounts(handler, TriggerOperation.BEFORE_INSERT);
      Assert.fail('Expected the trigger operation method to fail.');
    } catch (TriggerOperationMethodException triggerOperationMethodException) {
      Assert.areEqual('Trigger operation method failed.', triggerOperationMethodException.getMessage());
    }
    Assert.areEqual(0, getAccountRecursionDepth(TriggerOperation.BEFORE_INSERT));
  }

  private static void runHandlerOnAccounts(BaseTriggerHandler handler, TriggerOperation triggerOperation) {
    final List<SObject> records = new List<Account>{ new Account(Name = 'Trigger Handler Test') };
    handler.run(triggerOperation, records, records, new Map<Id, SObject>());
  }

  private static Integer getAccountRecursionDepth(TriggerOperation triggerOperation) {
    return BaseTriggerHandler.recursionDepthsByObjectAndTriggerOperation.get('Account:' + triggerOperation);
  }

  private class RecordingTriggerHandler extends BaseTriggerHandler {
    public Integer maxRecursionDepth;
    public Integer remainingNestedRuns = 0;
    public TriggerOperation nestedTriggerOperation = TriggerOperation.BEFORE_INSERT;
    public Boolean isTriggerOperationMethodThrowingException = false;

    public final List<String> calledTriggerOperationMethodNames = new List<String>();

    protected override Integer getMaxRecursionDepth() {
      return maxRecursionDepth;
    }

    protected override void beforeInsert(List<SObject> newRecords) {
      recordTriggerOperationMethodCall('beforeInsert');
    }

    protected override void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsById) {
      recordTriggerOperationMethodCall('beforeUpdate');
    }

    protected override void beforeDelete(List<SObject> oldRecords) {
      recordTriggerOperationMethodCall('beforeDelete');
    }

    protected override void afterInsert(List<SObject> newRecords) {
      recordTriggerOperationMethodCall('afterInsert');
    }

    protected override void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsById) {
      recordTriggerOperationMethodCall('afterUpdate');
    }

    protected override void afterDelete(List<SObject> oldRecords) {
      recordTriggerOperationMethodCall('afterDelete');
    }

    protected override void afterUndelete(List<SObject> newRecords) {
      recordTriggerOperationMethodCall('afterUndelete');
    }

    private void recordTriggerOperationMethodCall(String methodName) {
      calledTriggerOperationMethodNames.add(methodName);
      if (isTriggerOperationMethodThrowingException) {
        throw new TriggerOperationMethodException('Trigger operation method failed.');
      }
      if (remainingNestedRuns > 0) {
        remainingNestedRuns--;
        runHandlerOnAccounts(this, nestedTriggerOperation);
      }
    }
  }

  private class TriggerOperationMethodException extends Exception {}
}