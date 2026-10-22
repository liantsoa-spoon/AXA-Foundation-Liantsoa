/**
 * @description       : Lists a funding opportunity's expressions of interest and saves their EOI decision.
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 23-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
public with sharing class ApplicationFormEoiReviewController {
  @AuraEnabled(cacheable=true)
  public static List<ApplicationFormViewModel> getApplicationFormsToReview(Id fundingOpportunityId) {
    final List<ApplicationFormViewModel> applicationForms = new List<ApplicationFormViewModel>();
    for (ApplicationForm applicationForm : [
      SELECT
        Id,
        Name,
        Title,
        Stage,
        Contact.Name,
        Contact.Account.Name
      FROM
        ApplicationForm
      WHERE
        ReferenceRecordId = :fundingOpportunityId
        AND Stage IN ('EOI Submitted', 'EOI Approved', 'EOI Not Selected')
      WITH
        USER_MODE
      ORDER BY
        Contact.Account.Name NULLS LAST
    ]) {
      applicationForms.add(new ApplicationFormViewModel(applicationForm));
    }
    return applicationForms;
  }

  @AuraEnabled
  public static void updateStage(List<Id> applicationFormIds, String stage) {
    final List<ApplicationForm> applicationForms = new List<ApplicationForm>();
    for (Id applicationFormId : applicationFormIds) {
      applicationForms.add(new ApplicationForm(Id = applicationFormId, Stage = stage));
    }
    update as user applicationForms;
  }

  public class ApplicationFormViewModel {
    @AuraEnabled
    public final Id id;
    @AuraEnabled
    public final String reference;
    @AuraEnabled
    public final String stage;
    @AuraEnabled
    public final String contactName;
    @AuraEnabled
    public final String partnerName;
    @AuraEnabled
    public final String title;

    ApplicationFormViewModel(ApplicationForm applicationForm) {
      id          = applicationForm.Id;
      reference   = applicationForm.Name;
      stage       = applicationForm.Stage;
      contactName = applicationForm.Contact?.Name;
      partnerName = applicationForm.Contact?.Account?.Name;
      title       = applicationForm.Title;
    }
  }
}