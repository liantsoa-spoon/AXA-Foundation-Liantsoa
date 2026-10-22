public with sharing class ApplicationFormService {

    private static final String AAP_RECORDTYPEID = Schema.SObjectType.FundingOpportunity.getRecordTypeInfosByDeveloperName().get('CallForProjects').getRecordTypeId();

    public static void generateEoiPdfs(List<ApplicationForm> applicationForms) {
        Set<Id> aapFundingOpportunityIds = getAapFundingOpportunityIds(applicationForms);
        Id templateContentVersionId = getTemplateContentVersionId();

        for (ApplicationForm appForm : applicationForms) {
            if (!aapFundingOpportunityIds.contains(appForm.ProgrammeRattache__c)) {
                continue;
            }
            FormulairePDFGenerationController.generatePdf(appForm.Id, templateContentVersionId, true);
        }
    }

    public static void generateApplicationPdfs(List<ApplicationForm> applicationForms) {
        Id templateContentVersionId = getTemplateContentVersionId();

        for (ApplicationForm appForm : applicationForms) {
            FormulairePDFGenerationController.generatePdf(appForm.Id, templateContentVersionId, false);
        }
    }

    private static Set<Id> getAapFundingOpportunityIds(List<ApplicationForm> applicationForms) {
        Set<Id> fundingOpportunityIds = new Set<Id>();
        for (ApplicationForm appForm : applicationForms) {
            if (appForm.ProgrammeRattache__c != null) {
                fundingOpportunityIds.add(appForm.ProgrammeRattache__c);
            }
        }

        Set<Id> aapFundingOpportunityIds = new Set<Id>();
        for (FundingOpportunity fo : [
            SELECT Id
            FROM FundingOpportunity
            WHERE Id IN :fundingOpportunityIds
            AND RecordTypeId = :AAP_RECORDTYPEID
            WITH USER_MODE
        ]) {
            aapFundingOpportunityIds.add(fo.Id);
        }
        return aapFundingOpportunityIds;
    }

    private static Id getTemplateContentVersionId() {
        //String templateName = Label.ApplicationFormPdfTemplateName;
        String templateName = System.Label.get('', 'ApplicationFormPdfTemplateName', 'en_US');

        List<ContentVersion> versions = [
            SELECT Id
            FROM ContentVersion
            //WHERE (Title = :templateName OR Title ='Formulaire de candidature')
            WHERE Title = :templateName 
            AND IsLatest = true
            AND FileType = 'WORD_X'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            AuraHandledException ex = new AuraHandledException('No document template File found with Title: ' + templateName);
            ex.setMessage('No document template File found with Title: ' + templateName);
            throw ex;
        }
        return versions[0].Id;
    }
}