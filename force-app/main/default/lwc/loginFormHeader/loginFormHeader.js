import { LightningElement, api } from 'lwc';
import OrgLogo from '@salesforce/resourceUrl/OrgLogo';
import getSelfRegistrationUrl from '@salesforce/apex/LightningLoginFormController.getSelfRegistrationUrl';

export default class LoginFormHeader extends LightningElement {
    @api selfRegisterUrl = '/SelfRegister';
    @api signInUrl = '/portal/s/login/';

    logoUrl = OrgLogo;
    communitySelfRegisterUrl;

    get registerUrl() {
        return this.communitySelfRegisterUrl || this.selfRegisterUrl;
    }

    connectedCallback() {
        getSelfRegistrationUrl()
            .then((url) => {
                this.communitySelfRegisterUrl = url;
            })
            .catch(() => {
                this.communitySelfRegisterUrl = undefined;
            });
    }
}