/**
 * @description       : Manages application form questions and clones their catalogues onto Funding Opportunities.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 19-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   22-09-2026   LAN      Initial version
 * 1.1   08-10-2026   KRA      Add the generic question clone engine
 * 1.2   19-10-2026   LAN      Copy the budget table configuration onto cloned question versions
 **/
public with sharing class ApplicationFormLifecycleService {

  public static void purgeOrphanedDraftQuestions(Set<Id> questionIds) {
    if (questionIds == null || questionIds.isEmpty()) {
      return;
    }

    Set<Id> questionIdsWithAssignments = new Set<Id>();
    for (AssessmentQuestionAssignment aqa : [
      SELECT AssessmentQuestionId
      FROM AssessmentQuestionAssignment
      WHERE AssessmentQuestionId IN :questionIds
      WITH USER_MODE
    ]) {
      questionIdsWithAssignments.add(aqa.AssessmentQuestionId);
    }

    Set<Id> orphanCandidateIds = questionIds.clone();
    orphanCandidateIds.removeAll(questionIdsWithAssignments);
    if (orphanCandidateIds.isEmpty()) {
      return;
    }

    Set<Id> questionIdsWithNonDraftVersion = new Set<Id>();
    List<AssessmentQuestionVersion> draftVersionsByCandidate = [
      SELECT Id, AssessmentQuestionId, Status
      FROM AssessmentQuestionVersion
      WHERE AssessmentQuestionId IN :orphanCandidateIds
      WITH USER_MODE
    ];
    for (AssessmentQuestionVersion version : draftVersionsByCandidate) {
      if (version.Status != 'Draft') {
        questionIdsWithNonDraftVersion.add(version.AssessmentQuestionId);
      }
    }

    List<AssessmentQuestionVersion> versionsToDelete = new List<AssessmentQuestionVersion>();
    List<AssessmentQuestion> questionsToDelete = new List<AssessmentQuestion>();
    for (Id candidateId : orphanCandidateIds) {
      if (!questionIdsWithNonDraftVersion.contains(candidateId)) {
        questionsToDelete.add(new AssessmentQuestion(Id = candidateId));
      }
    }
    for (AssessmentQuestionVersion version : draftVersionsByCandidate) {
      if (!questionIdsWithNonDraftVersion.contains(version.AssessmentQuestionId)) {
        versionsToDelete.add(version);
      }
    }

    if (!versionsToDelete.isEmpty()) {
      Database.delete(versionsToDelete, AccessLevel.USER_MODE);
    }
    if (!questionsToDelete.isEmpty()) {
      Database.delete(questionsToDelete, AccessLevel.USER_MODE);
    }
  }

  public static void updateMandatoryStatus(Id questionId, Boolean isMandatory) {
    List<AssessmentQuestionAssignment> assignments = [
      SELECT Id
      FROM AssessmentQuestionAssignment
      WHERE AssessmentQuestionId = :questionId
      WITH USER_MODE
      LIMIT 1
    ];
    if (!assignments.isEmpty()) {
      Database.update(
        new AssessmentQuestionAssignment(Id = assignments[0].Id, IsMandatory__c = isMandatory != false),
        AccessLevel.USER_MODE
      );
    }
  }

  public static String serializeTableColumns(Boolean isTable, List<ApplicationFormCatalogueController.ColumnWrapper> columns) {
    if (isTable != true || columns == null || columns.isEmpty()) {
      return null;
    }
    List<ApplicationFormCatalogueController.ColumnWrapper> validColumns = new List<ApplicationFormCatalogueController.ColumnWrapper>();
    for (ApplicationFormCatalogueController.ColumnWrapper column : columns) {
      if (String.isBlank(column.label)) {
        continue;
      }
      if (String.isBlank(column.developerName)) {
        column.developerName = toDeveloperName(column.label);
      }
      validColumns.add(column);
    }
    return validColumns.isEmpty() ? null : JSON.serialize(validColumns);
  }

  public static String toDeveloperName(String label) {
    if (String.isBlank(label)) {
      return 'Item' + String.valueOf(Datetime.now().getTime());
    }
    List<String> words = label.split('[^a-zA-Z0-9]+');
    String pascalCase = '';
    for (String word : words) {
      if (String.isNotBlank(word)) {
        pascalCase += word.substring(0, 1).toUpperCase() + word.substring(1).toLowerCase();
      }
    }
    if (pascalCase.length() > 0 && pascalCase.substring(0, 1).isNumeric()) {
      pascalCase = 'Q' + pascalCase;
    }
    return pascalCase.left(80);
  }

  /**
   * Seeds new Funding Opportunities with template questions:
   * 1. Combine common templates with those of each pillar.
   * 2. Exclude EOI questions unless the record type is Call for Projects.
   * 3. Clone the selected questions onto each Funding Opportunity.
   */
  public static void cloneTemplateQuestionCataloguesToFundingOpportunities(Set<Id> fundingOpportunityIds) {
    if (fundingOpportunityIds == null || fundingOpportunityIds.isEmpty()) {
      return;
    }

    final List<FundingOpportunity> fundingOpportunities = [
      SELECT
        Id,
        ProgramId,
        RecordTypeId
      FROM
        FundingOpportunity
      WHERE
        Id IN :fundingOpportunityIds
      WITH
        SYSTEM_MODE
    ];
    if (fundingOpportunities.isEmpty()) {
      return;
    }

    final Map<Id, Set<Id>> templateQAIdsWithEOIByProgramId    = new Map<Id, Set<Id>>{ null => new Set<Id>() };
    final Map<Id, Set<Id>> templateQAIdsWithoutEOIByProgramId = new Map<Id, Set<Id>>{ null => new Set<Id>() };
    for (FundingOpportunity fundingOpportunity : fundingOpportunities) {
      final Id programId = fundingOpportunity.ProgramId;
      if (!templateQAIdsWithEOIByProgramId.containsKey(programId)) {
        templateQAIdsWithEOIByProgramId.put(programId, new Set<Id>());
        templateQAIdsWithoutEOIByProgramId.put(programId, new Set<Id>());
      }
    }

    final Set<Id> programIds = templateQAIdsWithEOIByProgramId.keySet();
    for (AssessmentQuestionAssignment templateQA : queryTemplateQuestionAssignments(programIds)) {
      final Id programId    = templateQA.Program__c;
      final Id templateQAId = templateQA.Id;
      templateQAIdsWithEOIByProgramId.get(programId).add(templateQAId);
      if (!templateQA.EOI__c) {
        templateQAIdsWithoutEOIByProgramId.get(programId).add(templateQAId);
      }
    }

    final Set<Id> commonTemplateQAIdsWithEOI    = templateQAIdsWithEOIByProgramId.get(null);
    final Set<Id> commonTemplateQAIdsWithoutEOI = templateQAIdsWithoutEOIByProgramId.get(null);
    for (Id programId : programIds) {
      if (programId != null) {
        templateQAIdsWithEOIByProgramId.get(programId).addAll(commonTemplateQAIdsWithEOI);
        templateQAIdsWithoutEOIByProgramId.get(programId).addAll(commonTemplateQAIdsWithoutEOI);
      }
    }

    final Id FOCallForProjectsRecordTypeId = FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS.Id;
    final Map<Id, Set<Id>> templateQAIdsByTargetFOId = new Map<Id, Set<Id>>();
    for (FundingOpportunity fundingOpportunity : fundingOpportunities) {
      templateQAIdsByTargetFOId.put(
        fundingOpportunity.Id,
        (fundingOpportunity.RecordTypeId == FOCallForProjectsRecordTypeId
          ? templateQAIdsWithEOIByProgramId
          : templateQAIdsWithoutEOIByProgramId
        ).get(fundingOpportunity.ProgramId)
      );
    }

    cloneQuestionCataloguesToFundingOpportunities(templateQAIdsByTargetFOId);
  }

  public static Map<Boolean, Map<Id, Set<Id>>> queryTemplateQuestionAssignmentIdsByIsEOIByProgramId(
    Set<Id> programIds
  ) {
    final Map<Id, Set<Id>> EOITemplateQAIdsByProgramId             = new Map<Id, Set<Id>>{ null => new Set<Id>() };
    final Map<Id, Set<Id>> fullApplicationTemplateQAIdsByProgramId = new Map<Id, Set<Id>>{ null => new Set<Id>() };
    final Map<Boolean, Map<Id, Set<Id>>> templateQAIdsByIsEOIByProgramId = new Map<Boolean, Map<Id, Set<Id>>>{
      true  => EOITemplateQAIdsByProgramId,
      false => fullApplicationTemplateQAIdsByProgramId
    };
    if (programIds.isEmpty()) {
      return templateQAIdsByIsEOIByProgramId;
    }

    for (Id programId : programIds) {
      EOITemplateQAIdsByProgramId.put(programId, new Set<Id>());
      fullApplicationTemplateQAIdsByProgramId.put(programId, new Set<Id>());
    }
    for (AssessmentQuestionAssignment templateQA : queryTemplateQuestionAssignments(programIds)) {
      (templateQA.EOI__c ? EOITemplateQAIdsByProgramId : fullApplicationTemplateQAIdsByProgramId)
        .get(templateQA.Program__c)
        .add(templateQA.Id);
    }

    return templateQAIdsByIsEOIByProgramId;
  }

  private static List<AssessmentQuestionAssignment> queryTemplateQuestionAssignments(Set<Id> programIds) {
    return [
      SELECT
        Id,
        Program__c,
        EOI__c
      FROM
        AssessmentQuestionAssignment
      WHERE
        FundingOpportunity__c = null
        AND (Program__c = null OR Program__c IN :programIds)
      WITH
        SYSTEM_MODE
    ];
  }

  // ============================== <Clone engine> ==============================

  @TestVisible
  private static final Integer DEVELOPER_NAME_MAX_LENGTH = 80;
  private static final String  DEVELOPER_NAME_SEPARATOR  = '_';

  private static final String KEY_SEPARATOR = '|';

  private class QuestionClone {
    public final Id sourceQuestionId;
    public final AssessmentQuestionSet clonedSection;
    public final AssessmentQuestion clonedQuestion;
    public final AssessmentQuestionAssignment clonedQuestionAssignment;

    public QuestionClone(
      Id sourceQuestionId,
      AssessmentQuestionSet clonedSection,
      AssessmentQuestion clonedQuestion,
      AssessmentQuestionAssignment clonedQuestionAssignment
    ) {
      this.sourceQuestionId = sourceQuestionId;
      this.clonedSection    = clonedSection;
      this.clonedQuestion   = clonedQuestion;
      this.clonedQuestionAssignment = clonedQuestionAssignment;
    }
  }

  public static void cloneQuestionCataloguesToFundingOpportunities(Map<Id, Set<Id>> questionAssignmentIdsByTargetFOId) {
    if (questionAssignmentIdsByTargetFOId == null || questionAssignmentIdsByTargetFOId.isEmpty()) {
      return;
    }

    final Set<Id> allQuestionAssignmentIds = new Set<Id>();
    for (Set<Id> questionAssignmentIds : questionAssignmentIdsByTargetFOId.values()) {
      if (questionAssignmentIds != null) {
        allQuestionAssignmentIds.addAll(questionAssignmentIds);
      }
    }
    if (allQuestionAssignmentIds.isEmpty()) {
      return;
    }

    final Map<Id, AssessmentQuestionAssignment> questionAssignmentById =
      new Map<Id, AssessmentQuestionAssignment>(queryQuestionAssignments(allQuestionAssignmentIds));

    final Set<String> questionKeys = new Set<String>();
    final Map<String, AssessmentQuestionSet> clonedSectionBySectionKey = new Map<String, AssessmentQuestionSet>();
    final List<AssessmentQuestion> clonedQuestions = new List<AssessmentQuestion>();
    final Set<Id> sourceQuestionIds = new Set<Id>();
    final List<QuestionClone> questionClones = new List<QuestionClone>();

    for (Id targetFOId : questionAssignmentIdsByTargetFOId.keySet()) {
      final Set<Id> questionAssignmentIds = questionAssignmentIdsByTargetFOId.get(targetFOId);
      if (questionAssignmentIds == null) {
        continue;
      }

      final String developerNameSuffixBase = DEVELOPER_NAME_SEPARATOR + targetFOId + DEVELOPER_NAME_SEPARATOR;
      final String sectionKeyPrefix = targetFOId + KEY_SEPARATOR;

      for (Id questionAssignmentId : questionAssignmentIds) {
        final AssessmentQuestionAssignment sourceQuestionAssignment = questionAssignmentById.get(questionAssignmentId);
        if (sourceQuestionAssignment == null) {
          continue;
        }

        final AssessmentQuestionSet sourceSection = sourceQuestionAssignment.AssessmentQuestionSet;
        final AssessmentQuestion sourceQuestion   = sourceQuestionAssignment.AssessmentQuestion;
        final String sourceSectionName  = sourceSection.Name;
        final String sourceQuestionName = sourceQuestion.Name;

        // Templates may contain duplicates, so sections with the same name are merged.
        // Within each section, only one question per name is copied.
        final String sectionKey = sectionKeyPrefix + sourceSectionName;
        if (!questionKeys.add(sectionKey + KEY_SEPARATOR + sourceQuestionName)) {
          continue;
        }

        AssessmentQuestionSet clonedSection = clonedSectionBySectionKey.get(sectionKey);
        if (clonedSection == null) {
          clonedSection = new AssessmentQuestionSet(
            Name          = sourceSectionName,
            DeveloperName = buildUniqueDeveloperName(
              sourceSectionName,
              developerNameSuffixBase + clonedSectionBySectionKey.size()
            ),
            Sequence__c   = sourceSection.Sequence__c
          );
          clonedSectionBySectionKey.put(sectionKey, clonedSection);
        }

        final AssessmentQuestion clonedQuestion = new AssessmentQuestion(
          Name                 = sourceQuestionName,
          DeveloperName        = buildUniqueDeveloperName(
            sourceQuestionName,
            developerNameSuffixBase + clonedQuestions.size()
          ),
          DataType             = sourceQuestion.DataType,
          QuestionCategory     = sourceQuestion.QuestionCategory,
          isTable__c           = sourceQuestion.isTable__c,
          ObjectAPIName__c     = sourceQuestion.ObjectAPIName__c,
          FieldAPIName__c      = sourceQuestion.FieldAPIName__c,
          MaximumCharacters__c = sourceQuestion.MaximumCharacters__c,
          Sequence__c          = sourceQuestion.Sequence__c
        );
        final Id sourceRecordTypeId = sourceQuestion.RecordTypeId;
        if (sourceRecordTypeId != null) {
          clonedQuestion.RecordTypeId = sourceRecordTypeId;
        }

        final Id sourceQuestionId = sourceQuestionAssignment.AssessmentQuestionId;
        clonedQuestions.add(clonedQuestion);
        sourceQuestionIds.add(sourceQuestionId);
        questionClones.add(new QuestionClone(
          sourceQuestionId,
          clonedSection,
          clonedQuestion,
          new AssessmentQuestionAssignment(
            FundingOpportunity__c = targetFOId,
            EOI__c                = sourceQuestionAssignment.EOI__c,
            IsMandatory__c        = sourceQuestionAssignment.IsMandatory__c
          )
        ));
      }
    }

    if (questionClones.isEmpty()) {
      return;
    }

    Database.insert(clonedSectionBySectionKey.values(), AccessLevel.USER_MODE);
    Database.insert(clonedQuestions, AccessLevel.USER_MODE);
    insertClonedVersionsAndQuestionAssignments(
      questionClones,
      ApplicationFormCatalogueQueryService.getLatestVersionByQuestionId(sourceQuestionIds)
    );
  }

  private static List<AssessmentQuestionAssignment> queryQuestionAssignments(Set<Id> questionAssignmentIds) {
    return [
      SELECT
        Id,
        EOI__c,
        IsMandatory__c,
        AssessmentQuestionSet.Name,
        AssessmentQuestionSet.Sequence__c,
        AssessmentQuestionId,
        AssessmentQuestion.Name,
        AssessmentQuestion.DataType,
        AssessmentQuestion.QuestionCategory,
        AssessmentQuestion.isTable__c,
        AssessmentQuestion.ObjectAPIName__c,
        AssessmentQuestion.FieldAPIName__c,
        AssessmentQuestion.MaximumCharacters__c,
        AssessmentQuestion.Sequence__c,
        AssessmentQuestion.RecordTypeId
      FROM
        AssessmentQuestionAssignment
      WHERE
        Id IN :questionAssignmentIds
      WITH
        SYSTEM_MODE
    ];
  }

  private static void insertClonedVersionsAndQuestionAssignments(
    List<QuestionClone> questionClones,
    Map<Id, AssessmentQuestionVersion> sourceVersionByQuestionId
  ) {
    final List<AssessmentQuestionVersion> clonedVersions = new List<AssessmentQuestionVersion>();
    final List<AssessmentQuestionAssignment> clonedQuestionAssignments = new List<AssessmentQuestionAssignment>();

    for (QuestionClone questionClone : questionClones) {
      final AssessmentQuestion clonedQuestion = questionClone.clonedQuestion;
      final Id clonedQuestionId = clonedQuestion.Id;
      final String clonedQuestionName = clonedQuestion.Name;
      final AssessmentQuestionVersion sourceVersion = sourceVersionByQuestionId.get(questionClone.sourceQuestionId);
      clonedVersions.add(new AssessmentQuestionVersion(
        Name                         = clonedQuestionName,
        AssessmentQuestionId         = clonedQuestionId,
        QuestionText                 = sourceVersion?.QuestionText ?? clonedQuestionName,
        QuestionTextFR__c            = sourceVersion?.QuestionTextFR__c,
        Description                  = sourceVersion?.Description,
        ResponseValues               = sourceVersion?.ResponseValues,
        ResponseValuesFR__c          = sourceVersion?.ResponseValuesFR__c,
        HelpText                     = sourceVersion?.HelpText,
        AdditionalInformation        = sourceVersion?.AdditionalInformation,
        NumberOfYears__c             = sourceVersion?.NumberOfYears__c,
        HasTotal__c                  = sourceVersion?.HasTotal__c ?? false,
        HasPercent__c                = sourceVersion?.HasPercent__c ?? false,
        HasPicklistSecuredPlanned__c = sourceVersion?.HasPicklistSecuredPlanned__c ?? false,
        HasPicklistPublicPrivate__c  = sourceVersion?.HasPicklistPublicPrivate__c ?? false,
        IsActive                     = true
      ));

      final AssessmentQuestionAssignment clonedQuestionAssignment = questionClone.clonedQuestionAssignment;
      clonedQuestionAssignment.AssessmentQuestionSetId = questionClone.clonedSection.Id;
      clonedQuestionAssignment.AssessmentQuestionId    = clonedQuestionId;
      clonedQuestionAssignments.add(clonedQuestionAssignment);
    }

    Database.insert(clonedVersions, AccessLevel.USER_MODE);
    Database.insert(clonedQuestionAssignments, AccessLevel.USER_MODE);
  }

  private static String buildUniqueDeveloperName(String name, String suffix) {
    return toDeveloperName(name).left(DEVELOPER_NAME_MAX_LENGTH - suffix.length()) + suffix;
  }

  // ============================== </Clone engine> ==============================
}