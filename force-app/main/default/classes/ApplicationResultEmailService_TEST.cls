/**
 * @description : Tests for ApplicationResultEmailService / ApplicationResultEmailController.
 *                Every test runs as the Org admin user created in the testSetup.
 **/
@IsTest
private class ApplicationResultEmailService_TEST {
  private static final String PROGRAMME_NAME = 'Programme Test';

  @TestSetup
  static void setupTestUser() {
    final Profile profile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    final User testUser = new User(
      Alias = 'orgres',
      Email = 'orgresult@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'OrgResultUser',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'orgresult' + DateTime.now().getTime() + '@testorg.com'
    );
    insert testUser;

    // ApplicationFormEvaluation (evaluation committee in the emails) is only available with the Grantmaking licenses.
    final List<PermissionSetLicenseAssign> licenseAssignments = new List<PermissionSetLicenseAssign>();
    for (PermissionSetLicense license : [
      SELECT Id FROM PermissionSetLicense WHERE DeveloperName IN ('GrantmakingPsl', 'TrackApplicationsPsl')
    ]) {
      licenseAssignments.add(new PermissionSetLicenseAssign(AssigneeId = testUser.Id, PermissionSetLicenseId = license.Id));
    }
    insert licenseAssignments;

    final List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permissionSet : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN ('Admin_Access', 'Grantmaking_Manager')
    ]) {
      assignments.add(new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = permissionSet.Id));
    }
    insert assignments;
  }

  @IsTest
  static void overviewCountsOnlyDecidedProjects() {
    System.runAs(getTestUser()) {
      createData();

      final ApplicationResultEmailService.Overview overview =
        ApplicationResultEmailController.getOverview(programmeId());

      Assert.areEqual(3, overview.totalCandidates);
      Assert.areEqual(2, overview.totalAccepted);
      Assert.areEqual(1, overview.totalRejected);
      Assert.areEqual(0, overview.totalNotified);
      Assert.isTrue(new Set<String>{ 'Partner organisation', 'Organisation partenaire' }.contains(overview.labels.get('organisation')));
      Assert.isTrue(String.isNotBlank(overview.labels.get('notificationStatus')));
      Assert.areEqual('Org Test', overview.candidates[0].organisationName);
      Assert.isTrue(String.isNotBlank(overview.candidates[0].stageLabel));
      final String accepted = overview.acceptedTemplate.htmlBody;
      Assert.isTrue(accepted.contains(PROGRAMME_NAME), accepted);
      final String text = overview.acceptedTemplate.textBody;
      Assert.isTrue(text.contains(PROGRAMME_NAME) && !text.contains('<') && text.contains('\n\n'), text);
      Assert.isTrue(accepted.contains(Datetime.now().addDays(14).format('d MMMM yyyy')), 'Deadline = today + 2 weeks');
      Assert.isTrue(accepted.contains('Mr.'), 'Salutation merged');
      Assert.isFalse(accepted.contains('[[') || accepted.contains('{{{'), 'No unresolved token');
      Assert.isTrue(overview.acceptedTemplate.subject.contains(PROGRAMME_NAME));
      final String rejected = overview.rejectedTemplate.htmlBody;
      Assert.isTrue(rejected.contains('Mrs. Test Rejected'), rejected);
      Assert.isTrue(rejected.contains('>Rejected<') , 'Project title merged');
      Assert.isFalse(rejected.contains('[[') || rejected.contains('{{{'), 'No unresolved token');
    }
  }

  @IsTest
  static void rejectedEmailIsSentAndFlagged() {
    System.runAs(getTestUser()) {
      createData();
      final Id rejectedId = byTitle('Rejected').Id;

      Test.startTest();
      final ApplicationResultEmailService.SendSummary summary =
        ApplicationResultEmailController.sendResults(programmeId(), new List<Id>{ rejectedId });
      Test.stopTest();

      Assert.areEqual(1, summary.sentCount);
      Assert.areEqual(0, summary.failedCount);
      final ApplicationForm reloaded = byTitle('Rejected');
      Assert.isTrue(reloaded.ApplicationResultEmailSent__c);
      Assert.isNotNull(reloaded.ResultEmailSentDate__c);
    }
  }

  @IsTest
  static void secondSendIsBlockedAsDuplicate() {
    System.runAs(getTestUser()) {
      createData();
      final Id rejectedId = byTitle('Rejected').Id;
      ApplicationResultEmailController.sendResults(programmeId(), new List<Id>{ rejectedId });

      final ApplicationResultEmailService.SendSummary second =
        ApplicationResultEmailController.sendResults(programmeId(), new List<Id>{ rejectedId });

      Assert.areEqual(0, second.sentCount);
      Assert.areEqual(1, second.skippedCount);
      Assert.areEqual('SKIPPED', second.outcomes[0].status);
    }
  }

  @IsTest
  static void failuresDoNotBlockOtherEmails() {
    System.runAs(getTestUser()) {
      createData();
      final List<Id> ids = new List<Id>{ byTitle('Accepted').Id, byTitle('Rejected').Id, byTitle('No email').Id };

      final ApplicationResultEmailService.SendSummary summary =
        ApplicationResultEmailController.sendResults(programmeId(), ids);

      Assert.areEqual(2, summary.sentCount);
      Assert.areEqual(1, summary.failedCount);
      Assert.isFalse(byTitle('No email').ApplicationResultEmailSent__c, 'A failed email must stay retryable');
      Assert.isNotNull(byTitle('No email').ResultEmailErrorLog__c);
      Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE Priority = 'High' AND Status = 'Completed']);
    }
  }

  @IsTest
  static void logKeepsHistoryAndNeverExceedsFieldLength() {
    System.runAs(getTestUser()) {
      createData();
      final ApplicationForm noEmail = byTitle('No email');
      update new ApplicationForm(Id = noEmail.Id, ResultEmailErrorLog__c = 'Previous EOI entry');

      ApplicationResultEmailController.sendResults(programmeId(), new List<Id>{ noEmail.Id });
      ApplicationResultEmailController.sendResults(programmeId(), new List<Id>{ noEmail.Id });

      final String log = byTitle('No email').ResultEmailErrorLog__c;
      Assert.isTrue(log.contains('Previous EOI entry') || log.endsWith('...'), 'Older content is kept unless cut for length');
      Assert.areEqual(2, log.countMatches('ÉCHEC'), 'Each attempt adds its own entry');
      Assert.isTrue(log.startsWith('['), 'Newest entry comes first');
      Assert.isTrue(log.length() <= 255);
    }
  }

  @IsTest
  static void sentEntryIsAppendedToExistingLog() {
    System.runAs(getTestUser()) {
      createData();
      final Id rejectedId = byTitle('Rejected').Id;
      update new ApplicationForm(Id = rejectedId, ResultEmailErrorLog__c = 'Older failure');

      ApplicationResultEmailController.sendResults(programmeId(), new List<Id>{ rejectedId });

      final String log = byTitle('Rejected').ResultEmailErrorLog__c;
      Assert.isTrue(log.contains('ENVOYÉ') && log.endsWith('Older failure'), log);
    }
  }

  @IsTest
  static void bulkSendOfManyCandidatesStaysWithinLimits() {
    System.runAs(getTestUser()) {
      createData();
      final List<Contact> contacts = new List<Contact>();
      for (Integer i = 0; i < 150; i++) {
        contacts.add(new Contact(FirstName = 'Test', LastName = 'Bulk' + i, Email = 'bulk' + i + '@example.com'));
      }
      insert contacts;
      final List<ApplicationForm> forms = new List<ApplicationForm>();
      final Id programmeId = programmeId();
      for (Integer i = 0; i < 150; i++) {
        forms.add(buildForm('Bulk ' + i, i < 75 ? 'Approved' : 'Rejected', programmeId, contacts[i].Id));
      }
      insert forms;
      final List<Id> ids = new List<Id>();
      for (ApplicationForm form : forms) {
        ids.add(form.Id);
      }

      final ApplicationResultEmailService.SendSummary summary = ApplicationResultEmailController.sendResults(programmeId, ids);

      Assert.areEqual(150, summary.sentCount, JSON.serialize(summary.outcomes[0]));
    }
  }

  @IsTest
  static void undecidedProjectIsSkipped() {
    System.runAs(getTestUser()) {
      createData();

      final ApplicationResultEmailService.SendSummary summary =
        ApplicationResultEmailController.sendResults(programmeId(), new List<Id>{ byTitle('Undecided').Id });

      Assert.areEqual(1, summary.skippedCount);
      Assert.isFalse(byTitle('Undecided').ApplicationResultEmailSent__c);
    }
  }

  @IsTest
  static void emptySelectionIsRejected() {
    System.runAs(getTestUser()) {
      createData();
      try {
        ApplicationResultEmailController.sendResults(programmeId(), new List<Id>());
        Assert.fail('Expected an exception for an empty selection');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('Aucun candidat'));
      }
    }
  }

  @IsTest
  static void unknownProgrammeIsRejected() {
    System.runAs(getTestUser()) {
      final Id unknownId = Id.valueOf(FundingOpportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
      try {
        ApplicationResultEmailController.getOverview(unknownId);
        Assert.fail('Expected an exception for an unknown programme');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('introuvable'));
      }
    }
  }

  private static User getTestUser() {
    return [SELECT Id FROM User WHERE LastName = 'OrgResultUser' LIMIT 1];
  }

  private static void createData() {
    final Account organisation = new Account(Name = 'Org Test');
    insert organisation;
    final List<Contact> contacts = new List<Contact>{
      new Contact(Salutation = 'Mr.', FirstName = 'Test', LastName = 'Accepted', AccountId = organisation.Id, Email = 'accepted@example.com'),
      new Contact(Salutation = 'Mrs.', FirstName = 'Test', LastName = 'Rejected', AccountId = organisation.Id, Email = 'rejected@example.com'),
      new Contact(Salutation = 'Ms.',FirstName = 'Test', LastName = 'NoEmail', AccountId = organisation.Id)
    };
    insert contacts;
    final Program program = new Program(Name = 'Test Program');
    insert program;
    final FundingOpportunity programme = new FundingOpportunity(
      Name = PROGRAMME_NAME,
      Status = 'Draft',
      ProgramId = program.Id
    );
    insert programme;

    insert new List<ApplicationForm>{
      buildForm('Accepted', 'Approved', programme.Id, contacts[0].Id),
      buildForm('Rejected', 'Rejected', programme.Id, contacts[1].Id),
      buildForm('No email', 'Approved', programme.Id, contacts[2].Id),
      buildForm('Undecided', 'Submitted', programme.Id, contacts[0].Id)
    };
  }

  private static ApplicationForm buildForm(String title, String stage, Id programmeId, Id contactId) {
    return new ApplicationForm(
      Title = title,
      Stage = stage,
      UsageType = 'Grantmaking',
      ReferenceRecordId = programmeId,
      ContactId = contactId
    );
  }

  private static Id programmeId() {
    return [SELECT Id FROM FundingOpportunity WHERE Name = :PROGRAMME_NAME LIMIT 1].Id;
  }

  private static ApplicationForm byTitle(String title) {
    return [
      SELECT Id, Stage, ApplicationResultEmailSent__c, ResultEmailSentDate__c, ResultEmailErrorLog__c
      FROM ApplicationForm
      WHERE Title = :title
      LIMIT 1
    ];
  }
}