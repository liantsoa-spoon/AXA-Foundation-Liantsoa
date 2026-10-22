import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import searchContacts from '@salesforce/apex/RecipientSelectorController.searchContacts';
import searchAccounts from '@salesforce/apex/RecipientSelectorController.searchAccounts';
import getAccountContacts from '@salesforce/apex/RecipientSelectorController.getAccountContacts';

const DEBOUNCE_DELAY = 300;
const MIN_SEARCH_LENGTH = 2;
const DEFAULT_ERROR = 'Une erreur est survenue lors de la recherche.';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const toRecipient = (contact) => ({
    type: 'contact',
    id: contact.Id,
    name: contact.Name,
    email: contact.Email,
    accountId: contact.AccountId,
    meta: [contact.Account?.Name, contact.Email].filter(Boolean).join(' • ')
});

export default class RecipientSelector extends LightningElement {
    @api recordId;
    @api selectedIds = [];
    @api selectedEmails = [];

    // Configurable in Flow Builder: max number of contacts shown in the dropdown
    @api maxResults = 10;

    searchTerm = '';
    emailInput = '';
    searchResults = [];
    accountResults = [];
    selectedRecipients = [];
    isLoading = false;
    hasFocus = false;
    errorMessage;

    debounceTimer;

    get trimmedSearchTerm() {
        return this.searchTerm.trim();
    }

    get showDropdown() {
        return this.hasFocus && this.trimmedSearchTerm.length >= MIN_SEARCH_LENGTH;
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${
            this.showDropdown ? ' slds-is-open' : ''
        }`;
    }

    get hasResults() {
        return this.searchResults.length > 0 || this.accountResults.length > 0;
    }

    get showNoResults() {
        return !this.isLoading && !this.errorMessage && !this.hasResults;
    }

    get hasSelection() {
        return this.selectedRecipients.length > 0;
    }

    get selectedCount() {
        return this.selectedRecipients.length;
    }

    get selectedPills() {
        return this.selectedRecipients.map((recipient) => ({
            type: 'icon',
            iconName: recipient.type === 'email' ? 'standard:email' : 'standard:contact',
            alternativeText: recipient.type === 'email' ? 'E-mail' : 'Contact',
            label: recipient.name,
            name: recipient.id
        }));
    }

    get isAddEmailDisabled() {
        return !this.emailInput.trim();
    }

    // Called by the flow on Next/Finish: the send is triggered by the flow, so it needs at least one recipient
    @api
    validate() {
        if (this.hasSelection) {
            return { isValid: true };
        }
        return { isValid: false, errorMessage: 'Sélectionnez au moins un destinataire.' };
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
        clearTimeout(this.debounceTimer);

        if (this.trimmedSearchTerm.length < MIN_SEARCH_LENGTH) {
            this.searchResults = [];
            this.accountResults = [];
            this.isLoading = false;
            this.errorMessage = undefined;
            return;
        }

        this.isLoading = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.debounceTimer = setTimeout(() => {
            this.runSearch(this.trimmedSearchTerm);
        }, DEBOUNCE_DELAY);
    }

    async runSearch(term) {
        try {
            const [contacts, accounts] = await Promise.all([
                searchContacts({
                    searchTerm: term,
                    maxResults: Number(this.maxResults),
                    excludedIds: this.selectedIds
                }),
                searchAccounts({ searchTerm: term, excludedIds: this.selectedIds })
            ]);
            // Ignore responses for a term the user has since changed
            if (term !== this.trimmedSearchTerm) {
                return;
            }
            this.searchResults = contacts.map(toRecipient);
            this.accountResults = accounts.map((account) => ({
                id: account.id,
                label: `Ajouter tous les contacts du compte ${account.name}`,
                meta: `${account.contactCount} contact${account.contactCount > 1 ? 's' : ''}`
            }));
            this.errorMessage = undefined;
        } catch (error) {
            if (term !== this.trimmedSearchTerm) {
                return;
            }
            this.searchResults = [];
            this.accountResults = [];
            this.errorMessage = error?.body?.message || DEFAULT_ERROR;
        }
        this.isLoading = false;
    }

    handleFocus() {
        this.hasFocus = true;
    }

    handleBlur() {
        this.hasFocus = false;
    }

    // Keeps focus in the search input while clicking an option, so the dropdown stays open
    handleDropdownMouseDown(event) {
        event.preventDefault();
    }

    handleSelect(event) {
        const id = event.currentTarget.dataset.id;
        const contact = this.searchResults.find((result) => result.id === id);
        if (!contact) {
            return;
        }
        this.selectedRecipients = [...this.selectedRecipients, contact];
        this.searchResults = this.searchResults.filter((result) => result.id !== id);
        this.notifySelectionChange();
    }

    async handleSelectAccount(event) {
        const accountId = event.currentTarget.dataset.id;
        this.isLoading = true;
        try {
            const contacts = await getAccountContacts({ accountId, excludedIds: this.selectedIds });
            const selectedIds = new Set(this.selectedIds);
            const newRecipients = contacts.map(toRecipient).filter((contact) => !selectedIds.has(contact.id));
            this.selectedRecipients = [...this.selectedRecipients, ...newRecipients];
            this.searchResults = this.searchResults.filter((result) => result.accountId !== accountId);
            this.accountResults = this.accountResults.filter((account) => account.id !== accountId);
            this.errorMessage = undefined;
            this.notifySelectionChange();
        } catch (error) {
            this.errorMessage = error?.body?.message || DEFAULT_ERROR;
        }
        this.isLoading = false;
    }

    handleEmailChange(event) {
        this.emailInput = event.target.value || '';
        // Clear a previous error as soon as the user edits the address
        event.target.setCustomValidity('');
    }

    handleEmailKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleAddEmail();
        }
    }

    handleAddEmail() {
        const input = this.refs.emailInput;
        const email = this.emailInput.trim();
        if (!email) {
            return;
        }

        let error = '';
        if (!EMAIL_PATTERN.test(email)) {
            error = 'Veuillez saisir une adresse e-mail valide.';
        } else if (this.isEmailAlreadySelected(email)) {
            error = 'Cette adresse e-mail est déjà dans les destinataires.';
        }
        input.setCustomValidity(error);
        input.reportValidity();
        if (error) {
            return;
        }

        this.selectedRecipients = [
            ...this.selectedRecipients,
            { type: 'email', id: `email:${email.toLowerCase()}`, name: email, email }
        ];
        this.emailInput = '';
        this.notifySelectionChange();
    }

    isEmailAlreadySelected(email) {
        const normalized = email.toLowerCase();
        return this.selectedRecipients.some((recipient) => recipient.email?.toLowerCase() === normalized);
    }

    handleRemove(event) {
        const id = event.detail.item.name;
        this.selectedRecipients = this.selectedRecipients.filter((recipient) => recipient.id !== id);
        this.notifySelectionChange();
    }

    handleClearAll() {
        this.selectedRecipients = [];
        this.notifySelectionChange();
    }

    notifySelectionChange() {
        this.selectedIds = this.selectedRecipients
            .filter((recipient) => recipient.type === 'contact')
            .map((recipient) => recipient.id);
        this.selectedEmails = this.selectedRecipients
            .filter((recipient) => recipient.type === 'email')
            .map((recipient) => recipient.email);
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedIds', this.selectedIds));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedEmails', this.selectedEmails));
        this.dispatchEvent(
            new CustomEvent('selectionchange', {
                detail: {
                    recipients: this.selectedRecipients.map(({ type, id, name, email }) => ({
                        type,
                        id,
                        name,
                        email
                    })),
                    selectedIds: this.selectedIds,
                    selectedEmails: this.selectedEmails
                }
            })
        );
    }
}