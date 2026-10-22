public with sharing class ApplicationFormCatalogueController {

    public class SectionWrapper {
        @AuraEnabled public Id sectionId;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal sectionSequence;
        @AuraEnabled public Boolean isLocal;
        @AuraEnabled public Boolean isPreconfigured;
        @AuraEnabled public List<QuestionWrapper> questions;
    }

    public class QuestionWrapper {
        @AuraEnabled public Id assignmentId;
        @AuraEnabled public Id questionId;
        @AuraEnabled public String label;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean isTable;
        @AuraEnabled public Decimal maximumCharacters;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public Boolean isFixed;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public Boolean isEOI;
        @AuraEnabled public Boolean isMandatory;
        @AuraEnabled public Boolean isAlreadyAdded;
        @AuraEnabled public Boolean isPreconfigured;
    }

    public class RemovalResultWrapper {
        @AuraEnabled public Integer deletedCount;
        @AuraEnabled public List<String> errorMessages;
    }

    public class ColumnWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String developerName;
        @AuraEnabled public String dataType;
    }

    public class QuestionDetailWrapper {
        @AuraEnabled public Id questionId;
        @AuraEnabled public String name;
        @AuraEnabled public String questionText;
        @AuraEnabled public String dataType;
        @AuraEnabled public String description;
        @AuraEnabled public String responseValues;
        @AuraEnabled public String questionTextFr;
        @AuraEnabled public String responseValuesFr;
        @AuraEnabled public String helpText;
        @AuraEnabled public Decimal maximumCharacters;
        @AuraEnabled public Boolean isTable;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isFixed;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public List<ColumnWrapper> columns;
        @AuraEnabled public Boolean isMandatory;
    }

    // ===================== FUNDING OPPORTUNITY VIEW =====================

    @AuraEnabled
    public static List<SectionWrapper> getFundingOpportunityCatalog(Id fundingOpportunityId) {
        try {
            requireId(fundingOpportunityId, ERROR_FUNDING_OPPORTUNITY_REQUIRED);
            return ApplicationFormCatalogueQueryService.getCatalogSections(fundingOpportunityId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_LOAD_CONFIGURATION_FAILED, e);
        }
    }

    @AuraEnabled
    public static void reorderFundingOpportunitySections(Id fundingOpportunityId, List<Id> orderedSectionIds) {
    }

    // ===== SHARED CREATE / ADD (catalog and Funding-Opportunity-local) =====

    @AuraEnabled
    public static void updateSection(Id sectionId, String label) {
        try {
            requireId(sectionId, ERROR_SECTION_ID_REQUIRED);
            requireText(label, ERROR_SECTION_LABEL_REQUIRED);

            Id fundingOpportunityId = getSectionFundingOpportunityId(sectionId);
            ensureFundingOpportunityAllowsFormEditing(fundingOpportunityId);
            if (fundingOpportunityId != null
                    && ApplicationFormCatalogueQueryService.isPreconfiguredSection(
                        fundingOpportunityId,
                        sectionId
                    )) {
                fail(ERROR_PRECONFIGURED_SECTION_NOT_EDITABLE);
            }

            Integer fixedQuestionCount = [
                SELECT COUNT()
                FROM AssessmentQuestionAssignment
                WHERE AssessmentQuestionSetId = :sectionId
                    AND AssessmentQuestion.RecordType.DeveloperName = 'Fixed'
            ];
            if (fixedQuestionCount > 0) {
                fail(ERROR_FIXED_SECTION_NOT_EDITABLE);
            }

            Database.update(
                new AssessmentQuestionSet(Id = sectionId, Name = label.left(80)),
                AccessLevel.USER_MODE
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_UPDATE_SECTION_FAILED, e);
        }
    }

    @AuraEnabled
    public static Id createSectionForMode(String label, Id fundingOpportunityId, Boolean isEoi) {
        try {
            requireText(label, ERROR_SECTION_LABEL_REQUIRED);
            ensureFundingOpportunityAllowsFormEditing(fundingOpportunityId);
            AssessmentQuestionSet section = new AssessmentQuestionSet(
                Name = label,
                DeveloperName = ApplicationFormLifecycleService.toDeveloperName(label),
                Sequence__c = getNextSectionSequence(fundingOpportunityId, isEoi == true)
            );
            Database.insert(section, AccessLevel.USER_MODE);
            return section.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_CREATE_SECTION_FAILED, e);
        }
    }

    @AuraEnabled
    public static Id createSection(String label, Id fundingOpportunityId) {
        return createSectionForMode(label, fundingOpportunityId, false);
    }


    private static Decimal getNextSectionSequence(Id fundingOpportunityId, Boolean isEoi) {
        AggregateResult highestSequence = [
            SELECT MAX(Sequence__c) maxSequence
            FROM AssessmentQuestionSet
            WHERE Id IN (
                SELECT AssessmentQuestionSetId FROM AssessmentQuestionAssignment
                WHERE FundingOpportunity__c = :fundingOpportunityId
                AND EOI__c = :isEoi
            )
            WITH USER_MODE
        ];
        Decimal maxSequence = (Decimal) highestSequence.get('maxSequence');
        return (maxSequence == null ? 0 : maxSequence) + 1;
    }

    private static Decimal getNextQuestionSequence(Id sectionId) {
        AggregateResult highestSequence = [
            SELECT MAX(AssessmentQuestion.Sequence__c) maxSequence
            FROM AssessmentQuestionAssignment
            WHERE AssessmentQuestionSetId = :sectionId
            WITH USER_MODE
        ];
        Decimal maxSequence = (Decimal) highestSequence.get('maxSequence');
        return (maxSequence == null ? 0 : maxSequence) + 1;
    }

    @AuraEnabled
    public static Id createQuestion(
        String name,
        String questionText,
        String dataType,
        String description,
        String responseValues,
        String helpText,
        Decimal maximumCharacters,
        Boolean isTable,
        String columnsJson,
        Id sectionId,
        Decimal sectionSequence,
        Decimal nextSequence,
        Id fundingOpportunityId,
        Boolean isFixed,
        String objectApiName,
        String fieldApiName
    ) {
        return createFormQuestion(
            name,
            questionText,
            dataType,
            description,
            responseValues,
            helpText,
            maximumCharacters,
            isTable,
            columnsJson,
            sectionId,
            sectionSequence,
            nextSequence,
            fundingOpportunityId,
            isFixed,
            objectApiName,
            fieldApiName,
            false,
            null,
            null
        );
    }

    @AuraEnabled
    public static Id createFormQuestion(
        String name,
        String questionText,
        String dataType,
        String description,
        String responseValues,
        String helpText,
        Decimal maximumCharacters,
        Boolean isTable,
        String columnsJson,
        Id sectionId,
        Decimal sectionSequence,
        Decimal nextSequence,
        Id fundingOpportunityId,
        Boolean isFixed,
        String objectApiName,
        String fieldApiName,
        Boolean isEoi,
        String questionTextFr,
        String responseValuesFr
    ) {
        try {
            requireText(questionText, ERROR_QUESTION_TEXT_REQUIRED);
            validateTranslation(responseValues, responseValuesFr);
            name = resolveQuestionName(name, questionText);
            requireId(sectionId, ERROR_QUESTION_SECTION_REQUIRED);
            ensureFundingOpportunityAllowsFormEditing(fundingOpportunityId);
            validateMaximumCharacters(dataType, maximumCharacters);
            if (isFixed == true) {
                requireText(objectApiName, ERROR_OBJECT_API_NAME_REQUIRED);
                requireText(fieldApiName, ERROR_FIELD_API_NAME_REQUIRED);
            }
            if (fundingOpportunityId != null
                    && ApplicationFormCatalogueQueryService.matchesPreconfiguredQuestion(
                        fundingOpportunityId,
                        sectionId,
                        name
                    )) {
                fail(ERROR_CUSTOM_QUESTION_NAME_TAKEN);
            }

            AssessmentQuestion question = new AssessmentQuestion(
                Name = name.left(80),
                DeveloperName = ApplicationFormLifecycleService.toDeveloperName(name),
                DataType = dataType,
                QuestionCategory = getDefaultQuestionCategory(),
                isTable__c = isTable == true,
                RecordTypeId = SchemaUtilities.getRecordTypeId(AssessmentQuestion.sObjectType, isFixed == true ? 'Fixed' : 'Dynamic'),
                ObjectAPIName__c = isFixed == true ? objectApiName : null,
                FieldAPIName__c = isFixed == true ? fieldApiName : null,
                MaximumCharacters__c = maximumCharacters,
                Sequence__c = nextSequence != null ? nextSequence : getNextQuestionSequence(sectionId)
            );
            Database.insert(question, AccessLevel.USER_MODE);

            List<ColumnWrapper> columns = String.isNotBlank(columnsJson)
                ? (List<ColumnWrapper>) JSON.deserialize(columnsJson, List<ColumnWrapper>.class)
                : null;
            String additionalInformation = ApplicationFormLifecycleService.serializeTableColumns(isTable, columns);

            AssessmentQuestionVersion version = new AssessmentQuestionVersion(
                Name = name.left(80),
                AssessmentQuestionId = question.Id,
                QuestionText = questionText,
                Description = description,
                ResponseValues = responseValues,
                HelpText = helpText,
                AdditionalInformation = additionalInformation,
                QuestionTextFR__c = cleanTranslation(questionTextFr),
                ResponseValuesFR__c = cleanTranslation(responseValuesFr),
                IsActive = true
            );
            Database.insert(version, AccessLevel.USER_MODE);
            AssessmentQuestionAssignment assignment = new AssessmentQuestionAssignment(
                AssessmentQuestionId = question.Id,
                AssessmentQuestionSetId = sectionId,
                FundingOpportunity__c = fundingOpportunityId,
                EOI__c = isEoi == true
            );
            Database.insert(assignment, AccessLevel.USER_MODE);
            return question.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_CREATE_QUESTION_FAILED, e);
        }
    }

    @AuraEnabled
    public static void setQuestionMandatory(Id questionId, Boolean isMandatory) {
        try {
            requireId(questionId, ERROR_QUESTION_ID_REQUIRED);
            ensureFundingOpportunityAllowsFormEditing(getQuestionFundingOpportunityId(questionId));
            ensureQuestionIsCustom(questionId);
            ApplicationFormLifecycleService.updateMandatoryStatus(questionId, isMandatory);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_UPDATE_MANDATORY_FAILED, e);
        }
    }

    @AuraEnabled
    public static QuestionDetailWrapper getQuestionForEdit(Id questionId) {
        try {
            requireId(questionId, ERROR_QUESTION_ID_REQUIRED);
            ensureQuestionIsCustom(questionId);

            AssessmentQuestion question = [
                SELECT Id, Name, DataType, isTable__c, MaximumCharacters__c,
                       RecordType.DeveloperName, ObjectAPIName__c, FieldAPIName__c
                FROM AssessmentQuestion
                WHERE Id = :questionId
                WITH USER_MODE
                LIMIT 1
            ];

            List<AssessmentQuestionVersion> versions = [
                SELECT QuestionText, QuestionTextFR__c, Description, ResponseValues, ResponseValuesFR__c, HelpText,
                       IsActive, AdditionalInformation
                FROM AssessmentQuestionVersion
                WHERE AssessmentQuestionId = :questionId
                WITH USER_MODE
                ORDER BY IsActive DESC, CreatedDate DESC
                LIMIT 1
            ];
            if (versions.isEmpty()) {
                fail(ERROR_QUESTION_VERSION_NOT_FOUND);
            }
            AssessmentQuestionVersion version = versions[0];

            List<AssessmentQuestionAssignment> assignments = [
                SELECT IsMandatory__c
                FROM AssessmentQuestionAssignment
                WHERE AssessmentQuestionId = :questionId
                WITH USER_MODE
                LIMIT 1
            ];

            QuestionDetailWrapper detail = new QuestionDetailWrapper();
            detail.questionId = question.Id;
            detail.name = question.Name;
            detail.dataType = question.DataType;
            detail.isTable = question.isTable__c;
            detail.maximumCharacters = question.MaximumCharacters__c;
            detail.questionText = version.QuestionText;
            detail.description = version.Description;
            detail.responseValues = version.ResponseValues;
            detail.questionTextFr = version.QuestionTextFR__c;
            detail.responseValuesFr = version.ResponseValuesFR__c;
            detail.helpText = version.HelpText;
            detail.isActive = version.IsActive;
            detail.isFixed = question.RecordType.DeveloperName == 'Fixed';
            detail.objectApiName = question.ObjectAPIName__c;
            detail.fieldApiName = question.FieldAPIName__c;
            detail.columns = String.isNotBlank(version.AdditionalInformation)
                ? (List<ColumnWrapper>) JSON.deserialize(version.AdditionalInformation, List<ColumnWrapper>.class)
                : new List<ColumnWrapper>();
            detail.isMandatory = assignments.isEmpty() ? true : assignments[0].IsMandatory__c != false;
            return detail;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_LOAD_QUESTION_FAILED, e);
        }
    }

    @AuraEnabled
    public static void updateQuestion(
        Id questionId,
        String name,
        String questionText,
        String dataType,
        String description,
        String responseValues,
        String helpText,
        Decimal maximumCharacters,
        Boolean isTable,
        String columnsJson,
        String questionTextFr,
        String responseValuesFr
    ) {
        try {
            requireId(questionId, ERROR_QUESTION_ID_REQUIRED);
            requireText(questionText, ERROR_QUESTION_TEXT_REQUIRED);
            validateTranslation(responseValues, responseValuesFr);
            name = resolveQuestionName(name, questionText);
            ensureFundingOpportunityAllowsFormEditing(getQuestionFundingOpportunityId(questionId));
            validateMaximumCharacters(dataType, maximumCharacters);

            AssessmentQuestion existingQuestion = [
                SELECT Id, RecordType.DeveloperName
                FROM AssessmentQuestion
                WHERE Id = :questionId
                WITH USER_MODE
                LIMIT 1
            ];
            if (existingQuestion.RecordType.DeveloperName == 'Fixed') {
                fail(ERROR_FIXED_QUESTION_NOT_EDITABLE);
            }
            ensureQuestionIsCustom(questionId);

            List<AssessmentQuestionVersion> versions = [
                SELECT Id
                FROM AssessmentQuestionVersion
                WHERE AssessmentQuestionId = :questionId
                WITH USER_MODE
                ORDER BY IsActive DESC, CreatedDate DESC
                LIMIT 1
            ];
            if (versions.isEmpty()) {
                fail(ERROR_QUESTION_VERSION_NOT_FOUND);
            }
            AssessmentQuestionVersion version = versions[0];

            List<ColumnWrapper> columns = String.isNotBlank(columnsJson)
                ? (List<ColumnWrapper>) JSON.deserialize(columnsJson, List<ColumnWrapper>.class)
                : null;
            String additionalInformation = ApplicationFormLifecycleService.serializeTableColumns(isTable, columns);

            // A question created through the builder is Active from the start (US-042), so
            // editing it never rewrites its published version in place: that version is
            // archived (Status/VersionNumber/timestamps are platform-managed off IsActive), and
            // the edit lands on a brand new active version. This must land BEFORE the DataType
            // change below: the platform validates "ResponseValues required for Select/Multiselect/
            // RadioGroup" against whichever version is active at the time of that AssessmentQuestion
            // update, so switching DataType first would check it against the still-active OLD
            // version (which has no ResponseValues yet) and fail with REQUIRED_FIELD_MISSING.
            Database.update(
                new AssessmentQuestionVersion(Id = version.Id, IsActive = false),
                AccessLevel.USER_MODE
            );
            Database.insert(
                new AssessmentQuestionVersion(
                    Name = name.left(80),
                    AssessmentQuestionId = questionId,
                    QuestionText = questionText,
                    Description = description,
                    ResponseValues = responseValues,
                    HelpText = helpText,
                    AdditionalInformation = additionalInformation,
                    QuestionTextFR__c = cleanTranslation(questionTextFr),
                    ResponseValuesFR__c = cleanTranslation(responseValuesFr),
                    IsActive = true
                ),
                AccessLevel.USER_MODE
            );

            Database.update(
                new AssessmentQuestion(
                    Id = questionId,
                    Name = name.left(80),
                    DeveloperName = ApplicationFormLifecycleService.toDeveloperName(name),
                    DataType = dataType,
                    isTable__c = isTable == true,
                    MaximumCharacters__c = maximumCharacters
                ),
                AccessLevel.USER_MODE
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_UPDATE_QUESTION_FAILED, e);
        }
    }

    // Every pillar but Science expects the French question text and response values.
    @AuraEnabled(cacheable=true)
    public static Boolean isTranslationExpected(Id fundingOpportunityId) {
        try {
            requireId(fundingOpportunityId, ERROR_FUNDING_OPPORTUNITY_REQUIRED);
            return FormLanguageService.isTranslationExpected(fundingOpportunityId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_READ_PILLAR_FAILED, e);
        }
    }

    // The French response values must line up one to one with the English ones: the English value at the same
    // position is saved. Checked before any DML, so a rejected translation creates or changes nothing.
    private static void validateTranslation(String responseValues, String responseValuesFr) {
        final Boolean isSameCount =
            splitResponseValues(responseValuesFr).size() == splitResponseValues(responseValues).size();
        if (String.isNotBlank(responseValuesFr) && !isSameCount) {
            fail(ERROR_TRANSLATION_LINE_COUNT_MISMATCH);
        }
    }

    private static String cleanTranslation(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    // The question name is managed in the back: when none is given, it is the question text on one line.
    @TestVisible
    private static String resolveQuestionName(String name, String questionText) {
        final String source = String.isNotBlank(name) ? name : questionText;
        return source.normalizeSpace().left(80);
    }

    // One value per line, blank lines ignored, as the form displays them.
    private static List<String> splitResponseValues(String responseValues) {
        final List<String> values = new List<String>();
        for (String line : (responseValues == null ? '' : responseValues).split('\\r?\\n')) {
            if (String.isNotBlank(line)) {
                values.add(line.trim());
            }
        }
        return values;
    }

    @AuraEnabled(cacheable=true)
    public static List<ColumnWrapper> getTableColumns(Id questionId) {
        try {
            requireId(questionId, ERROR_QUESTION_ID_REQUIRED);
            List<AssessmentQuestionVersion> versions = [
                SELECT AdditionalInformation
                FROM AssessmentQuestionVersion
                WHERE AssessmentQuestionId = :questionId
                WITH USER_MODE
                ORDER BY IsActive DESC, CreatedDate DESC
                LIMIT 1
            ];
            String additionalInformation = !versions.isEmpty() ? versions[0].AdditionalInformation : null;
            if (String.isBlank(additionalInformation)) {
                return new List<ColumnWrapper>();
            }
            return (List<ColumnWrapper>) JSON.deserialize(additionalInformation, List<ColumnWrapper>.class);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_LOAD_TABLE_COLUMNS_FAILED, e);
        }
    }

    // ===================== REMOVE (deactivate or permanently delete) =====================
    @AuraEnabled
    public static RemovalResultWrapper removePreconfiguredQuestionAssignments(
        Id fundingOpportunityId,
        List<Id> assignmentIds
    ) {
        try {
            requireId(fundingOpportunityId, ERROR_FUNDING_OPPORTUNITY_REQUIRED);
            ensureFundingOpportunityAllowsFormEditing(fundingOpportunityId);
            if (assignmentIds == null || assignmentIds.isEmpty()) {
                fail(ERROR_PRECONFIGURED_SELECTION_REQUIRED);
            }

            Set<Id> requestedAssignmentIds = new Set<Id>(assignmentIds);

            List<AssessmentQuestionAssignment> assignments = [
                SELECT Id, AssessmentQuestionId, AssessmentQuestionSetId, AssessmentQuestion.RecordType.DeveloperName,
                    AssessmentQuestion.ObjectAPIName__c, AssessmentQuestion.FieldAPIName__c
                FROM AssessmentQuestionAssignment
                WHERE Id IN :requestedAssignmentIds
                    AND FundingOpportunity__c = :fundingOpportunityId
                WITH USER_MODE
            ];
            if (assignments.size() != requestedAssignmentIds.size()) {
                fail(ERROR_SELECTED_QUESTIONS_NOT_FOUND);
            }

            Set<Id> preconfiguredAssignmentIds = ApplicationFormCatalogueQueryService.getPreconfiguredAssignmentIds(
                fundingOpportunityId,
                requestedAssignmentIds
            );
            for (AssessmentQuestionAssignment aqa : assignments) {
                Boolean isMappedToCrm = String.isNotBlank(aqa.AssessmentQuestion.ObjectAPIName__c)
                    && String.isNotBlank(aqa.AssessmentQuestion.FieldAPIName__c);
                if (
                    aqa.AssessmentQuestion.RecordType.DeveloperName == 'Fixed'
                    || isMappedToCrm
                    || preconfiguredAssignmentIds.contains(aqa.Id)
                ) {
                    fail(ERROR_PROTECTED_QUESTION_NOT_REMOVABLE);
                }
            }

            // A section must always keep at least one question: reject the batch if it would
            // empty any section (the admin can delete that section entirely instead).
            Set<Id> affectedSectionIds = new Set<Id>();
            for (AssessmentQuestionAssignment aqa : assignments) {
                affectedSectionIds.add(aqa.AssessmentQuestionSetId);
            }
            Map<Id, Integer> totalCountBySectionId = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT AssessmentQuestionSetId sectionId, COUNT(Id) total
                FROM AssessmentQuestionAssignment
                WHERE AssessmentQuestionSetId IN :affectedSectionIds
                GROUP BY AssessmentQuestionSetId
            ]) {
                totalCountBySectionId.put((Id) ar.get('sectionId'), (Integer) ar.get('total'));
            }
            Map<Id, Integer> removedCountBySectionId = new Map<Id, Integer>();
            for (AssessmentQuestionAssignment aqa : assignments) {
                Integer count = removedCountBySectionId.get(aqa.AssessmentQuestionSetId);
                removedCountBySectionId.put(aqa.AssessmentQuestionSetId, (count == null ? 0 : count) + 1);
            }
            for (Id sectionId : affectedSectionIds) {
                Integer total = totalCountBySectionId.get(sectionId);
                Integer removed = removedCountBySectionId.get(sectionId);
                if (total != null && removed != null && total == removed) {
                    fail(ERROR_SECTION_CANNOT_BE_EMPTY);
                }
            }

            RemovalResultWrapper result = new RemovalResultWrapper();
            result.deletedCount = 0;
            result.errorMessages = new List<String>();
            Set<Id> deletedQuestionIds = new Set<Id>();
            List<Database.DeleteResult> deleteResults =
                Database.delete(assignments, false, AccessLevel.USER_MODE);

            for (Integer i = 0; i < deleteResults.size(); i++) {
                if (deleteResults[i].isSuccess()) {
                    result.deletedCount++;
                    deletedQuestionIds.add(assignments[i].AssessmentQuestionId);
                } else {
                    for (Database.Error error : deleteResults[i].getErrors()) {
                        result.errorMessages.add(error.getStatusCode() + ' - ' + error.getMessage());
                    }
                }
            }

            ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(deletedQuestionIds);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_REMOVE_CLONES_FAILED, e);
        }
    }

    @AuraEnabled
    public static void removeQuestionAssignment(Id assignmentId, Boolean permanentlyDelete) {
        try {
            requireId(assignmentId, ERROR_ASSIGNMENT_ID_REQUIRED);

            AssessmentQuestionAssignment aqa = [
                SELECT Id, AssessmentQuestionId, AssessmentQuestionSetId, FundingOpportunity__c,
                    AssessmentQuestion.RecordType.DeveloperName,
                    AssessmentQuestion.ObjectAPIName__c, AssessmentQuestion.FieldAPIName__c
                FROM AssessmentQuestionAssignment
                WHERE Id = :assignmentId
                WITH USER_MODE
                LIMIT 1
            ];
            ensureFundingOpportunityAllowsFormEditing(aqa.FundingOpportunity__c);

            if (permanentlyDelete == true) {
                Boolean isMappedToCrm = String.isNotBlank(aqa.AssessmentQuestion.ObjectAPIName__c)
                    && String.isNotBlank(aqa.AssessmentQuestion.FieldAPIName__c);
                if (aqa.AssessmentQuestion.RecordType.DeveloperName == 'Fixed' || isMappedToCrm) {
                    fail(ERROR_FIXED_QUESTION_NOT_REMOVABLE);
                }
                // A section must always keep at least one question: delete the whole section
                // instead of leaving it empty.
                Integer remainingInSection = [
                    SELECT COUNT()
                    FROM AssessmentQuestionAssignment
                    WHERE AssessmentQuestionSetId = :aqa.AssessmentQuestionSetId AND Id != :assignmentId
                ];
                if (remainingInSection == 0) {
                    fail(ERROR_SECTION_CANNOT_BE_EMPTY);
                }
                Database.delete(aqa, AccessLevel.USER_MODE);
                ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(new Set<Id>{ aqa.AssessmentQuestionId });
            }
            // "Deactivate" (permanentlyDelete = false) is temporarily a no-op: IsActive__c (the
            // field it used to flip) is being removed from AssessmentQuestionAssignment.
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_REMOVE_QUESTION_FAILED, e);
        }
    }

    @AuraEnabled
    public static void removeSectionAssignments(Id fundingOpportunityId, Id sectionId, Boolean permanentlyDelete) {
        try {
            requireId(sectionId, ERROR_SECTION_ID_REQUIRED);
            ensureFundingOpportunityAllowsFormEditing(fundingOpportunityId);
            if (fundingOpportunityId != null
                    && ApplicationFormCatalogueQueryService.isPreconfiguredSection(
                        fundingOpportunityId,
                        sectionId
                    )) {
                fail(ERROR_PRECONFIGURED_SECTION_NOT_REMOVABLE);
            }

            List<AssessmentQuestionAssignment> assignments = [
                SELECT Id, AssessmentQuestionId, AssessmentQuestion.RecordType.DeveloperName,
                    AssessmentQuestion.ObjectAPIName__c, AssessmentQuestion.FieldAPIName__c
                FROM AssessmentQuestionAssignment
                WHERE AssessmentQuestionSetId = :sectionId AND FundingOpportunity__c = :fundingOpportunityId
                WITH USER_MODE
            ];

            if (permanentlyDelete == true) {
                for (AssessmentQuestionAssignment aqa : assignments) {
                    Boolean isMappedToCrm = String.isNotBlank(aqa.AssessmentQuestion.ObjectAPIName__c)
                        && String.isNotBlank(aqa.AssessmentQuestion.FieldAPIName__c);
                    if (aqa.AssessmentQuestion.RecordType.DeveloperName == 'Fixed' || isMappedToCrm) {
                        fail(ERROR_FIXED_SECTION_NOT_REMOVABLE);
                    }
                }
                if (!assignments.isEmpty()) {
                    Set<Id> questionIds = new Set<Id>();
                    for (AssessmentQuestionAssignment aqa : assignments) {
                        questionIds.add(aqa.AssessmentQuestionId);
                    }
                    Database.delete(assignments, AccessLevel.USER_MODE);
                    ApplicationFormLifecycleService.purgeOrphanedDraftQuestions(questionIds);
                }
                Integer remainingAssignments = [
                    SELECT COUNT()
                    FROM AssessmentQuestionAssignment
                    WHERE AssessmentQuestionSetId = :sectionId
                ];
                if (remainingAssignments == 0) {
                    Database.delete(new AssessmentQuestionSet(Id = sectionId), AccessLevel.USER_MODE);
                }
            }
            // "Deactivate" (permanentlyDelete = false) is temporarily a no-op: IsActive__c (the
            // field it used to flip) is being removed from AssessmentQuestionAssignment.
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_REMOVE_SECTION_FAILED, e);
        }
    }

    // ===== SHARED CATALOG ORDERING (default order, not FO-specific) =====

    @AuraEnabled
    public static void reorderSections(List<Id> orderedSectionIds) {
        try {
            if (orderedSectionIds == null || orderedSectionIds.isEmpty()) {
                return;
            }
            ensureSectionsAllowFormEditing(new Set<Id>(orderedSectionIds));

            // The numbers already used by these sections are reused in the new order, so the
            // sections of a mode (EOI or not) keep their own range of numbers instead of being
            // renumbered from 1.
            List<Decimal> existingSequences = new List<Decimal>();
            for (AssessmentQuestionSet section : [
                SELECT Id, Sequence__c
                FROM AssessmentQuestionSet
                WHERE Id IN :orderedSectionIds
                WITH USER_MODE
            ]) {
                if (section.Sequence__c != null) {
                    existingSequences.add(section.Sequence__c);
                }
            }
            existingSequences.sort();

            // The numbers are redistributed as they are, duplicates included (cloned sections keep
            // the numbers of their templates, which overlap): a section that did not change
            // position keeps its number. Only a missing number continues after the previous one.
            List<AssessmentQuestionSet> toUpdate = new List<AssessmentQuestionSet>();
            Decimal previousSequence = 0;
            for (Integer i = 0; i < orderedSectionIds.size(); i++) {
                Decimal sequence = i < existingSequences.size() ? existingSequences[i] : previousSequence + 1;
                toUpdate.add(new AssessmentQuestionSet(Id = orderedSectionIds[i], Sequence__c = sequence));
                previousSequence = sequence;
            }
            Database.update(toUpdate, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw wrapException(ERROR_REORDER_SECTIONS_FAILED, e);
        }
    }

    @AuraEnabled
    public static void moveQuestion(Id assignmentId, Id targetSectionId, List<Id> targetSectionOrderedAssignmentIds) {
        try {
            requireId(assignmentId, ERROR_QUESTION_ASSIGNMENT_ID_REQUIRED);
            requireId(targetSectionId, ERROR_TARGET_SECTION_ID_REQUIRED);

            AssessmentQuestionAssignment movingAssignment = [
                SELECT Id, AssessmentQuestionId, AssessmentQuestionSetId, FundingOpportunity__c,
                    AssessmentQuestion.RecordType.DeveloperName,
                    AssessmentQuestion.ObjectAPIName__c, AssessmentQuestion.FieldAPIName__c
                FROM AssessmentQuestionAssignment
                WHERE Id = :assignmentId
                WITH USER_MODE
                LIMIT 1
            ];
            ensureFundingOpportunityAllowsFormEditing(movingAssignment.FundingOpportunity__c);
            Boolean isMovingQuestionMappedToCrm = String.isNotBlank(movingAssignment.AssessmentQuestion.ObjectAPIName__c)
                && String.isNotBlank(movingAssignment.AssessmentQuestion.FieldAPIName__c);
            if (movingAssignment.AssessmentQuestion.RecordType.DeveloperName == 'Fixed' || isMovingQuestionMappedToCrm) {
                fail(ERROR_FIXED_QUESTION_NOT_MOVABLE);
            }
            ensureQuestionIsCustom(movingAssignment.AssessmentQuestionId);
            if (movingAssignment.AssessmentQuestionSetId != targetSectionId) {
                Integer remainingInSourceSection = [
                    SELECT COUNT()
                    FROM AssessmentQuestionAssignment
                    WHERE AssessmentQuestionSetId = :movingAssignment.AssessmentQuestionSetId
                        AND FundingOpportunity__c = :movingAssignment.FundingOpportunity__c
                        AND Id != :assignmentId
                ];
                if (remainingInSourceSection == 0) {
                    fail(ERROR_SECTION_CANNOT_BE_EMPTY);
                }
            }

            Database.update(
                new AssessmentQuestionAssignment(Id = assignmentId, AssessmentQuestionSetId = targetSectionId),
                AccessLevel.USER_MODE
            );

            if (targetSectionOrderedAssignmentIds != null && !targetSectionOrderedAssignmentIds.isEmpty()) {
                applyQuestionOrder(targetSectionOrderedAssignmentIds, assignmentId);
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw wrapException(ERROR_MOVE_QUESTION_FAILED, e);
        }
    }

    @AuraEnabled
    public static void reorderQuestions(List<Id> orderedAssignmentIds) {
        try {
            applyQuestionOrder(orderedAssignmentIds, null);
        } catch (Exception e) {
            throw wrapException(ERROR_REORDER_QUESTIONS_FAILED, e);
        }
    }

    // Writes the sequence of the questions following the given order of assignments.
    // The numbers already used by the questions of the section (e.g. 10 to 15 for a template
    // section) are reused in the new order, so the section keeps its own range of numbers.
    // movedAssignmentId is the assignment just moved in from another section: its old number
    // belongs to its previous section, so it is left out and the range is extended by one number
    // instead, which leaves the questions before its new position untouched.
    private static void applyQuestionOrder(List<Id> orderedAssignmentIds, Id movedAssignmentId) {
        if (orderedAssignmentIds == null || orderedAssignmentIds.isEmpty()) {
            return;
        }
        ensureAssignmentsAllowFormEditing(new Set<Id>(orderedAssignmentIds));
        Map<Id, Id> questionIdByAssignmentId = new Map<Id, Id>();
        List<Decimal> existingSequences = new List<Decimal>();
        for (AssessmentQuestionAssignment aqa : [
            SELECT Id, AssessmentQuestionId, AssessmentQuestion.Sequence__c
            FROM AssessmentQuestionAssignment
            WHERE Id IN :orderedAssignmentIds
            WITH USER_MODE
        ]) {
            questionIdByAssignmentId.put(aqa.Id, aqa.AssessmentQuestionId);
            if (aqa.Id != movedAssignmentId && aqa.AssessmentQuestion.Sequence__c != null) {
                existingSequences.add(aqa.AssessmentQuestion.Sequence__c);
            }
        }
        existingSequences.sort();
        if (movedAssignmentId != null && questionIdByAssignmentId.containsKey(movedAssignmentId)) {
            existingSequences.add(
                existingSequences.isEmpty() ? 1 : existingSequences[existingSequences.size() - 1] + 1
            );
        }

        List<AssessmentQuestion> toUpdate = new List<AssessmentQuestion>();
        Decimal previousSequence = 0;
        for (Integer i = 0; i < orderedAssignmentIds.size(); i++) {
            Id questionId = questionIdByAssignmentId.get(orderedAssignmentIds[i]);
            if (questionId == null) {
                continue;
            }
            Decimal existingSequence = i < existingSequences.size() ? existingSequences[i] : null;
            // Keep the sequence strictly increasing: a duplicated or missing number continues
            // just after the previous one.
            Decimal sequence = existingSequence != null && existingSequence > previousSequence
                ? existingSequence
                : previousSequence + 1;
            toUpdate.add(new AssessmentQuestion(Id = questionId, Sequence__c = sequence));
            previousSequence = sequence;
        }
        Database.update(toUpdate, AccessLevel.USER_MODE);
    }

    // ===================== INTERNALS =====================

    // Allow question creation and editing only when the FundingOpportunity status is Active
    private static final Set<String> EDITABLE_STATUSES = new Set<String>{ 'Active' };

    private static void ensureFundingOpportunityAllowsFormEditing(Id fundingOpportunityId) {
        if (fundingOpportunityId == null) {
            return;
        }
        ensureFundingOpportunitiesAllowFormEditing(new Set<Id>{ fundingOpportunityId });
    }

    private static void ensureSectionsAllowFormEditing(Set<Id> sectionIds) {
        Set<Id> fundingOpportunityIds = new Set<Id>();
        for (AssessmentQuestionAssignment assignment : [
            SELECT FundingOpportunity__c
            FROM AssessmentQuestionAssignment
            WHERE AssessmentQuestionSetId IN :sectionIds AND FundingOpportunity__c != null
            WITH USER_MODE
        ]) {
            fundingOpportunityIds.add(assignment.FundingOpportunity__c);
        }
        ensureFundingOpportunitiesAllowFormEditing(fundingOpportunityIds);
    }

    private static void ensureAssignmentsAllowFormEditing(Set<Id> assignmentIds) {
        Set<Id> fundingOpportunityIds = new Set<Id>();
        for (AssessmentQuestionAssignment assignment : [
            SELECT FundingOpportunity__c
            FROM AssessmentQuestionAssignment
            WHERE Id IN :assignmentIds AND FundingOpportunity__c != null
            WITH USER_MODE
        ]) {
            fundingOpportunityIds.add(assignment.FundingOpportunity__c);
        }
        ensureFundingOpportunitiesAllowFormEditing(fundingOpportunityIds);
    }

    private static void ensureFundingOpportunitiesAllowFormEditing(Set<Id> fundingOpportunityIds) {
        if (fundingOpportunityIds.isEmpty()) {
            return;
        }
        for (FundingOpportunity fundingOpportunity : [
            SELECT Status
            FROM FundingOpportunity
            WHERE Id IN :fundingOpportunityIds
            WITH USER_MODE
        ]) {
            if (fundingOpportunity.Status != null && !EDITABLE_STATUSES.contains(fundingOpportunity.Status)) {
                fail(ERROR_FUNDING_OPPORTUNITY_NOT_ACTIVE);
            }
        }
    }

    private static Id getQuestionFundingOpportunityId(Id questionId) {
        List<AssessmentQuestionAssignment> assignments = [
            SELECT FundingOpportunity__c
            FROM AssessmentQuestionAssignment
            WHERE AssessmentQuestionId = :questionId AND FundingOpportunity__c != null
            WITH USER_MODE
            LIMIT 1
        ];
        return assignments.isEmpty() ? null : assignments[0].FundingOpportunity__c;
    }

    private static String getDefaultQuestionCategory() {
        String firstActiveValue;
        for (Schema.PicklistEntry entry :
                AssessmentQuestion.QuestionCategory.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            if (entry.isDefaultValue()) {
                return entry.getValue();
            }
            if (firstActiveValue == null) {
                firstActiveValue = entry.getValue();
            }
        }
        if (firstActiveValue == null) {
            fail(ERROR_QUESTION_CATEGORY_REQUIRED);
        }
        return firstActiveValue;
    }

    private static void ensureQuestionIsCustom(Id questionId) {
        if (ApplicationFormCatalogueQueryService.isPreconfiguredQuestion(questionId)) {
            fail(ERROR_PRECONFIGURED_CLONE_NOT_EDITABLE);
        }
    }

    private static Id getSectionFundingOpportunityId(Id sectionId) {
        List<AssessmentQuestionAssignment> assignments = [
            SELECT FundingOpportunity__c
            FROM AssessmentQuestionAssignment
            WHERE AssessmentQuestionSetId = :sectionId
            WITH USER_MODE
            LIMIT 1
        ];
        return assignments.isEmpty() ? null : assignments[0].FundingOpportunity__c;
    }

    private static void requireId(Id value, String code) {
        if (value == null) {
            fail(code);
        }
    }

    private static void requireText(String value, String code) {
        if (String.isBlank(value)) {
            fail(code);
        }
    }

    private static Boolean requiresMaximumCharacters(String dataType) {
        return dataType == 'Text' || dataType == 'TextArea';
    }

    private static void validateMaximumCharacters(String dataType, Decimal maximumCharacters) {
        if (requiresMaximumCharacters(dataType) && maximumCharacters == null) {
            fail(ERROR_MAXIMUM_CHARACTERS_REQUIRED);
        }
        if (maximumCharacters != null &&
            (maximumCharacters < 1 || maximumCharacters != maximumCharacters.setScale(0))) {
            fail(ERROR_MAXIMUM_CHARACTERS_INVALID);
        }
    }

    // Error codes translated by the LWC, with the English detail kept for the logs and the tests.
    private static final String ERROR_FUNDING_OPPORTUNITY_REQUIRED = 'FUNDING_OPPORTUNITY_REQUIRED';
    private static final String ERROR_LOAD_CONFIGURATION_FAILED = 'LOAD_CONFIGURATION_FAILED';
    private static final String ERROR_SECTION_ID_REQUIRED = 'SECTION_ID_REQUIRED';
    private static final String ERROR_SECTION_LABEL_REQUIRED = 'SECTION_LABEL_REQUIRED';
    private static final String ERROR_PRECONFIGURED_SECTION_NOT_EDITABLE = 'PRECONFIGURED_SECTION_NOT_EDITABLE';
    private static final String ERROR_FIXED_SECTION_NOT_EDITABLE = 'FIXED_SECTION_NOT_EDITABLE';
    private static final String ERROR_UPDATE_SECTION_FAILED = 'UPDATE_SECTION_FAILED';
    private static final String ERROR_CREATE_SECTION_FAILED = 'CREATE_SECTION_FAILED';
    private static final String ERROR_QUESTION_TEXT_REQUIRED = 'QUESTION_TEXT_REQUIRED';
    private static final String ERROR_QUESTION_SECTION_REQUIRED = 'QUESTION_SECTION_REQUIRED';
    private static final String ERROR_OBJECT_API_NAME_REQUIRED = 'OBJECT_API_NAME_REQUIRED';
    private static final String ERROR_FIELD_API_NAME_REQUIRED = 'FIELD_API_NAME_REQUIRED';
    private static final String ERROR_CUSTOM_QUESTION_NAME_TAKEN = 'CUSTOM_QUESTION_NAME_TAKEN';
    private static final String ERROR_CREATE_QUESTION_FAILED = 'CREATE_QUESTION_FAILED';
    private static final String ERROR_QUESTION_ID_REQUIRED = 'QUESTION_ID_REQUIRED';
    private static final String ERROR_UPDATE_MANDATORY_FAILED = 'UPDATE_MANDATORY_FAILED';
    private static final String ERROR_QUESTION_VERSION_NOT_FOUND = 'QUESTION_VERSION_NOT_FOUND';
    private static final String ERROR_LOAD_QUESTION_FAILED = 'LOAD_QUESTION_FAILED';
    private static final String ERROR_FIXED_QUESTION_NOT_EDITABLE = 'FIXED_QUESTION_NOT_EDITABLE';
    private static final String ERROR_UPDATE_QUESTION_FAILED = 'UPDATE_QUESTION_FAILED';
    private static final String ERROR_READ_PILLAR_FAILED = 'READ_PILLAR_FAILED';
    private static final String ERROR_TRANSLATION_LINE_COUNT_MISMATCH = 'TRANSLATION_LINE_COUNT_MISMATCH';
    private static final String ERROR_LOAD_TABLE_COLUMNS_FAILED = 'LOAD_TABLE_COLUMNS_FAILED';
    private static final String ERROR_PRECONFIGURED_SELECTION_REQUIRED = 'PRECONFIGURED_SELECTION_REQUIRED';
    private static final String ERROR_SELECTED_QUESTIONS_NOT_FOUND = 'SELECTED_QUESTIONS_NOT_FOUND';
    private static final String ERROR_PROTECTED_QUESTION_NOT_REMOVABLE = 'PROTECTED_QUESTION_NOT_REMOVABLE';
    private static final String ERROR_SECTION_CANNOT_BE_EMPTY = 'SECTION_CANNOT_BE_EMPTY';
    private static final String ERROR_REMOVE_CLONES_FAILED = 'REMOVE_CLONES_FAILED';
    private static final String ERROR_ASSIGNMENT_ID_REQUIRED = 'ASSIGNMENT_ID_REQUIRED';
    private static final String ERROR_FIXED_QUESTION_NOT_REMOVABLE = 'FIXED_QUESTION_NOT_REMOVABLE';
    private static final String ERROR_REMOVE_QUESTION_FAILED = 'REMOVE_QUESTION_FAILED';
    private static final String ERROR_PRECONFIGURED_SECTION_NOT_REMOVABLE = 'PRECONFIGURED_SECTION_NOT_REMOVABLE';
    private static final String ERROR_FIXED_SECTION_NOT_REMOVABLE = 'FIXED_SECTION_NOT_REMOVABLE';
    private static final String ERROR_REMOVE_SECTION_FAILED = 'REMOVE_SECTION_FAILED';
    private static final String ERROR_REORDER_SECTIONS_FAILED = 'REORDER_SECTIONS_FAILED';
    private static final String ERROR_QUESTION_ASSIGNMENT_ID_REQUIRED = 'QUESTION_ASSIGNMENT_ID_REQUIRED';
    private static final String ERROR_TARGET_SECTION_ID_REQUIRED = 'TARGET_SECTION_ID_REQUIRED';
    private static final String ERROR_FIXED_QUESTION_NOT_MOVABLE = 'FIXED_QUESTION_NOT_MOVABLE';
    private static final String ERROR_MOVE_QUESTION_FAILED = 'MOVE_QUESTION_FAILED';
    private static final String ERROR_REORDER_QUESTIONS_FAILED = 'REORDER_QUESTIONS_FAILED';
    private static final String ERROR_FUNDING_OPPORTUNITY_NOT_ACTIVE = 'FUNDING_OPPORTUNITY_NOT_ACTIVE';
    private static final String ERROR_QUESTION_CATEGORY_REQUIRED = 'QUESTION_CATEGORY_REQUIRED';
    private static final String ERROR_PRECONFIGURED_CLONE_NOT_EDITABLE = 'PRECONFIGURED_CLONE_NOT_EDITABLE';
    private static final String ERROR_MAXIMUM_CHARACTERS_REQUIRED = 'MAXIMUM_CHARACTERS_REQUIRED';
    private static final String ERROR_MAXIMUM_CHARACTERS_INVALID = 'MAXIMUM_CHARACTERS_INVALID';

    private static final Map<String, String> DETAILS_BY_CODE = new Map<String, String>{
        ERROR_FUNDING_OPPORTUNITY_REQUIRED =>
            'A Funding Opportunity is required.',
        ERROR_LOAD_CONFIGURATION_FAILED =>
            'Unable to load the Funding Opportunity configuration',
        ERROR_SECTION_ID_REQUIRED =>
            'A section Id is required.',
        ERROR_SECTION_LABEL_REQUIRED =>
            'The section label is required.',
        ERROR_PRECONFIGURED_SECTION_NOT_EDITABLE =>
            'A preconfigured section cannot be edited.',
        ERROR_FIXED_SECTION_NOT_EDITABLE =>
            'A section containing a Fixed question cannot be edited here.',
        ERROR_UPDATE_SECTION_FAILED =>
            'Unable to update the section',
        ERROR_CREATE_SECTION_FAILED =>
            'Unable to create the section',
        ERROR_QUESTION_TEXT_REQUIRED =>
            'The question text is required.',
        ERROR_QUESTION_SECTION_REQUIRED =>
            'A section must be selected for this question.',
        ERROR_OBJECT_API_NAME_REQUIRED =>
            'An Object API Name is required for a Fixed question.',
        ERROR_FIELD_API_NAME_REQUIRED =>
            'A Field API Name is required for a Fixed question.',
        ERROR_CUSTOM_QUESTION_NAME_TAKEN =>
            'A CUSTOM question must have a different name from the preconfigured question in this section.',
        ERROR_CREATE_QUESTION_FAILED =>
            'Unable to create the question',
        ERROR_QUESTION_ID_REQUIRED =>
            'A question Id is required.',
        ERROR_UPDATE_MANDATORY_FAILED =>
            'Unable to update the question\'s mandatory status',
        ERROR_QUESTION_VERSION_NOT_FOUND =>
            'No version found for this question.',
        ERROR_LOAD_QUESTION_FAILED =>
            'Unable to load the question',
        ERROR_FIXED_QUESTION_NOT_EDITABLE =>
            'A Fixed question is mapped to a Salesforce field and cannot be edited here.',
        ERROR_UPDATE_QUESTION_FAILED =>
            'Unable to update the question',
        ERROR_READ_PILLAR_FAILED =>
            'Unable to read the pillar of the program',
        ERROR_TRANSLATION_LINE_COUNT_MISMATCH =>
            'The French response values must have as many lines as the English ones, in the same order.',
        ERROR_LOAD_TABLE_COLUMNS_FAILED =>
            'Unable to load the table columns',
        ERROR_PRECONFIGURED_SELECTION_REQUIRED =>
            'Select at least one preconfigured question to remove.',
        ERROR_SELECTED_QUESTIONS_NOT_FOUND =>
            'Some selected questions could not be found for this Funding Opportunity.',
        ERROR_PROTECTED_QUESTION_NOT_REMOVABLE =>
            'A Fixed, CRM-mapped or preconfigured question cannot be removed here.',
        ERROR_SECTION_CANNOT_BE_EMPTY =>
            'A section must contain at least one question. Delete the section itself instead.',
        ERROR_REMOVE_CLONES_FAILED =>
            'Unable to remove the preconfigured question clones',
        ERROR_ASSIGNMENT_ID_REQUIRED =>
            'An assignment Id is required.',
        ERROR_FIXED_QUESTION_NOT_REMOVABLE =>
            'A Fixed question is mapped to a Salesforce field and cannot be removed here.',
        ERROR_REMOVE_QUESTION_FAILED =>
            'Unable to remove the question',
        ERROR_PRECONFIGURED_SECTION_NOT_REMOVABLE =>
            'A preconfigured section cannot be removed.',
        ERROR_FIXED_SECTION_NOT_REMOVABLE =>
            'A section containing a Fixed question cannot be removed here.',
        ERROR_REMOVE_SECTION_FAILED =>
            'Unable to remove the section',
        ERROR_REORDER_SECTIONS_FAILED =>
            'Unable to reorder the sections',
        ERROR_QUESTION_ASSIGNMENT_ID_REQUIRED =>
            'A question assignment Id is required.',
        ERROR_TARGET_SECTION_ID_REQUIRED =>
            'A target section Id is required.',
        ERROR_FIXED_QUESTION_NOT_MOVABLE =>
            'A Fixed question cannot be moved.',
        ERROR_MOVE_QUESTION_FAILED =>
            'Unable to move the question',
        ERROR_REORDER_QUESTIONS_FAILED =>
            'Unable to reorder the questions',
        ERROR_FUNDING_OPPORTUNITY_NOT_ACTIVE =>
            'The questionnaire can only be modified while the Funding Opportunity status is Active.',
        ERROR_QUESTION_CATEGORY_REQUIRED =>
            'At least one active Question Category is required.',
        ERROR_PRECONFIGURED_CLONE_NOT_EDITABLE =>
            'A preconfigured question clone cannot be modified.',
        ERROR_MAXIMUM_CHARACTERS_REQUIRED =>
            'Maximum Characters is required when Data Type is Text or Text Area.',
        ERROR_MAXIMUM_CHARACTERS_INVALID =>
            'The maximum character count must be a positive whole number.'
    };

    private static void fail(String code) {
        throw FormLanguageService.buildError(code, null, DETAILS_BY_CODE.get(code));
    }

    private static AuraHandledException wrapException(String code, Exception e) {
        return FormLanguageService.buildError(code, null, DETAILS_BY_CODE.get(code) + ': ' + e.getMessage());
    }
}