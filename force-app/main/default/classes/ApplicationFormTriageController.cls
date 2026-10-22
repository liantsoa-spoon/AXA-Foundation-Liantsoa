/**
 * @description       : Lists a funding opportunity's applications for triage and saves their prequalification.
 * @author            : Kevin RAMAROZATOVO
 * @group             :
 * @last modified on  : 09-09-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
public with sharing class ApplicationFormTriageController {

  @AuraEnabled(cacheable=true)
  public static TriageViewModel getTriageViewModel(Id fundingOpportunityId) {
    return new TriageViewModel(
      [
        SELECT
          MinimumFundingAmount,
          MaximumFundingAmount,
          EndDate
        FROM
          FundingOpportunity
        WHERE
          Id = :fundingOpportunityId
        WITH
          USER_MODE
      ],
      [
        SELECT
          Id,
          Name,
          Title,
          Contact.Name,
          Account.Name,
          RequestedAmount,
          SubmissionDate,
          Prequalification__c
        FROM
          ApplicationForm
        WHERE
          ReferenceRecordId = :fundingOpportunityId
        WITH
          USER_MODE
        ORDER BY
          RequestedAmount DESC NULLS LAST
      ]
    );
  }

  @AuraEnabled
  public static void updatePrequalification(List<Id> applicationFormIds, String prequalification) {
    final List<ApplicationForm> applications = new List<ApplicationForm>();
    for (Id applicationFormId : applicationFormIds) {
      applications.add(new ApplicationForm(Id = applicationFormId, Prequalification__c = prequalification));
    }
    update as user applications;
  }

  public class TriageViewModel {
    @AuraEnabled
    public final FundingOpportunityViewModel fundingOpportunity;
    @AuraEnabled
    public final List<ApplicationFormViewModel> applicationForms;

    TriageViewModel(
      FundingOpportunity    fundingOpportunityRecord,
      List<ApplicationForm> applicationFormRecords
    ) {
      fundingOpportunity = new FundingOpportunityViewModel(fundingOpportunityRecord);
      applicationForms   = new List<ApplicationFormViewModel>();
      for (ApplicationForm applicationFormRecord : applicationFormRecords) {
        applicationForms.add(new ApplicationFormViewModel(applicationFormRecord));
      }
    }
  }

  public class FundingOpportunityViewModel {
    @AuraEnabled
    public final Decimal minimumAmount;
    @AuraEnabled
    public final Decimal maximumAmount;
    @AuraEnabled
    public final Datetime closingDate;

    FundingOpportunityViewModel(FundingOpportunity fundingOpportunity) {
      minimumAmount = fundingOpportunity.MinimumFundingAmount;
      maximumAmount = fundingOpportunity.MaximumFundingAmount;
      closingDate   = fundingOpportunity.EndDate;
    }
  }

  public class ApplicationFormViewModel {
    @AuraEnabled
    public final Id id;
    @AuraEnabled
    public final String reference;
    @AuraEnabled
    public final String title;
    @AuraEnabled
    public final String contactName;
    @AuraEnabled
    public final String accountName;
    @AuraEnabled
    public final Decimal requestedAmount;
    @AuraEnabled
    public final Date submissionDate;
    @AuraEnabled
    public final String prequalification;

    ApplicationFormViewModel(ApplicationForm applicationForm) {
      id              = applicationForm.Id;
      reference       = applicationForm.Name;
      title           = applicationForm.Title;
      contactName     = applicationForm.Contact?.Name;
      accountName     = applicationForm.Account?.Name;
      requestedAmount = applicationForm.RequestedAmount;
      submissionDate  = applicationForm.SubmissionDate;
      prequalification = applicationForm.Prequalification__c;
    }
  }
}