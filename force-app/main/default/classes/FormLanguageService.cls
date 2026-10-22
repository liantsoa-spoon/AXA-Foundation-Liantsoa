/**
 * @description       : Resolves the language of the application form from the pillar of its program.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 09-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   08-10-2026   LAN      Initial version
 * 1.1   08-10-2026   LAN      Add isTranslationExpected: every pillar but Science is translated into French
 * 1.2   09-10-2026   LAN      Add buildError, moved from FormErrorService: error codes translated by the form
 **/
// Without sharing: a portal user cannot read the Program of a Funding Opportunity, nor its record type.
// Only the record type developer name of the Program of the given Funding Opportunity is read.
public without sharing class FormLanguageService {
  public static final String LANGUAGE_ENGLISH = 'EN';
  public static final String LANGUAGE_FRENCH = 'FR';
  private static final String USER_LANGUAGE_FRENCH_PREFIX = 'fr';
  private static final String PILLAR_SCIENCE = 'Science';
  public static final String ERROR_TECHNICAL = 'TECHNICAL_ERROR';
  public static final String ERROR_USER_NOT_LINKED = 'USER_NOT_LINKED';
  public static final String ERROR_ORGANIZATION_NOT_LINKED = 'ORGANIZATION_NOT_LINKED';

  // Tests set the configuration instead of the Custom Metadata records of the org.
  @TestVisible
  private static List<ConfigPillarFormLanguage__mdt> configsOverride;

  // The language set for the pillar of the program wins (Science: always English);
  // otherwise the form follows the language of the connected user.
  public static String getFormLanguage(final Id fundingOpportunityId) {
    final String pillar = findPillarDeveloperName(fundingOpportunityId);
    if (String.isNotBlank(pillar)) {
      for (ConfigPillarFormLanguage__mdt config : getConfigs()) {
        if (config.Pillar__c == pillar && String.isNotBlank(config.Language__c)) {
          return config.Language__c.toUpperCase();
        }
      }
    }
    return getUserLanguage();
  }

  // The questions of a Science program stay in English: every other pillar expects a French translation.
  public static Boolean isTranslationExpected(final Id fundingOpportunityId) {
    return findPillarDeveloperName(fundingOpportunityId) != PILLAR_SCIENCE;
  }

  private static String findPillarDeveloperName(final Id fundingOpportunityId) {
    if (fundingOpportunityId == null) {
      return null;
    }
    final List<FundingOpportunity> fundingOpportunities = [
      SELECT
        Program.RecordType.DeveloperName
      FROM
        FundingOpportunity
      WHERE
        Id = :fundingOpportunityId
      WITH
        SYSTEM_MODE
      LIMIT
        1
    ];
    return fundingOpportunities.isEmpty() ? null : fundingOpportunities[0].Program?.RecordType?.DeveloperName;
  }

  private static List<ConfigPillarFormLanguage__mdt> getConfigs() {
    return configsOverride != null ? configsOverride : ConfigPillarFormLanguage__mdt.getAll().values();
  }

  private static String getUserLanguage() {
    return UserInfo.getLanguage().startsWith(USER_LANGUAGE_FRENCH_PREFIX) ? LANGUAGE_FRENCH : LANGUAGE_ENGLISH;
  }

  // JSON { code, params, detail }: the code and its parameters are shown translated, the English detail is
  // kept for the logs and the tests.
  public static AuraHandledException buildError(
    final String code,
    final List<String> params,
    final String detail
  ) {
    final String message = JSON.serialize(
      new Map<String, Object>{
        'code' => code,
        'params' => params == null ? new List<String>() : params,
        'detail' => detail
      }
    );
    final AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}