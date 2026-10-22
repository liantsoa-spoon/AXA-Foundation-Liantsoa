/**
 * Crée un Programme (FundingOpportunity) rattaché au Pilier (Program) donné.
 *
 * Le Pilier est obligatoire ("Le pilier est requis pour pouvoir créer le programme") : il est renseigné ici par
 * ProgramId. À la création, le catalogue Common Core (et celui du Pilier) est cloné sur le Programme par
 * ApplicationFormLifecycleService : un Programme Call for Projects reçoit les questions EOI et dossier complet,
 * un Programme Direct Management seulement celles du dossier complet.
 */

final Id PILLAR_ID = '11WKN00000000D52AI'; // LAN Culture
final String PROGRAM_TITLE = 'LAN Culture - Test Budget';
final String RECORD_TYPE = 'CallForProjects'; // ou 'DirectManagement'
final String EDITION_YEAR = '2026';
final Date APPLICATIONS_OPEN_DATE = Date.newInstance(2026, 10, 14);
final Date APPLICATIONS_CLOSE_DATE = Date.newInstance(2026, 12, 31);
final String STATUS = 'Draft';
final Boolean DRY_RUN = true;

final Program pillar = [
  SELECT Id, Name, RecordType.DeveloperName
  FROM Program
  WHERE Id = :PILLAR_ID
  LIMIT 1
];
final Id recordTypeId = Schema.SObjectType.FundingOpportunity.getRecordTypeInfosByDeveloperName()
  .get(RECORD_TYPE)
  .getRecordTypeId();

final FundingOpportunity fundingOpportunity = new FundingOpportunity(
  Name = PROGRAM_TITLE,
  Program_Name__c = PROGRAM_TITLE,
  ProgramId = pillar.Id,
  RecordTypeId = recordTypeId,
  EditionYear__c = EDITION_YEAR,
  ApplicationsOpenDate__c = APPLICATIONS_OPEN_DATE,
  ApplicationsCloseDate__c = APPLICATIONS_CLOSE_DATE,
  Status = STATUS
);

System.debug(
  'Programme "' + PROGRAM_TITLE + '" (' + RECORD_TYPE + ', ' + STATUS + ') sur le Pilier ' + pillar.Name
  + ' (' + pillar.RecordType.DeveloperName + ').'
);
if (DRY_RUN) {
  System.debug('DRY_RUN : rien n\'est créé. Passer DRY_RUN à false pour créer.');
  return;
}

insert fundingOpportunity;

final Integer clonedQuestionCount = [
  SELECT COUNT()
  FROM AssessmentQuestionAssignment
  WHERE FundingOpportunity__c = :fundingOpportunity.Id
];
System.debug('Programme créé : ' + fundingOpportunity.Id + ', ' + clonedQuestionCount + ' questions clonées.');
