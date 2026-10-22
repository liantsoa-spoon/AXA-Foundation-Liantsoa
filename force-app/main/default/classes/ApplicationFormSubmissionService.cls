/**
 * @description       : Checks whether a Funding Opportunity already has a submission from the connected user or from
 *                      a colleague of the same Account, to block duplicate submissions.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 19-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   05-10-2026   LAN      Initial version
 * 1.1   05-10-2026   LAN      Require the connected user to be linked to a Contact and to an Account
 * 1.2   05-10-2026   LAN      Apply the Stage rules of the ticket: every other stage and every colleague form block
 * 1.3   06-10-2026   LAN      Read the program name without sharing: a blocked candidate may not see the program
 * 1.4   06-10-2026   LAN      Open the full application after a submitted EOI when the form is not the EOI alone
 * 1.5   06-10-2026   LAN      Find the colleagues through the Account set on the Application Form
 * 1.6   06-10-2026   LAN      Run the whole class without sharing: external users cannot read their colleagues' forms
 * 1.7   06-10-2026   LAN      Back to with sharing: the colleagues' forms are now shared by Account
 * 1.8   07-10-2026   LAN      Add isConnectedUserApplicantLead: only the Project applicant lead fills the form
 * 1.9   07-10-2026   LAN      Add canConnectedUserEditApplicationForm: internal users keep their access
 * 2.0   07-10-2026   LAN      Return isEditAllowed with the check so a colleague who cannot edit reads the form
 * 2.1   08-10-2026   LAN      Give the submission check errors a code translated by the form (FormErrorService)
 * 2.2   08-10-2026   LAN      Block a submitted EOI in every mode: the full application opens only once approved
 * 2.3   09-10-2026   LAN      buildError and the error codes now come from FormLanguageService
 * 2.4   09-10-2026   LAN      Add getConnectedContactId: the form updates the Contact of the user instead of creating one
 **/
public with sharing class ApplicationFormSubmissionService {
  public static final String STATUS_NONE = 'NONE';
  public static final String STATUS_OPEN_EOI = 'OPEN_EOI';
  public static final String STATUS_OPEN_FULL_APPLICATION = 'OPEN_FULL_APPLICATION';
  public static final String STATUS_ALREADY_SUBMITTED = 'ALREADY_SUBMITTED';
  private static final String CALL_FOR_PROJECTS_RECORD_TYPE = 'CallForProjects';
  private static final String STAGE_EOI_DRAFT = 'EOI Draft';
  private static final String STAGE_DRAFT = 'Draft';
  private static final String STAGE_EOI_SUBMITTED = 'EOI Submitted';
  private static final String STAGE_EOI_APPROVED = 'EOI Approved';
  private static final Set<String> FULL_APPLICATION_OPEN_STAGES = new Set<String>{ STAGE_DRAFT, STAGE_EOI_APPROVED };
  private static final String USER_TYPE_STANDARD = 'Standard';
  private static final String MESSAGE_NO_CONTACT = 'The connected user is not linked to a Contact.';
  private static final String MESSAGE_NO_ACCOUNT = 'The Contact of the connected user is not linked to an Account.';

  // An internal user has no Contact: tests set the Contact to use instead of the connected user's one.
  @TestVisible
  private static Id contactIdOverride;

  // code: the FormLanguageService code shown translated by the form.
  public class SubmissionCheckException extends Exception {
    public String code;
  }

  private static SubmissionCheckException buildSubmissionCheckException(final String code, final String message) {
    final SubmissionCheckException checkException = new SubmissionCheckException(message);
    checkException.code = code;
    return checkException;
  }

  public class SubmissionCheckResult {
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Id applicationFormId;
    @AuraEnabled
    public String applicationFormName;
    @AuraEnabled
    public String programName;
    @AuraEnabled
    public Boolean isOwnApplicationForm;
    @AuraEnabled
    public Boolean isEditAllowed = true;
  }

  // Without a form type, the strictest one applies: the EOI-only form, where a submitted EOI blocks.
  public static SubmissionCheckResult checkExistingSubmission(final Id fundingOpportunityId) {
    return checkExistingSubmission(fundingOpportunityId, true);
  }

  // isEoiOnly: the form shown is the EOI alone. On the full application form (alone, or after the EOI),
  // a submitted EOI opens the full application instead of blocking.
  public static SubmissionCheckResult checkExistingSubmission(
    final Id fundingOpportunityId,
    final Boolean isEoiOnly
  ) {
    final SubmissionCheckResult result = new SubmissionCheckResult();
    result.status = STATUS_NONE;
    result.isOwnApplicationForm = false;
    if (fundingOpportunityId == null) {
      return result;
    }

    final Id recordTypeId = SchemaUtilities.getRecordTypeId(ApplicationForm.SObjectType, CALL_FOR_PROJECTS_RECORD_TYPE);
    if (recordTypeId == null) {
      return result;
    }

    final Id currentUserId = UserInfo.getUserId();
    final List<ApplicationForm> applicationForms = findApplicationFormsInScope(
      fundingOpportunityId,
      recordTypeId,
      currentUserId
    );
    return resolveResult(applicationForms, currentUserId, fundingOpportunityId, isEoiOnly == true);
  }

  public static Boolean isSubmissionBlocked(final Id fundingOpportunityId) {
    return checkExistingSubmission(fundingOpportunityId).status == STATUS_ALREADY_SUBMITTED;
  }

  @TestVisible
  private static SubmissionCheckResult resolveResult(
    final List<ApplicationForm> applicationForms,
    final Id currentUserId,
    final Id fundingOpportunityId
  ) {
    return resolveResult(applicationForms, currentUserId, fundingOpportunityId, true);
  }

  // Applies the business rules to the Application Forms found in the user's scope.
  @TestVisible
  private static SubmissionCheckResult resolveResult(
    final List<ApplicationForm> applicationForms,
    final Id currentUserId,
    final Id fundingOpportunityId,
    final Boolean isEoiOnly
  ) {
    final SubmissionCheckResult result = new SubmissionCheckResult();
    result.status = STATUS_NONE;
    result.isOwnApplicationForm = false;

    ApplicationForm blockingForm;
    ApplicationForm fullApplicationForm;
    ApplicationForm eoiDraftForm;
    for (ApplicationForm applicationForm : applicationForms) {
      final Boolean isOwn = applicationForm.CreatedById == currentUserId;
      if (isOwn && applicationForm.Stage == STAGE_EOI_DRAFT) {
        eoiDraftForm = applicationForm;
      } else if (isOwn && FULL_APPLICATION_OPEN_STAGES.contains(applicationForm.Stage)) {
        // The full application opens only once the EOI is approved: a submitted or rejected EOI blocks.
        fullApplicationForm = applicationForm;
      } else if (blockingForm == null || (isOwn && blockingForm.CreatedById != currentUserId)) {
        blockingForm = applicationForm;
      }
    }

    if (blockingForm != null) {
      fillResult(result, STATUS_ALREADY_SUBMITTED, blockingForm, currentUserId);
      result.programName = getProgramName(fundingOpportunityId);
    } else if (fullApplicationForm != null) {
      fillResult(result, STATUS_OPEN_FULL_APPLICATION, fullApplicationForm, currentUserId);
    } else if (eoiDraftForm != null) {
      fillResult(result, STATUS_OPEN_EOI, eoiDraftForm, currentUserId);
    }
    return result;
  }

  private static void fillResult(
    final SubmissionCheckResult result,
    final String status,
    final ApplicationForm applicationForm,
    final Id currentUserId
  ) {
    result.status = status;
    result.applicationFormId = applicationForm.Id;
    result.applicationFormName = applicationForm.Name;
    result.isOwnApplicationForm = applicationForm.CreatedById == currentUserId;
    result.isEditAllowed = canConnectedUserEditApplicationForm(applicationForm.CreatedById);
  }

  // The Account of the connected user's Contact, set on a new Application Form so that the colleagues of the
  // same Account find it.
  public static Id getConnectedAccountId() {
    return findAccountId(UserInfo.getUserId());
  }

  public static Boolean canConnectedUserEditApplicationForm(Id creatorId) {
    if (creatorId == null || creatorId == UserInfo.getUserId()) {
      return true;
    }
    return UserInfo.getUserType() == USER_TYPE_STANDARD && contactIdOverride == null;
  }

  private static String getProgramName(final Id fundingOpportunityId) {
    final List<FundingOpportunity> fundingOpportunities = [
      SELECT
        Name
      FROM
        FundingOpportunity
      WHERE
        Id = :fundingOpportunityId
      LIMIT
        1
    ];
    return fundingOpportunities.isEmpty() ? null : fundingOpportunities[0].Name;
  }

  private static List<ApplicationForm> findApplicationFormsInScope(
    final Id fundingOpportunityId,
    final Id recordTypeId,
    final Id currentUserId
  ) {
    final Id accountId = findAccountId(currentUserId);
    // The colleagues are reached through the Account set on the Application Form: an external user cannot
    // read the other users of its Account, nor join to the creator.
    return [
      SELECT
        Id,
        Name,
        Stage,
        CreatedById
      FROM
        ApplicationForm
      WHERE
        ReferenceRecordId = :fundingOpportunityId
        AND ProgrammeRattache__c = :fundingOpportunityId
        AND RecordTypeId  = :recordTypeId
        AND (
          CreatedById = :currentUserId
          OR AccountId = :accountId
        )
      WITH
        SYSTEM_MODE
      ORDER BY
        CreatedDate ASC
    ];
  }

  // The Contact of the connected user: it must exist.
  private static Id findContactId(final Id currentUserId) {
    final List<User> currentUsers = [
      SELECT
        ContactId
      FROM
        User
      WHERE
        Id = :currentUserId
      LIMIT
        1
    ];
    final Id contactId = contactIdOverride != null
      ? contactIdOverride
      : (currentUsers.isEmpty() ? null : currentUsers[0].ContactId);
    if (contactId == null) {
      throw buildSubmissionCheckException(FormLanguageService.ERROR_USER_NOT_LINKED, MESSAGE_NO_CONTACT);
    }
    return contactId;
  }

  // The Contact of the connected user, or null for an internal user, who has none.
  public static Id getConnectedContactId() {
    if (contactIdOverride != null) {
      return contactIdOverride;
    }
    final List<User> currentUsers = [
      SELECT
        ContactId
      FROM
        User
      WHERE
        Id = :UserInfo.getUserId()
      LIMIT
        1
    ];
    return currentUsers.isEmpty() ? null : currentUsers[0].ContactId;
  }

  // The Account of the connected user's Contact: both must exist.
  private static Id findAccountId(final Id currentUserId) {
    final Id contactId = findContactId(currentUserId);
    final List<Contact> contacts = [
      SELECT
        AccountId
      FROM
        Contact
      WHERE
        Id = :contactId
      LIMIT
        1
    ];
    if (contacts.isEmpty() || contacts[0].AccountId == null) {
      throw buildSubmissionCheckException(FormLanguageService.ERROR_ORGANIZATION_NOT_LINKED, MESSAGE_NO_ACCOUNT);
    }
    return contacts[0].AccountId;
  }
}