/**
 * @description       : Clones Funding Opportunities and their question catalogues.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 13-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 **/
public with sharing class FundingOpportunityCloneService {

  public class CloneInput {
    @InvocableVariable(required=true)
    public FundingOpportunity fundingOpportunity;
  }

  public class CloneOutput {
    @InvocableVariable
    public Id clonedFundingOpportunityId;
  }

  @InvocableMethod(label='Clone Funding Opportunities with Forms')
  public static List<CloneOutput> cloneFundingOpportunities(List<CloneInput> inputs) {
    if (inputs == null || inputs.isEmpty()) {
      throw new IllegalArgumentException('Expected at least one Funding Opportunity.');
    }

    final Id callForProjectsRecordTypeId = FundingOpportunityConstants.RecordTypes.CALL_FOR_PROJECTS.Id;
    final Set<Id> sourceFOIds = new Set<Id>();
    final Set<Id> sourceFOIdsClonedToCallForProjects = new Set<Id>();
    for (CloneInput input : inputs) {
      final FundingOpportunity inputFO = input?.fundingOpportunity;
      final Id sourceFOId = inputFO?.Id;
      if (sourceFOId == null) {
        throw new IllegalArgumentException('Expected each Funding Opportunity with its Id.');
      }
      sourceFOIds.add(sourceFOId);
      if (inputFO.RecordTypeId == callForProjectsRecordTypeId) {
        sourceFOIdsClonedToCallForProjects.add(sourceFOId);
      }
    }

    final Map<Id, FundingOpportunity> sourceFOById = new Map<Id, FundingOpportunity>([
      SELECT
        Id,
        ProgramId,
        RecordTypeId
      FROM
        FundingOpportunity
      WHERE
        Id IN :sourceFOIds
      WITH
        SYSTEM_MODE
    ]);
    if (sourceFOById.size() != sourceFOIds.size()) {
      throw new IllegalArgumentException('Expected every source Funding Opportunity to exist.');
    }

    final Map<Id, Set<Id>> QAIdsWithEOIBySourceFOId    = new Map<Id, Set<Id>>();
    final Map<Id, Set<Id>> QAIdsWithoutEOIBySourceFOId = new Map<Id, Set<Id>>();
    for (Id sourceFOId : sourceFOIds) {
      QAIdsWithEOIBySourceFOId.put(sourceFOId, new Set<Id>());
      QAIdsWithoutEOIBySourceFOId.put(sourceFOId, new Set<Id>());
    }
    for (AssessmentQuestionAssignment sourceQA : [
      SELECT
        Id,
        FundingOpportunity__c,
        EOI__c
      FROM
        AssessmentQuestionAssignment
      WHERE
        FundingOpportunity__c IN :sourceFOIds
      WITH
        SYSTEM_MODE
    ]) {
      final Id sourceFOId = sourceQA.FundingOpportunity__c;
      final Id sourceQAId = sourceQA.Id;
      QAIdsWithEOIBySourceFOId.get(sourceFOId).add(sourceQAId);
      if (!sourceQA.EOI__c) {
        QAIdsWithoutEOIBySourceFOId.get(sourceFOId).add(sourceQAId);
      }
    }

    final Set<Id> sourceFOIdsWithEOI = new Set<Id>();
    final Set<Id> programIdsWithTemplatesToAdd = new Set<Id>();
    for (Id sourceFOId : sourceFOIds) {
      final FundingOpportunity sourceFO = sourceFOById.get(sourceFOId);
      final Integer sourceFullApplicationQACount = QAIdsWithoutEOIBySourceFOId.get(sourceFOId).size();
      final Boolean hasSourceEOI = sourceFO.RecordTypeId == callForProjectsRecordTypeId
        && QAIdsWithEOIBySourceFOId.get(sourceFOId).size() > sourceFullApplicationQACount;
      if (hasSourceEOI) {
        sourceFOIdsWithEOI.add(sourceFOId);
      }
      if (
        sourceFullApplicationQACount == 0
        || (!hasSourceEOI && sourceFOIdsClonedToCallForProjects.contains(sourceFOId))
      ) {
        programIdsWithTemplatesToAdd.add(sourceFO.ProgramId);
      }
    }
    final Map<Boolean, Map<Id, Set<Id>>> templateQAIdsByIsEOIByProgramId =
      ApplicationFormLifecycleService.queryTemplateQuestionAssignmentIdsByIsEOIByProgramId(
        programIdsWithTemplatesToAdd
      );
    final Map<Id, Set<Id>> EOITemplateQAIdsByProgramId             = templateQAIdsByIsEOIByProgramId.get(true);
    final Map<Id, Set<Id>> fullApplicationTemplateQAIdsByProgramId = templateQAIdsByIsEOIByProgramId.get(false);

    final List<FundingOpportunity> clonedFOs = new List<FundingOpportunity>();
    final List<Set<Id>> QAIdSets = new List<Set<Id>>();
    for (CloneInput input : inputs) {
      final FundingOpportunity inputFO = input.fundingOpportunity;
      final Id sourceFOId         = inputFO.Id;
      final Id targetRecordTypeId = inputFO.RecordTypeId;
      final FundingOpportunity sourceFO = sourceFOById.get(sourceFOId);
      final Id sourceProgramId = sourceFO.ProgramId;
      final Boolean isTargetCallForProjects = targetRecordTypeId == callForProjectsRecordTypeId;

      clonedFOs.add(new FundingOpportunity(
        RecordTypeId       = targetRecordTypeId,
        Name               = inputFO.Name,
        ProgramCode__c     = inputFO.ProgramCode__c,
        Description__c     = inputFO.Description__c,
        StartDate          = inputFO.StartDate,
        EndDate            = inputFO.EndDate,
        Theme__c           = inputFO.Theme__c,
        Program_Name__c    = inputFO.Program_Name__c,
        GeographicScope__c = inputFO.GeographicScope__c,
        ProgramId          = sourceProgramId
      ));

      final Set<Id> sourceFullApplicationQAIds = QAIdsWithoutEOIBySourceFOId.get(sourceFOId);
      final Boolean hasSourceFullApplication   = !sourceFullApplicationQAIds.isEmpty();
      final Boolean hasSourceEOI = sourceFOIdsWithEOI.contains(sourceFOId);
      final Boolean isEOIFromTemplates = isTargetCallForProjects && !hasSourceEOI;
      final Set<Id> sourceQAIds = isTargetCallForProjects && hasSourceEOI
        ? QAIdsWithEOIBySourceFOId.get(sourceFOId)
        : sourceFullApplicationQAIds;
      if (hasSourceFullApplication && !isEOIFromTemplates) {
        QAIdSets.add(sourceQAIds);
      } else {
        final Set<Id> QAIds = sourceQAIds.clone();
        if (isEOIFromTemplates) {
          addTemplateQAIds(QAIds, EOITemplateQAIdsByProgramId, sourceProgramId);
        }
        if (!hasSourceFullApplication) {
          addTemplateQAIds(QAIds, fullApplicationTemplateQAIdsByProgramId, sourceProgramId);
        }
        QAIdSets.add(QAIds);
      }
    }

    final List<CloneOutput> outputs = new List<CloneOutput>();
    final Savepoint savepoint = Database.setSavepoint();
    FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled = false;
    try {
      Database.insert(clonedFOs, AccessLevel.USER_MODE);

      final Map<Id, Set<Id>> QAIdsByTargetFOId = new Map<Id, Set<Id>>();
      final Integer cloneCount = clonedFOs.size();
      for (Integer index = 0; index < cloneCount; index++) {
        final Id clonedFOId = clonedFOs[index].Id;
        QAIdsByTargetFOId.put(clonedFOId, QAIdSets[index]);
        final CloneOutput output = new CloneOutput();
        output.clonedFundingOpportunityId = clonedFOId;
        outputs.add(output);
      }

      ApplicationFormLifecycleService.cloneQuestionCataloguesToFundingOpportunities(QAIdsByTargetFOId);
    } catch (Exception e) {
      Database.rollback(savepoint);
      throw e;
    } finally {
      FundingOpportunityTriggerHandler.isCatalogueSeedingEnabled = true;
    }

    return outputs;
  }

  private static void addTemplateQAIds(Set<Id> QAIds, Map<Id, Set<Id>> templateQAIdsByProgramId, Id programId) {
    QAIds.addAll(templateQAIdsByProgramId.get(null));
    QAIds.addAll(templateQAIdsByProgramId.get(programId));
  }
}