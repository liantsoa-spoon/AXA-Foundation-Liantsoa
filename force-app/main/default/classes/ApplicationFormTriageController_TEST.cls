@IsTest
private class ApplicationFormTriageController_TEST {
  @TestSetup
  static void setupTestUser() {
    final Profile profile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    final User testUser = new User(
      Alias = 'axatri',
      Email = 'axatriage@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AXATriageUser',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'axatriage' + DateTime.now().getTime() + '@testorg.com'
    );
    insert testUser;

    final List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permissionSet : [SELECT Id FROM PermissionSet WHERE Name IN ('AXA_Foundation_Admin', 'Grantmaking_Manager')]) {
      assignments.add(new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = permissionSet.Id));
    }
    insert assignments;
  }

  @IsTest
  static void getTriageViewModel_givenApplications_returnsThemLargestAmountFirst() {
    final FundingOpportunity programme = createProgramme();
    insert new List<ApplicationForm>{ buildForm('Small', 100, programme.Id), buildForm('Large', 900, programme.Id) };

    System.runAs(getTestUser()) {
      final ApplicationFormTriageController.TriageViewModel viewModel =
        ApplicationFormTriageController.getTriageViewModel(programme.Id);

      Assert.areEqual(2, viewModel.applicationForms.size());
      Assert.areEqual('Large', viewModel.applicationForms[0].title);
      Assert.areEqual(900, viewModel.applicationForms[0].requestedAmount);
      Assert.areEqual('Small', viewModel.applicationForms[1].title);
      Assert.isNotNull(viewModel.fundingOpportunity);
    }
  }

  @IsTest
  static void getTriageViewModel_givenNoApplication_returnsAnEmptyList() {
    final FundingOpportunity programme = createProgramme();

    System.runAs(getTestUser()) {
      final ApplicationFormTriageController.TriageViewModel viewModel =
        ApplicationFormTriageController.getTriageViewModel(programme.Id);

      Assert.isTrue(viewModel.applicationForms.isEmpty());
    }
  }

  @IsTest
  static void updatePrequalification_givenApplications_savesTheValue() {
    final FundingOpportunity programme = createProgramme();
    final List<ApplicationForm> forms = new List<ApplicationForm>{
      buildForm('First', 100, programme.Id),
      buildForm('Second', 200, programme.Id)
    };
    insert forms;

    System.runAs(getTestUser()) {
      ApplicationFormTriageController.updatePrequalification(new List<Id>{ forms[0].Id, forms[1].Id }, 'Green');
    }

    for (ApplicationForm form : [SELECT Prequalification__c FROM ApplicationForm WHERE ReferenceRecordId = :programme.Id]) {
      Assert.areEqual('Green', form.Prequalification__c);
    }
  }

  private static User getTestUser() {
    return [SELECT Id FROM User WHERE LastName = 'AXATriageUser' LIMIT 1];
  }

  private static FundingOpportunity createProgramme() {
    final Program program = new Program(Name = 'Triage Program');
    insert program;
    final FundingOpportunity programme = new FundingOpportunity(Name = 'Triage Programme', Status = 'Draft', ProgramId = program.Id);
    insert programme;
    return programme;
  }

  private static ApplicationForm buildForm(String title, Decimal amount, Id programmeId) {
    return new ApplicationForm(
      Title = title,
      Stage = 'Submitted',
      UsageType = 'Grantmaking',
      RequestedAmount = amount,
      ReferenceRecordId = programmeId
    );
  }
}