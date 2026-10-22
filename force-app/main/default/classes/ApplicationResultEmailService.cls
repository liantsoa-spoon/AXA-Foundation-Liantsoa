/**
 * @description : Sends the final application decision (Approved / Rejected) to candidates, in bulk or one by one.
 *
 * Safety rules enforced here (never trusted from the UI):
 *  - a candidate is emailed only if the Projet is Approved/Rejected AND ApplicationResultEmailSent__c = false;
 *  - rows are locked (FOR UPDATE) so two concurrent sends cannot both pass the duplicate check;
 *  - one failing email never blocks the others (partial success);
 *  - ApplicationResultEmailSent__c is set to true ONLY for emails Salesforce accepted;
 *  - failures are kept on the Projet (ResultEmailErrorLog__c), logged as a Task, and notified to the sender.
 **/
public with sharing class ApplicationResultEmailService {
  public static final String STAGE_APPROVED = 'Approved';
  public static final String STAGE_REJECTED = 'Rejected';

  public static final String STATUS_SENT = 'SENT';
  public static final String STATUS_FAILED = 'FAILED';
  public static final String STATUS_SKIPPED = 'SKIPPED';

  public static final Integer MAX_RECIPIENTS_PER_REQUEST = 500;

  private static final String LABEL_PARTNER_ORGANISATION_EN = 'Partner organisation';
  private static final String LABEL_PARTNER_ORGANISATION_FR = 'Organisation partenaire';
    private static final String LABEL_NOTIFICATION_STATUS_EN = 'Notification Status';
  private static final String LABEL_NOTIFICATION_STATUS_FR = 'Statut de notification';
  private static final Integer EMAILS_PER_CALL = 100;
  private static final Integer ERROR_LOG_LENGTH = 255;
  private static final String SENDER_DISPLAY_NAME = 'AXA Foundation';
  private static final String NOTIFICATION_TYPE_NAME = 'Error_EOI_email_sent';

  /**
   * Wording lives in Email Templates (Setup > Email Templates), NOT in code: admins can edit them freely.
   * Each template is read once per request and these placeholders are filled in memory (no query per candidate):
   *   [[SALUTATION]] [[CONTACT_NAME]]   the Projet's Contact (project manager)
   *   [[PROJECT_TITLE]]                 title of the Projet
   *   [[PROGRAMME_NAME]]                name of the Programme (FundingOpportunity)
   *   [[RESPONSE_DEADLINE]]             today + RESPONSE_DEADLINE_DAYS
   */
  @TestVisible
  private static final String TEMPLATE_ACCEPTED = 'Application_Result_Accepted';
  @TestVisible
  private static final String TEMPLATE_REJECTED = 'Application_Result_Rejected';
  private static final Integer RESPONSE_DEADLINE_DAYS = 14;
  private static final String DEADLINE_FORMAT = 'd MMMM yyyy';

  public class ResultEmailException extends Exception {}

  // ---------------------------------------------------------------- Read

  public static Overview getOverview(Id fundingOpportunityId) {
    final FundingOpportunity programme = loadProgramme(fundingOpportunityId);
    final Overview overview = new Overview();
    overview.programmeName = programme.Name;
    overview.maxRecipientsPerRequest = MAX_RECIPIENTS_PER_REQUEST;
    overview.labels = getFieldLabels();
    final Map<String, String> stageLabels = getStageLabels();

    for (ApplicationForm form : [
      SELECT
        Id, Name, Title, Stage, ContactId, Contact.Name, Contact.Salutation, Contact.Email, Contact.Account.Name, Account.Name,
        ApplicationResultEmailSent__c, ResultEmailSentDate__c, ResultEmailErrorLog__c
      FROM
        ApplicationForm
      WHERE
        (ReferenceRecordId = :fundingOpportunityId OR ProgrammeRattache__c = :fundingOpportunityId)
        AND Stage IN (:STAGE_APPROVED, :STAGE_REJECTED)
      WITH
        USER_MODE
      ORDER BY
        Contact.Account.Name NULLS LAST, Contact.Name
      LIMIT
        2000
    ]) {
      final CandidateRow row = new CandidateRow(form, stageLabels);
      overview.candidates.add(row);
      if (row.isAccepted) {
        overview.totalAccepted++;
      } else {
        overview.totalRejected++;
      }
      if (row.isNotified) {
        overview.totalNotified++;
      }
    }
    overview.totalCandidates = overview.candidates.size();

    // Previews are the real templates rendered for the first candidate of each kind.
    overview.acceptedTemplate = noPreview();
    overview.rejectedTemplate = noPreview();
    final Map<String, EmailTemplate> templates = loadTemplates();
    for (ApplicationForm form : firstFormPerDecision(fundingOpportunityId)) {
      final Boolean isAccepted = form.Stage == STAGE_APPROVED;
      final Template preview = tryRender(templates.get(templateNameFor(isAccepted)), form, programme.Name);
      if (isAccepted) {
        overview.acceptedTemplate = preview;
      } else {
        overview.rejectedTemplate = preview;
      }
    }
    return overview;
  }

  // ---------------------------------------------------------------- Send

  public static SendSummary sendResults(Id fundingOpportunityId, List<Id> applicationFormIds) {
    if (fundingOpportunityId == null || applicationFormIds == null || applicationFormIds.isEmpty()) {
      throw new ResultEmailException('Aucun candidat sélectionné.');
    }
    final Set<Id> requestedIds = new Set<Id>(applicationFormIds);
    if (requestedIds.size() > MAX_RECIPIENTS_PER_REQUEST) {
      throw new ResultEmailException(
        'Maximum ' + MAX_RECIPIENTS_PER_REQUEST + ' candidats par envoi (' + requestedIds.size() + ' sélectionnés).'
      );
    }

    final FundingOpportunity programme = loadProgramme(fundingOpportunityId);
    final Map<Id, ApplicationForm> forms = lockForms(fundingOpportunityId, requestedIds);
    final SendSummary summary = new SendSummary();
    final List<Outgoing> outgoing = new List<Outgoing>();
    final Map<String, EmailTemplate> templates = loadTemplates();

    for (Id formId : requestedIds) {
      final ApplicationForm form = forms.get(formId);
      final String skipReason = getSkipReason(form);
      if (skipReason != null) {
        summary.add(new Outcome(formId, form, STATUS_SKIPPED, skipReason));
        continue;
      }
      final String blockingError = getBlockingError(form, templates);
      if (blockingError != null) {
        summary.add(new Outcome(formId, form, STATUS_FAILED, blockingError));
        continue;
      }
      try {
        outgoing.add(new Outgoing(form, buildMessage(form, templates, programme.Name)));
      } catch (Exception renderError) {
        summary.add(new Outcome(formId, form, STATUS_FAILED, 'Modèle d\'e-mail non applicable : ' + renderError.getMessage()));
      }
    }

    sendInChunks(outgoing, summary);
    saveResults(summary, forms);
    logFailures(summary, forms);
    notifyFailures(summary, programme);
    summary.finish();
    return summary;
  }

  // ----------------------------------------------------------- Internals

  private static FundingOpportunity loadProgramme(Id fundingOpportunityId) {
    final List<FundingOpportunity> programmes = [
      SELECT Id, Name, OwnerId FROM FundingOpportunity WHERE Id = :fundingOpportunityId WITH USER_MODE LIMIT 1
    ];
    if (programmes.isEmpty()) {
      throw new ResultEmailException('Programme introuvable ou accès refusé.');
    }
    return programmes[0];
  }

  private static Map<Id, ApplicationForm> lockForms(Id fundingOpportunityId, Set<Id> formIds) {
    return new Map<Id, ApplicationForm>(
      [
        SELECT
          Id, Name, Title, Stage, ContactId, Contact.Name, Contact.Salutation, Contact.Email, Contact.Account.Name, Account.Name,
          ApplicationResultEmailSent__c, ResultEmailErrorLog__c
        FROM
          ApplicationForm
        WHERE
          Id IN :formIds
          AND (ReferenceRecordId = :fundingOpportunityId OR ProgrammeRattache__c = :fundingOpportunityId)
        WITH
          USER_MODE
        FOR UPDATE
      ]
    );
  }

  /** Reasons a candidate is silently not emailed (nothing is wrong, nothing is logged as an error). */
  private static String getSkipReason(ApplicationForm form) {
    if (form == null) {
      return 'Dossier introuvable pour ce programme.';
    }
    if (form.Stage != STAGE_APPROVED && form.Stage != STAGE_REJECTED) {
      return 'La décision n\'est pas encore prise (statut : ' + form.Stage + ').';
    }
    if (form.ApplicationResultEmailSent__c) {
      return 'Résultat déjà envoyé.';
    }
    return null;
  }

  /** Problems that make the email impossible to send: reported as failures so the owner can fix and retry. */
  private static String getBlockingError(ApplicationForm form, Map<String, EmailTemplate> templates) {
    if (form.ContactId == null) {
      return 'Aucun contact rattaché au dossier.';
    }
    if (String.isBlank(form.Contact.Email)) {
      return 'Le contact n\'a pas d\'adresse e-mail.';
    }
    final String templateName = templateNameFor(form.Stage == STAGE_APPROVED);
    if (!templates.containsKey(templateName)) {
      return 'Modèle d\'e-mail introuvable ou inactif : ' + templateName + '.';
    }
    return null;
  }

  private static Messaging.SingleEmailMessage buildMessage(
    ApplicationForm form, Map<String, EmailTemplate> templates, String programmeName
  ) {
    final Template template = render(templates.get(templateNameFor(form.Stage == STAGE_APPROVED)), form, programmeName);
    final Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
    message.setTargetObjectId(form.ContactId);
    message.setWhatId(form.Id);
    message.setSaveAsActivity(true);
    message.setSenderDisplayName(SENDER_DISPLAY_NAME);
    message.setSubject(template.subject);
    message.setHtmlBody(template.htmlBody);
    return message;
  }

  private static void sendInChunks(List<Outgoing> outgoing, SendSummary summary) {
    if (outgoing.isEmpty()) {
      return;
    }
    try {
      Messaging.reserveSingleEmailCapacity(outgoing.size());
    } catch (Exception capacityError) {
      for (Outgoing item : outgoing) {
        summary.add(new Outcome(item.form.Id, item.form, STATUS_FAILED, 'Limite d\'envoi e-mail atteinte : ' + capacityError.getMessage()));
      }
      return;
    }

    for (Integer start = 0; start < outgoing.size(); start += EMAILS_PER_CALL) {
      final Integer stop = Math.min(start + EMAILS_PER_CALL, outgoing.size());
      final List<Outgoing> chunk = new List<Outgoing>();
      final List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
      for (Integer i = start; i < stop; i++) {
        chunk.add(outgoing[i]);
        messages.add(outgoing[i].message);
      }
      try {
        final List<Messaging.SendEmailResult> results = Messaging.sendEmail(messages, false);
        for (Integer i = 0; i < chunk.size(); i++) {
          final Boolean ok = results[i].isSuccess();
          summary.add(new Outcome(
            chunk[i].form.Id, chunk[i].form, ok ? STATUS_SENT : STATUS_FAILED,
            ok ? null : results[i].getErrors()[0].getMessage()
          ));
        }
      } catch (Exception callError) {
        // The whole call was rejected: mark only this chunk as failed, other chunks still go out.
        for (Outgoing item : chunk) {
          summary.add(new Outcome(item.form.Id, item.form, STATUS_FAILED, callError.getMessage()));
        }
      }
    }
  }

  /**
   * Bookkeeping runs in system mode on purpose: once an email has left, the "sent" flag MUST be saved
   * even if the user lacks edit rights on the technical fields (otherwise the candidate could be emailed twice).
   */
  private static void saveResults(SendSummary summary, Map<Id, ApplicationForm> forms) {
    final List<ApplicationForm> updates = new List<ApplicationForm>();
    final Datetime now = Datetime.now();
    for (Outcome outcome : summary.outcomes) {
      if (outcome.status == STATUS_SKIPPED) {
        continue;
      }
      final String previousLog = forms.get(outcome.applicationFormId)?.ResultEmailErrorLog__c;
      final ApplicationForm changes = new ApplicationForm(Id = outcome.applicationFormId);
      if (outcome.status == STATUS_SENT) {
        changes.ApplicationResultEmailSent__c = true;
        changes.ResultEmailSentDate__c = now;
        changes.ResultEmailErrorLog__c = appendLog(previousLog, now, 'ENVOYÉ');
      } else {
        changes.ResultEmailErrorLog__c = appendLog(previousLog, now, 'ÉCHEC : ' + outcome.message);
      }
      updates.add(changes);
    }
    if (updates.isEmpty()) {
      return;
    }
    final List<Database.SaveResult> saveResults = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
    for (Integer i = 0; i < saveResults.size(); i++) {
      if (!saveResults[i].isSuccess()) {
        summary.warnings.add(
          'Le suivi du dossier ' + updates[i].Id + ' n\'a pas pu être enregistré : ' +
          saveResults[i].getErrors()[0].getMessage() + ' — vérifiez-le avant tout nouvel envoi.'
        );
      }
    }
  }

  /**
   * Keeps the history instead of overwriting it: newest entry first, older entries kept as long as the
   * 255-character field allows (the oldest are cut first).
   */
  @TestVisible
  private static String appendLog(String previousLog, Datetime timestamp, String message) {
    final String entry = '[' + timestamp.format('dd/MM/yyyy HH:mm') + '] ' + message;
    final String combined = String.isBlank(previousLog) ? entry : entry + ' | ' + previousLog;
    return combined.abbreviate(ERROR_LOG_LENGTH);
  }

  /** One completed Task per failure, related to the Projet and the Contact, so it shows in the Activity timeline. */
  private static void logFailures(SendSummary summary, Map<Id, ApplicationForm> forms) {
    final List<Task> tasks = new List<Task>();
    for (Outcome outcome : summary.outcomes) {
      if (outcome.status != STATUS_FAILED) {
        continue;
      }
      final ApplicationForm form = forms.get(outcome.applicationFormId);
      tasks.add(new Task(
        Subject = 'Échec de l\'envoi du résultat de candidature',
        Description = outcome.message,
        Status = 'Completed',
        Priority = 'High',
        ActivityDate = Date.today(),
        WhatId = outcome.applicationFormId,
        WhoId = form?.ContactId
      ));
    }
    if (tasks.isEmpty()) {
      return;
    }
    // A Task that cannot be saved (storage full, validation...) must not stay silent: tell the user.
    final List<Database.SaveResult> saveResults = Database.insert(tasks, false, AccessLevel.SYSTEM_MODE);
    Integer notLogged = 0;
    String firstReason;
    for (Database.SaveResult saveResult : saveResults) {
      if (!saveResult.isSuccess()) {
        notLogged++;
        firstReason = firstReason ?? saveResult.getErrors()[0].getMessage();
      }
    }
    if (notLogged > 0) {
      summary.warnings.add(
        notLogged + ' échec(s) n\'ont pas pu être consignés comme Activité (' + firstReason +
        '). L\'erreur reste visible dans « Result email error log » du dossier.'
      );
    }
  }

  /** Best effort: a missing notification type or a platform hiccup must never break the send result. */
  /** Bell notification to the user who sent AND to the Programme owner (when the owner is a user, not a queue). */
  private static void notifyFailures(SendSummary summary, FundingOpportunity programme) {
    final Integer failed = summary.countOf(STATUS_FAILED);
    if (failed == 0) {
      return;
    }
    try {
      final List<CustomNotificationType> types = [
        SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE_NAME LIMIT 1
      ];
      if (types.isEmpty()) {
        summary.warnings.add('Notification non envoyée : le type de notification « ' + NOTIFICATION_TYPE_NAME + ' » est introuvable.');
        return;
      }
      final Set<String> recipients = new Set<String>{ UserInfo.getUserId() };
      if (programme.OwnerId != null && programme.OwnerId.getSObjectType() == User.SObjectType) {
        recipients.add(programme.OwnerId);
      }
      final Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setNotificationTypeId(types[0].Id);
      notification.setTargetId(programme.Id);
      notification.setTitle('Échec d\'envoi des résultats de candidature');
      notification.setBody(failed + ' e-mail(s) en échec pour « ' + programme.Name + ' ». Ouvrez le programme pour réessayer.');
      notification.send(recipients);
    } catch (Exception e) {
      summary.warnings.add('Notification non envoyée : ' + e.getMessage());
    }
  }

  // ------------------------------------------------------------ Templates

  private static String templateNameFor(Boolean isAccepted) {
    return isAccepted ? TEMPLATE_ACCEPTED : TEMPLATE_REJECTED;
  }

  /** Active templates by developer name; a missing one is reported per candidate, never as a crash. */
  private static Map<String, EmailTemplate> loadTemplates() {
    final Map<String, EmailTemplate> templates = new Map<String, EmailTemplate>();
    for (EmailTemplate template : [
      SELECT Id, DeveloperName, Subject, HtmlValue
      FROM EmailTemplate
      WHERE DeveloperName IN (:TEMPLATE_ACCEPTED, :TEMPLATE_REJECTED) AND IsActive = TRUE
      WITH SYSTEM_MODE
    ]) {
      templates.put(template.DeveloperName, template);
    }
    return templates;
  }

  /** Single source for the real emails and the on-screen preview. */
  private static Template render(EmailTemplate emailTemplate, ApplicationForm form, String programmeName) {

    ApplicationFormEvaluation evaluation = [SELECT EvaluationAuthority__c FROM ApplicationFormEvaluation WHERE 	ApplicationFormId = :form.Id LIMIT 1];
    
    final Map<String, String> values = new Map<String, String>{
      '[[SALUTATION]]' => form.Contact?.Salutation,
      '[[CONTACT_NAME]]' => form.Contact?.Name,
      '[[PROJECT_TITLE]]' => form.Title,
      '[[PROGRAMME_NAME]]' => programmeName,
      '[[RESPONSE_DEADLINE]]' => Datetime.now().addDays(RESPONSE_DEADLINE_DAYS).format(DEADLINE_FORMAT),
      '[[EVALUATION_COMMITTEE]]' => evaluation?.EvaluationAuthority__c
    };

    final Template template = new Template();
    template.subject = fillTokens(emailTemplate.Subject, values, false);
    template.htmlBody = fillTokens(emailTemplate.HtmlValue, values, true);
    template.textBody = toPlainText(template.htmlBody);
    return template;
  }

  /** AccountId's standard label is "Account Id"; the screen needs "Partner organisation" in both languages. */
  private static Boolean isFrench() {
    return UserInfo.getLanguage().startsWith('fr');
  }

  private static Map<String, String> getFieldLabels() {
    return new Map<String, String>{
      'projectName' => ApplicationForm.Title.getDescribe().getLabel(),
      'organisation' => isFrench() ? LABEL_PARTNER_ORGANISATION_FR : LABEL_PARTNER_ORGANISATION_EN,
      'email' => Contact.Email.getDescribe().getLabel(),
      'currentStatus' => ApplicationForm.Stage.getDescribe().getLabel(),
      'notificationStatus' => isFrench() ? LABEL_NOTIFICATION_STATUS_FR : LABEL_NOTIFICATION_STATUS_EN
    };
  }

  /** Picklist API value -> translated label (e.g. Approved -> Validé). */
  private static Map<String, String> getStageLabels() {
    final Map<String, String> labels = new Map<String, String>();
    for (Schema.PicklistEntry entry : ApplicationForm.Stage.getDescribe().getPicklistValues()) {
      labels.put(entry.getValue(), entry.getLabel());
    }
    return labels;
  }

  /** Plain-text version of the HTML body, for the confirmation dialog. */
  @TestVisible
  private static String toPlainText(String html) {
    return (html ?? '')
      .replaceAll('(?i)<br\s*/?>', '\n')
      .replaceAll('(?i)</(p|div|li|h[1-6])>', '\n\n')
      .replaceAll('<[^>]+>', '')
      .unescapeHtml4()
      .replaceAll('\n{3,}', '\n\n')
      .trim();
  }

  private static Template noPreview() {
    final Template template = new Template();
    template.subject = 'Aucun aperçu';
    template.htmlBody = '<p>Aucun candidat de ce type pour générer un aperçu.</p>';
    template.textBody = 'Aucun candidat de ce type pour générer un aperçu.';
    return template;
  }

  private static Template tryRender(EmailTemplate emailTemplate, ApplicationForm form, String programmeName) {
    final Template template = new Template();
    if (emailTemplate == null) {
      template.subject = 'Modèle introuvable';
      template.htmlBody = '<p>Le modèle d\'e-mail est introuvable ou inactif.</p>';
      return template;
    }
    try {
      return render(emailTemplate, form, programmeName);
    } catch (Exception e) {
      template.subject = 'Aperçu indisponible';
      template.htmlBody = '<p>' + e.getMessage().escapeHtml4() + '</p>';
      template.textBody = e.getMessage();
      return template;
    }
  }

  /** Values are HTML-escaped in the body (names can contain & or <), left raw in the plain-text subject. */
  private static String fillTokens(String text, Map<String, String> values, Boolean escapeHtml) {
    String result = text ?? '';
    for (String token : values.keySet()) {
      final String value = values.get(token) ?? '';
      result = result.replace(token, escapeHtml ? value.escapeHtml4() : value);
    }
    return result;
  }

  private static List<ApplicationForm> firstFormPerDecision(Id fundingOpportunityId) {
    final List<ApplicationForm> firsts = new List<ApplicationForm>();
    for (String stage : new List<String>{ STAGE_APPROVED, STAGE_REJECTED }) {
      final List<ApplicationForm> found = [
        SELECT Id, Stage, Title, ContactId, Contact.Name, Contact.Salutation
        FROM ApplicationForm
        WHERE (ReferenceRecordId = :fundingOpportunityId OR ProgrammeRattache__c = :fundingOpportunityId)
          AND Stage = :stage AND ContactId != NULL
        WITH USER_MODE
        LIMIT 1
      ];
      firsts.addAll(found);
    }
    return firsts;
  }

  // ------------------------------------------------------- Helper types

  private class Outgoing {
    final ApplicationForm form;
    final Messaging.SingleEmailMessage message;
    Outgoing(ApplicationForm form, Messaging.SingleEmailMessage message) {
      this.form = form;
      this.message = message;
    }
  }

  public class Template {
    @AuraEnabled public String subject;
    @AuraEnabled public String htmlBody;
    @AuraEnabled public String textBody;
  }

  public class CandidateRow {
    @AuraEnabled public Id id;
    @AuraEnabled public String reference;
    @AuraEnabled public String projectTitle;
    @AuraEnabled public String projectName;
    @AuraEnabled public String candidateName;
    @AuraEnabled public String organisationName;
    @AuraEnabled public String stageLabel;
    @AuraEnabled public String email;
    @AuraEnabled public String recordUrl;
    @AuraEnabled public Boolean isAccepted;
    @AuraEnabled public Boolean isNotified;
    @AuraEnabled public Datetime sentDate;
    @AuraEnabled public String errorLog;

    CandidateRow(ApplicationForm form, Map<String, String> stageLabels) {
      id = form.Id;
      reference = form.Name;
      projectTitle = form.Title;
      projectName = String.isNotBlank(form.Title) ? form.Title : form.Name;
      candidateName = form.Contact?.Name;
      // Organisation = the Projet's AccountId; falls back to the Contact's account when it is empty.
      organisationName = form.Account?.Name ?? form.Contact?.Account?.Name;
      stageLabel = stageLabels.get(form.Stage) ?? form.Stage;
      email = form.Contact?.Email;
      recordUrl = '/lightning/r/ApplicationForm/' + form.Id + '/view';
      isAccepted = form.Stage == STAGE_APPROVED;
      isNotified = form.ApplicationResultEmailSent__c == true;
      sentDate = form.ResultEmailSentDate__c;
      // Only flag a failure when the latest log entry is one (the field may also hold EOI or "ENVOYÉ" entries).
      final String log = form.ResultEmailErrorLog__c;
      errorLog = !isNotified && log != null && log.substringBefore(' | ').contains('ÉCHEC') ? log : null;
    }
  }

  public class Overview {
    @AuraEnabled public String programmeName;
    @AuraEnabled public Integer maxRecipientsPerRequest;
    /** Column headers = the real field labels (follow the user language and any admin relabeling). */
    @AuraEnabled public Map<String, String> labels = new Map<String, String>();
    @AuraEnabled public Integer totalCandidates = 0;
    @AuraEnabled public Integer totalAccepted = 0;
    @AuraEnabled public Integer totalRejected = 0;
    @AuraEnabled public Integer totalNotified = 0;
    @AuraEnabled public List<CandidateRow> candidates = new List<CandidateRow>();
    @AuraEnabled public Template acceptedTemplate;
    @AuraEnabled public Template rejectedTemplate;
  }

  public class Outcome {
    @AuraEnabled public Id applicationFormId;
    @AuraEnabled public String candidateName;
    @AuraEnabled public String email;
    @AuraEnabled public String status;
    @AuraEnabled public String message;

    Outcome(Id applicationFormId, ApplicationForm form, String status, String message) {
      this.applicationFormId = applicationFormId;
      this.candidateName = form?.Contact?.Name ?? String.valueOf(applicationFormId);
      this.email = form?.Contact?.Email;
      this.status = status;
      this.message = message;
    }
  }

  public class SendSummary {
    @AuraEnabled public Integer sentCount = 0;
    @AuraEnabled public Integer failedCount = 0;
    @AuraEnabled public Integer skippedCount = 0;
    @AuraEnabled public Datetime completedAt;
    @AuraEnabled public List<Outcome> outcomes = new List<Outcome>();
    @AuraEnabled public List<String> warnings = new List<String>();

    void add(Outcome outcome) {
      outcomes.add(outcome);
    }
    Integer countOf(String status) {
      Integer count = 0;
      for (Outcome outcome : outcomes) {
        if (outcome.status == status) {
          count++;
        }
      }
      return count;
    }
    void finish() {
      sentCount = countOf(STATUS_SENT);
      failedCount = countOf(STATUS_FAILED);
      skippedCount = countOf(STATUS_SKIPPED);
      completedAt = Datetime.now();
    }
  }
}