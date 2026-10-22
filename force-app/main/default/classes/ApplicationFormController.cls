/**
 * @description       : Serves and saves the candidate-facing application form, including file uploads.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 20-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   LAN      Name uploaded files after the field label; remove renameUploadedFile
 * 1.1   02-10-2026   LAN      Make the form read-only according to the Funding Opportunity status
 * 1.2   05-10-2026   LAN      Add renameUploadedFiles to name the files sent with the standard file upload
 * 1.3   05-10-2026   LAN      Add linkUploadedFiles to attach the uploaded files to the Application Form on save
 * 1.4   05-10-2026   LAN      Remove the custom upload (uploadFile): the standard file upload is used
 * 1.5   05-10-2026   LAN      Add checkExistingSubmission and block duplicate submissions on save
 * 1.6   06-10-2026   LAN      Make the form editable when the Funding Opportunity is Open for EOIs
 * 1.7   06-10-2026   LAN      Pass the EOI-only form type to the submission check
 * 1.8   06-10-2026   LAN      Set the Account of the connected user on the new Application Form
 * 1.9   06-10-2026   LAN      Open the EOI then the full application for a Call for Projects program, the full application otherwise
 * 2.0   06-10-2026   LAN      Read the question versions through the catalogue service, in system mode
 * 2.1   06-10-2026   LAN      Derive the form mode from the program type also when resumed from an Application Form
 * 2.2   07-10-2026   LAN      Only the Project applicant lead fills the form: expose isEditAllowed and refuse the saves
 * 2.3   07-10-2026   LAN      Link the Contact created from the Fixed answers to the Account of the connected user
 * 2.4   07-10-2026   LAN      Give that Contact the owner of the Account: a portal user cannot own it
 * 2.5   07-10-2026   LAN      Insert, update and read the form data in system mode, behind the user mode reads of the form
 * 2.6   07-10-2026   LAN      Remove the link of the created Contact to the Account and to its owner
 * 2.7   07-10-2026   LAN      Read the Fixed targets of a readable form without sharing for the read-only colleagues
 * 2.8   08-10-2026   LAN      Return the form language resolved from the pillar of the program
 * 2.9   08-10-2026   LAN      Show the French question text and response values when the form language is FR
 * 3.0   08-10-2026   LAN      Return error codes translated by the form instead of English messages
 * 3.1   08-10-2026   LAN      Build the errors with FormErrorService, shared with the file and submission services
 * 3.2   08-10-2026   LAN      A submitted EOI shows the EOI and refuses the saves: the full application waits for its approval
 * 3.3   08-10-2026   LAN      A rejected EOI is shown in read-only like a submitted one, instead of an unavailable text
 * 3.4   08-10-2026   LAN      Add openReadOnlyForm: in read-only, the EOI checkbox decides between EOI and full application
 * 3.5   08-10-2026   LAN      Return DUPLICATE_CONTACT or DUPLICATE_RECORD when a duplicate rule blocks a Fixed target
 * 3.6   09-10-2026   LAN      buildError and the error codes now come from FormLanguageService
 * 3.7   09-10-2026   LAN      Set the Account of the Application Form on the new Assessment
 * 3.8   09-10-2026   LAN      Update the Contact of the connected user instead of creating a Contact for each form
 * 3.9   09-10-2026   LAN      Remove getApplicantContactId and findDuplicateContactId: no Contact is created for the form anymore
 * 4.0   09-10-2026   LAN      Set the Contact of the connected user on the new Application Form; a saved form shows its own Contact
 * 4.1   09-10-2026   LAN      Update the Contact of the connected user, and only it, without sharing
 * 4.2   13-10-2026   LAN      Add ensureCanEditApplicationForm, used by the save of the budget tables
 * 4.3   13-10-2026   LAN      Leave the budget columns to the budget table and flag the sections that hold one
 * 4.4   19-10-2026   LAN      Detect the budget tables through ApplicationFormBudgetController
 * 4.5   20-10-2026   LAN      Require the terms and conditions and the image rights on submission and record the consents
 **/
public with sharing class ApplicationFormController {
    private static final String CALL_FOR_PROJECTS_RECORD_TYPE = 'CallForProjects';
    private static final String APPLICATION_FORM_API_NAME = 'ApplicationForm';
    private static final String CONTACT_API_NAME = 'Contact';
    @TestVisible private static final String ERROR_TECHNICAL = FormLanguageService.ERROR_TECHNICAL;
    @TestVisible private static final String ERROR_ID_REQUIRED = 'ID_REQUIRED';
    @TestVisible private static final String ERROR_FORM_NOT_LINKED = 'FORM_NOT_LINKED';
    @TestVisible private static final String ERROR_FORM_NOT_FOUND = 'APPLICATION_FORM_NOT_FOUND';
    @TestVisible private static final String ERROR_ALREADY_SUBMITTED = 'APPLICATION_ALREADY_SUBMITTED';
    @TestVisible private static final String ERROR_FUNDING_OPPORTUNITY_LOCKED = 'FUNDING_OPPORTUNITY_LOCKED';
    @TestVisible private static final String ERROR_FUNDING_OPPORTUNITY_NOT_FOUND = 'FUNDING_OPPORTUNITY_NOT_FOUND';
    @TestVisible private static final String ERROR_EDIT_NOT_ALLOWED = 'EDIT_NOT_ALLOWED';
    @TestVisible private static final String ERROR_STATUS_REQUIRED = 'STATUS_REQUIRED';
    @TestVisible private static final String ERROR_QUESTION_REQUIRED = 'QUESTION_REQUIRED';
    @TestVisible private static final String ERROR_MAXIMUM_CHARACTERS = 'MAXIMUM_CHARACTERS_EXCEEDED';
    @TestVisible private static final String ERROR_REQUIRED_FIELDS_MISSING = 'REQUIRED_FIELDS_MISSING';
    @TestVisible private static final String ERROR_INVALID_VALUE = 'INVALID_VALUE';
    @TestVisible private static final String ERROR_USER_NOT_LINKED = FormLanguageService.ERROR_USER_NOT_LINKED;
    @TestVisible private static final String ERROR_DUPLICATE_CONTACT = 'DUPLICATE_CONTACT';
    @TestVisible private static final String ERROR_DUPLICATE_RECORD = 'DUPLICATE_RECORD';
    @TestVisible private static final String ERROR_CONSENTS_NOT_ACCEPTED = 'CONSENTS_NOT_ACCEPTED';

    private static final String CONSENT_SOURCE_EOI              = 'EOI Submission';
    private static final String CONSENT_SOURCE_FULL_APPLICATION = 'Full Application Submission';
    private static final String LABEL_LANGUAGE_ENGLISH          = 'en_US';
    private static final String LABEL_LANGUAGE_FRENCH           = 'fr';

    private static final Set<String> EDITABLE_FUNDING_OPPORTUNITY_STATUSES = new Set<String>{
        'Active',
        'Draft',
        'Published',
        'Open for Applications',
        'Open for EOIs'
    };

    public class FormDefinitionWrapper {
        @AuraEnabled public Boolean isFundingOpportunityLocked;
        @AuraEnabled public Boolean isEditAllowed;
        @AuraEnabled public String creatorName;
        // EN or FR: the language of the pillar of the program (Science: EN), otherwise the user's one.
        @AuraEnabled public String formLanguage;
        @AuraEnabled public List<SectionWrapper> sections;
        @AuraEnabled public String applicationStatus;
        @AuraEnabled public Id applicationFormId;
        @AuraEnabled public Id fundingOpportunityId;
        @AuraEnabled public Boolean isEoi;
        @AuraEnabled public Boolean isUnavailable;
        @AuraEnabled public String unavailableMessage;
        @AuraEnabled public ConsentsWrapper consents;
    }

    // The consent checkboxes shown at the end of the form, in the language of the form.
    public class ConsentsWrapper {
        @AuraEnabled public String prefix;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public ConsentWrapper termsAndConditions;
        @AuraEnabled public ConsentWrapper imageRights;
    }

    public class ConsentWrapper {
        @AuraEnabled public Id formTextId;
        @AuraEnabled public String url;
        @AuraEnabled public String linkLabel;
    }

    public class SectionWrapper {
        @AuraEnabled public Id sectionId;
        @AuraEnabled public String label;
        @AuraEnabled public List<QuestionWrapper> questions;
        // The section shows budget tables, loaded by ApplicationFormBudgetController.
        @AuraEnabled public Boolean hasBudget;
    }

    public class QuestionWrapper {
        @AuraEnabled public Id questionId;
        @AuraEnabled public Id versionId;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean isTable;
        @AuraEnabled public String helpText;
        @AuraEnabled public Decimal maximumCharacters;
        @AuraEnabled public String responseValues;
        // French labels of responseValues, same order: shown to the candidate while the English value is saved.
        @AuraEnabled public String responseLabels;
        @AuraEnabled public List<ApplicationFormCatalogueController.ColumnWrapper> columns;
        @AuraEnabled public String existingValueJson;
        @AuraEnabled public Boolean isFixed;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public Boolean isMandatory;
        @AuraEnabled public Boolean isSchemaRequired;
    }

    public class ResponseInputWrapper {
        @AuraEnabled public String versionId;
        @AuraEnabled public String valueJson;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean isFixed;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isMandatory;
    }

    public class FundingOpportunitySaveResult {
        @AuraEnabled public Id applicationFormId;
        @AuraEnabled public String applicationStatus;
    }

    @AuraEnabled(cacheable=true)
    public static FormDefinitionWrapper getFormDefinition(Id applicationFormId, Boolean eoiOnly) {
        try {
            requireId(applicationFormId, 'An Application Form Id is required.');
            ApplicationForm appForm = [
                SELECT Id, ReferenceRecordId, AccountId, ContactId, Stage, ProgrammeRattache__c, CreatedById
                FROM ApplicationForm
                WHERE Id = :applicationFormId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (appForm.ReferenceRecordId == null && appForm.ProgrammeRattache__c == null) {
                fail(ERROR_FORM_NOT_LINKED, 'This Application Form is not linked to a Funding Opportunity yet.');
            }
            return buildFormDefinition(appForm, eoiOnly == true);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to load the application form', e);
        }
    }

    @AuraEnabled
    public static FormDefinitionWrapper openFundingOpportunityForm(
        Id contextRecordId,
        Boolean isEoiChecked,
        Boolean isEoiAndFullApplicationChecked
    ) {
        try {
            requireId(
                contextRecordId,
                'A Funding Opportunity or Application Form Id is required.'
            );
            FormContext formContext = resolveFormContext(contextRecordId, false);
            Boolean isEoiAndFullApplication = resolveEoiAndFullApplication(
                formContext,
                isEoiChecked,
                isEoiAndFullApplicationChecked
            );
            Boolean isEoiOnly = isEoiOnlyMode(isEoiChecked, isEoiAndFullApplication);
            Boolean isFullApplicationOnly = isFullApplicationOnlyMode(isEoiChecked, isEoiAndFullApplication);

            String stage = formContext.applicationForm == null
                ? null
                : formContext.applicationForm.Stage;
            // Every stage renders the questions: a submitted or rejected EOI is reviewed in read-only (CRM,
            // colleague); the candidate gets the already-submitted message before reaching this point.
            Boolean isEoi = isEoiOnly
                || (!isFullApplicationOnly
                    && (formContext.applicationForm == null
                        || String.isBlank(stage)
                        || stage == 'EOI Draft'
                        || stage == 'EOI Submitted'
                        || stage == 'EOI Not Selected'));
            ApplicationForm appForm = formContext.applicationForm;
            if (appForm == null) {
                appForm = new ApplicationForm(
                    ReferenceRecordId = formContext.fundingOpportunityId,
                    ProgrammeRattache__c = formContext.fundingOpportunityId
                );
            }
            FormDefinitionWrapper result = buildFormDefinition(appForm, isEoi);
            result.isEoi = isEoi;
            result.isUnavailable = false;
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to open the Funding Opportunity application form', e);
        }
    }


    // Read-only display (CRM record page): the configuration of the component decides, never the stage. EOI
    // checked shows the EOI questions, otherwise the full application questions.
    @AuraEnabled
    public static FormDefinitionWrapper openReadOnlyForm(Id contextRecordId, Boolean isEoiChecked) {
        try {
            requireId(contextRecordId, 'A Funding Opportunity or Application Form Id is required.');
            FormContext formContext = resolveFormContext(contextRecordId, false);
            ApplicationForm appForm = formContext.applicationForm;
            if (appForm == null) {
                appForm = new ApplicationForm(
                    ReferenceRecordId = formContext.fundingOpportunityId,
                    ProgrammeRattache__c = formContext.fundingOpportunityId
                );
            }
            final Boolean isEoi = isEoiChecked == true;
            FormDefinitionWrapper result = buildFormDefinition(appForm, isEoi);
            result.isEoi = isEoi;
            result.isUnavailable = false;
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to open the application form in read-only', e);
        }
    }

    @AuraEnabled
    public static ApplicationFormSubmissionService.SubmissionCheckResult checkExistingSubmission(
        Id fundingOpportunityId,
        Boolean isEoiOnly
    ) {
        try {
            return ApplicationFormSubmissionService.checkExistingSubmission(fundingOpportunityId, isEoiOnly);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to check the existing submissions', e);
        }
    }

    // Primitive parameters rather than a request wrapper: the platform hands an empty instance to
    // the method when a Lightning component sends a custom Apex type, losing every value.
    // The two form text ids are the consents ticked by the candidate: only read on submission.
    @AuraEnabled
    public static FundingOpportunitySaveResult saveFundingOpportunityForm(
        String contextRecordId,
        String responsesJson,
        Boolean isSubmit,
        Boolean isEoiChecked,
        Boolean isEoiAndFullApplicationChecked,
        String termsAndConditionsFormTextId,
        String imageRightsFormTextId
    ) {
        try {
            Id parsedContextRecordId = parseId(
                contextRecordId,
                'A Funding Opportunity or Application Form Id is required.'
            );
            FormContext formContext = resolveFormContext(parsedContextRecordId, true);
            ensureUserCanEdit(formContext.applicationForm?.CreatedById);
            Boolean isEoiAndFullApplication = resolveEoiAndFullApplication(
                formContext,
                isEoiChecked,
                isEoiAndFullApplicationChecked
            );
            Boolean isEoiOnly = isEoiOnlyMode(isEoiChecked, isEoiAndFullApplication);
            Boolean isFullApplicationOnly = isFullApplicationOnlyMode(isEoiChecked, isEoiAndFullApplication);
            ensureFundingOpportunityIsEditable(formContext.fundingOpportunityId);
            ApplicationForm appForm = formContext.applicationForm;
            if (appForm != null && isLockedForEditStage(appForm.Stage)) {
                fail(
                    ERROR_ALREADY_SUBMITTED,
                    'This application has already been submitted and can no longer be modified.'
                );
            }
            // A submitted EOI cannot be modified, and the full application waits for its approval.
            if (appForm != null && appForm.Stage == 'EOI Submitted') {
                fail(
                    ERROR_ALREADY_SUBMITTED,
                    'This application has already been submitted and can no longer be modified.'
                );
            }
            ensureNoExistingSubmission(formContext.fundingOpportunityId, isEoiOnly);
            final List<AuthorizationFormText> consentedTexts = isSubmit == true
                ? requireConsentedTexts(
                      formContext.fundingOpportunityId,
                      termsAndConditionsFormTextId,
                      imageRightsFormTextId
                  )
                : null;
            final Id consentGiverId = isSubmit == true ? requireConsentGiverId() : null;

            Boolean isEoi = !isFullApplicationOnly
                && (appForm == null || String.isBlank(appForm.Stage)
                    || appForm.Stage == 'EOI Draft');
            String draftStage = isEoi ? 'EOI Draft' : 'Draft';
            String targetStage = isSubmit == true
                ? (isEoi ? 'EOI Submitted' : 'Submitted')
                : draftStage;

            if (appForm == null) {
                if (formContext.isApplicationFormContext) {
                    fail(ERROR_FORM_NOT_FOUND, 'The Application Form could not be found.');
                }
                ApplicationForm newForm = new ApplicationForm(
                    RecordTypeId = getCallForProjectsRecordTypeId(),
                    ReferenceRecordId = formContext.fundingOpportunityId,
                    ProgrammeRattache__c = formContext.fundingOpportunityId,
                    AccountId = ApplicationFormSubmissionService.getConnectedAccountId(),
                    ContactId = ApplicationFormSubmissionService.getConnectedContactId(),
                    UsageType = 'Grantmaking',
                    Stage = draftStage
                );
                appForm = newForm;
                Database.insert(appForm, AccessLevel.SYSTEM_MODE);
            }

            saveSectionResponses(
                appForm.Id,
                responsesJson,
                isSubmit == true
            );
            if (appForm.Stage != targetStage) {
                Database.update(
                    new ApplicationForm(Id = appForm.Id, Stage = targetStage),
                    AccessLevel.SYSTEM_MODE
                );
            }
            if (isSubmit == true) {
                ConsentService.insertConsents(
                    consentGiverId,
                    consentedTexts,
                    appForm.Id,
                    isEoi ? CONSENT_SOURCE_EOI : CONSENT_SOURCE_FULL_APPLICATION
                );
            }

            FundingOpportunitySaveResult result = new FundingOpportunitySaveResult();
            result.applicationFormId = appForm.Id;
            result.applicationStatus = targetStage;
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to save the Funding Opportunity application form', e);
        }
    }

    private static FormDefinitionWrapper buildFormDefinition(
        ApplicationForm appForm,
        Boolean isEoi
    ) {
        List<ApplicationFormCatalogueController.SectionWrapper> catalogSections =
            ApplicationFormCatalogueQueryService.getCatalogSections(appForm.ReferenceRecordId);

        Set<Id> questionIds = new Set<Id>();
        for (ApplicationFormCatalogueController.SectionWrapper section : catalogSections) {
            for (ApplicationFormCatalogueController.QuestionWrapper question : section.questions) {
                if ((question.isEOI == true) == isEoi) {
                    questionIds.add(question.questionId);
                }
            }
        }

        Map<Id, AssessmentQuestionVersion> versionsByQuestionId =
            ApplicationFormCatalogueQueryService.getFormVersionByQuestionId(questionIds);
        Map<Id, String> existingValuesByVersionId = appForm.Id == null
            ? new Map<Id, String>()
            : getExistingResponsesByVersionId(appForm.Id, versionsByQuestionId);
        Map<Id, String> fixedValuesByQuestionId =
            getFixedQuestionValues(appForm, catalogSections);
        final String formLanguage = FormLanguageService.getFormLanguage(appForm.ReferenceRecordId);
        final Boolean isFrench = formLanguage == FormLanguageService.LANGUAGE_FRENCH;

        List<SectionWrapper> sections = new List<SectionWrapper>();
        for (ApplicationFormCatalogueController.SectionWrapper section : catalogSections) {
            SectionWrapper sectionWrapper = new SectionWrapper();
            sectionWrapper.sectionId = section.sectionId;
            sectionWrapper.label = section.label;
            sectionWrapper.questions = new List<QuestionWrapper>();
            sectionWrapper.hasBudget = false;
            for (ApplicationFormCatalogueController.QuestionWrapper question : section.questions) {
                if ((question.isEOI == true) != isEoi) {
                    continue;
                }
                if (ApplicationFormBudgetController.isBudgetColumn(question.objectApiName, question.isFixed)) {
                    sectionWrapper.hasBudget = true;
                    continue;
                }
                AssessmentQuestionVersion version = versionsByQuestionId.get(question.questionId);
                if (version == null) {
                    continue;
                }
                QuestionWrapper questionWrapper = new QuestionWrapper();
                questionWrapper.questionId = question.questionId;
                questionWrapper.versionId = version.Id;
                questionWrapper.label = resolveQuestionLabel(question.label, version, isFrench);
                questionWrapper.dataType = question.dataType;
                questionWrapper.isTable = question.isTable;
                questionWrapper.helpText = version.HelpText;
                questionWrapper.maximumCharacters = question.maximumCharacters;
                questionWrapper.responseValues = version.ResponseValues;
                questionWrapper.isFixed = question.isFixed;
                questionWrapper.objectApiName = question.objectApiName;
                questionWrapper.fieldApiName = question.fieldApiName;
                questionWrapper.isMandatory = question.isMandatory != false;
                questionWrapper.isSchemaRequired = question.isFixed == true
                    && isFieldRequired(question.objectApiName, question.fieldApiName);
                if (question.isFixed == true
                        && isPicklistDataType(question.dataType)
                        && String.isBlank(questionWrapper.responseValues)) {
                    String dynamicPicklist = getPicklistResponseValues(
                        question.objectApiName,
                        question.fieldApiName
                    );
                    if (String.isNotBlank(dynamicPicklist)) {
                        questionWrapper.responseValues = dynamicPicklist;
                    }
                }
                if (questionWrapper.responseValues == version.ResponseValues) {
                    questionWrapper.responseLabels = resolveResponseLabels(version, isFrench);
                }
                questionWrapper.existingValueJson = question.isFixed == true
                    ? fixedValuesByQuestionId.get(question.questionId)
                    : existingValuesByVersionId.get(version.Id);
                if (question.isTable == true
                        && String.isNotBlank(version.AdditionalInformation)) {
                    questionWrapper.columns =
                        (List<ApplicationFormCatalogueController.ColumnWrapper>) JSON.deserialize(
                            version.AdditionalInformation,
                            List<ApplicationFormCatalogueController.ColumnWrapper>.class
                        );
                }
                sectionWrapper.questions.add(questionWrapper);
            }
            if (!sectionWrapper.questions.isEmpty() || sectionWrapper.hasBudget) {
                sections.add(sectionWrapper);
            }
        }

        FormDefinitionWrapper result = new FormDefinitionWrapper();
        result.sections = sections;
        result.applicationFormId = appForm.Id;
        result.fundingOpportunityId = appForm.ReferenceRecordId;
        result.applicationStatus = appForm.Stage;
        result.isEoi = isEoi;
        result.isUnavailable = false;
        result.isFundingOpportunityLocked = isFundingOpportunityLocked(appForm.ReferenceRecordId);
        result.formLanguage = formLanguage;
        result.isEditAllowed =
            ApplicationFormSubmissionService.canConnectedUserEditApplicationForm(appForm.CreatedById);
        if (!result.isEditAllowed) {
            result.creatorName = new CreatorNameReader().readName(appForm.CreatedById);
        }
        result.consents = buildConsents(formLanguage);
        return result;
    }

    // The labels and documents follow the language of the form, not the user's: a Science form stays in English.
    @TestVisible
    private static ConsentsWrapper buildConsents(String formLanguage) {
        final String labelLanguage = formLanguage == FormLanguageService.LANGUAGE_FRENCH
            ? LABEL_LANGUAGE_FRENCH
            : LABEL_LANGUAGE_ENGLISH;
        final ConsentsWrapper consents = new ConsentsWrapper();
        consents.prefix = System.Label.get('', 'ApplicationFormConsentPrefix', labelLanguage);
        consents.errorMessage = System.Label.get('', 'ApplicationFormErrorConsentsNotAccepted', labelLanguage);
        consents.termsAndConditions = buildConsent(
            ConsentService.TERMS_AND_CONDITIONS_FORM_NAME,
            formLanguage,
            System.Label.get('', 'ApplicationFormConsentTermsAndConditionsLink', labelLanguage)
        );
        consents.imageRights = buildConsent(
            ConsentService.IMAGE_RIGHTS_FORM_NAME,
            formLanguage,
            System.Label.get('', 'ApplicationFormConsentImageRightsLink', labelLanguage)
        );
        return consents;
    }

    private static ConsentWrapper buildConsent(String formName, String formLanguage, String linkLabel) {
        final ConsentService.ConsentDocument document = ConsentService.getActiveDocument(formName, formLanguage);
        final ConsentWrapper consent = new ConsentWrapper();
        consent.formTextId = document?.formTextId;
        consent.url = document?.url;
        consent.linkLabel = linkLabel;
        return consent;
    }

    // Both documents must be accepted. A Science form is in English only: only the English texts are consented
    // to; every other pillar records the English and French versions.
    private static List<AuthorizationFormText> requireConsentedTexts(
        Id fundingOpportunityId,
        String termsAndConditionsFormTextId,
        String imageRightsFormTextId
    ) {
        final Boolean isEnglishOnly = !FormLanguageService.isTranslationExpected(fundingOpportunityId);
        final List<AuthorizationFormText> consentedTexts = new List<AuthorizationFormText>();
        try {
            consentedTexts.addAll(
                ConsentService.requireActiveTexts(
                    ConsentService.TERMS_AND_CONDITIONS_FORM_NAME,
                    toIdOrNull(termsAndConditionsFormTextId),
                    isEnglishOnly
                )
            );
            consentedTexts.addAll(
                ConsentService.requireActiveTexts(
                    ConsentService.IMAGE_RIGHTS_FORM_NAME,
                    toIdOrNull(imageRightsFormTextId),
                    isEnglishOnly
                )
            );
        } catch (ConsentService.ConsentException e) {
            fail(ERROR_CONSENTS_NOT_ACCEPTED, 'The ' + e.getMessage() + ' must be accepted before submitting.');
        }
        return consentedTexts;
    }

    // The consent is given by the person who submits: a user without Contact cannot submit.
    private static Id requireConsentGiverId() {
        final Id contactId = ApplicationFormSubmissionService.getConnectedContactId();
        if (contactId == null) {
            fail(ERROR_CONSENTS_NOT_ACCEPTED, 'The connected user has no Contact to record the consents.');
        }
        return contactId;
    }

    private static Id toIdOrNull(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value);
        } catch (StringException e) {
            return null;
        }
    }

    // In French, the French text of the version, or the English label when it is not filled in.
    @TestVisible
    private static String resolveQuestionLabel(
        String englishLabel,
        AssessmentQuestionVersion version,
        Boolean isFrench
    ) {
        return isFrench && String.isNotBlank(version.QuestionTextFR__c) ? version.QuestionTextFR__c : englishLabel;
    }

    // In French, the French response values when they match the English ones one to one: the answer saved
    // is the English value at the same position. Otherwise null, and the English values are shown.
    @TestVisible
    private static String resolveResponseLabels(AssessmentQuestionVersion version, Boolean isFrench) {
        if (!isFrench || String.isBlank(version.ResponseValuesFR__c)) {
            return null;
        }
        final Boolean isSameCount =
            splitResponseValues(version.ResponseValuesFR__c).size() == splitResponseValues(version.ResponseValues).size();
        return isSameCount ? version.ResponseValuesFR__c : null;
    }

    // Same split as the form: one value per line, blank lines ignored.
    private static List<String> splitResponseValues(String responseValues) {
        final List<String> values = new List<String>();
        for (String line : (responseValues == null ? '' : responseValues).split('\\r?\\n')) {
            if (String.isNotBlank(line)) {
                values.add(line.trim());
            }
        }
        return values;
    }

    private static Boolean isFundingOpportunityLocked(Id fundingOpportunityId) {
        if (fundingOpportunityId == null) {
            return false;
        }
        final List<FundingOpportunity> fundingOpportunities = [
            SELECT
                Status
            FROM
                FundingOpportunity
            WHERE
                Id = :fundingOpportunityId
            WITH
                USER_MODE
            LIMIT
                1
        ];
        return !fundingOpportunities.isEmpty()
            && fundingOpportunities[0].Status != null
            && !EDITABLE_FUNDING_OPPORTUNITY_STATUSES.contains(fundingOpportunities[0].Status);
    }

    private static Boolean resolveEoiAndFullApplication(
        FormContext formContext,
        Boolean isEoiChecked,
        Boolean isEoiAndFullApplicationChecked
    ) {
        if (isFullApplicationOnlyMode(isEoiChecked, isEoiAndFullApplicationChecked)) {
            return isCallForProjectsFundingOpportunity(formContext.fundingOpportunityId);
        }
        return isEoiAndFullApplicationChecked;
    }

    private static Boolean isCallForProjectsFundingOpportunity(Id fundingOpportunityId) {
        if (fundingOpportunityId == null) {
            return false;
        }
        final List<FundingOpportunity> fundingOpportunities = [
            SELECT
                RecordType.DeveloperName
            FROM
                FundingOpportunity
            WHERE
                Id = :fundingOpportunityId
            WITH
                USER_MODE
            LIMIT
                1
        ];
        return !fundingOpportunities.isEmpty()
            && fundingOpportunities[0].RecordType.DeveloperName == CALL_FOR_PROJECTS_RECORD_TYPE;
    }

    private static void ensureFundingOpportunityIsEditable(Id fundingOpportunityId) {
        if (isFundingOpportunityLocked(fundingOpportunityId)) {
            fail(
                ERROR_FUNDING_OPPORTUNITY_LOCKED,
                'This Funding Opportunity no longer accepts modifications of its application form.'
            );
        }
    }

    private static void ensureUserCanEdit(Id creatorId) {
        if (!ApplicationFormSubmissionService.canConnectedUserEditApplicationForm(creatorId)) {
            fail(ERROR_EDIT_NOT_ALLOWED, 'Only the contact who created this form can edit it.');
        }
    }

    private static void ensureNoExistingSubmission(Id fundingOpportunityId, Boolean isEoiOnly) {
        final ApplicationFormSubmissionService.SubmissionCheckResult check =
            ApplicationFormSubmissionService.checkExistingSubmission(fundingOpportunityId, isEoiOnly);
        if (check.status != ApplicationFormSubmissionService.STATUS_ALREADY_SUBMITTED) {
            return;
        }
        // An error cannot carry a link: the link marker is replaced by the name of the Application Form.
        final String programName = String.isBlank(check.programName) ? '' : check.programName;
        final String applicationFormName = String.isBlank(check.applicationFormName)
            ? ''
            : check.applicationFormName;
        failWithMessage(
            Label.ApplicationFormAlreadySubmittedMessage
                .replace('{ProgramName}', programName)
                .replace('{ApplicationFormLink}', applicationFormName)
        );
    }

    // The budget tables are saved apart from the answers, with the same guards as the save of the form.
    public static void ensureCanEditApplicationForm(Id applicationFormId) {
        requireId(applicationFormId, 'An Application Form Id is required.');
        final List<ApplicationForm> applicationForms = [
            SELECT
                ReferenceRecordId,
                Stage,
                CreatedById
            FROM
                ApplicationForm
            WHERE
                Id = :applicationFormId
            WITH
                SYSTEM_MODE
            LIMIT
                1
        ];
        if (applicationForms.isEmpty()) {
            fail(ERROR_FORM_NOT_FOUND, 'The Application Form could not be found.');
        }
        ensureUserCanEdit(applicationForms[0].CreatedById);
        ensureFundingOpportunityIsEditable(applicationForms[0].ReferenceRecordId);
        if (isLockedForEditStage(applicationForms[0].Stage) || applicationForms[0].Stage == 'EOI Submitted') {
            fail(
                ERROR_ALREADY_SUBMITTED,
                'This application has already been submitted and can no longer be modified.'
            );
        }
    }

    private static void ensureApplicationFormIsEditable(Id applicationFormId) {
        final List<ApplicationForm> applicationForms = [
            SELECT
                ReferenceRecordId,
                CreatedById
            FROM
                ApplicationForm
            WHERE
                Id = :applicationFormId
            WITH
                USER_MODE
            LIMIT
                1
        ];
        if (!applicationForms.isEmpty()) {
            ensureUserCanEdit(applicationForms[0].CreatedById);
            ensureFundingOpportunityIsEditable(applicationForms[0].ReferenceRecordId);
        }
    }

    private class FormContext {
        Id fundingOpportunityId;
        ApplicationForm applicationForm;
        Boolean isApplicationFormContext;
    }

    private static FormContext resolveFormContext(Id contextRecordId, Boolean isForUpdate) {
        FormContext formContext = new FormContext();
        Schema.SObjectType contextType = contextRecordId.getSObjectType();
        if (contextType == ApplicationForm.SObjectType) {
            formContext.isApplicationFormContext = true;
            formContext.applicationForm = findApplicationFormById(contextRecordId, isForUpdate);
            if (formContext.applicationForm == null) {
                fail(ERROR_FORM_NOT_FOUND, 'The Application Form could not be found.');
            }
            if (formContext.applicationForm.ReferenceRecordId == null) {
                fail(ERROR_FORM_NOT_LINKED, 'This Application Form is not linked to a Funding Opportunity yet.');
            }
            formContext.fundingOpportunityId = formContext.applicationForm.ReferenceRecordId;
            return formContext;
        }
        if (contextType != FundingOpportunity.SObjectType) {
            fail(ERROR_ID_REQUIRED, 'A Funding Opportunity or Application Form Id is required.');
        }

        formContext.isApplicationFormContext = false;
        formContext.fundingOpportunityId = contextRecordId;
        if (isForUpdate == true) {
            List<FundingOpportunity> lockedFundingOpportunities = [
                SELECT Id
                FROM FundingOpportunity
                WHERE Id = :contextRecordId
                WITH USER_MODE
                LIMIT 1
                FOR UPDATE
            ];
            if (lockedFundingOpportunities.isEmpty()) {
                fail(ERROR_FUNDING_OPPORTUNITY_NOT_FOUND, 'The Funding Opportunity could not be found.');
            }
        }
        formContext.applicationForm = null;
        return formContext;
    }

    private static ApplicationForm findApplicationFormById(
        Id applicationFormId,
        Boolean isForUpdate
    ) {
        if (isForUpdate == true) {
            List<ApplicationForm> lockedApplicationForms = [
                SELECT Id, ReferenceRecordId, AccountId, ContactId, Stage, CreatedById
                FROM ApplicationForm
                WHERE Id = :applicationFormId
                WITH SYSTEM_MODE
                LIMIT 1
                FOR UPDATE
            ];
            return lockedApplicationForms.isEmpty() ? null : lockedApplicationForms[0];
        }

        List<ApplicationForm> applicationForms = [
            SELECT Id, ReferenceRecordId, AccountId, ContactId, Stage, CreatedById
            FROM ApplicationForm
            WHERE Id = :applicationFormId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return applicationForms.isEmpty() ? null : applicationForms[0];
    }

    // The two App Builder checkboxes resolve into three journeys: the combined one wins when both
    // are checked, EOI alone stops once the EOI is submitted, and neither opens the full
    // application straight away.
    private static Boolean isEoiOnlyMode(
        Boolean isEoiChecked,
        Boolean isEoiAndFullApplicationChecked
    ) {
        return isEoiAndFullApplicationChecked != true && isEoiChecked == true;
    }

    private static Boolean isFullApplicationOnlyMode(
        Boolean isEoiChecked,
        Boolean isEoiAndFullApplicationChecked
    ) {
        return isEoiAndFullApplicationChecked != true && isEoiChecked != true;
    }

    // Stages past final submission: the form stays visible in read-only, but saves are blocked.
    private static Boolean isLockedForEditStage(String stage) {
        return stage == 'Submitted'
            || stage == 'Under Evaluation'
            || stage == 'Approved'
            || stage == 'Rejected'
            || stage == 'Canceled'
            || stage == 'Signed'
            || stage == 'Closed'
            || stage == 'EOI Not Selected';
    }

    public class UploadedFileWrapper {
        @AuraEnabled public String documentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String name;
    }

    // Names the files sent with the standard file upload after the question label.
    @AuraEnabled
    public static List<UploadedFileWrapper> renameUploadedFiles(
        List<Id> contentDocumentIds,
        String fieldLabel,
        List<String> existingTitles
    ) {
        try {
            final List<UploadedFileWrapper> wrappers = new List<UploadedFileWrapper>();
            for (FileUploadService.UploadedFileWrapper result :
                FileUploadService.renameUploadedFiles(contentDocumentIds, fieldLabel, existingTitles)) {
                final UploadedFileWrapper wrapper = new UploadedFileWrapper();
                wrapper.documentId = result.documentId;
                wrapper.title = result.title;
                wrapper.fileExtension = result.fileExtension;
                wrapper.name = result.name;
                wrappers.add(wrapper);
            }
            return wrappers;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to rename the files', e);
        }
    }

    // Attaches the files uploaded for the answers to the Application Form, when it is saved.
    @AuraEnabled
    public static void linkUploadedFiles(Id applicationFormId, List<Id> contentDocumentIds) {
        try {
            ensureApplicationFormIsEditable(applicationFormId);
            FileUploadService.linkFilesToRecord(applicationFormId, contentDocumentIds);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to attach the files to the application form', e);
        }
    }

    @AuraEnabled
    public static void deleteUploadedFile(Id contentDocumentId) {
        try {
            FileUploadService.deleteUploadedFile(contentDocumentId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to delete the file', e);
        }
    }

    @AuraEnabled
    public static void updateApplicationStatus(Id applicationFormId, String status) {
        try {
            requireId(applicationFormId, 'An Application Form Id is required.');
            if (String.isBlank(status)) {
                fail(ERROR_STATUS_REQUIRED, 'A status is required.');
            }
            Database.update(
                new ApplicationForm(Id = applicationFormId, Stage = status),
                AccessLevel.USER_MODE
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to update the application status', e);
        }
    }

    @TestVisible
    private static void saveSectionResponses(Id applicationFormId, String responsesJson, Boolean isRequiredEnforced) {
        try {
            requireId(applicationFormId, 'An Application Form Id is required.');
            if (String.isBlank(responsesJson)) {
                return;
            }

            List<ResponseInputWrapper> allInputs = (List<ResponseInputWrapper>) JSON.deserialize(
                responsesJson,
                List<ResponseInputWrapper>.class
            );
            if (allInputs == null || allInputs.isEmpty()) {
                return;
            }

            validateMaximumCharacters(allInputs);

            if (isRequiredEnforced == true) {
                for (ResponseInputWrapper input : allInputs) {
                    if (input.isMandatory == true && isBlankValue(input.valueJson)) {
                        fail(
                            ERROR_QUESTION_REQUIRED,
                            new List<String>{ input.label },
                            '"' + (String.isNotBlank(input.label) ? input.label : 'This question') + '" is required.'
                        );
                    }
                }
            }

            List<ResponseInputWrapper> inputs = new List<ResponseInputWrapper>();
            List<ResponseInputWrapper> fixedInputs = new List<ResponseInputWrapper>();
            for (ResponseInputWrapper input : allInputs) {
                if (input.isFixed == true) {
                    fixedInputs.add(input);
                } else {
                    inputs.add(input);
                }
            }
            if (!fixedInputs.isEmpty()) {
                saveFixedQuestionValues(applicationFormId, fixedInputs);
            }
            if (inputs.isEmpty()) {
                return;
            }

            Id assessmentId = getOrCreateAssessment(applicationFormId);

            Set<Id> versionIds = new Set<Id>();
            for (ResponseInputWrapper input : inputs) {
                if (String.isNotBlank(input.versionId)) {
                    versionIds.add((Id) input.versionId);
                }
            }

            Map<Id, AssessmentQuestionResponse> existingByVersionId = new Map<Id, AssessmentQuestionResponse>();
            for (AssessmentQuestionResponse response : [
                SELECT Id, AssessmentQuestionId
                FROM AssessmentQuestionResponse
                WHERE AssessmentId = :assessmentId AND AssessmentQuestionId IN :versionIds
                WITH SYSTEM_MODE
            ]) {
                existingByVersionId.put(response.AssessmentQuestionId, response);
            }

            List<AssessmentQuestionResponse> toInsert = new List<AssessmentQuestionResponse>();
            List<AssessmentQuestionResponse> toUpdate = new List<AssessmentQuestionResponse>();

            for (ResponseInputWrapper input : inputs) {
                if (String.isBlank(input.versionId)) {
                    continue;
                }
                Id versionId = (Id) input.versionId;
                AssessmentQuestionResponse existing = existingByVersionId.get(versionId);
                if (existing != null) {
                    existing.ResponseText = input.valueJson;
                    toUpdate.add(existing);
                } else {
                    toInsert.add(new AssessmentQuestionResponse(
                        Name = ('Response ' + versionId).left(80),
                        AssessmentId = assessmentId,
                        AssessmentQuestionId = versionId,
                        ProjetRattache__c = applicationFormId,
                        ResponseText = input.valueJson
                    ));
                }
            }

            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, AccessLevel.SYSTEM_MODE);
            }
            if (!toUpdate.isEmpty()) {
                Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException('Unable to save your responses', e);
        }
    }

    private static Boolean isBlankValue(String valueJson) {
        if (String.isBlank(valueJson)) {
            return true;
        }
        String trimmed = valueJson.trim();
        return trimmed == '[]' || trimmed == 'null' || trimmed == '""';
    }

    private static void validateMaximumCharacters(List<ResponseInputWrapper> inputs) {
        Set<Id> versionIds = new Set<Id>();
        for (ResponseInputWrapper input : inputs) {
            if (String.isNotBlank(input.versionId)) {
                versionIds.add((Id) input.versionId);
            }
        }
        if (versionIds.isEmpty()) {
            return;
        }

        Map<Id, AssessmentQuestionVersion> versionsById =
            ApplicationFormCatalogueQueryService.getAnsweredVersionById(versionIds);

        for (ResponseInputWrapper input : inputs) {
            if (String.isBlank(input.versionId) || input.valueJson == null) {
                continue;
            }
            AssessmentQuestionVersion version = versionsById.get((Id) input.versionId);
            if (version == null || !supportsMaximumCharacters(version.AssessmentQuestion.DataType)) {
                continue;
            }
            Decimal maximumCharacters = version.AssessmentQuestion.MaximumCharacters__c;
            if (maximumCharacters != null && input.valueJson.length() > maximumCharacters.intValue()) {
                String label = String.isNotBlank(version.QuestionText) ? version.QuestionText : 'This question';
                fail(
                    ERROR_MAXIMUM_CHARACTERS,
                    new List<String>{ label, String.valueOf(maximumCharacters.intValue()) },
                    '"' + label + '" cannot exceed ' + maximumCharacters.intValue() + ' characters.'
                );
            }
        }
    }

    private static Boolean supportsMaximumCharacters(String dataType) {
        return dataType == 'Text' || dataType == 'TextArea' || dataType == 'Email' ||
            dataType == 'Telephone' || dataType == 'URL';
    }

    private static Id getOrCreateAssessment(Id applicationFormId) {
        List<Assessment> existing = [
            SELECT Id
            FROM Assessment
            WHERE ResponseContextId = :applicationFormId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        Assessment newAssessment = new Assessment(
            Name = ('Assessment ' + applicationFormId).left(80),
            AssessmentStatus = 'In Progress',
            ResponseContextId = applicationFormId,
            AccountId = getApplicationFormAccountId(applicationFormId)
        );
        Database.insert(newAssessment, AccessLevel.SYSTEM_MODE);
        return newAssessment.Id;
    }

    // The Account drives the portal Sharing Set of the Assessment.
    private static Id getApplicationFormAccountId(Id applicationFormId) {
        List<ApplicationForm> applicationForms = [
            SELECT AccountId
            FROM ApplicationForm
            WHERE Id = :applicationFormId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return applicationForms.isEmpty() ? null : applicationForms[0].AccountId;
    }

    // One version per question, whether or not it is active, so Draft questions still render.
    private static Map<Id, String> getExistingResponsesByVersionId(Id applicationFormId, Map<Id, AssessmentQuestionVersion> versionByQuestionId) {
        Map<Id, String> result = new Map<Id, String>();
        List<Assessment> assessments = [
            SELECT Id
            FROM Assessment
            WHERE ResponseContextId = :applicationFormId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (assessments.isEmpty() || versionByQuestionId.isEmpty()) {
            return result;
        }

        Set<Id> versionIds = new Set<Id>();
        for (AssessmentQuestionVersion version : versionByQuestionId.values()) {
            versionIds.add(version.Id);
        }

        for (AssessmentQuestionResponse response : [
            SELECT AssessmentQuestionId, ResponseText
            FROM AssessmentQuestionResponse
            WHERE AssessmentId = :assessments[0].Id AND AssessmentQuestionId IN :versionIds
            WITH SYSTEM_MODE
        ]) {
            result.put(response.AssessmentQuestionId, response.ResponseText);
        }
        return result;
    }

    // Fixed Object / Field API Names are free: every named object is upserted and prefilled.
    // Application Form → the current form. Objects with an AF lookup → create/link then update.
    // Objects without an AF lookup → create/update independently; their Ids are kept on the
    // related Assessment so later opens (including read-only) can still prefill.
    private static final String FIXED_TARGET_MARKER_START = '[[AXA_FIXED_TARGETS:';
    private static final String FIXED_TARGET_MARKER_END = ']]';

    private static Map<String, Id> targetRecordIdByObjectApiName(
        ApplicationForm appForm,
        Set<String> objectApiNames,
        Map<String, Id> independentTargetIdByObjectApiName
    ) {
        Map<String, Id> targetIdByObjectApiName = new Map<String, Id>();
        if (appForm == null || objectApiNames == null || objectApiNames.isEmpty()) {
            return targetIdByObjectApiName;
        }
        if (objectApiNames.contains(APPLICATION_FORM_API_NAME) && appForm.Id != null) {
            targetIdByObjectApiName.put(APPLICATION_FORM_API_NAME, appForm.Id);
        }
        Map<String, String> lookupFieldByObjectApiName = findLookupFieldsOnApplicationForm(
            objectApiNames
        );
        for (String objectApiName : lookupFieldByObjectApiName.keySet()) {
            Id linkedId = (Id) appForm.get(lookupFieldByObjectApiName.get(objectApiName));
            if (linkedId != null) {
                targetIdByObjectApiName.put(objectApiName, linkedId);
            }
        }
        if (independentTargetIdByObjectApiName != null) {
            for (String objectApiName : objectApiNames) {
                if (targetIdByObjectApiName.containsKey(objectApiName)) {
                    continue;
                }
                Id storedId = independentTargetIdByObjectApiName.get(objectApiName);
                if (storedId != null) {
                    targetIdByObjectApiName.put(objectApiName, storedId);
                }
            }
        }
        return targetIdByObjectApiName;
    }

    // Optional: returns the AF lookup for a Fixed object when one exists (prefers <Object>Id).
    private static Map<String, String> findLookupFieldsOnApplicationForm(Set<String> objectApiNames) {
        Map<String, String> lookupFieldByObjectApiName = new Map<String, String>();
        if (objectApiNames == null || objectApiNames.isEmpty()) {
            return lookupFieldByObjectApiName;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Map<String, Schema.SObjectField> applicationFormFields =
            ApplicationForm.SObjectType.getDescribe().fields.getMap();

        for (String objectApiName : objectApiNames) {
            if (objectApiName == APPLICATION_FORM_API_NAME || String.isBlank(objectApiName)) {
                continue;
            }
            Schema.SObjectType targetType = globalDescribe.get(objectApiName);
            if (targetType == null) {
                fail(ERROR_TECHNICAL, 'The object "' + objectApiName + '" does not exist.');
            }

            String preferredFieldName = objectApiName + 'Id';
            String chosenFieldName = null;
            for (Schema.SObjectField field : applicationFormFields.values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if (fieldDescribe.getType() != Schema.DisplayType.REFERENCE) {
                    continue;
                }
                List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
                if (referenceTo.size() != 1 || referenceTo[0] != targetType) {
                    continue;
                }
                if (!fieldDescribe.isUpdateable()) {
                    continue;
                }
                String fieldName = fieldDescribe.getName();
                if (chosenFieldName == null || fieldName == preferredFieldName) {
                    chosenFieldName = fieldName;
                }
            }
            if (chosenFieldName != null) {
                lookupFieldByObjectApiName.put(objectApiName, chosenFieldName);
            }
        }
        return lookupFieldByObjectApiName;
    }

    private static ApplicationForm queryApplicationFormWithLookupFields(
        Id applicationFormId,
        Set<String> objectApiNames
    ) {
        Map<String, String> lookupFieldByObjectApiName = findLookupFieldsOnApplicationForm(
            objectApiNames
        );
        Set<String> selectFields = new Set<String>{ 'Id', 'Name' };
        selectFields.addAll(lookupFieldByObjectApiName.values());
        String soql =
            'SELECT '
            + String.join(new List<String>(selectFields), ', ')
            + ' FROM ApplicationForm WHERE Id = :applicationFormId WITH USER_MODE LIMIT 1';
        List<ApplicationForm> forms = Database.query(soql);
        if (forms.isEmpty()) {
            fail(ERROR_FORM_NOT_FOUND, 'The Application Form could not be found.');
        }
        return forms[0];
    }

    // Ids of Fixed targets that have no Application Form lookup. Stored on Assessment.Identifier
    // (accessed dynamically — not all Assessment text fields are visible in static SOQL).
    private static final String ASSESSMENT_FIXED_TARGET_FIELD = 'Iden' + 'tifier';

    private static Map<String, Id> loadIndependentFixedTargetIds(Id applicationFormId) {
        Map<String, Id> targetIdByObjectApiName = new Map<String, Id>();
        String storageField = ASSESSMENT_FIXED_TARGET_FIELD;
        List<SObject> assessments = Database.query(
            'SELECT Id, '
            + storageField
            + ' FROM Assessment WHERE ResponseContextId = :applicationFormId WITH SYSTEM_MODE LIMIT 1'
        );
        if (assessments.isEmpty()) {
            return targetIdByObjectApiName;
        }
        String stored = (String) assessments[0].get(storageField);
        if (String.isBlank(stored)) {
            return targetIdByObjectApiName;
        }
        Integer startIndex = stored.indexOf(FIXED_TARGET_MARKER_START);
        Integer endIndex = stored.indexOf(FIXED_TARGET_MARKER_END);
        if (startIndex < 0 || endIndex <= startIndex) {
            return targetIdByObjectApiName;
        }
        String jsonMap = stored.substring(
            startIndex + FIXED_TARGET_MARKER_START.length(),
            endIndex
        );
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(jsonMap);
            for (String objectApiName : raw.keySet()) {
                Object value = raw.get(objectApiName);
                if (value != null && String.isNotBlank(String.valueOf(value))) {
                    targetIdByObjectApiName.put(objectApiName, (Id) String.valueOf(value));
                }
            }
        } catch (Exception e) {
            // Corrupt marker: treat as empty so a later save can rewrite it.
        }
        return targetIdByObjectApiName;
    }

    private static void saveIndependentFixedTargetIds(
        Id applicationFormId,
        Map<String, Id> independentTargetIdByObjectApiName
    ) {
        if (independentTargetIdByObjectApiName == null || independentTargetIdByObjectApiName.isEmpty()) {
            return;
        }
        Id assessmentId = getOrCreateAssessment(applicationFormId);
        String storageField = ASSESSMENT_FIXED_TARGET_FIELD;
        List<SObject> assessments = Database.query(
            'SELECT Id, '
            + storageField
            + ' FROM Assessment WHERE Id = :assessmentId WITH SYSTEM_MODE LIMIT 1'
        );
        if (assessments.isEmpty()) {
            return;
        }
        Map<String, Id> merged = loadIndependentFixedTargetIds(applicationFormId);
        merged.putAll(independentTargetIdByObjectApiName);

        Map<String, String> serializable = new Map<String, String>();
        for (String objectApiName : merged.keySet()) {
            serializable.put(objectApiName, String.valueOf(merged.get(objectApiName)));
        }
        String marker =
            FIXED_TARGET_MARKER_START
            + JSON.serialize(serializable)
            + FIXED_TARGET_MARKER_END;

        String stored = (String) assessments[0].get(storageField);
        if (String.isBlank(stored)) {
            stored = marker;
        } else {
            Integer startIndex = stored.indexOf(FIXED_TARGET_MARKER_START);
            Integer endIndex = stored.indexOf(FIXED_TARGET_MARKER_END);
            if (startIndex >= 0 && endIndex > startIndex) {
                stored =
                    stored.substring(0, startIndex)
                    + marker
                    + stored.substring(endIndex + FIXED_TARGET_MARKER_END.length());
            } else {
                stored = marker;
            }
        }
        if (stored.length() > 255) {
            fail(ERROR_TECHNICAL, 'Too many independent Fixed objects to remember for prefill on this application.');
        }
        SObject toUpdate = new Assessment(Id = assessments[0].Id);
        toUpdate.put(storageField, stored);
        Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
    }

    private static Boolean needsIndependentFixedTargetStorage(
        Set<String> objectApiNames,
        Map<String, String> lookupFieldByObjectApiName
    ) {
        for (String objectApiName : objectApiNames) {
            if (objectApiName == APPLICATION_FORM_API_NAME || String.isBlank(objectApiName)) {
                continue;
            }
            if (!lookupFieldByObjectApiName.containsKey(objectApiName)) {
                return true;
            }
        }
        return false;
    }

    // A form without a Contact yet takes the Contact of the connected user as its Contact target, so the answers
    // update that Contact instead of creating a new one. An internal user has no Contact: nothing is added.
    private static void addConnectedContactTarget(Map<String, Id> targetIdByObjectApiName, Set<String> objectApiNames) {
        if (!objectApiNames.contains(CONTACT_API_NAME) || targetIdByObjectApiName.containsKey(CONTACT_API_NAME)) {
            return;
        }
        final Id connectedContactId = ApplicationFormSubmissionService.getConnectedContactId();
        if (connectedContactId != null) {
            targetIdByObjectApiName.put(CONTACT_API_NAME, connectedContactId);
        }
    }

    private static Map<Id, String> getFixedQuestionValues(ApplicationForm appForm, List<ApplicationFormCatalogueController.SectionWrapper> catalogSections) {
        Map<Id, String> valueByQuestionId = new Map<Id, String>();
        Set<String> objectApiNames = new Set<String>();
        Map<String, Set<String>> fieldNamesByObjectApiName = new Map<String, Set<String>>();
        // SOQL field names are case-insensitive, so dedup on the lowercase form to avoid
        // "duplicate field selected" when two Fixed questions map to the same field with
        // different casing (e.g. BirthDate vs Birthdate).
        Map<String, Set<String>> seenLowerFieldNamesByObjectApiName = new Map<String, Set<String>>();
        Map<String, List<ApplicationFormCatalogueController.QuestionWrapper>> fixedQuestionsByObjectApiName =
            new Map<String, List<ApplicationFormCatalogueController.QuestionWrapper>>();

        for (ApplicationFormCatalogueController.SectionWrapper section : catalogSections) {
            for (ApplicationFormCatalogueController.QuestionWrapper question : section.questions) {
                if (question.isFixed != true || String.isBlank(question.objectApiName) || String.isBlank(question.fieldApiName)) {
                    continue;
                }
                objectApiNames.add(question.objectApiName);
                if (!fieldNamesByObjectApiName.containsKey(question.objectApiName)) {
                    fieldNamesByObjectApiName.put(question.objectApiName, new Set<String>());
                    seenLowerFieldNamesByObjectApiName.put(question.objectApiName, new Set<String>());
                    fixedQuestionsByObjectApiName.put(
                        question.objectApiName,
                        new List<ApplicationFormCatalogueController.QuestionWrapper>()
                    );
                }
                Set<String> seenLowerFieldNames = seenLowerFieldNamesByObjectApiName.get(question.objectApiName);
                String lowerFieldName = question.fieldApiName.toLowerCase();
                if (!seenLowerFieldNames.contains(lowerFieldName)) {
                    seenLowerFieldNames.add(lowerFieldName);
                    fieldNamesByObjectApiName.get(question.objectApiName).add(question.fieldApiName);
                }
                fixedQuestionsByObjectApiName.get(question.objectApiName).add(question);
            }
        }
        if (objectApiNames.isEmpty()) {
            return valueByQuestionId;
        }

        // The Contact of the connected user is the Contact target of its forms: it is prefilled with the user's own
        // information, even before the first save. The other Fixed targets (Account, Budget, ...) are prefilled only
        // from the record linked on this specific Application Form; the first open on a Funding Opportunity builds an
        // in-memory form with no Id yet, so there is nothing to prefill for them until the first draft save.
        Map<String, Id> targetIdByObjectApiName = new Map<String, Id>();
        if (appForm != null && appForm.Id != null) {
            ApplicationForm formWithLookups = queryApplicationFormWithLookupFields(
                appForm.Id,
                objectApiNames
            );
            Map<String, String> lookupFieldByObjectApiName = findLookupFieldsOnApplicationForm(
                objectApiNames
            );
            Map<String, Id> independentTargetIdByObjectApiName =
                needsIndependentFixedTargetStorage(objectApiNames, lookupFieldByObjectApiName)
                    ? loadIndependentFixedTargetIds(appForm.Id)
                    : new Map<String, Id>();
            targetIdByObjectApiName = targetRecordIdByObjectApiName(
                formWithLookups,
                objectApiNames,
                independentTargetIdByObjectApiName
            );
        }
        // Only a form not saved yet takes the Contact of the user: a saved form shows the Contact linked on it (the
        // read-only view of a colleague or of the CRM must not show the information of whoever opens it).
        if (appForm == null || appForm.Id == null) {
            addConnectedContactTarget(targetIdByObjectApiName, objectApiNames);
        }
        if (targetIdByObjectApiName.isEmpty()) {
            return valueByQuestionId;
        }

        for (String objectApiName : fieldNamesByObjectApiName.keySet()) {
            Id targetId = targetIdByObjectApiName.get(objectApiName);
            if (targetId == null) {
                continue;
            }
            String fieldList = String.join(new List<String>(fieldNamesByObjectApiName.get(objectApiName)), ', ');
            List<SObject> results = new FixedTargetReader().readTarget(objectApiName, fieldList, targetId);
            if (results.isEmpty()) {
                continue;
            }
            SObject record = results[0];
            populateFixedValuesFromRecord(record, fixedQuestionsByObjectApiName.get(objectApiName), valueByQuestionId);
        }
        return valueByQuestionId;
    }

    // WITH SYSTEM_MODE still applies the sharing of this with sharing class: a Fixed target linked on a form
    // the user can read (checked in user mode above), such as the candidate Contact of a colleague, may be
    // private to its owner. It is read without sharing, by its Id only.
    private without sharing class FixedTargetReader {
        private List<SObject> readTarget(String objectApiName, String fieldList, Id targetId) {
            return Database.queryWithBinds(
                'SELECT Id, ' + fieldList + ' FROM ' + String.escapeSingleQuotes(objectApiName)
                    + ' WHERE Id = :targetId LIMIT 1',
                new Map<String, Object>{ 'targetId' => targetId },
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    // The Contact of the creator may be private to the colleague.
    private without sharing class CreatorNameReader {
        private String readName(Id creatorId) {
            final User creator = [
                SELECT
                    Name,
                    Contact.Name
                FROM
                    User
                WHERE
                    Id = :creatorId
                WITH
                    SYSTEM_MODE
                LIMIT
                    1
            ];
            return creator.Contact?.Name ?? creator.Name;
        }
    }

    // Writes only the Contact of the connected user, without sharing: any other record is refused.
    private without sharing class ConnectedContactWriter {
        private void updateContact(SObject contact, Id connectedContactId) {
            if (connectedContactId == null || contact.Id != connectedContactId) {
                throw new SecurityException('Only the Contact of the connected user can be updated.');
            }
            Database.update(contact, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void populateFixedValuesFromRecord(
        SObject record,
        List<ApplicationFormCatalogueController.QuestionWrapper> questions,
        Map<Id, String> valueByQuestionId
    ) {
        for (ApplicationFormCatalogueController.QuestionWrapper question : questions) {
            Object fieldValue = record.get(question.fieldApiName);
            if (fieldValue == null) {
                valueByQuestionId.put(question.questionId, null);
            } else if (question.dataType == 'Multiselect') {
                List<String> parts = String.valueOf(fieldValue).split(';');
                valueByQuestionId.put(question.questionId, JSON.serialize(parts));
            } else {
                valueByQuestionId.put(question.questionId, String.valueOf(fieldValue));
            }
        }
    }

    private static void linkConnectedContact(
        Id applicationFormId,
        ApplicationForm appForm,
        Set<String> objectApiNames,
        Map<String, Id> targetIdByObjectApiName,
        Map<String, String> lookupFieldByObjectApiName,
        Map<String, Id> independentTargetIdByObjectApiName
    ) {
        addConnectedContactTarget(targetIdByObjectApiName, objectApiNames);
        final Id contactId = targetIdByObjectApiName.get(CONTACT_API_NAME);
        if (contactId == null) {
            return;
        }
        final String lookupField = lookupFieldByObjectApiName.get(CONTACT_API_NAME);
        if (lookupField == null) {
            independentTargetIdByObjectApiName.put(CONTACT_API_NAME, contactId);
        } else if (appForm.get(lookupField) == null) {
            final ApplicationForm link = new ApplicationForm(Id = applicationFormId);
            link.put(lookupField, contactId);
            Database.update(link, AccessLevel.SYSTEM_MODE);
        }
    }

    // Upserts Fixed answers for every Object API Name: update when a target already exists,
    // otherwise create (and link on the AF when a lookup exists). Independent targets are
    // remembered on the Assessment so read-only can still prefill.
    private static void saveFixedQuestionValues(Id applicationFormId, List<ResponseInputWrapper> fixedInputs) {
        Map<String, List<ResponseInputWrapper>> inputsByObjectApiName = groupFixedInputsByObjectApiName(
            fixedInputs
        );
        if (inputsByObjectApiName.isEmpty()) {
            return;
        }

        Set<String> objectApiNames = inputsByObjectApiName.keySet();
        ApplicationForm appForm = queryApplicationFormWithLookupFields(
            applicationFormId,
            objectApiNames
        );
        Map<String, String> lookupFieldByObjectApiName = findLookupFieldsOnApplicationForm(
            objectApiNames
        );
        Map<String, Id> independentTargetIdByObjectApiName =
            needsIndependentFixedTargetStorage(objectApiNames, lookupFieldByObjectApiName)
                ? loadIndependentFixedTargetIds(applicationFormId)
                : new Map<String, Id>();
        Map<String, Id> targetIdByObjectApiName = targetRecordIdByObjectApiName(
            appForm,
            objectApiNames,
            independentTargetIdByObjectApiName
        );
        // The Contact of the connected user is linked on the form and updated: no Contact is created for it.
        linkConnectedContact(
            applicationFormId,
            appForm,
            objectApiNames,
            targetIdByObjectApiName,
            lookupFieldByObjectApiName,
            independentTargetIdByObjectApiName
        );
        // The other Fixed targets (Account, Budget, ...) are created only by createMissingFixedTargets below,
        // when the candidate has actually answered a Fixed question mapped to them.
        Set<String> createdObjectApiNames = createMissingFixedTargets(
            appForm,
            inputsByObjectApiName,
            targetIdByObjectApiName,
            lookupFieldByObjectApiName,
            independentTargetIdByObjectApiName
        );
        if (!independentTargetIdByObjectApiName.isEmpty()) {
            saveIndependentFixedTargetIds(applicationFormId, independentTargetIdByObjectApiName);
        }

        List<SObject> recordsToUpdate = new List<SObject>();
        for (String objectApiName : inputsByObjectApiName.keySet()) {
            Id targetId = targetIdByObjectApiName.get(objectApiName);
            if (targetId == null || createdObjectApiNames.contains(objectApiName)) {
                continue;
            }
            List<ResponseInputWrapper> answeredInputs = new List<ResponseInputWrapper>();
            for (ResponseInputWrapper input : inputsByObjectApiName.get(objectApiName)) {
                if (!isBlankValue(input.valueJson) || !isFieldRequired(objectApiName, input.fieldApiName)) {
                    answeredInputs.add(input);
                }
            }
            if (answeredInputs.isEmpty()) {
                continue;
            }
            SObject record = targetId.getSObjectType().newSObject(targetId);
            applyFixedValues(record, answeredInputs);
            recordsToUpdate.add(record);
        }

        if (!recordsToUpdate.isEmpty()) {
            // The Contact of the connected user is the only record written without sharing: the candidate reads it
            // but is not always allowed to edit it. Every other target keeps the sharing of this class.
            final Id connectedContactId = ApplicationFormSubmissionService.getConnectedContactId();
            final List<SObject> otherRecordsToUpdate = new List<SObject>();
            final List<SObject> connectedContactRecords = new List<SObject>();
            for (SObject record : recordsToUpdate) {
                if (connectedContactId != null && record.Id == connectedContactId) {
                    connectedContactRecords.add(record);
                } else {
                    otherRecordsToUpdate.add(record);
                }
            }
            try {
                if (!otherRecordsToUpdate.isEmpty()) {
                    Database.update(otherRecordsToUpdate, AccessLevel.SYSTEM_MODE);
                }
                if (!connectedContactRecords.isEmpty()) {
                    new ConnectedContactWriter().updateContact(connectedContactRecords[0], connectedContactId);
                }
            } catch (DmlException e) {
                // The candidate changed an email to one already used by another contact.
                if (e.getDmlType(0) == StatusCode.DUPLICATES_DETECTED) {
                    final Set<String> blockedObjectApiNames = new Set<String>();
                    for (SObject record : recordsToUpdate) {
                        blockedObjectApiNames.add(String.valueOf(record.getSObjectType()));
                    }
                    fail(getDuplicateErrorCode(blockedObjectApiNames), e.getMessage());
                }
                throw e;
            }
        }
    }

    private static Map<String, List<ResponseInputWrapper>> groupFixedInputsByObjectApiName(
        List<ResponseInputWrapper> fixedInputs
    ) {
        Map<String, List<ResponseInputWrapper>> inputsByObjectApiName = new Map<String, List<ResponseInputWrapper>>();
        for (ResponseInputWrapper input : fixedInputs) {
            if (String.isBlank(input.objectApiName) || String.isBlank(input.fieldApiName)) {
                continue;
            }
            if (!inputsByObjectApiName.containsKey(input.objectApiName)) {
                inputsByObjectApiName.put(input.objectApiName, new List<ResponseInputWrapper>());
            }
            inputsByObjectApiName.get(input.objectApiName).add(input);
        }
        return inputsByObjectApiName;
    }

    // Creates Fixed target records that do not exist yet. Links them on the Application Form when
    // a lookup is available; otherwise keeps their Ids for independent upsert / prefill.
    private static Set<String> createMissingFixedTargets(
        ApplicationForm appForm,
        Map<String, List<ResponseInputWrapper>> inputsByObjectApiName,
        Map<String, Id> targetIdByObjectApiName,
        Map<String, String> lookupFieldByObjectApiName,
        Map<String, Id> independentTargetIdByObjectApiName
    ) {
        Map<String, SObject> newRecordByObjectApiName = new Map<String, SObject>();
        for (String objectApiName : inputsByObjectApiName.keySet()) {
            if (objectApiName == APPLICATION_FORM_API_NAME) {
                continue;
            }
            if (targetIdByObjectApiName.containsKey(objectApiName)) {
                continue;
            }
            Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sobjectType == null) {
                fail(ERROR_TECHNICAL, 'The object "' + objectApiName + '" does not exist.');
            }
            List<ResponseInputWrapper> inputs = inputsByObjectApiName.get(objectApiName);
            if (!hasAnswer(inputs)) {
                continue;
            }
            SObject record = sobjectType.newSObject();
            applyFixedValues(record, inputs);
            // Budget.Name is required but no Fixed question maps it: default it so the record
            // isn't silently dropped by the required-fields check below.
            if (objectApiName == 'Budget' && record.get('Name') == null) {
                record.put('Name', 'Budget-' + appForm.Name);
            }
            List<String> missingRequiredFields = getMissingRequiredFieldNames(sobjectType, record);
            if (missingRequiredFields.isEmpty()) {
                newRecordByObjectApiName.put(objectApiName, record);
            } else {
                fail(
                    ERROR_REQUIRED_FIELDS_MISSING,
                    'Required fields are missing for ' + objectApiName + ': '
                        + String.join(missingRequiredFields, ', ') + '.'
                );
            }
        }

        if (newRecordByObjectApiName.isEmpty()) {
            return new Set<String>();
        }
        try {
            Database.insert(newRecordByObjectApiName.values(), AccessLevel.SYSTEM_MODE);
        } catch (DmlException e) {
            // A duplicate rule blocks the record (for example a Contact with the same email): the candidate gets a
            // clear message instead of a technical error.
            if (e.getDmlType(0) == StatusCode.DUPLICATES_DETECTED) {
                fail(getDuplicateErrorCode(newRecordByObjectApiName.keySet()), e.getMessage());
            }
            throw e;
        }

        ApplicationForm formLinks = new ApplicationForm(Id = appForm.Id);
        Boolean hasFormLink = false;
        for (String objectApiName : newRecordByObjectApiName.keySet()) {
            Id createdRecordId = newRecordByObjectApiName.get(objectApiName).Id;
            targetIdByObjectApiName.put(objectApiName, createdRecordId);
            String lookupFieldName = lookupFieldByObjectApiName.get(objectApiName);
            if (lookupFieldName != null) {
                formLinks.put(lookupFieldName, createdRecordId);
                hasFormLink = true;
            } else {
                independentTargetIdByObjectApiName.put(objectApiName, createdRecordId);
            }
        }
        if (hasFormLink) {
            Database.update(formLinks, AccessLevel.SYSTEM_MODE);
        }
        return newRecordByObjectApiName.keySet();
    }

    // A Contact among the blocked records gets its own message (email already used); any other object a generic one.
    @TestVisible
    private static String getDuplicateErrorCode(Set<String> objectApiNames) {
        return objectApiNames.contains('Contact') ? ERROR_DUPLICATE_CONTACT : ERROR_DUPLICATE_RECORD;
    }

    private static void applyFixedValues(SObject record, List<ResponseInputWrapper> inputs) {
        for (ResponseInputWrapper input : inputs) {
            try {
                record.put(
                    input.fieldApiName,
                    convertFixedFieldValue(input.dataType, input.valueJson)
                );
            } catch (Exception e) {
                fail(
                    ERROR_INVALID_VALUE,
                    new List<String>{ input.label },
                    'Unable to save "' + input.fieldApiName + '": ' + e.getMessage()
                );
            }
        }
    }

    private static Boolean hasAnswer(List<ResponseInputWrapper> inputs) {
        for (ResponseInputWrapper input : inputs) {
            if (!isBlankValue(input.valueJson)) {
                return true;
            }
        }
        return false;
    }

    // Fields required by the platform (creatable, not nillable, no default on insert) that still
    // have no value on the record — empty when the record is ready to insert.
    private static List<String> getMissingRequiredFieldNames(Schema.SObjectType sobjectType, SObject record) {
        List<String> missingFieldNames = new List<String>();
        for (Schema.SObjectField field : sobjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (
                !fieldDescribe.isCreateable()
                || fieldDescribe.isNillable()
                || fieldDescribe.isDefaultedOnCreate()
                || fieldDescribe.isAutoNumber()
            ) {
                continue;
            }
            if (record.get(fieldDescribe.getName()) == null) {
                missingFieldNames.add(fieldDescribe.getName());
            }
        }
        return missingFieldNames;
    }

    // Same "required" definition as hasRequiredFieldValues, but for a single field by API name —
    // used to decide whether a blank answer may null out that field on an update.
    private static Boolean isFieldRequired(String objectApiName, String fieldApiName) {
        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sobjectType == null) {
            return false;
        }
        Schema.SObjectField field = sobjectType.getDescribe().fields.getMap().get(fieldApiName);
        if (field == null) {
            return false;
        }
        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
        return fieldDescribe.isCreateable()
            && !fieldDescribe.isNillable()
            && !fieldDescribe.isDefaultedOnCreate()
            && !fieldDescribe.isAutoNumber();
    }

    // Converts the plain-string value the player sends for a scalar answer into the Apex type
    // the target field expects. Falls back to the raw string for anything not explicitly handled.
    private static Object convertFixedFieldValue(String dataType, String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        if (dataType == 'Integer') {
            return Integer.valueOf(rawValue);
        }
        if (dataType == 'Decimal' || dataType == 'Currency') {
            return Decimal.valueOf(rawValue);
        }
        if (dataType == 'Date') {
            return Date.valueOf(rawValue);
        }
        if (dataType == 'DateTime') {
            return DateTime.valueOfGmt(rawValue.replace('T', ' ').replace('Z', ''));
        }
        if (dataType == 'Checkbox') {
            return Boolean.valueOf(rawValue);
        }
        if (dataType == 'Multiselect') {
            try {
                List<Object> rawList = (List<Object>) JSON.deserializeUntyped(rawValue);
                List<String> values = new List<String>();
                for (Object item : rawList) {
                    if (item != null && String.isNotBlank(String.valueOf(item))) {
                        values.add(String.valueOf(item));
                    }
                }
                return String.join(values, ';');
            } catch (Exception e) {
                return rawValue;
            }
        }
        return rawValue;
    }

    private static Boolean isPicklistDataType(String dataType) {
        return dataType == 'Select' || dataType == 'Multiselect' || dataType == 'RadioGroup';
    }

    private static Map<String, String> picklistValuesCache = new Map<String, String>();

    @TestVisible
    private static String getPicklistResponseValues(String objectApiName, String fieldApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return null;
        }
        String cacheKey = (objectApiName + '.' + fieldApiName).toLowerCase();
        if (picklistValuesCache.containsKey(cacheKey)) {
            return picklistValuesCache.get(cacheKey);
        }

        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null) {
            picklistValuesCache.put(cacheKey, null);
            return null;
        }
        Map<String, Schema.SObjectField> fieldsMap = sObjectType.getDescribe().fields.getMap();
        Schema.SObjectField sField = fieldsMap.get(fieldApiName);
        if (sField == null) {
            picklistValuesCache.put(cacheKey, null);
            return null;
        }
        Schema.DescribeFieldResult fieldDescribe = sField.getDescribe();
        Schema.DisplayType displayType = fieldDescribe.getType();
        if (displayType != Schema.DisplayType.PICKLIST && displayType != Schema.DisplayType.MULTIPICKLIST) {
            picklistValuesCache.put(cacheKey, null);
            return null;
        }

        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        String result = values.isEmpty() ? null : String.join(values, '\n');
        picklistValuesCache.put(cacheKey, result);
        return result;
    }

    private static void requireId(Id value, String message) {
        if (value == null) {
            fail(ERROR_ID_REQUIRED, message);
        }
    }

    private static Id parseId(String value, String message) {
        if (String.isBlank(value)) {
            fail(ERROR_ID_REQUIRED, message);
        }
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            fail(ERROR_ID_REQUIRED, message);
        }
        return null;
    }

    private static Id getCallForProjectsRecordTypeId() {
        Id recordTypeId = SchemaUtilities.getRecordTypeId(
            ApplicationForm.SObjectType,
            CALL_FOR_PROJECTS_RECORD_TYPE
        );
        if (recordTypeId == null) {
            fail(ERROR_TECHNICAL, 'The Call For Projects record type is required to create an Application Form.');
        }
        return recordTypeId;
    }

    // Errors reach the form as JSON: a code translated in the language of the form, its parameters, and the
    // English detail kept for the logs and the tests.
    private static void fail(String code, String detail) {
        fail(code, new List<String>(), detail);
    }

    private static void fail(String code, List<String> params, String detail) {
        throw buildError(code, params, detail);
    }

    // A message already translated, such as a Custom Label, is shown as it is.
    private static void failWithMessage(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }

    @TestVisible
    private static AuraHandledException buildError(String code, List<String> params, String detail) {
        return FormLanguageService.buildError(code, params, detail);
    }

    // An unexpected error is shown as a technical error; its detail is logged.
    private static AuraHandledException wrapException(String context, Exception e) {
        final String detail = context + ': ' + e.getMessage();
        System.debug(LoggingLevel.ERROR, detail + '\n' + e.getStackTraceString());
        if (e instanceof ApplicationFormSubmissionService.SubmissionCheckException) {
            final String code = ((ApplicationFormSubmissionService.SubmissionCheckException) e).code;
            return buildError(String.isBlank(code) ? ERROR_USER_NOT_LINKED : code, new List<String>(), detail);
        }
        return buildError(ERROR_TECHNICAL, new List<String>(), detail);
    }
}