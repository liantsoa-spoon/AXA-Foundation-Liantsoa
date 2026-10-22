import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCurrentStatus from '@salesforce/apex/DecisionComitePathController.getCurrentStatus';
import updateStatus from '@salesforce/apex/DecisionComitePathController.updateStatus';

const STAGES = [
    { label: 'Approuvé', value: 'Approved' },
    { label: 'Rejeté', value: 'Rejected' },
    { label: 'Annulé', value: 'Canceled' }
];

export default class DecisionComitePath extends LightningElement {
    @api recordId;
    @api fieldApiName = 'Stage';

    currentValue;

    connectedCallback() {
        this.loadCurrentStatus();
    }

    loadCurrentStatus() {
        getCurrentStatus({ recordId: this.recordId, fieldApiName: this.fieldApiName })
            .then((value) => {
                this.currentValue = value;
            })
            .catch(() => {
                this.showToast('Error', 'Could not load the current status', 'error');
            });
    }

    get stages() {
        return STAGES.map((stage) => {
            const isCurrent = this.currentValue === stage.value;
            return {
                ...stage,
                isCurrent,
                isComplete: false,
                cssClass: isCurrent
                    ? 'slds-path__item slds-is-current slds-is-active'
                    : 'slds-path__item slds-is-incomplete'
            };
        });
    }

    handleStageClick(event) {
        event.preventDefault();
        const selectedValue = event.currentTarget.dataset.value;
        if (selectedValue === this.currentValue) {
            return;
        }

        updateStatus({ recordId: this.recordId, fieldApiName: this.fieldApiName, newValue: selectedValue })
            .then(() => {
                this.loadCurrentStatus();
                this.showToast('Success', 'Status updated', 'success');
            })
            .catch((error) => {
                const message = error.body ? error.body.message : error.message;
                this.showToast('Error updating status', message, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}