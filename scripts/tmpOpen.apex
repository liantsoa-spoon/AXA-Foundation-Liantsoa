Id foId = '119KN000000004EYAQ';
List<ApplicationFormCatalogueController.SectionWrapper> sections =
    ApplicationFormCatalogueQueryService.getCatalogSections(foId);
Integer q = 0;
Integer fixed = 0;
for (ApplicationFormCatalogueController.SectionWrapper s : sections) {
    for (ApplicationFormCatalogueController.QuestionWrapper qq : s.questions) {
        q++;
        if (qq.isFixed == true) {
            fixed++;
        }
    }
}
System.debug('sections=' + sections.size() + ' questions=' + q + ' fixed=' + fixed);
try {
    ApplicationFormController.FormDefinitionWrapper r =
        ApplicationFormController.openFundingOpportunityForm(foId, false, false);
    System.debug('ok sections=' + r.sections.size() + ' afId=' + r.applicationFormId);
} catch (Exception e) {
    System.debug('ERR ' + e.getMessage());
}
