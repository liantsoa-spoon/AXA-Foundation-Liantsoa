/**
 * @description       : Candidate-facing application form player with multi-file upload.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 20-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   LAN      Multi-file upload named after the question label
 * 1.1   20-10-2026   LAN      Require the terms and conditions and image rights consents before submitting
 **/
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import alreadySubmittedMessage from '@salesforce/label/c.ApplicationFormAlreadySubmittedMessage';
import alreadySubmittedLinkText from '@salesforce/label/c.ApplicationFormAlreadySubmittedLinkText';
import submissionReceivedMessage from '@salesforce/label/c.ApplicationFormSubmissionReceivedMessage';
import technicalError from '@salesforce/label/c.ApplicationFormErrorTechnicalError';
import userNotLinkedError from '@salesforce/label/c.ApplicationFormErrorUserNotLinked';
import organizationNotLinkedError from '@salesforce/label/c.ApplicationFormErrorOrganizationNotLinked';
import duplicateContactError from '@salesforce/label/c.ApplicationFormErrorDuplicateContact';
import duplicateRecordError from '@salesforce/label/c.ApplicationFormErrorDuplicateRecord';
import USER_LANGUAGE from '@salesforce/i18n/lang';
import checkExistingSubmission from '@salesforce/apex/ApplicationFormController.checkExistingSubmission';
import openFundingOpportunityForm from '@salesforce/apex/ApplicationFormController.openFundingOpportunityForm';
import openReadOnlyForm from '@salesforce/apex/ApplicationFormController.openReadOnlyForm';
import saveFundingOpportunityForm from '@salesforce/apex/ApplicationFormController.saveFundingOpportunityForm';
import deleteUploadedFile from '@salesforce/apex/ApplicationFormController.deleteUploadedFile';
import renameUploadedFiles from '@salesforce/apex/ApplicationFormController.renameUploadedFiles';
import linkUploadedFiles from '@salesforce/apex/ApplicationFormController.linkUploadedFiles';

const LABELS = {
    alreadySubmittedMessage,
    alreadySubmittedLinkText,
    en: {
        loading: 'Loading',
        saving: 'Saving',
        submissionReceivedMessage,
        submissionReceivedLinkText: 'here',
        information: 'Information',
        required: 'required',
        available: 'Available',
        selected: 'Selected',
        preview: 'Preview',
        download: 'Download',
        deleteFile: 'Delete file',
        deleteRow: 'Delete row',
        addRow: 'Add a row',
        previous: 'Previous',
        saveAsDraft: 'Save as Draft',
        next: 'Next',
        submit: 'Submit',
        close: 'Close',
        cancel: 'Cancel',
        confirm: 'Confirm',
        noQuestions: 'No questions are configured for this Programme yet.',
        selectPlaceholder: 'Select an option',
        invalidValue: 'Enter a valid value.',
        tooLong: 'Your entry is too long.',
        invalidNumber: 'Enter a valid number.',
        editRestricted: {
            responsibilityStatement: ' is responsible for this application form on behalf of your organization.',
            readOnlyAccessAndContactRequest: 'You have read-only access. Please contact them to request changes.'
        },

        confirmation: {
            eoiTitle: 'Submit the expression of interest',
            applicationTitle: 'Submit the application',
            eoiMessage: 'Once submitted, your expression of interest can no longer be modified. '
                + 'Do you confirm the submission?',
            applicationMessage: 'Once submitted, your application can no longer be modified. '
                + 'Do you confirm the submission?'
        },

        feedback: {
            successTitle: 'Success',
            errorTitle: 'Error',
            unexpectedError: 'An unexpected error occurred.',
            requiredFieldsMissing: 'Required fields are missing.',
            eoiSubmitted: 'Expression of interest submitted.',
            applicationSubmitted: 'Application submitted.',
            savedAsDraft: 'Saved as draft.'
        },

        // Codes returned by ApplicationFormController; {0}, {1} are replaced by the parameters of the error.
        errors: {
            thisQuestion: 'This question',
            TECHNICAL_ERROR: technicalError,
            ID_REQUIRED: 'The form could not be opened: its program is missing.',
            FORM_NOT_LINKED: 'This application is not linked to a program yet.',
            APPLICATION_FORM_NOT_FOUND: 'The application could not be found.',
            APPLICATION_ALREADY_SUBMITTED: 'This application has already been submitted and can no longer be modified.',
            FUNDING_OPPORTUNITY_LOCKED: 'This program no longer accepts changes to its application form.',
            FUNDING_OPPORTUNITY_NOT_FOUND: 'The program could not be found.',
            EDIT_NOT_ALLOWED: 'Only the contact who created this form can edit it.',
            STATUS_REQUIRED: 'A status is required.',
            QUESTION_REQUIRED: '"{0}" is required.',
            MAXIMUM_CHARACTERS_EXCEEDED: '"{0}" cannot exceed {1} characters.',
            REQUIRED_FIELDS_MISSING: 'Some required information is missing. Please check your answers.',
            INVALID_VALUE: 'The value of "{0}" is not valid.',
            USER_NOT_LINKED: userNotLinkedError,
            ORGANIZATION_NOT_LINKED: organizationNotLinkedError,
            DUPLICATE_CONTACT: duplicateContactError,
            DUPLICATE_RECORD: duplicateRecordError
        }
    },

    fr: {
        loading: 'Chargement',
        saving: 'Enregistrement',
        submissionReceivedMessage,
        submissionReceivedLinkText: 'ici',
        information: 'Information',
        required: 'obligatoire',
        available: 'Disponibles',
        selected: 'Sélectionnés',
        preview: 'Aperçu',
        download: 'Télécharger',
        deleteFile: 'Supprimer le fichier',
        deleteRow: 'Supprimer la ligne',
        addRow: 'Ajouter une ligne',
        previous: 'Précédent',
        saveAsDraft: 'Enregistrer le brouillon',
        next: 'Suivant',
        submit: 'Soumettre',
        close: 'Fermer',
        cancel: 'Annuler',
        confirm: 'Confirmer',
        noQuestions: 'Aucune question n\'est encore configurée pour ce programme.',
        selectPlaceholder: 'Sélectionner une option',
        invalidValue: 'Saisissez une valeur valide.',
        tooLong: 'Votre saisie est trop longue.',
        invalidNumber: 'Saisissez un nombre valide.',
        editRestricted: {
            responsibilityStatement: ' est responsable de ce formulaire de candidature pour votre organisation.',
            readOnlyAccessAndContactRequest:
                'Vous pouvez le consulter en lecture seule. Pour toute modification, veuillez contacter cette personne.'
        },

        confirmation: {
            eoiTitle: 'Soumettre la manifestation d\'intérêt',
            applicationTitle: 'Soumettre la candidature',
            eoiMessage: 'Une fois soumise, votre manifestation d\'intérêt ne pourra plus être modifiée. '
                + 'Confirmez-vous la soumission ?',
            applicationMessage: 'Une fois soumise, votre candidature ne pourra plus être modifiée. '
                + 'Confirmez-vous la soumission ?'
        },

        feedback: {
            successTitle: 'Succès',
            errorTitle: 'Erreur',
            unexpectedError: 'Une erreur inattendue est survenue.',
            requiredFieldsMissing: 'Des champs obligatoires ne sont pas renseignés.',
            eoiSubmitted: 'Manifestation d\'intérêt soumise.',
            applicationSubmitted: 'Candidature soumise.',
            savedAsDraft: 'Brouillon enregistré.'
        },

        errors: {
            thisQuestion: 'Cette question',
            TECHNICAL_ERROR: technicalError,
            ID_REQUIRED: 'Le formulaire n\'a pas pu être ouvert : son programme est manquant.',
            FORM_NOT_LINKED: 'Cette candidature n\'est pas encore rattachée à un programme.',
            APPLICATION_FORM_NOT_FOUND: 'La candidature est introuvable.',
            APPLICATION_ALREADY_SUBMITTED: 'Cette candidature a déjà été soumise et ne peut plus être modifiée.',
            FUNDING_OPPORTUNITY_LOCKED: 'Ce programme n\'accepte plus de modification de son formulaire de candidature.',
            FUNDING_OPPORTUNITY_NOT_FOUND: 'Le programme est introuvable.',
            EDIT_NOT_ALLOWED: 'Seul le contact qui a créé ce formulaire peut le modifier.',
            STATUS_REQUIRED: 'Un statut est obligatoire.',
            QUESTION_REQUIRED: '« {0} » est obligatoire.',
            MAXIMUM_CHARACTERS_EXCEEDED: '« {0} » ne peut pas dépasser {1} caractères.',
            REQUIRED_FIELDS_MISSING: 'Des informations obligatoires sont manquantes. Veuillez vérifier vos réponses.',
            INVALID_VALUE: 'La valeur de « {0} » n\'est pas valide.',
            USER_NOT_LINKED: userNotLinkedError,
            ORGANIZATION_NOT_LINKED: organizationNotLinkedError,
            DUPLICATE_CONTACT: duplicateContactError,
            DUPLICATE_RECORD: duplicateRecordError
        }
    }
};
const FORM_LANGUAGE_FRENCH = 'FR';
// Replaces {0}, {1}... with the given values.
function formatLabel(template, values) {
    return values.reduce((text, value, index) => text.replace(`{${index}}`, value), template);
}
// An Apex error is JSON { code, params, detail }; any other message (Custom Label, client check) is kept as it is.
function parseApexError(message) {
    try {
        const error = JSON.parse(message);
        return error && error.code ? error : null;
    } catch {
        return null;
    }
}
const USER_LANGUAGE_FRENCH_PREFIX = 'fr';
const STATUS_ALREADY_SUBMITTED = 'ALREADY_SUBMITTED';
const SALESFORCE_ID_PATTERN = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;
const PROGRAM_NAME_MARKER = '{ProgramName}';
const APPLICATION_FORM_LINK_MARKER = '{ApplicationFormLink}';
const FORM_TYPE_MARKER = '{FormType}';
const FORM_TYPE_EOI = 'EOI';
const ERROR_CONSENTS_NOT_ACCEPTED = 'CONSENTS_NOT_ACCEPTED';

// A question of the form is targeted by its Contact field and by the sections named here (compared without case).
function isFieldInSections(question, sectionLabel, fields) {
    const normalizedSectionLabel = (sectionLabel || '').trim().toLowerCase();
    return fields.some(
        (field) =>
            field.objectApiName === question.objectApiName &&
            field.fieldApiName === question.fieldApiName &&
            field.sectionLabels.some((label) => label.toLowerCase() === normalizedSectionLabel)
    );
}

// Fields greyed out once they carry a value.
const LOCKED_FIELDS = [
    {
        objectApiName: 'Contact',
        fieldApiName: 'Email',
        sectionLabels: ['Candidate Information', 'Applicant Identity']
    }
];
const HIDDEN_QUESTIONS = [
    {
        objectApiName: 'Contact',
        fieldApiName: 'Roles__c',
        sectionLabels: ['Candidate Information']
    }
];

function isLockedField(question, sectionLabel) {
    return isFieldInSections(question, sectionLabel, LOCKED_FIELDS);
}

function isHiddenQuestion(question, sectionLabel) {
    return isFieldInSections(question, sectionLabel, HIDDEN_QUESTIONS);
}

const INPUT_TYPE_BY_DATA_TYPE = {
    Integer: 'number',
    Decimal: 'number',
    Currency: 'number',
    Date: 'date',
    DateTime: 'datetime',
    Email: 'email',
    Telephone: 'tel',
    URL: 'url',
    Checkbox: 'checkbox'
};


const NUMBER_FORMATTER_BY_DATA_TYPE = {
    Currency: 'currency',
    Decimal: 'decimal'
};

function buildFieldConfig(dataType) {
    if (dataType === 'TextArea') {
        return { kind: 'textarea' };
    }
    if (dataType === 'Checkbox') {
        return { kind: 'checkbox' };
    }
    if (dataType === 'Select') {
        return { kind: 'select' };
    }
    if (dataType === 'Multiselect') {
        return { kind: 'multiselect' };
    }
    if (dataType === 'RadioGroup') {
        return { kind: 'radio' };
    }
    if (dataType === 'File') {
        return { kind: 'file' };
    }
    if (INPUT_TYPE_BY_DATA_TYPE[dataType]) {
        return {
            kind: 'input',
            inputType: INPUT_TYPE_BY_DATA_TYPE[dataType],
            formatter: NUMBER_FORMATTER_BY_DATA_TYPE[dataType],
            step: dataType === 'Integer' ? '1' : null
        };
    }
    return { kind: 'input', inputType: 'text' };
}


function splitLines(text) {
    return (text || '')
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line.length > 0);
}

// responseLabels (French) lines up with responseValues (English): the label is shown, the English value is saved.
function parseOptions(responseValues, responseLabels) {
    const values = splitLines(responseValues);
    const labels = splitLines(responseLabels);
    const hasLabels = labels.length === values.length;
    return values.map((value, index) => ({ label: hasLabels ? labels[index] : value, value }));
}

let rowKeySeed = 0;
function nextRowKey() {
    rowKeySeed += 1;
    return `row-${rowKeySeed}`;
}


function buildRow(columns, valuesByColumn = {}) {
    return {
        key: nextRowKey(),
        cells: (columns || []).map((column) => {
            const isCheckbox = column.field.kind === 'checkbox';
            const existing = valuesByColumn[column.developerName];
            return {
                developerName: column.developerName,
                inputType: column.field.inputType,
                isCheckbox,
                value: isCheckbox ? existing === true : existing || ''
            };
        })
    };
}

function rowToMap(row) {
    const map = {};
    row.cells.forEach((cell) => {
        map[cell.developerName] = cell.value;
    });
    return map;
}

function getFileBaseName(fileName) {
    const dotIndex = (fileName || '').lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName || '';
}

function mapFile(file) {
    return {
        documentId: file.documentId,
        name: file.name,
        downloadUrl: `/sfc/servlet.shepherd/document/download/${file.documentId}`,
        previewUrl: `/lightning/r/ContentDocument/${file.documentId}/view`
    };
}


/**
 * Candidate-facing player. recordId is detected automatically: an Application Form record page
 * opens that form, a Funding Opportunity record page opens or starts the FO journey. Elsewhere,
 * fundingOpportunityId is set in App Builder.
 */
export default class ApplicationForm extends NavigationMixin(LightningElement) {
    @api recordId;
    @api fundingOpportunityId;
    @api eoi = false;
    @api eoiAndFullApplication = false;
    @api readOnly = false;
    @api hideSteps = false;

    // Funding Opportunity Id read from the id URL parameter, e.g. /formulaire?id=119...
    urlFundingOpportunityId;
    loadedContextRecordId;
    hasLoadedDefinition = false;

    get displaySteps() {
        return !this.hideSteps;
    }

    sections = [];
    isLoading = true;
    isSaving = false;
    currentIndex = 0;
    applicationStatus;
    activeApplicationFormId;
    // Funding Opportunity of the form, returned by Apex: the program of the budget block.
    formFundingOpportunityId;
    sessionIsEoi = true;
    isFormUnavailable = false;
    unavailableMessage;
    isSubmissionBlocked = false;
    // From a submission to the next reload: the reload shows the received message once.
    isSubmissionJustReceived = false;
    receivedFormType = '';
    blockedMessage;
    isConfirmVisible = false;
    isFundingOpportunityLocked = false;
    isEditAllowed = true;
    creatorName;
    // EN or FR, returned by Apex: before the form is loaded, the language of the user applies.
    formLanguage;
    // Labels and documents of the two consents, returned by Apex in the language of the form.
    consents;
    // The only stages in which the candidate can edit: the EOI draft, the full application draft, and an
    // approved EOI (it opens the full application, the first save moves it to Draft). Any other stage is locked.
    static EDITABLE_STAGES = ['EOI Draft', 'Draft', 'EOI Approved'];

    // The manual readOnly attribute always wins, then the Funding Opportunity status (computed by
    // Apex); otherwise, the form is locked unless it is in an editable stage (no stage yet = new form).
    get effectiveReadOnly() {
        if (this.readOnly || this.isFundingOpportunityLocked || !this.isEditAllowed) {
            return true;
        }
        if (!this.applicationStatus) {
            return false;
        }
        return !ApplicationForm.EDITABLE_STAGES.includes(this.applicationStatus);
    }

    get labels() {
        const isFrench = this.formLanguage
            ? this.formLanguage === FORM_LANGUAGE_FRENCH
            : USER_LANGUAGE.toLowerCase().startsWith(USER_LANGUAGE_FRENCH_PREFIX);
        return isFrench ? LABELS.fr : LABELS.en;
    }

    get isEditRestricted() {
        return !this.isEditAllowed;
    }

    // The EOI checkbox alone: the journey stops once the EOI is submitted.
    get isEoiOnlyForm() {
        return this.eoi === true && this.eoiAndFullApplication !== true;
    }

    // The form loads here rather than in connectedCallback, once per context, so the id URL parameter is
    // known before the first Apex call.
    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const urlId = pageReference?.state?.id;
        this.urlFundingOpportunityId = SALESFORCE_ID_PATTERN.test(urlId || '') ? urlId : undefined;
        if (this.hasLoadedDefinition && this.contextRecordId === this.loadedContextRecordId) {
            return;
        }
        this.hasLoadedDefinition = true;
        this.loadedContextRecordId = this.contextRecordId;
        this.activeApplicationFormId = undefined;
        this.loadDefinition();
    }

    // A record page wins, then the id URL parameter, then the Id set in Experience Builder.
    get contextRecordId() {
        return this.recordId || this.urlFundingOpportunityId || this.fundingOpportunityId;
    }

    // Once a draft exists, every save/reload must target that Application Form Id so the same
    // Contact keeps upserting one AF instead of creating a new one on each step.
    get persistenceContextId() {
        return this.activeApplicationFormId || this.contextRecordId;
    }

    get activeEoi() {
        return this.sessionIsEoi;
    }

    get isEoiAndFullMode() {
        return this.eoiAndFullApplication === true;
    }

    // Internal persistence id, filled after the first draft, submission, or file upload.
    get effectiveRecordId() {
        return this.activeApplicationFormId;
    }

    async loadDefinition() {
        if (!this.contextRecordId) {
            this.isLoading = false;
            return;
        }
        this.isLoading = true;
        this.isSubmissionBlocked = false;
        try {
            if (!this.activeApplicationFormId && !this.readOnly) {
                const check = await checkExistingSubmission({
                    fundingOpportunityId: this.contextRecordId,
                    isEoiOnly: this.isEoiOnlyForm
                });
                const isReadOnlyColleague = check?.isEditAllowed === false && !!check?.applicationFormId;
                if (check?.status === STATUS_ALREADY_SUBMITTED && !isReadOnlyColleague) {
                    await this.showSubmissionBlocked(check);
                    return;
                }
                this.activeApplicationFormId = check?.applicationFormId;
            }
            // Read only (CRM): the EOI checkbox decides between EOI and full application, whatever the stage.
            const result = this.readOnly
                ? await openReadOnlyForm({
                      contextRecordId: this.persistenceContextId,
                      isEoiChecked: this.eoi === true
                  })
                : await openFundingOpportunityForm({
                      contextRecordId: this.persistenceContextId,
                      isEoiChecked: this.eoi === true,
                      isEoiAndFullApplicationChecked: this.eoiAndFullApplication === true
                  });
            this.activeApplicationFormId = result?.applicationFormId;
            this.formFundingOpportunityId = result?.fundingOpportunityId;
            this.applicationStatus = result?.applicationStatus;
            this.sessionIsEoi = result?.isEoi !== false;
            this.isFundingOpportunityLocked = result?.isFundingOpportunityLocked === true;
            this.isEditAllowed = result?.isEditAllowed !== false;
            this.creatorName = result?.creatorName;
            this.formLanguage = result?.formLanguage;
            this.consents = result?.consents;
            this.isFormUnavailable = result?.isUnavailable === true;
            this.unavailableMessage = result?.unavailableMessage;
            this.sections = (result?.sections || [])
                .map((section) => ({
                    ...section,
                    questions: (section.questions || [])
                        .filter((question) => !isHiddenQuestion(question, section.label))
                        .map((question) => this.buildQuestionState(question, section.label))
                }))
                // A section that only holds budget tables is kept: the budget block shows them.
                .filter((section) => section.questions.length > 0 || section.hasBudget);
            this.currentIndex = 0;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSubmissionJustReceived = false;
            this.isLoading = false;
        }
    }

    // The label holds both markers. The link marker is cut out of the text so a real link can be placed
    // there; the Application Form is linked whoever created it (a colleague's one is shared by Account).
    // Right after a submission the received message is shown; on a refresh, or when the candidate comes
    // back to the form, the default message of the Custom Label is shown.
    async showSubmissionBlocked(check) {
        const isReceived = this.isSubmissionJustReceived && check.isOwnApplicationForm === true;
        // Without a form type (the full application) the marker leaves a double space, which is collapsed.
        const template = isReceived
            ? this.labels.submissionReceivedMessage
                  .replace(FORM_TYPE_MARKER, this.receivedFormType)
                  .replace(/ {2,}/g, ' ')
            : LABELS.alreadySubmittedMessage;
        const text = template.replace(PROGRAM_NAME_MARKER, () => check.programName || '');
        const [beforeLink, afterLink = ''] = text.split(APPLICATION_FORM_LINK_MARKER);
        const linkUrl = await this.getApplicationFormUrl(check.applicationFormId);
        this.blockedMessage = {
            beforeLink,
            afterLink,
            linkUrl,
            hasLink: Boolean(linkUrl),
            linkText: isReceived ? this.labels.submissionReceivedLinkText : LABELS.alreadySubmittedLinkText
        };
        this.sections = [];
        this.isSubmissionBlocked = true;
    }

    // Standard record page of the Application Form: there is no dedicated page for it yet.
    async getApplicationFormUrl(applicationFormId) {
        try {
            return await this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: applicationFormId,
                    objectApiName: 'ApplicationForm',
                    actionName: 'view'
                }
            });
        } catch (error) {
            return null;
        }
    }

    // A save refused because of a submission made elsewhere (another tab, a colleague) shows the same
    // message as the opening, on screen, instead of an error toast.
    async handleSaveError(error) {
        try {
            const check = await checkExistingSubmission({
                fundingOpportunityId: this.contextRecordId,
                isEoiOnly: this.isEoiOnlyForm
            });
            if (check?.status === STATUS_ALREADY_SUBMITTED) {
                await this.showSubmissionBlocked(check);
                return;
            }
        } catch (checkError) {
            // The original error is the one to report.
        }
        this.showError(error);
    }

    buildQuestionState(question, sectionLabel) {
        const field = buildFieldConfig(question.dataType);
        const isCharacterLimitedField =
            field.kind === 'textarea' ||
            (field.kind === 'input' && ['text', 'email', 'tel', 'url'].includes(field.inputType));
        const columns = (question.columns || []).map((column) => ({
            ...column,
            field: buildFieldConfig(column.dataType)
        }));

        const isSingleColumn =
            Boolean(question.isTable) ||
            field.kind === 'multiselect' ||
            field.kind === 'textarea' ||
            field.kind === 'file';

        const state = {
            ...question,
            isTextarea: field.kind === 'textarea',
            isCheckbox: field.kind === 'checkbox',
            isSelect: field.kind === 'select',
            isMultiselect: field.kind === 'multiselect',
            isRadio: field.kind === 'radio',
            isFile: field.kind === 'file',
            isPlainInput: field.kind === 'input',
            isSingleColumn,
            containerClass: isSingleColumn
                ? 'slds-col slds-size_1-of-1 slds-form-element slds-p-bottom_medium'
                : 'slds-col slds-size_1-of-1 slds-medium-size_1-of-2 slds-form-element slds-p-bottom_medium',
            inputType: field.inputType,
            formatter: field.formatter,
            step: field.step,
            maxLength:
                isCharacterLimitedField && Number(question.maximumCharacters) > 0
                    ? Number(question.maximumCharacters)
                    : null,
            options: ['select', 'multiselect', 'radio'].includes(field.kind) ? parseOptions(question.responseValues, question.responseLabels) : undefined,
            columns
        };

        if (question.isTable) {
            const savedRows = question.existingValueJson ? JSON.parse(question.existingValueJson) : [];
            state.rows = savedRows.length ? savedRows.map((valuesByColumn) => buildRow(columns, valuesByColumn)) : [buildRow(columns)];
        } else if (state.isMultiselect) {
            state.value = question.existingValueJson ? JSON.parse(question.existingValueJson) : [];
        } else if (state.isFile) {
            // Files go through the standard lightning-file-upload, without record-id: they are
            // only owned by the user and attached to nothing (not to the Application Form). The
            // {documentId, name} list is saved as this question's answer like any other value.
            const savedFiles = question.existingValueJson ? JSON.parse(question.existingValueJson) : [];
            state.uploadedFiles = savedFiles.map(mapFile);
        } else if (state.isCheckbox) {
            state.value = question.existingValueJson === 'true' || question.existingValueJson === true;
        } else {
            state.value = question.existingValueJson || '';
        }
        // A locked field is greyed out only once it holds a value: an empty one stays fillable, else the form is stuck.
        state.isLocked = isLockedField(question, sectionLabel) && String(state.value ?? '').trim() !== '';
        return state;
    }

    // ---- Budget block ----

    // The section of the budget tables; the block stays loaded in the other sections, hidden, so the candidate keeps
    // the rows typed in it.
    get budgetSectionId() {
        return this.sections.find((section) => section.hasBudget)?.sectionId;
    }

    get hasBudgetBlock() {
        return Boolean(this.budgetSectionId) && Boolean(this.formFundingOpportunityId);
    }

    get budgetBlockClass() {
        return this.currentSection?.sectionId === this.budgetSectionId ? '' : 'slds-hide';
    }

    get budgetBlock() {
        return this.template.querySelector('c-application-form-budget');
    }

    get currentSection() {
        const section = this.sections[this.currentIndex];
        if (!section) {
            return undefined;
        }
        return {
            ...section,
            questions: section.questions.map((q) => {
                if (!q.isFile) {
                    return {
                        ...q,
                        isInputDisabled: this.effectiveReadOnly || q.isLocked === true
                    };
                }
                return {
                    ...q,
                    isFileDisabled: this.effectiveReadOnly
                };
            })
        };
    }

    get hasSections() {
        return this.sections.length > 0;
    }

    get pathSteps() {
        return this.sections.map((section, index) => {
            const isCurrent = index === this.currentIndex;
            const isCompleted = index < this.currentIndex;
            return {
                label: section.label,
                value: section.sectionId,
                isCurrent,
                itemClass: `slds-path__item slds-is-${isCurrent ? 'current slds-is-active' : isCompleted ? 'complete' : 'incomplete'}`
            };
        });
    }

    get isFirstSection() {
        return this.currentIndex === 0;
    }

    get isLastSection() {
        return this.currentIndex === this.sections.length - 1;
    }

    get nextButtonLabel() {
        if (this.isLastSection) {
            return this.effectiveReadOnly ? this.labels.close : this.labels.submit;
        }
        return this.labels.next;
    }

    get showNextButton() {
        return !(this.isLastSection && this.effectiveReadOnly);
    }

    static FIELDS_REQUIRED_FOR_DRAFT_BY_OBJECT_API_NAME = {
        Contact: ['Email']
    };

    get showSaveAsDraft() {
        return this.sections.every((section) =>
            section.questions.every((question) => {
                const hardCodedFields =
                    ApplicationForm.FIELDS_REQUIRED_FOR_DRAFT_BY_OBJECT_API_NAME[question.objectApiName] || [];
                const isRequiredForDraft =
                    question.isSchemaRequired === true || hardCodedFields.includes(question.fieldApiName);
                if (!isRequiredForDraft) {
                    return true;
                }
                const value = question.value;
                return value !== null && value !== undefined && String(value).trim() !== '';
            })
        );
    }

    get confirmTitle() {
        return this.activeEoi
            ? this.labels.confirmation.eoiTitle
            : this.labels.confirmation.applicationTitle;
    }

    get confirmMessage() {
        return this.activeEoi
            ? this.labels.confirmation.eoiMessage
            : this.labels.confirmation.applicationMessage;
    }

    // Immutably updates one question (matched by versionId) within the current section only,
    // via updateFn(question) => partial fields to merge in.
    // Same as updateCurrentQuestion, across every section: the upload can finish after the
    // candidate moved to another section.
    updateQuestion(versionId, updateFn) {
        this.sections = this.sections.map((section) => ({
            ...section,
            questions: section.questions.map((question) =>
                question.versionId === versionId ? { ...question, ...updateFn(question) } : question
            )
        }));
    }

    updateCurrentQuestion(versionId, updateFn) {
        this.sections = this.sections.map((section, index) => {
            if (index !== this.currentIndex) {
                return section;
            }
            return {
                ...section,
                questions: section.questions.map((question) =>
                    question.versionId === versionId ? { ...question, ...updateFn(question) } : question
                )
            };
        });
    }

    // ---- Answer capture (scalar questions) ----

    handleFieldChange(event) {
        const versionId = event.currentTarget.dataset.versionId;
        const isCheckbox = event.currentTarget.dataset.checkbox === 'true';
        // lightning-input/-textarea/-combobox/-dual-listbox all report their new value through
        // event.detail (detail.checked for a checkbox, detail.value otherwise, string or array).
        const value = isCheckbox ? event.detail.checked : event.detail.value;
        this.updateCurrentQuestion(versionId, () => ({ value }));
    }

    // ---- Answer capture (File questions) ----
    // Standard lightning-file-upload, without record-id: each file is uploaded as soon as it is
    // selected and is only owned by the user. Right after the upload, the files are named after the
    // question label (Apex renameUploadedFiles). The documents are added to the question's answer
    // and saved with the rest of the section on Save as Draft / Submit.
    async handleUploadFinished(event) {
        const versionId = event.currentTarget.dataset.versionId;
        const uploadedDocuments = event.detail.files || [];
        const question = this.sections
            .flatMap((section) => section.questions)
            .find((q) => q.versionId === versionId);

        let uploadedFiles = uploadedDocuments.map(mapFile);
        try {
            const renamedFiles = await renameUploadedFiles({
                contentDocumentIds: uploadedDocuments.map((file) => file.documentId),
                fieldLabel: question?.label,
                existingTitles: (question?.uploadedFiles || []).map((file) => getFileBaseName(file.name))
            });
            uploadedFiles = renamedFiles.map(mapFile);
        } catch (error) {
            // The files are uploaded: if they cannot be renamed they keep their original name.
            this.showError(error);
        }
        this.updateQuestion(versionId, (q) => ({
            uploadedFiles: [...(q.uploadedFiles || []), ...uploadedFiles]
        }));
    }

    // Deletes the file for good (not just from the visible list), then persists the now-empty
    // answer immediately rather than waiting for the next Save/Submit.
    async handleRemoveFile(event) {
        const versionId = event.currentTarget.dataset.versionId;
        const documentId = event.currentTarget.dataset.documentId;
        try {
            await deleteUploadedFile({ contentDocumentId: documentId });
        } catch (error) {
            this.showError(error);
            return;
        }
        this.updateCurrentQuestion(versionId, (question) => ({
            uploadedFiles: (question.uploadedFiles || []).filter((file) => file.documentId !== documentId)
        }));
        await this.saveCurrentSection();
    }

    // ---- Answer capture (Table questions) ----

    handleAddRow(event) {
        const versionId = event.currentTarget.dataset.versionId;
        this.updateCurrentQuestion(versionId, (question) => ({
            rows: [...question.rows, buildRow(question.columns)]
        }));
    }

    handleRemoveRow(event) {
        const versionId = event.currentTarget.dataset.versionId;
        const rowKey = event.currentTarget.dataset.rowKey;
        this.updateCurrentQuestion(versionId, (question) => {
            const remaining = question.rows.filter((row) => row.key !== rowKey);
            return { rows: remaining.length ? remaining : [buildRow(question.columns)] };
        });
    }

    handleCellChange(event) {
        const versionId = event.currentTarget.dataset.versionId;
        const rowKey = event.currentTarget.dataset.rowKey;
        const columnName = event.currentTarget.dataset.column;
        const isCheckbox = event.currentTarget.dataset.checkbox === 'true';
        const newValue = isCheckbox ? event.detail.checked : event.detail.value;
        this.updateCurrentQuestion(versionId, (question) => ({
            rows: question.rows.map((row) =>
                row.key === rowKey
                    ? { ...row, cells: row.cells.map((cell) => (cell.developerName === columnName ? { ...cell, value: newValue } : cell)) }
                    : row
            )
        }));
    }

    // ---- Path navigation ----

    // Missing mandatory fields are reported before the confirmation opens, so the candidate is
    // never asked to confirm a submission that would be refused straight after.
    // Next only navigates, exactly like Previous and the path steps — answers are only persisted
    // via Save as Draft (or the final Submit confirmation).
    handleNext() {
        if (!this.isLastSection) {
            this.currentIndex += 1;
            return;
        }
        if (this.effectiveReadOnly || !this.reportAllSectionsValidity() || !this.reportConsentsValidity()) {
            return;
        }
        this.isConfirmVisible = true;
    }

    // A question counts as answered depending on the shape its value takes — mirrors the branches
    // in buildQuestionState/buildResponses.
    isQuestionAnswered(question) {
        if (question.isTable) {
            return (question.rows || []).some((row) =>
                row.cells.every((cell) => (cell.isCheckbox ? true : String(cell.value ?? '').trim() !== ''))
            );
        }
        if (question.isMultiselect) {
            return Array.isArray(question.value) && question.value.length > 0;
        }
        if (question.isFile) {
            return (question.uploadedFiles || []).length > 0;
        }
        if (question.isCheckbox) {
            return question.value === true;
        }
        return question.value !== null && question.value !== undefined && String(question.value).trim() !== '';
    }

    // Since Next no longer saves, a mandatory question left blank in an earlier section only
    // exists in this component's in-memory state, never in the DOM (only the current section is
    // rendered) — so reportSectionValidity() alone can't catch it. This checks every section's
    // mandatory questions against their in-memory value, jumps to the first section with a gap,
    // and only then falls back to the native DOM-level reportSectionValidity() (format/min/max
    // checks) on the section that's actually visible.
    reportAllSectionsValidity() {
        const firstIncompleteIndex = this.sections.findIndex((section) =>
            section.questions.some((question) => question.isMandatory && !this.isQuestionAnswered(question))
        );
        if (firstIncompleteIndex !== -1) {
            this.currentIndex = firstIncompleteIndex;
            this.showError({ message: this.labels.feedback.requiredFieldsMissing });
            return false;
        }
        // The mandatory budget tables: at least one complete row each.
        if (this.budgetBlock && !this.budgetBlock.validate()) {
            this.currentIndex = this.sections.findIndex((section) => section.sectionId === this.budgetSectionId);
            this.showError({ message: this.labels.feedback.requiredFieldsMissing });
            return false;
        }
        return this.reportSectionValidity();
    }

    // Shown on the last section only, where the candidate submits.
    get showConsents() {
        return this.isLastSection && !this.effectiveReadOnly && Boolean(this.consents);
    }

    reportConsentsValidity() {
        return [...this.template.querySelectorAll('c-consent-checkbox')].reduce(
            (isValid, consent) => consent.reportValidity() && isValid,
            true
        );
    }

    handleConfirmCancel() {
        this.isConfirmVisible = false;
    }

    async handleConfirmSubmit() {
        this.isConfirmVisible = false;
        // Read before saving: the save moves the Stage forward, which flips effectiveReadOnly to
        // true and would otherwise skip the reload below.
        const isSubmittingEoi = this.activeEoi;
        try {
            await this.saveFundingOpportunitySections(true);
        } catch (error) {
            return;
        }
        // Show success toast first, then reload after a short delay to allow the toast to display.
        this.showSuccess(
            isSubmittingEoi ? this.labels.feedback.eoiSubmitted : this.labels.feedback.applicationSubmitted
        );
        // Reload so the player follows the new Stage on its own: the full application in combined
        // mode, or the submitted message once the journey is over. The spinner (isSaving) stays
        // visible until loadDefinition completes, then disappears when the new state renders.
        await new Promise((resolve) => setTimeout(resolve, 1500));
        this.activeApplicationFormId = undefined;
        this.isSubmissionJustReceived = true;
        this.receivedFormType = isSubmittingEoi ? FORM_TYPE_EOI : '';
        await this.loadDefinition();
    }

    handlePrevious() {
        if (this.isFirstSection) {
            return;
        }
        this.currentIndex -= 1;
    }

    // Clicking a step on the path only navigates — answers are only persisted via Save as Draft.
    handleStepClick(event) {
        event.preventDefault();
        const targetSectionId = event.currentTarget.dataset.sectionId;
        const targetIndex = this.sections.findIndex((section) => section.sectionId === targetSectionId);
        if (targetIndex === -1 || targetIndex === this.currentIndex) {
            return;
        }
        this.currentIndex = targetIndex;
    }

    // Saves the current section's answers and marks the Application Form as Draft, without
    // navigating away — usable from any section, any number of times.
    async handleSaveAsDraft() {
        try {
            await this.saveFundingOpportunitySections(false);
            this.showSuccess(this.labels.feedback.savedAsDraft);
        } catch (error) {
            return;
        }
    }

    // Reports validity on every input bound to `required` in the current section (mandatory
    // questions), so a blank required field is caught client-side before the server round-trip.
    reportSectionValidity() {
        const fields = this.template.querySelectorAll(
            'lightning-input, lightning-textarea, lightning-combobox, lightning-dual-listbox, lightning-radio-group'
        );
        let allValid = true;
        fields.forEach((field) => {
            if (typeof field.reportValidity === 'function' && !field.reportValidity()) {
                allValid = false;
            }
        });
        return allValid;
    }

    buildResponses(sections) {
        return sections.flatMap((section) =>
            section.questions.map((question) => ({
                versionId: question.versionId,
                valueJson: question.isTable
                    ? JSON.stringify(question.rows.map(rowToMap))
                    : question.isMultiselect
                    ? JSON.stringify(question.value)
                    : question.isFile
                    ? JSON.stringify(
                          (question.uploadedFiles || []).map((file) => ({
                              documentId: file.documentId,
                              name: file.name
                          }))
                      )
                    : question.value,
                dataType: question.dataType,
                isFixed: question.isFixed,
                objectApiName: question.objectApiName,
                fieldApiName: question.fieldApiName,
                isMandatory: question.isMandatory,
                label: question.label
            }))
        );
    }

    // Saves every section's answers (the file answers carry the uploaded document ids).
    async saveFundingOpportunitySections(isSubmit) {
        if (this.isSaving) {
            return;
        }
        if (isSubmit && !this.reportAllSectionsValidity()) {
            throw new Error(this.labels.feedback.requiredFieldsMissing);
        }

        this.isSaving = true;
        try {
            const budgetBlock = this.budgetBlock;
            const saveForm = (isFormSubmit, contextRecordId) =>
                saveFundingOpportunityForm({
                    contextRecordId,
                    responsesJson: JSON.stringify(this.buildResponses(this.sections)),
                    isSubmit: isFormSubmit,
                    isEoiChecked: this.eoi === true,
                    isEoiAndFullApplicationChecked: this.eoiAndFullApplication === true,
                    // Checked before the confirmation: only sent with the submission.
                    termsAndConditionsFormTextId: isFormSubmit
                        ? this.consents?.termsAndConditions?.formTextId
                        : null,
                    imageRightsFormTextId: isFormSubmit ? this.consents?.imageRights?.formTextId : null
                });
            // The submission locks the form: the budget is saved before it, on a form saved as a draft first when it
            // does not exist yet. A draft saves the budget after the form, which creates the form if needed.
            let contextRecordId = this.persistenceContextId;
            if (isSubmit && budgetBlock) {
                let applicationFormId = this.activeApplicationFormId;
                if (!applicationFormId) {
                    applicationFormId = (await saveForm(false, contextRecordId)).applicationFormId;
                    contextRecordId = applicationFormId;
                }
                await budgetBlock.save(applicationFormId, true);
            }
            const result = await saveForm(isSubmit, contextRecordId);
            if (!isSubmit && budgetBlock) {
                await budgetBlock.save(result.applicationFormId, false);
            }
            this.activeApplicationFormId = result.applicationFormId;
            this.applicationStatus = result.applicationStatus;
            await this.attachUploadedFilesToApplicationForm();
        } catch (error) {
            await this.handleSaveError(error);
            throw error;
        } finally {
            this.isSaving = false;
        }
    }

    // The files are uploaded attached to nothing: they are linked to the Application Form when the
    // candidate saves it (Save as Draft / Submit), once the form exists. Already linked files are skipped.
    async attachUploadedFilesToApplicationForm() {
        const contentDocumentIds = this.sections
            .flatMap((section) => section.questions)
            .filter((question) => question.isFile)
            .flatMap((question) => (question.uploadedFiles || []).map((file) => file.documentId));
        if (!this.effectiveRecordId || contentDocumentIds.length === 0) {
            return;
        }
        await linkUploadedFiles({
            applicationFormId: this.effectiveRecordId,
            contentDocumentIds
        });
    }

    // enforceRequired only blocks on missing mandatory fields for the final Submit action; every
    // other save (Save as Draft, mid-form Next, step navigation, the immediate save after a file
    // removal) must always persist whatever has been answered so far.
    async saveCurrentSection(enforceRequired = false) {
        if (!this.currentSection || this.isSaving) {
            return;
        }
        // Read-only mode: Next/Previous only navigate, nothing is written.
        if (this.effectiveReadOnly) {
            return;
        }
        if (enforceRequired && !this.reportSectionValidity()) {
            throw new Error(this.labels.feedback.requiredFieldsMissing);
        }
        const section = this.currentSection;
        const responses = this.buildResponses([section]);

        this.isSaving = true;
        try {
            const result = await saveFundingOpportunityForm({
                contextRecordId: this.persistenceContextId,
                responsesJson: JSON.stringify(responses),
                isSubmit: enforceRequired,
                isEoiChecked: this.eoi === true,
                isEoiAndFullApplicationChecked: this.eoiAndFullApplication === true
            });
            this.activeApplicationFormId = result.applicationFormId;
            this.applicationStatus = result.applicationStatus;
        } catch (error) {
            await this.handleSaveError(error);
            throw error;
        } finally {
            this.isSaving = false;
        }
    }

    // ---- Toasts ----

    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ title: this.labels.feedback.successTitle, message, variant: 'success' }));
    }

    showError(error) {
        const message = this.translateError(error?.body?.message || error?.message);
        this.dispatchEvent(new ShowToastEvent({ title: this.labels.feedback.errorTitle, message, variant: 'error' }));
    }

    // Translates an Apex error code in the language of the form; an unknown code shows the technical error.
    translateError(rawMessage) {
        if (!rawMessage) {
            return this.labels.feedback.unexpectedError;
        }
        const apexError = parseApexError(rawMessage);
        if (!apexError) {
            return rawMessage;
        }
        const errors = this.labels.errors;
        // The consents message is a Custom Label returned by Apex in the language of the form.
        const consentsMessage =
            apexError.code === ERROR_CONSENTS_NOT_ACCEPTED ? this.consents?.errorMessage : undefined;
        const template = consentsMessage || errors[apexError.code] || errors.TECHNICAL_ERROR;
        const params = (apexError.params || []).map((param) => param || errors.thisQuestion);
        return formatLabel(template, params);
    }
}