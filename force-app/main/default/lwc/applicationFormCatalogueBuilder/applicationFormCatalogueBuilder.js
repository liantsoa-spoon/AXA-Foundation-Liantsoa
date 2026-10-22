import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import USER_LANGUAGE from '@salesforce/i18n/lang';
import FUNDING_OPPORTUNITY_STATUS_FIELD from '@salesforce/schema/FundingOpportunity.Status';
import getFundingOpportunityCatalog from '@salesforce/apex/ApplicationFormCatalogueController.getFundingOpportunityCatalog';
import removePreconfiguredQuestionAssignments from '@salesforce/apex/ApplicationFormCatalogueController.removePreconfiguredQuestionAssignments';
import createSectionForMode from '@salesforce/apex/ApplicationFormCatalogueController.createSectionForMode';
import updateSection from '@salesforce/apex/ApplicationFormCatalogueController.updateSection';
import createQuestion from '@salesforce/apex/ApplicationFormCatalogueController.createFormQuestion';
import getQuestionForEdit from '@salesforce/apex/ApplicationFormCatalogueController.getQuestionForEdit';
import updateQuestion from '@salesforce/apex/ApplicationFormCatalogueController.updateQuestion';
import setQuestionMandatory from '@salesforce/apex/ApplicationFormCatalogueController.setQuestionMandatory';
import reorderSections from '@salesforce/apex/ApplicationFormCatalogueController.reorderSections';
import moveQuestion from '@salesforce/apex/ApplicationFormCatalogueController.moveQuestion';
import reorderQuestions from '@salesforce/apex/ApplicationFormCatalogueController.reorderQuestions';
import removeQuestionAssignment from '@salesforce/apex/ApplicationFormCatalogueController.removeQuestionAssignment';
import removeSectionAssignments from '@salesforce/apex/ApplicationFormCatalogueController.removeSectionAssignments';
import isTranslationExpected from '@salesforce/apex/ApplicationFormCatalogueController.isTranslationExpected';

// Every user-facing string, in English and in French: the language of the connected user is used.
const LABELS = {
    en: {
        cardTitle: 'Program questionnaire',
        cardTitleEoi: 'EOI questionnaire',
        addQuestion: 'Add a question',
        deleteSelection: 'Delete selection',
        deleteSelectionCount: 'Delete selection ({0})',
        loading: 'Loading',
        emptyCatalog: 'No questions yet. Click "Add a question" to get started.',
        emptySection: 'No questions in this section yet.',
        dragSection: 'Drag to reorder the section',
        dragQuestion: 'Drag to reorder the question',
        lockedSectionIcon: 'Preconfigured section or section containing a Fixed question',
        lockedSectionTitle: 'This section cannot be edited or deleted',
        editSection: 'Edit section',
        deleteSection: 'Delete section',
        editQuestion: 'Edit question',
        deleteQuestion: 'Delete question',
        eoiBadge: 'EOI',
        information: 'Information',
        cancel: 'Cancel',
        save: 'Save',
        delete: 'Delete',

        selectionModal: {
            title: 'Delete the selected clones',
            body: 'The selected preconfigured clones will be permanently removed from this form. '
                + 'The questions of the original template will not be deleted.'
        },

        sectionModal: {
            addTitle: 'Add a section',
            editTitle: 'Edit section',
            sectionLabel: 'Section label'
        },

        questionModal: {
            addTitle: 'Add a question',
            editTitle: 'Edit question',
            draftPrefix: 'The question is saved as',
            draftStatus: 'Draft',
            section: 'Section',
            newSectionOption: '+ New section',
            newSectionName: 'New section name',
            dataType: 'Data type',
            questionTextEn: 'Question text (EN)',
            questionTextFr: 'Question text (FR)',
            questionTextFrHelp: 'Shown to the candidates in French. When left blank, the English text is shown.',
            description: 'Description',
            responseValuesEn: 'Response values (EN)',
            responseValuesFr: 'Response values (FR)',
            responseValuesHelp: 'Enter one value per line (press Enter to add the next one).',
            responseValuesFrHelp: 'One translation per line, in the same order and the same number as the English '
                + 'values: the English value on the same line is saved.',
            helpText: 'Help text',
            maximumCharacters: 'Maximum number of characters',
            maximumCharactersMissing: 'The maximum number of characters is required for Text and Text Area.',
            maximumCharactersUnderflow: 'Enter a number greater than zero.',
            mandatory: 'Mandatory (uncheck for "If applicable")',
            tableColumns: 'Table columns',
            columnName: 'Column name',
            deleteColumn: 'Delete column',
            addColumn: 'Add a column'
        },

        removeModal: {
            title: 'Delete {0}',
            section: 'the section',
            question: 'the question',
            permanentDelete: 'Delete permanently',
            body: 'removes {0} permanently from this Program. Fixed questions and sections can never be deleted here.'
        },

        errors: {
            FUNDING_OPPORTUNITY_REQUIRED: 'A Funding Opportunity is required.',
            LOAD_CONFIGURATION_FAILED: 'Unable to load the Funding Opportunity configuration',
            LOAD_TEMPLATE_QUESTIONS_FAILED: 'Unable to load the Program template questions',
            QUESTION_SELECTION_REQUIRED: 'Select at least one question to add to this Funding Opportunity.',
            ADD_QUESTIONS_FAILED: 'Unable to add the selected questions to this Funding Opportunity',
            SECTION_ID_REQUIRED: 'A section Id is required.',
            SECTION_LABEL_REQUIRED: 'The section label is required.',
            PRECONFIGURED_SECTION_NOT_EDITABLE: 'A preconfigured section cannot be edited.',
            FIXED_SECTION_NOT_EDITABLE: 'A section containing a Fixed question cannot be edited here.',
            UPDATE_SECTION_FAILED: 'Unable to update the section',
            CREATE_SECTION_FAILED: 'Unable to create the section',
            QUESTION_TEXT_REQUIRED: 'The question text is required.',
            QUESTION_SECTION_REQUIRED: 'A section must be selected for this question.',
            OBJECT_API_NAME_REQUIRED: 'An Object API Name is required for a Fixed question.',
            FIELD_API_NAME_REQUIRED: 'A Field API Name is required for a Fixed question.',
            CUSTOM_QUESTION_NAME_TAKEN: 'A CUSTOM question must have a different name from the preconfigured question in this section.',
            CREATE_QUESTION_FAILED: 'Unable to create the question',
            QUESTION_ID_REQUIRED: 'A question Id is required.',
            UPDATE_MANDATORY_FAILED: 'Unable to update the question\'s mandatory status',
            QUESTION_VERSION_NOT_FOUND: 'No version found for this question.',
            LOAD_QUESTION_FAILED: 'Unable to load the question',
            FIXED_QUESTION_NOT_EDITABLE: 'A Fixed question is mapped to a Salesforce field and cannot be edited here.',
            UPDATE_QUESTION_FAILED: 'Unable to update the question',
            READ_PILLAR_FAILED: 'Unable to read the pillar of the program',
            TRANSLATION_LINE_COUNT_MISMATCH: 'The French response values must have as many lines as the English ones, in the same order.',
            LOAD_TABLE_COLUMNS_FAILED: 'Unable to load the table columns',
            PRECONFIGURED_SELECTION_REQUIRED: 'Select at least one preconfigured question to remove.',
            SELECTED_QUESTIONS_NOT_FOUND: 'Some selected questions could not be found for this Funding Opportunity.',
            PROTECTED_QUESTION_NOT_REMOVABLE: 'A Fixed, CRM-mapped or preconfigured question cannot be removed here.',
            SECTION_CANNOT_BE_EMPTY: 'A section must contain at least one question. Delete the section itself instead.',
            REMOVE_CLONES_FAILED: 'Unable to remove the preconfigured question clones',
            ASSIGNMENT_ID_REQUIRED: 'An assignment Id is required.',
            FIXED_QUESTION_NOT_REMOVABLE: 'A Fixed question is mapped to a Salesforce field and cannot be removed here.',
            REMOVE_QUESTION_FAILED: 'Unable to remove the question',
            PRECONFIGURED_SECTION_NOT_REMOVABLE: 'A preconfigured section cannot be removed.',
            FIXED_SECTION_NOT_REMOVABLE: 'A section containing a Fixed question cannot be removed here.',
            REMOVE_SECTION_FAILED: 'Unable to remove the section',
            REORDER_SECTIONS_FAILED: 'Unable to reorder the sections',
            QUESTION_ASSIGNMENT_ID_REQUIRED: 'A question assignment Id is required.',
            TARGET_SECTION_ID_REQUIRED: 'A target section Id is required.',
            FIXED_QUESTION_NOT_MOVABLE: 'A Fixed question cannot be moved.',
            MOVE_QUESTION_FAILED: 'Unable to move the question',
            REORDER_QUESTIONS_FAILED: 'Unable to reorder the questions',
            FUNDING_OPPORTUNITY_NOT_ACTIVE: 'The questionnaire can only be modified while the Funding Opportunity status is Active.',
            QUESTION_CATEGORY_REQUIRED: 'At least one active Question Category is required.',
            PRECONFIGURED_CLONE_NOT_EDITABLE: 'A preconfigured question clone cannot be modified.',
            MAXIMUM_CHARACTERS_REQUIRED: 'Maximum Characters is required when Data Type is Text or Text Area.',
            MAXIMUM_CHARACTERS_INVALID: 'The maximum character count must be a positive whole number.'
        },

        feedback: {
            successTitle: 'Success',
            errorTitle: 'Error',
            unexpectedError: 'An unexpected error occurred.',
            sectionUpdated: 'Section updated.',
            sectionAdded: 'Section added.',
            questionUpdated: 'Question updated.',
            questionAdded: 'Question added.',
            mandatoryOn: 'The question is now mandatory.',
            mandatoryOff: 'The question is now marked "If applicable".',
            deletedPermanently: 'Permanently deleted.',
            clonesDeleted: '{0} clone(s) removed from the form.',
            clonesDeletedWithErrors: '{0} clone(s) deleted. {1}',
            preconfiguredReorder: 'A preconfigured question can only be reordered within its own section.'
        },

        dataTypes: {
            Text: 'Text',
            TextArea: 'Text Area',
            Integer: 'Integer',
            Decimal: 'Decimal',
            Currency: 'Currency',
            Date: 'Date',
            DateTime: 'Date/Time',
            Email: 'Email',
            Telephone: 'Telephone',
            URL: 'URL',
            RadioGroup: 'Radio Group',
            Select: 'Select',
            Multiselect: 'Multiselect',
            Checkbox: 'Checkbox',
            File: 'File',
            Table: 'Table'
        }
    },

    fr: {
        cardTitle: 'Questionnaire du Programme',
        cardTitleEoi: 'Questionnaire EOI',
        addQuestion: 'Ajouter une question',
        deleteSelection: 'Supprimer la sélection',
        deleteSelectionCount: 'Supprimer la sélection ({0})',
        loading: 'Chargement',
        emptyCatalog: 'Aucune question pour l\'instant. Cliquez sur « Ajouter une question » pour commencer.',
        emptySection: 'Aucune question dans cette section pour l\'instant.',
        dragSection: 'Glisser pour réordonner la section',
        dragQuestion: 'Glisser pour réordonner la question',
        lockedSectionIcon: 'Section préconfigurée ou contenant une question Fixed',
        lockedSectionTitle: 'Cette section ne peut pas être modifiée ou supprimée',
        editSection: 'Modifier la section',
        deleteSection: 'Supprimer la section',
        editQuestion: 'Modifier la question',
        deleteQuestion: 'Supprimer la question',
        eoiBadge: 'EOI',
        information: 'Informations',
        cancel: 'Annuler',
        save: 'Enregistrer',
        delete: 'Supprimer',

        selectionModal: {
            title: 'Supprimer les clones sélectionnés',
            body: 'Les clones préconfigurés sélectionnés seront retirés définitivement de ce formulaire. '
                + 'Les questions du template d\'origine ne seront pas supprimées.'
        },

        sectionModal: {
            addTitle: 'Ajouter une section',
            editTitle: 'Modifier la section',
            sectionLabel: 'Libellé de la section'
        },

        questionModal: {
            addTitle: 'Ajouter une question',
            editTitle: 'Modifier la question',
            draftPrefix: 'La question est enregistrée en',
            draftStatus: 'Brouillon',
            section: 'Section',
            newSectionOption: '+ Nouvelle section',
            newSectionName: 'Nom de la nouvelle section',
            dataType: 'Type de donnée',
            questionTextEn: 'Texte de la question (EN)',
            questionTextFr: 'Texte de la question (FR)',
            questionTextFrHelp: 'Affiché aux candidats en français. Laissé vide, le texte anglais est affiché.',
            description: 'Description',
            responseValuesEn: 'Valeurs de réponse (EN)',
            responseValuesFr: 'Valeurs de réponse (FR)',
            responseValuesHelp: 'Saisissez une valeur par ligne (appuyez sur Entrée pour ajouter la suivante).',
            responseValuesFrHelp: 'Une traduction par ligne, dans le même ordre et en même nombre que les valeurs '
                + 'anglaises : la valeur anglaise de la même ligne est enregistrée.',
            helpText: 'Texte d\'aide',
            maximumCharacters: 'Nombre maximum de caractères',
            maximumCharactersMissing: 'Le nombre maximum de caractères est obligatoire pour Text et Text Area.',
            maximumCharactersUnderflow: 'Saisissez un nombre supérieur à zéro.',
            mandatory: 'Obligatoire (décocher pour « Si applicable »)',
            tableColumns: 'Colonnes du tableau',
            columnName: 'Nom de la colonne',
            deleteColumn: 'Supprimer la colonne',
            addColumn: 'Ajouter une colonne'
        },

        removeModal: {
            title: 'Supprimer {0}',
            section: 'la section',
            question: 'la question',
            permanentDelete: 'Supprimer définitivement',
            body: 'retire {0} de façon définitive de ce Programme. '
                + 'Les questions/sections Fixed ne peuvent jamais être supprimées ici.'
        },

        errors: {
            FUNDING_OPPORTUNITY_REQUIRED: 'Un programme est requis.',
            LOAD_CONFIGURATION_FAILED: 'Impossible de charger la configuration du programme',
            LOAD_TEMPLATE_QUESTIONS_FAILED: 'Impossible de charger les questions modèles du pilier',
            QUESTION_SELECTION_REQUIRED: 'Sélectionnez au moins une question à ajouter à ce programme.',
            ADD_QUESTIONS_FAILED: 'Impossible d\'ajouter les questions sélectionnées à ce programme',
            SECTION_ID_REQUIRED: 'L\'identifiant de la section est requis.',
            SECTION_LABEL_REQUIRED: 'Le libellé de la section est requis.',
            PRECONFIGURED_SECTION_NOT_EDITABLE: 'Une section préconfigurée ne peut pas être modifiée.',
            FIXED_SECTION_NOT_EDITABLE: 'Une section contenant une question fixe ne peut pas être modifiée ici.',
            UPDATE_SECTION_FAILED: 'Impossible de mettre à jour la section',
            CREATE_SECTION_FAILED: 'Impossible de créer la section',
            QUESTION_TEXT_REQUIRED: 'Le texte de la question est requis.',
            QUESTION_SECTION_REQUIRED: 'Une section doit être sélectionnée pour cette question.',
            OBJECT_API_NAME_REQUIRED: 'Le nom API de l\'objet est requis pour une question fixe.',
            FIELD_API_NAME_REQUIRED: 'Le nom API du champ est requis pour une question fixe.',
            CUSTOM_QUESTION_NAME_TAKEN: 'Une question personnalisée doit avoir un nom différent de la question préconfigurée de cette section.',
            CREATE_QUESTION_FAILED: 'Impossible de créer la question',
            QUESTION_ID_REQUIRED: 'L\'identifiant de la question est requis.',
            UPDATE_MANDATORY_FAILED: 'Impossible de mettre à jour le caractère obligatoire de la question',
            QUESTION_VERSION_NOT_FOUND: 'Aucune version trouvée pour cette question.',
            LOAD_QUESTION_FAILED: 'Impossible de charger la question',
            FIXED_QUESTION_NOT_EDITABLE: 'Une question fixe est liée à un champ Salesforce et ne peut pas être modifiée ici.',
            UPDATE_QUESTION_FAILED: 'Impossible de mettre à jour la question',
            READ_PILLAR_FAILED: 'Impossible de lire le pilier du programme',
            TRANSLATION_LINE_COUNT_MISMATCH: 'Les valeurs de réponse en français doivent avoir autant de lignes que les valeurs en anglais, dans le même ordre.',
            LOAD_TABLE_COLUMNS_FAILED: 'Impossible de charger les colonnes du tableau',
            PRECONFIGURED_SELECTION_REQUIRED: 'Sélectionnez au moins une question préconfigurée à supprimer.',
            SELECTED_QUESTIONS_NOT_FOUND: 'Certaines questions sélectionnées sont introuvables pour ce programme.',
            PROTECTED_QUESTION_NOT_REMOVABLE: 'Une question fixe, liée au CRM ou préconfigurée ne peut pas être supprimée ici.',
            SECTION_CANNOT_BE_EMPTY: 'Une section doit contenir au moins une question. Supprimez plutôt la section elle-même.',
            REMOVE_CLONES_FAILED: 'Impossible de supprimer les copies des questions préconfigurées',
            ASSIGNMENT_ID_REQUIRED: 'L\'identifiant de l\'affectation est requis.',
            FIXED_QUESTION_NOT_REMOVABLE: 'Une question fixe est liée à un champ Salesforce et ne peut pas être supprimée ici.',
            REMOVE_QUESTION_FAILED: 'Impossible de supprimer la question',
            PRECONFIGURED_SECTION_NOT_REMOVABLE: 'Une section préconfigurée ne peut pas être supprimée.',
            FIXED_SECTION_NOT_REMOVABLE: 'Une section contenant une question fixe ne peut pas être supprimée ici.',
            REMOVE_SECTION_FAILED: 'Impossible de supprimer la section',
            REORDER_SECTIONS_FAILED: 'Impossible de réordonner les sections',
            QUESTION_ASSIGNMENT_ID_REQUIRED: 'L\'identifiant de l\'affectation de la question est requis.',
            TARGET_SECTION_ID_REQUIRED: 'L\'identifiant de la section cible est requis.',
            FIXED_QUESTION_NOT_MOVABLE: 'Une question fixe ne peut pas être déplacée.',
            MOVE_QUESTION_FAILED: 'Impossible de déplacer la question',
            REORDER_QUESTIONS_FAILED: 'Impossible de réordonner les questions',
            FUNDING_OPPORTUNITY_NOT_ACTIVE: 'Le questionnaire ne peut être modifié que lorsque le statut du programme est Actif.',
            QUESTION_CATEGORY_REQUIRED: 'Au moins une catégorie de question active est requise.',
            PRECONFIGURED_CLONE_NOT_EDITABLE: 'La copie d\'une question préconfigurée ne peut pas être modifiée.',
            MAXIMUM_CHARACTERS_REQUIRED: 'Le nombre maximum de caractères est requis lorsque le type de donnée est Texte ou Zone de texte.',
            MAXIMUM_CHARACTERS_INVALID: 'Le nombre maximum de caractères doit être un nombre entier positif.'
        },

        feedback: {
            successTitle: 'Succès',
            errorTitle: 'Erreur',
            unexpectedError: 'Une erreur inattendue est survenue.',
            sectionUpdated: 'Section modifiée.',
            sectionAdded: 'Section ajoutée.',
            questionUpdated: 'Question modifiée.',
            questionAdded: 'Question ajoutée.',
            mandatoryOn: 'La question est maintenant obligatoire.',
            mandatoryOff: 'La question est maintenant marquée « Si applicable ».',
            deletedPermanently: 'Supprimé définitivement.',
            clonesDeleted: '{0} clone(s) supprimé(s) du formulaire.',
            clonesDeletedWithErrors: '{0} clone(s) supprimé(s). {1}',
            preconfiguredReorder: 'Une question préconfigurée ne peut être réordonnée qu\'à l\'intérieur de sa propre section.'
        },

        dataTypes: {
            Text: 'Texte',
            TextArea: 'Zone de texte',
            Integer: 'Entier',
            Decimal: 'Décimal',
            Currency: 'Devise',
            Date: 'Date',
            DateTime: 'Date/Heure',
            Email: 'E-mail',
            Telephone: 'Téléphone',
            URL: 'URL',
            RadioGroup: 'Boutons radio',
            Select: 'Liste de sélection',
            Multiselect: 'Sélection multiple',
            Checkbox: 'Case à cocher',
            File: 'Fichier',
            Table: 'Tableau'
        }
    }
};

const UI_LABELS = USER_LANGUAGE.toLowerCase().startsWith('fr') ? LABELS.fr : LABELS.en;

// Replaces {0}, {1}... with the given values.
function formatLabel(template, ...values) {
    return values.reduce((text, value, index) => text.replace(`{${index}}`, value), template);
}

const EDITABLE_STATUSES = ['Active'];

const DATA_TYPE_OPTIONS = Object.keys(UI_LABELS.dataTypes).map((value) => ({
    label: UI_LABELS.dataTypes[value],
    value
}));

const COLUMN_DATA_TYPE_OPTIONS = DATA_TYPE_OPTIONS.filter(
    (option) => !['File', 'Multiselect', 'RadioGroup', 'Select', 'Table'].includes(option.value)
);

const DATA_TYPES_WITH_RESPONSE_VALUES = ['RadioGroup', 'Select', 'Multiselect'];
const TABLE_FALLBACK_DATA_TYPE = 'TextBlock';
const NEW_SECTION_OPTION_VALUE = '__new_section__';

const NEW_QUESTION_FORM_DEFAULTS = {
    text: '',
    textFr: '',
    dataType: 'Text',
    description: '',
    responseValues: '',
    responseValuesFr: '',
    helpText: '',
    maximumCharacters: null,
    isTable: false,
    isMandatory: true
};

// Apex returns { code, params, detail } as JSON: the code is shown in the language of the user, any other
// message is shown as is.
function translateError(message) {
    if (!message) {
        return UI_LABELS.feedback.unexpectedError;
    }
    try {
        const parsed = JSON.parse(message);
        if (parsed?.code) {
            return UI_LABELS.errors[parsed.code] || UI_LABELS.feedback.unexpectedError;
        }
    } catch (e) {
        // Not a JSON error payload: show the message as is.
    }
    return message;
}

function reorderArray(array, idKey, fromId, toId) {
    if (!fromId || fromId === toId) {
        return null;
    }
    const order = [...array];
    const fromIndex = order.findIndex((item) => item[idKey] === fromId);
    const toIndex = order.findIndex((item) => item[idKey] === toId);
    if (fromIndex === -1 || toIndex === -1) {
        return null;
    }
    const [moved] = order.splice(fromIndex, 1);
    order.splice(toIndex, 0, moved);
    return order;
}

function moveItem(sourceList, targetList, idKey, itemId, beforeId, isSameList) {
    const item = sourceList.find((i) => i[idKey] === itemId);
    if (!item) {
        return null;
    }
    const newSource = sourceList.filter((i) => i[idKey] !== itemId);
    const newTarget = isSameList ? newSource : [...targetList];
    const insertAt = beforeId ? newTarget.findIndex((i) => i[idKey] === beforeId) : -1;
    newTarget.splice(insertAt === -1 ? newTarget.length : insertAt, 0, item);
    return { item, newSource, newTarget };
}

export default class ApplicationFormCatalogueBuilder extends LightningElement {
    @api recordId;
    @api eoi = false;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [FUNDING_OPPORTUNITY_STATUS_FIELD]
    })
    fundingOpportunityRecord;

    // Every pillar but Science: the question text and response values are also entered in French.
    @wire(isTranslationExpected, { fundingOpportunityId: '$recordId' })
    translationExpected;

    sections = [];
    dataTypeOptions = DATA_TYPE_OPTIONS;
    columnDataTypeOptions = COLUMN_DATA_TYPE_OPTIONS;

    selectedPreconfiguredAssignmentIds = [];

    isLoading = true;
    isSaving = false;
    isSelectionConfirmationModalOpen = false;

    draggedSectionId;
    draggedQuestionId;
    draggedQuestionSectionId;
    dropTargetAssignmentId;
    dropAfterTarget = false;

    isSectionModalOpen = false;
    newSectionLabel = '';
    editingSectionId;

    isQuestionModalOpen = false;
    questionForm = { ...NEW_QUESTION_FORM_DEFAULTS };
    questionColumns = [];
    activeSectionId;
    editingQuestionId;
    columnKeySeed = 0;
    selectedNewQuestionSectionId = '';
    newQuestionSectionName = '';

    isRemoveModalOpen = false;
    removeTargetId;
    removeTargetType;

    connectedCallback() {
        this.refresh();
    }

    get labels() {
        return UI_LABELS;
    }

    get cardTitle() {
        return this.eoi ? UI_LABELS.cardTitleEoi : UI_LABELS.cardTitle;
    }

    get fundingOpportunityStatus() {
        return getFieldValue(
            this.fundingOpportunityRecord.data,
            FUNDING_OPPORTUNITY_STATUS_FIELD
        );
    }

    // Enable the form builder only when the program status is Active
    get isCatalogLocked() {
        return (
            this.fundingOpportunityStatus != null &&
            !EDITABLE_STATUSES.includes(this.fundingOpportunityStatus)
        );
    }

    get sectionModalTitle() {
        return this.editingSectionId ? UI_LABELS.sectionModal.editTitle : UI_LABELS.sectionModal.addTitle;
    }

    get questionModalTitle() {
        return this.editingQuestionId ? UI_LABELS.questionModal.editTitle : UI_LABELS.questionModal.addTitle;
    }

    // Le picklist "Section" est affiché à chaque création de question (bouton d'en-tête ou "+"
    // sur une section existante — dans ce cas la section est pré-sélectionnée mais reste
    // modifiable). Il liste les sections déjà présentes sur cette FO pour le mode courant
    // (Full Application ou EOI), plus une option pour en créer une.
    get isNewQuestionSection() {
        return !this.editingQuestionId;
    }

    get existingSectionOptions() {
        const options = this.catalogSections.map((section) => ({
            label: section.label,
            value: section.sectionId
        }));
        options.push({ label: UI_LABELS.questionModal.newSectionOption, value: NEW_SECTION_OPTION_VALUE });
        return options;
    }

    get isCreatingNewSection() {
        return this.selectedNewQuestionSectionId === NEW_SECTION_OPTION_VALUE;
    }

    // Accesseurs pour la modale d'édition/ajout de question
    get hasFrenchFields() {
        return this.translationExpected?.data === true;
    }

    // The main text and values are always the English ones, Science included: their label says so.
    get questionTextLabel() {
        return UI_LABELS.questionModal.questionTextEn;
    }

    get questionResponseValuesLabel() {
        return UI_LABELS.questionModal.responseValuesEn;
    }

    get responseValuesSizeClass() {
        return this.hasFrenchFields
            ? 'slds-col slds-size_1-of-1 slds-medium-size_1-of-2 slds-p-bottom_small'
            : 'slds-col slds-size_1-of-1 slds-p-bottom_small';
    }

    get questionText() {
        return this.questionForm.text;
    }

    get questionTextFr() {
        return this.questionForm.textFr;
    }

    get questionResponseValuesFr() {
        return this.questionForm.responseValuesFr;
    }

    get questionDataType() {
        return this.questionForm.dataType;
    }

    get questionDescription() {
        return this.questionForm.description;
    }

    get questionResponseValues() {
        return this.questionForm.responseValues;
    }

    get questionHelpText() {
        return this.questionForm.helpText;
    }

    get questionMaximumCharacters() {
        return this.questionForm.maximumCharacters;
    }

    get questionSupportsMaximumCharacters() {
        return ['Text', 'TextArea', 'Email', 'Telephone', 'URL'].includes(this.questionForm.dataType);
    }

    get questionRequiresMaximumCharacters() {
        return this.questionForm.dataType === 'Text' || this.questionForm.dataType === 'TextArea';
    }

    get questionIsTable() {
        return this.questionForm.isTable;
    }

    get questionIsMandatory() {
        return this.questionForm.isMandatory;
    }

    get questionHasResponseValues() {
        return DATA_TYPES_WITH_RESPONSE_VALUES.includes(this.questionForm.dataType);
    }

    async loadCatalog() {
        try {
            const result = await getFundingOpportunityCatalog({ fundingOpportunityId: this.recordId });
            this.sections = (result || []).map((section) => {
                const questions = (section.questions || []).map((question) => ({
                    ...question,
                    displayType: UI_LABELS.dataTypes[question.isTable ? 'Table' : question.dataType] || question.dataType
                }));
                return {
                    ...section,
                    isExpanded: true,
                    sectionClass: 'slds-accordion__section slds-is-open',
                    isLocked: questions.some((q) => q.isFixed || (q.objectApiName && q.fieldApiName)),
                    questions
                };
            });
        } catch (error) {
            this.showError(error);
        }
    }

    async refresh() {
        this.isLoading = true;
        try {
            await this.loadCatalog();
        } finally {
            this.isLoading = false;
        }
    }

    // Les clones préconfigurés peuvent uniquement être sélectionnés pour suppression.
    // Les questions CUSTOM Dynamic conservent les actions d'édition, suppression et déplacement.
    get catalogSections() {
        return this.sections
            .map((section) => {
                const isSectionLocked =
                    this.isCatalogLocked || section.isLocked || section.isPreconfigured;
                const questions = section.questions
                    .filter((question) => !!question.isEOI === !!this.eoi)
                    .map((question) => this.toAttachedQuestion(question));
                return {
                    ...section,
                    isVisibleForMode: questions.length > 0 || section.questions.length === 0,
                    isSectionLocked,
                    isEditable: !isSectionLocked,
                    canAddQuestion: !this.isCatalogLocked,
                    canDrag: !isSectionLocked,
                    draggableValue: isSectionLocked ? 'false' : 'true',
                    questions
                };
            })
            .filter((section) => section.isVisibleForMode);
    }

    toAttachedQuestion(question) {
        const isMappedToCrm = !!(question.objectApiName && question.fieldApiName);
        const isCustomDynamic =
            !this.isCatalogLocked && !question.isFixed && !question.isPreconfigured && !isMappedToCrm;
        return {
            ...question,
            isAttached: true,
            isSelected: this.selectedPreconfiguredAssignmentIds.includes(question.assignmentId),
            canSelectForRemoval: isCustomDynamic,
            canDrag: !this.isCatalogLocked,
            canEdit: isCustomDynamic,
            canDelete: false,
            draggableValue: !this.isCatalogLocked ? 'true' : 'false',
            showEoiBadge: this.eoi === true || question.isEOI === true,
            itemClass: 'slds-item slds-box slds-box_x-small slds-m-bottom_xx-small'
                + (question.assignmentId === this.dropTargetAssignmentId
                    ? (this.dropAfterTarget ? ' catalogue-drop-target-after' : ' catalogue-drop-target-before')
                    : '')
        };
    }

    get hasCatalogSections() {
        return this.catalogSections.length > 0;
    }

    get hasSelectedPreconfiguredQuestions() {
        return this.selectedPreconfiguredAssignmentIds.length > 0;
    }

    get isConfirmSelectionDisabled() {
        return this.isCatalogLocked || this.isSaving || !this.hasSelectedPreconfiguredQuestions;
    }

    get confirmSelectionLabel() {
        const selectedCount = this.selectedPreconfiguredAssignmentIds.length;
        return selectedCount > 0
            ? formatLabel(UI_LABELS.deleteSelectionCount, selectedCount)
            : UI_LABELS.deleteSelection;
    }

    handleTemplateQuestionToggle(event) {
        if (this.isCatalogLocked) {
            return;
        }
        const assignmentId = event.currentTarget.dataset.id;
        this.selectedPreconfiguredAssignmentIds = event.target.checked
            ? [...this.selectedPreconfiguredAssignmentIds, assignmentId]
            : this.selectedPreconfiguredAssignmentIds.filter((id) => id !== assignmentId);
    }

    openSelectionConfirmationModal() {
        if (this.isConfirmSelectionDisabled) {
            return;
        }
        this.isSelectionConfirmationModalOpen = true;
    }

    closeSelectionConfirmationModal() {
        if (!this.isSaving) {
            this.isSelectionConfirmationModalOpen = false;
        }
    }

    async confirmSelectedTemplateQuestions() {
        if (this.isConfirmSelectionDisabled) {
            return;
        }
        this.isSaving = true;
        try {
            const result = await removePreconfiguredQuestionAssignments({
                fundingOpportunityId: this.recordId,
                assignmentIds: this.selectedPreconfiguredAssignmentIds
            });
            if (result.errorMessages?.length) {
                this.showError({
                    message: formatLabel(
                        UI_LABELS.feedback.clonesDeletedWithErrors,
                        result.deletedCount,
                        result.errorMessages.join(' | ')
                    )
                });
            } else {
                this.showSuccess(formatLabel(UI_LABELS.feedback.clonesDeleted, result.deletedCount));
            }
            this.selectedPreconfiguredAssignmentIds = [];
            await this.refresh();
            this.isSelectionConfirmationModalOpen = false;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    // Gestion du basculement afficher/masquer d'une section, qu'elle soit rattachée à ce
    // Programme ou issue du pool Socle Commun / Pilier.
    handleToggleSection(event) {
        const sectionId = event.currentTarget.dataset.id;
        this.sections = this.toggleSectionExpansion(this.sections, sectionId);
    }

    toggleSectionExpansion(sections, sectionId) {
        return sections.map((section) =>
            section.sectionId === sectionId
                ? {
                      ...section,
                      isExpanded: !section.isExpanded,
                      sectionClass: `slds-accordion__section${!section.isExpanded ? ' slds-is-open' : ''}`
                  }
                : section
        );
    }

    // Gestion du Drag & Drop des sections
    handleSectionDragStart(event) {
        const sectionId = event.currentTarget.dataset.id;
        const section = this.sections.find((s) => s.sectionId === sectionId);
        if (this.isCatalogLocked || !section || section.isLocked || section.isPreconfigured) {
            event.preventDefault();
            return;
        }
        this.draggedSectionId = sectionId;
        event.dataTransfer.effectAllowed = 'move';
    }

    handleSectionDragOver(event) {
        event.preventDefault();
    }

    async handleSectionDrop(event) {
        event.preventDefault();
        if (this.isCatalogLocked) {
            return;
        }
        const targetId = event.currentTarget.dataset.id;

        // A question can be dropped into any section; only the reordering of sections is
        // restricted to sections that are neither locked nor preconfigured.
        if (this.draggedQuestionId) {
            await this.moveQuestionTo(targetId, null);
            return;
        }

        const targetSection = this.sections.find((s) => s.sectionId === targetId);
        if (targetSection && (targetSection.isLocked || targetSection.isPreconfigured)) {
            this.draggedSectionId = null;
            return;
        }

        // Only the sections of the current mode (EOI or full application) are reordered: the
        // sections of the other mode keep their place and their numbers.
        const isInCurrentMode = (section) =>
            section.questions.length === 0 ||
            section.questions.some((question) => !!question.isEOI === !!this.eoi);
        const modeSections = this.sections.filter(isInCurrentMode);
        const reorderedModeSections = reorderArray(
            modeSections,
            'sectionId',
            this.draggedSectionId,
            targetId
        );
        this.draggedSectionId = null;
        if (!reorderedModeSections) {
            return;
        }
        const remainingModeSections = [...reorderedModeSections];
        this.sections = this.sections.map((section) =>
            isInCurrentMode(section) ? remainingModeSections.shift() : section
        );

        try {
            const orderedSectionIds = reorderedModeSections.map((s) => s.sectionId);
            await reorderSections({ orderedSectionIds });
        } catch (error) {
            this.showError(error);
            await this.refresh();
        }
    }

    // Gestion du Drag & Drop des questions
    handleQuestionDragStart(event) {
        const questionId = event.currentTarget.dataset.id;
        const sectionId = event.currentTarget.dataset.sectionId;
        const section = this.sections.find((s) => s.sectionId === sectionId);
        const question = section && section.questions.find((q) => q.assignmentId === questionId);
        if (this.isCatalogLocked || !question) {
            event.preventDefault();
            return;
        }
        this.draggedQuestionId = questionId;
        this.draggedQuestionSectionId = sectionId;
        event.dataTransfer.effectAllowed = 'move';
        event.stopPropagation();
    }

    handleQuestionDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        const targetId = event.currentTarget.dataset.id;
        if (!this.draggedQuestionId || targetId === this.draggedQuestionId) {
            return;
        }
        // Drop above the target's vertical midpoint inserts before it, below inserts after —
        // this is what lets a question be dropped past the last row of its section.
        const rect = event.currentTarget.getBoundingClientRect();
        const isAfter = event.clientY - rect.top > rect.height / 2;
        if (this.dropTargetAssignmentId !== targetId || this.dropAfterTarget !== isAfter) {
            this.dropTargetAssignmentId = targetId;
            this.dropAfterTarget = isAfter;
        }
    }

    handleQuestionDragLeave(event) {
        event.stopPropagation();
        if (this.dropTargetAssignmentId === event.currentTarget.dataset.id) {
            this.dropTargetAssignmentId = null;
            this.dropAfterTarget = false;
        }
    }

    async handleQuestionDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.isCatalogLocked) {
            return;
        }

        const targetSectionId = event.currentTarget.dataset.sectionId;
        const targetQuestionId = event.currentTarget.dataset.id;
        if (targetQuestionId === this.draggedQuestionId) {
            return;
        }

        let beforeAssignmentId = targetQuestionId;
        if (this.dropAfterTarget) {
            const targetSection = this.sections.find((s) => s.sectionId === targetSectionId);
            // Exclude the dragged item itself before locating "the one right after the target",
            // otherwise dropping just after a target whose next sibling is the dragged item would
            // wrongly resolve to "append at the very end" instead of leaving it where it is.
            const questionsWithoutDragged = targetSection
                ? targetSection.questions.filter((q) => q.assignmentId !== this.draggedQuestionId)
                : [];
            const targetIndex = questionsWithoutDragged.findIndex((q) => q.assignmentId === targetQuestionId);
            const nextQuestion = targetIndex === -1 ? null : questionsWithoutDragged[targetIndex + 1];
            // null means "append at the end of the section" (see moveItem's insertAt fallback).
            beforeAssignmentId = nextQuestion ? nextQuestion.assignmentId : null;
        }

        await this.moveQuestionTo(targetSectionId, beforeAssignmentId);
    }

    async moveQuestionTo(targetSectionId, beforeAssignmentId) {
        this.dropTargetAssignmentId = null;
        this.dropAfterTarget = false;
        if (this.isCatalogLocked) {
            return;
        }
        const draggedId = this.draggedQuestionId;
        const sourceSectionId = this.draggedQuestionSectionId;
        this.draggedQuestionId = null;
        this.draggedQuestionSectionId = null;
        if (!draggedId) {
            return;
        }

        const sourceSection = this.sections.find((s) => s.sectionId === sourceSectionId);
        const targetSection = this.sections.find((s) => s.sectionId === targetSectionId);
        if (!sourceSection || !targetSection) {
            return;
        }
        const isSameSection = sourceSectionId === targetSectionId;

        const draggedQuestion = sourceSection.questions.find((q) => q.assignmentId === draggedId);
        const isLockedQuestion = !!(
            draggedQuestion
            && (draggedQuestion.isFixed
                || draggedQuestion.isPreconfigured
                || (draggedQuestion.objectApiName && draggedQuestion.fieldApiName))
        );
        // A Fixed/CRM-mapped/preconfigured question can be reordered within its own section, but
        // never moved out of it — its section membership is part of the catalog's template.
        if (isLockedQuestion && !isSameSection) {
            this.showError(new Error(UI_LABELS.feedback.preconfiguredReorder));
            return;
        }

        const moved = moveItem(
            sourceSection.questions,
            targetSection.questions,
            'assignmentId',
            draggedId,
            beforeAssignmentId,
            isSameSection
        );
        if (!moved) {
            return;
        }

        this.sections = this.sections.map((s) => {
            if (s.sectionId === targetSectionId) {
                return { ...s, questions: moved.newTarget };
            }
            if (!isSameSection && s.sectionId === sourceSectionId) {
                return { ...s, questions: moved.newSource };
            }
            return s;
        });

        try {
            if (isLockedQuestion) {
                // Same section only (enforced above): reorder in place, bypassing moveQuestion's
                // Fixed/CRM guard which is meant for actual cross-section moves.
                await reorderQuestions({
                    orderedAssignmentIds: moved.newTarget.map((q) => q.assignmentId)
                });
            } else {
                await moveQuestion({
                    assignmentId: draggedId,
                    targetSectionId,
                    targetSectionOrderedAssignmentIds: moved.newTarget.map((q) => q.assignmentId)
                });
            }
        } catch (error) {
            this.showError(error);
            await this.refresh();
        }
    }

    // Gestion de la modale de Section (renommage uniquement — la création se fait désormais
    // via le modal de question, qui crée sa section cible à la volée si besoin)
    openEditSectionModal(event) {
        const sectionId = event.currentTarget.dataset.id;
        const section = this.sections.find((s) => s.sectionId === sectionId);
        if (this.isCatalogLocked || !section || section.isLocked || section.isPreconfigured) {
            return;
        }
        this.editingSectionId = sectionId;
        this.newSectionLabel = section.label;
        this.isSectionModalOpen = true;
    }

    closeSectionModal() {
        this.isSectionModalOpen = false;
    }

    handleNewSectionLabelChange(event) {
        this.newSectionLabel = event.target.value;
    }

    async saveSection() {
        const labelField = this.template.querySelector('.section-label-field');
        if (this.isSaving || (labelField && !labelField.reportValidity())) {
            return;
        }
        this.isSaving = true;
        try {
            const label = this.newSectionLabel.trim();
            if (this.editingSectionId) {
                await updateSection({ sectionId: this.editingSectionId, label });
                this.showSuccess(UI_LABELS.feedback.sectionUpdated);
            } else {
                await createSectionForMode({
                    label,
                    fundingOpportunityId: this.recordId,
                    isEoi: this.eoi === true
                });
                this.showSuccess(UI_LABELS.feedback.sectionAdded);
            }
            this.isSectionModalOpen = false;
            await this.refresh();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    // Gestion de la modale de Question
    openAddQuestionModal(event) {
        if (this.isCatalogLocked) {
            return;
        }
        this.editingQuestionId = null;
        this.activeSectionId = event.currentTarget.dataset.sectionId;
        // Opened from a section's own "+" button: pre-select that section in the picklist
        // (still changeable). Opened from the header button: no preselection.
        this.selectedNewQuestionSectionId = this.activeSectionId || '';
        this.newQuestionSectionName = '';
        this.questionForm = { ...NEW_QUESTION_FORM_DEFAULTS };
        this.questionColumns = [];
        this.isQuestionModalOpen = true;
    }

    handleNewQuestionSectionChange(event) {
        this.selectedNewQuestionSectionId = event.detail.value;
        if (this.selectedNewQuestionSectionId !== NEW_SECTION_OPTION_VALUE) {
            this.newQuestionSectionName = '';
        }
    }

    handleNewQuestionSectionNameChange(event) {
        this.newQuestionSectionName = event.target.value;
    }

    async openEditQuestionModal(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const sectionId = event.currentTarget.dataset.sectionId;
        const section = this.sections.find((item) => item.sectionId === sectionId);
        const question = section?.questions.find((item) => item.questionId === questionId);
        if (
            this.isCatalogLocked ||
            this.isSaving ||
            !question ||
            question.isFixed ||
            question.isPreconfigured ||
            (question.objectApiName && question.fieldApiName)
        ) {
            return;
        }
        this.isSaving = true;
        try {
            const detail = await getQuestionForEdit({ questionId });
            this.editingQuestionId = questionId;
            this.activeSectionId = sectionId;
            this.questionForm = {
                text: detail.questionText || '',
                textFr: detail.questionTextFr || '',
                dataType: detail.isTable ? 'Table' : detail.dataType,
                description: detail.description || '',
                responseValues: detail.responseValues || '',
                responseValuesFr: detail.responseValuesFr || '',
                helpText: detail.helpText || '',
                maximumCharacters: detail.maximumCharacters || null,
                isTable: !!detail.isTable,
                isMandatory: detail.isMandatory !== false
            };
            this.columnKeySeed = 0;
            this.questionColumns = (detail.columns || []).map((column) => {
                this.columnKeySeed += 1;
                return { key: `col-${this.columnKeySeed}`, label: column.label, dataType: column.dataType };
            });
            this.isQuestionModalOpen = true;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    closeQuestionModal() {
        this.isQuestionModalOpen = false;
    }

    handleQuestionTextChange(event) {
        this.questionForm = { ...this.questionForm, text: event.target.value };
    }

    handleQuestionTextFrChange(event) {
        this.questionForm = { ...this.questionForm, textFr: event.target.value };
    }

    handleQuestionResponseValuesFrChange(event) {
        this.questionForm = { ...this.questionForm, responseValuesFr: event.target.value };
    }

    handleQuestionDataTypeChange(event) {
        const dataType = event.detail.value;
        this.questionForm = { ...this.questionForm, dataType, isTable: dataType === 'Table' };
        if (this.questionForm.isTable && this.questionColumns.length === 0) {
            this.handleAddColumn();
        }
    }

    handleQuestionDescriptionChange(event) {
        this.questionForm = { ...this.questionForm, description: event.target.value };
    }

    handleQuestionResponseValuesChange(event) {
        this.questionForm = { ...this.questionForm, responseValues: event.target.value };
    }

    handleQuestionHelpTextChange(event) {
        this.questionForm = { ...this.questionForm, helpText: event.target.value };
    }

    handleQuestionMaximumCharactersChange(event) {
        const value = event.target.value;
        this.questionForm = {
            ...this.questionForm,
            maximumCharacters: value === '' || value == null ? null : Number(value)
        };
    }

    handleQuestionIsMandatoryChange(event) {
        this.questionForm = { ...this.questionForm, isMandatory: event.target.checked };
    }

    // Modification dynamique depuis la liste si une checkbox de statut y est présente
    async handleListMandatoryToggle(event) {
        const questionId = event.target.dataset.questionId;
        const isMandatory = event.target.checked;
        this.isLoading = true;
        try {
            await setQuestionMandatory({ questionId, isMandatory });
            this.showSuccess(isMandatory ? UI_LABELS.feedback.mandatoryOn : UI_LABELS.feedback.mandatoryOff);
            await this.refresh();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleAddColumn() {
        this.columnKeySeed += 1;
        this.questionColumns = [
            ...this.questionColumns,
            { key: `col-${this.columnKeySeed}`, label: '', dataType: 'Text' }
        ];
    }

    handleRemoveColumn(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.questionColumns = this.questionColumns.filter((_, i) => i !== index);
    }

    handleColumnLabelChange(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.questionColumns = this.questionColumns.map((column, i) =>
            i === index ? { ...column, label: event.target.value } : column
        );
    }

    handleColumnDataTypeChange(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.questionColumns = this.questionColumns.map((column, i) =>
            i === index ? { ...column, dataType: event.detail.value } : column
        );
    }

    reportQuestionFormValidity() {
        const fields = this.template.querySelectorAll('.question-required-field');
        let allValid = true;
        fields.forEach((field) => {
            if (!field.reportValidity()) {
                allValid = false;
            }
        });
        return allValid;
    }

    // French text and response values, only for the pillars translated into French (not Science).
    // Sent with the question itself, so a rejected translation creates or changes nothing.
    buildTranslation(form) {
        if (!this.hasFrenchFields) {
            return { questionTextFr: null, responseValuesFr: null };
        }
        return {
            questionTextFr: form.textFr ? form.textFr.trim() : null,
            responseValuesFr:
                this.questionHasResponseValues && form.responseValuesFr ? form.responseValuesFr.trim() : null
        };
    }

    async saveQuestion() {
        if (this.isSaving || !this.reportQuestionFormValidity()) {
            return;
        }
        const form = this.questionForm;
        const columns = form.isTable
            ? this.questionColumns
                  .filter((column) => column.label && column.label.trim())
                  .map((column) => ({ label: column.label.trim(), dataType: column.dataType }))
            : null;

        this.isSaving = true;
        try {
            if (this.editingQuestionId) {
                await updateQuestion({
                    questionId: this.editingQuestionId,
                    name: null,
                    questionText: form.text.trim(),
                    dataType: form.isTable ? TABLE_FALLBACK_DATA_TYPE : form.dataType,
                    description: form.description ? form.description.trim() : null,
                    responseValues: form.responseValues ? form.responseValues.trim() : null,
                    helpText: form.helpText ? form.helpText.trim() : null,
                    maximumCharacters: this.questionSupportsMaximumCharacters ? form.maximumCharacters : null,
                    isTable: form.isTable,
                    columnsJson: columns ? JSON.stringify(columns) : null,
                    ...this.buildTranslation(form)
                });
                await setQuestionMandatory({ questionId: this.editingQuestionId, isMandatory: form.isMandatory });
                this.showSuccess(UI_LABELS.feedback.questionUpdated);
            } else {
                const targetSectionId = this.isCreatingNewSection
                    ? await createSectionForMode({
                          label: this.newQuestionSectionName.trim(),
                          fundingOpportunityId: this.recordId,
                          isEoi: this.eoi === true
                      })
                    : this.selectedNewQuestionSectionId;
                const newQuestionId = await createQuestion({
                    name: null,
                    questionText: form.text.trim(),
                    dataType: form.isTable ? TABLE_FALLBACK_DATA_TYPE : form.dataType,
                    description: form.description ? form.description.trim() : null,
                    responseValues: form.responseValues ? form.responseValues.trim() : null,
                    helpText: form.helpText ? form.helpText.trim() : null,
                    maximumCharacters: this.questionSupportsMaximumCharacters ? form.maximumCharacters : null,
                    isTable: form.isTable,
                    columnsJson: columns ? JSON.stringify(columns) : null,
                    sectionId: targetSectionId,
                    sectionSequence: null,
                    nextSequence: null,
                    fundingOpportunityId: this.recordId,
                    isFixed: false,
                    objectApiName: null,
                    fieldApiName: null,
                    isEoi: this.eoi,
                    ...this.buildTranslation(form)
                });
                if (!form.isMandatory) {
                    await setQuestionMandatory({ questionId: newQuestionId, isMandatory: false });
                }
                this.showSuccess(UI_LABELS.feedback.questionAdded);
            }
            this.isQuestionModalOpen = false;
            await this.refresh();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    // Gestion de la suppression
    openRemoveModal(event) {
        if (this.isCatalogLocked) {
            return;
        }
        this.removeTargetId = event.currentTarget.dataset.id;
        this.removeTargetType = event.currentTarget.dataset.type;
        this.isRemoveModalOpen = true;
    }

    closeRemoveModal() {
        this.isRemoveModalOpen = false;
    }

    get removeTargetTypeLabel() {
        return this.removeTargetType === 'section' ? UI_LABELS.removeModal.section : UI_LABELS.removeModal.question;
    }

    get removeModalTitle() {
        return formatLabel(UI_LABELS.removeModal.title, this.removeTargetTypeLabel);
    }

    get removeModalBody() {
        return formatLabel(UI_LABELS.removeModal.body, this.removeTargetTypeLabel);
    }

    async handlePermanentDelete() {
        await this.performRemoval(true);
    }

    async performRemoval(permanentlyDelete) {
        if (this.isSaving) {
            return;
        }
        const targetId = this.removeTargetId;
        const targetType = this.removeTargetType;
        this.isRemoveModalOpen = false;
        this.isSaving = true;

        try {
            if (targetType === 'section') {
                await removeSectionAssignments({
                    fundingOpportunityId: this.recordId,
                    sectionId: targetId,
                    permanentlyDelete
                });
            } else {
                await removeQuestionAssignment({ assignmentId: targetId, permanentlyDelete });
            }
            this.showSuccess(UI_LABELS.feedback.deletedPermanently);
            await this.refresh();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    // Gestions des notifications Toasts
    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({ title: UI_LABELS.feedback.successTitle, message, variant: 'success' })
        );
    }

    showError(error) {
        const message = translateError(error?.body?.message || error?.message);
        this.dispatchEvent(
            new ShowToastEvent({ title: UI_LABELS.feedback.errorTitle, message, variant: 'error' })
        );
    }
}