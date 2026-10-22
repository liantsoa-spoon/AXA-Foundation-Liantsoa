/**
 * @description       : Queries and cleans the Application Form catalogue of a FundingOpportunity.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 19-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   LAN      Initial version
 * 1.1   06-10-2026   LAN      Read the form catalogue (sections, questions, versions) in system mode, without sharing
 * 1.2   06-10-2026   LAN      Add the form version reads used by ApplicationFormController, in system mode
 * 1.3   08-10-2026   KRA      Remove the clone code replaced by ApplicationFormLifecycleService
 * 1.4   19-10-2026   LAN      Read the budget table configuration of the latest question versions
 **/
// Without sharing: the catalogue is configuration read to display the form, so the candidate reads it in system mode.
// Every query that reads or writes on behalf of the user stays in USER_MODE, which enforces sharing and FLS.
public without sharing class ApplicationFormCatalogueQueryService {

    public static List<ApplicationFormCatalogueController.SectionWrapper> getCatalogSections(Id fundingOpportunityId) {
        TemplateIdentity templateIdentity = getApplicableTemplateIdentity(fundingOpportunityId);
        // A section's FO membership is derived from its Assignments (never a lookup on the
        // Section itself): every section is guaranteed to carry at least one Assignment, since
        // a section can no longer be created or left empty (see ApplicationFormCatalogueController).
        List<AssessmentQuestionSet> sectionRecords = [
            SELECT Id, Name
            FROM AssessmentQuestionSet
            WHERE Id IN (
                SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment
                WHERE FundingOpportunity__c = :fundingOpportunityId
            )
            WITH SYSTEM_MODE
            ORDER BY Sequence__c ASC NULLS LAST
        ];

        Map<Id, ApplicationFormCatalogueController.SectionWrapper> sectionById = new Map<Id, ApplicationFormCatalogueController.SectionWrapper>();
        List<ApplicationFormCatalogueController.SectionWrapper> orderedSections = new List<ApplicationFormCatalogueController.SectionWrapper>();
        for (AssessmentQuestionSet s : sectionRecords) {
            ApplicationFormCatalogueController.SectionWrapper sw = new ApplicationFormCatalogueController.SectionWrapper();
            sw.sectionId = s.Id;
            sw.label = s.Name;
            sw.isLocal = true;
            sw.isPreconfigured = templateIdentity.sectionNames.contains(s.Name);
            sw.questions = new List<ApplicationFormCatalogueController.QuestionWrapper>();
            sectionById.put(s.Id, sw);
            orderedSections.add(sw);
        }

        List<AssessmentQuestionAssignment> assignments = [
            SELECT Id, AssessmentQuestionSetId, AssessmentQuestionSet.Name,
                   AssessmentQuestionId, AssessmentQuestion.Name, AssessmentQuestion.QuestionText,
                   AssessmentQuestion.DataType,
                   AssessmentQuestion.isTable__c, AssessmentQuestion.RecordType.DeveloperName,
                   AssessmentQuestion.ObjectAPIName__c, AssessmentQuestion.FieldAPIName__c,
                   AssessmentQuestion.MaximumCharacters__c, AssessmentQuestion.Sequence__c,
                   EOI__c, IsMandatory__c
            FROM AssessmentQuestionAssignment
            WHERE FundingOpportunity__c = :fundingOpportunityId
            WITH SYSTEM_MODE
            ORDER BY AssessmentQuestion.Sequence__c NULLS LAST
        ];

        Set<Id> questionIds = new Set<Id>();
        for (AssessmentQuestionAssignment aqa : assignments) {
            questionIds.add(aqa.AssessmentQuestionId);
        }
        Map<Id, AssessmentQuestionVersion> latestVersionByQuestionId = getLatestVersionByQuestionId(questionIds);

        for (AssessmentQuestionAssignment aqa : assignments) {
            ApplicationFormCatalogueController.SectionWrapper sw = sectionById.get(aqa.AssessmentQuestionSetId);
            if (sw == null) {
                sw = new ApplicationFormCatalogueController.SectionWrapper();
                sw.sectionId = aqa.AssessmentQuestionSetId;
                sw.label = aqa.AssessmentQuestionSet.Name;
                sw.isLocal = true;
                sw.isPreconfigured = templateIdentity.sectionNames.contains(aqa.AssessmentQuestionSet.Name);
                sw.questions = new List<ApplicationFormCatalogueController.QuestionWrapper>();
                sectionById.put(aqa.AssessmentQuestionSetId, sw);
                orderedSections.add(sw);
            }
            AssessmentQuestionVersion latestVersion = latestVersionByQuestionId.get(aqa.AssessmentQuestionId);

            ApplicationFormCatalogueController.QuestionWrapper qw = new ApplicationFormCatalogueController.QuestionWrapper();
            qw.assignmentId = aqa.Id;
            qw.questionId = aqa.AssessmentQuestionId;
            qw.label = latestVersion != null ? latestVersion.QuestionText : aqa.AssessmentQuestion.QuestionText;
            qw.dataType = aqa.AssessmentQuestion.DataType;
            qw.isTable = aqa.AssessmentQuestion.isTable__c;
            qw.maximumCharacters = aqa.AssessmentQuestion.MaximumCharacters__c;
            qw.isActive = latestVersion != null && latestVersion.IsActive;
            qw.isFixed = aqa.AssessmentQuestion.RecordType.DeveloperName == 'Fixed';
            qw.objectApiName = aqa.AssessmentQuestion.ObjectAPIName__c;
            qw.fieldApiName = aqa.AssessmentQuestion.FieldAPIName__c;
            qw.sequence = aqa.AssessmentQuestion.Sequence__c;
            qw.isEOI = aqa.EOI__c;
            qw.isMandatory = aqa.IsMandatory__c != false;
            qw.isPreconfigured = templateIdentity.questionKeys.contains(
                sectionQuestionKey(aqa.AssessmentQuestionSet.Name, aqa.AssessmentQuestion.Name)
            );
            sw.questions.add(qw);
        }

        return orderedSections;
    }

    public static Set<Id> getPreconfiguredAssignmentIds(
        Id fundingOpportunityId,
        Set<Id> assignmentIds
    ) {
        Set<Id> preconfiguredAssignmentIds = new Set<Id>();
        if (fundingOpportunityId == null || assignmentIds == null || assignmentIds.isEmpty()) {
            return preconfiguredAssignmentIds;
        }

        TemplateIdentity templateIdentity = getApplicableTemplateIdentity(fundingOpportunityId);
        for (AssessmentQuestionAssignment assignment : [
            SELECT Id, AssessmentQuestion.Name, AssessmentQuestionSet.Name
            FROM AssessmentQuestionAssignment
            WHERE Id IN :assignmentIds AND FundingOpportunity__c = :fundingOpportunityId
            WITH USER_MODE
        ]) {
            String questionKey = sectionQuestionKey(
                assignment.AssessmentQuestionSet.Name,
                assignment.AssessmentQuestion.Name
            );
            if (templateIdentity.questionKeys.contains(questionKey)) {
                preconfiguredAssignmentIds.add(assignment.Id);
            }
        }
        return preconfiguredAssignmentIds;
    }

    public static Boolean isPreconfiguredQuestion(Id questionId) {
        List<AssessmentQuestionAssignment> assignments = [
            SELECT Id, FundingOpportunity__c
            FROM AssessmentQuestionAssignment
            WHERE AssessmentQuestionId = :questionId AND FundingOpportunity__c != null
            WITH USER_MODE
            LIMIT 1
        ];
        for (AssessmentQuestionAssignment assignment : assignments) {
            if (getPreconfiguredAssignmentIds(
                assignment.FundingOpportunity__c,
                new Set<Id>{ assignment.Id }
            ).contains(assignment.Id)) {
                return true;
            }
        }
        return false;
    }

    public static Boolean isPreconfiguredSection(Id fundingOpportunityId, Id sectionId) {
        AssessmentQuestionSet section = [
            SELECT Name
            FROM AssessmentQuestionSet
            WHERE Id = :sectionId
                AND Id IN (
                    SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment
                    WHERE FundingOpportunity__c = :fundingOpportunityId
                )
            WITH USER_MODE
            ORDER BY Sequence__c ASC NULLS LAST
            LIMIT 1
        ];
        return getApplicableTemplateIdentity(fundingOpportunityId).sectionNames.contains(section.Name);
    }

    public static Boolean matchesPreconfiguredQuestion(
        Id fundingOpportunityId,
        Id sectionId,
        String questionName
    ) {
        AssessmentQuestionSet section = [
            SELECT Name
            FROM AssessmentQuestionSet
            WHERE Id = :sectionId
            WITH USER_MODE
            ORDER BY Sequence__c ASC NULLS LAST
            LIMIT 1
        ];
        return getApplicableTemplateIdentity(fundingOpportunityId).questionKeys.contains(
            sectionQuestionKey(section.Name, questionName)
        );
    }

    private class TemplateIdentity {
        private Set<String> sectionNames = new Set<String>();
        private Set<String> questionKeys = new Set<String>();
    }

    private static TemplateIdentity getApplicableTemplateIdentity(Id fundingOpportunityId) {
        FundingOpportunity fundingOpportunity = [
            SELECT ProgramId
            FROM FundingOpportunity
            WHERE Id = :fundingOpportunityId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Id programId = fundingOpportunity.ProgramId;

        TemplateIdentity identity = new TemplateIdentity();
        for (AssessmentQuestionAssignment templateAssignment : [
            SELECT AssessmentQuestionSet.Name, AssessmentQuestion.Name
            FROM AssessmentQuestionAssignment
            WHERE FundingOpportunity__c = null
                AND (Program__c = null OR Program__c = :programId)
            WITH SYSTEM_MODE
        ]) {
            identity.sectionNames.add(templateAssignment.AssessmentQuestionSet.Name);
            identity.questionKeys.add(
                sectionQuestionKey(
                    templateAssignment.AssessmentQuestionSet.Name,
                    templateAssignment.AssessmentQuestion.Name
                )
            );
        }
        return identity;
    }

    // Deletes the catalogue cloned for the given FundingOpportunities: Responses, Assignments,
    // Versions, Questions and Sections. Active Versions are deactivated first, then only Draft
    // Versions and Questions made of Draft Versions are deleted (the rest cannot be deleted).
    // Questions and Sections still used by another Assignment are kept.
    public static void deleteClonedCatalogues(final Set<Id> fundingOpportunityIds) {
        if (fundingOpportunityIds == null || fundingOpportunityIds.isEmpty()) {
            return;
        }

        final List<AssessmentQuestionAssignment> assignments = [
            SELECT
                Id,
                AssessmentQuestionId,
                AssessmentQuestionSetId
            FROM
                AssessmentQuestionAssignment
            WHERE
                FundingOpportunity__c IN :fundingOpportunityIds
            WITH
                USER_MODE
        ];
        if (assignments.isEmpty()) {
            return;
        }

        final Set<Id> questionIds = new Set<Id>();
        final Set<Id> sectionIds = new Set<Id>();
        for (AssessmentQuestionAssignment assignment : assignments) {
            questionIds.add(assignment.AssessmentQuestionId);
            sectionIds.add(assignment.AssessmentQuestionSetId);
        }

        Database.delete(assignments, AccessLevel.USER_MODE);

        final Set<Id> orphanQuestionIds = questionIds.clone();
        final Set<Id> emptySectionIds = sectionIds.clone();
        for (AssessmentQuestionAssignment remainingAssignment : [
            SELECT
                AssessmentQuestionId,
                AssessmentQuestionSetId
            FROM
                AssessmentQuestionAssignment
            WHERE
                AssessmentQuestionId IN :questionIds
                OR AssessmentQuestionSetId IN :sectionIds
            WITH
                USER_MODE
        ]) {
            orphanQuestionIds.remove(remainingAssignment.AssessmentQuestionId);
            emptySectionIds.remove(remainingAssignment.AssessmentQuestionSetId);
        }

        if (!orphanQuestionIds.isEmpty()) {
            deleteQuestionsWithVersionsAndResponses(orphanQuestionIds);
        }
        if (!emptySectionIds.isEmpty()) {
            Database.delete(
                [
                    SELECT
                        Id
                    FROM
                        AssessmentQuestionSet
                    WHERE
                        Id IN :emptySectionIds
                    WITH
                        USER_MODE
                ],
                AccessLevel.USER_MODE
            );
        }
    }

    private static void deleteQuestionsWithVersionsAndResponses(final Set<Id> questionIds) {
        final List<AssessmentQuestionVersion> versions = [
            SELECT
                Id,
                IsActive
            FROM
                AssessmentQuestionVersion
            WHERE
                AssessmentQuestionId IN :questionIds
            WITH
                USER_MODE
        ];
        final Set<Id> versionIds = new Map<Id, AssessmentQuestionVersion>(versions).keySet();

        final List<AssessmentQuestionResponse> responses = [
            SELECT
                Id
            FROM
                AssessmentQuestionResponse
            WHERE
                AssessmentQuestionId IN :versionIds
            WITH
                USER_MODE
        ];
        if (!responses.isEmpty()) {
            Database.delete(responses, AccessLevel.USER_MODE);
        }

        final List<AssessmentQuestionVersion> versionsToDeactivate = new List<AssessmentQuestionVersion>();
        for (AssessmentQuestionVersion version : versions) {
            if (version.IsActive) {
                versionsToDeactivate.add(new AssessmentQuestionVersion(Id = version.Id, IsActive = false));
            }
        }
        if (!versionsToDeactivate.isEmpty()) {
            Database.update(versionsToDeactivate, AccessLevel.USER_MODE);
        }

        // Only Draft versions can be deleted, and a Question only when all its versions are Draft.
        ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(questionIds);
    }

    private static String sectionQuestionKey(String sectionName, String questionName) {
        return (sectionName == null ? '' : sectionName) + '|' + (questionName == null ? '' : questionName);
    }

    public static Map<Id, AssessmentQuestionVersion> getLatestVersionByQuestionId(Set<Id> questionIds) {
        final Map<Id, AssessmentQuestionVersion> latestVersionByQuestionId = new Map<Id, AssessmentQuestionVersion>();
        if (questionIds.isEmpty()) {
            return latestVersionByQuestionId;
        }
        for (AssessmentQuestion question : [
            SELECT
                Id,
                (
                    SELECT
                        Id,
                        AssessmentQuestionId,
                        QuestionText,
                        QuestionTextFR__c,
                        IsActive,
                        Description,
                        ResponseValues,
                        ResponseValuesFR__c,
                        HelpText,
                        AdditionalInformation,
                        NumberOfYears__c,
                        HasTotal__c,
                        HasPercent__c,
                        HasPicklistSecuredPlanned__c,
                        HasPicklistPublicPrivate__c
                    FROM
                        AssessmentQuestionVersions
                    ORDER BY
                        IsActive DESC,
                        CreatedDate DESC
                    LIMIT
                        1
                )
            FROM
                AssessmentQuestion
            WHERE
                Id IN :questionIds
            WITH
                SYSTEM_MODE
        ]) {
            final List<AssessmentQuestionVersion> versions = question.AssessmentQuestionVersions;
            if (!versions.isEmpty()) {
                latestVersionByQuestionId.put(question.Id, versions[0]);
            }
        }
        return latestVersionByQuestionId;
    }

    // Form read: the latest version of each question, as the candidate's form displays it.
    public static Map<Id, AssessmentQuestionVersion> getFormVersionByQuestionId(Set<Id> questionIds) {
        Map<Id, AssessmentQuestionVersion> result = new Map<Id, AssessmentQuestionVersion>();
        if (questionIds.isEmpty()) {
            return result;
        }
        for (AssessmentQuestionVersion version : [
            SELECT Id, AssessmentQuestionId, HelpText, AdditionalInformation, ResponseValues, ResponseValuesFR__c, QuestionText, QuestionTextFR__c, Description
            FROM AssessmentQuestionVersion
            WHERE AssessmentQuestionId IN :questionIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {
            if (!result.containsKey(version.AssessmentQuestionId)) {
                result.put(version.AssessmentQuestionId, version);
            }
        }
        return result;
    }

    // Form read: the versions a candidate answers, with the limits of their question, to validate the answers.
    public static Map<Id, AssessmentQuestionVersion> getAnsweredVersionById(Set<Id> versionIds) {
        return new Map<Id, AssessmentQuestionVersion>([
            SELECT Id, QuestionText, AssessmentQuestion.DataType, AssessmentQuestion.MaximumCharacters__c
            FROM AssessmentQuestionVersion
            WHERE Id IN :versionIds
            WITH SYSTEM_MODE
        ]);
    }
}