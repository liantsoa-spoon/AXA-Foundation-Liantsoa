/**
 * @description       : Test class for FormLanguageService.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 09-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   08-10-2026   LAN      Initial version
 * 1.1   08-10-2026   LAN      Test isTranslationExpected
 * 1.2   09-10-2026   LAN      Test buildError, moved from FormErrorService_TEST
 * 1.3   09-10-2026   LAN      Assign the Grantmaking permission sets to the test users
 **/
@isTest
private class FormLanguageService_TEST {
  private static final String FRENCH_USER_LAST_NAME = 'AXAFormLanguageFr';
  private static final String ENGLISH_USER_LAST_NAME = 'AXAFormLanguageEn';

  @testSetup
  static void setupTestData() {
    final Profile adminProfile = [
      SELECT
        Id
      FROM
        Profile
      WHERE
        Name = 'System Administrator'
      LIMIT
        1
    ];
    final List<User> users = new List<User>{
      buildUser(FRENCH_USER_LAST_NAME, 'fr', adminProfile.Id),
      buildUser(ENGLISH_USER_LAST_NAME, 'en_US', adminProfile.Id)
    };
    insert users;

    // The Grantmaking objects (Program, FundingOpportunity) are granted by permission sets, not by the profile.
    final List<PermissionSet> permissionSets = [
      SELECT
        Id
      FROM
        PermissionSet
      WHERE
        Name IN ('AXA_Foundation_Admin', 'Grantmaking_Manager')
    ];
    final List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (User user : users) {
      for (PermissionSet permissionSet : permissionSets) {
        assignments.add(new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = permissionSet.Id));
      }
    }
    insert assignments;
  }

  private static User buildUser(final String lastName, final String languageLocaleKey, final Id profileId) {
    final String alias = lastName.right(8);
    return new User(
      Alias             = alias,
      Email             = alias + '@testorg.com',
      EmailEncodingKey  = 'UTF-8',
      LastName          = lastName,
      LanguageLocaleKey = languageLocaleKey,
      LocaleSidKey      = 'en_US',
      ProfileId         = profileId,
      TimeZoneSidKey    = 'Europe/Paris',
      Username          = alias + DateTime.now().getTime() + '@testorg.com'
    );
  }

  private static User getUser(final String lastName) {
    return [
      SELECT
        Id
      FROM
        User
      WHERE
        LastName = :lastName
      LIMIT
        1
    ];
  }

  private static Id createFundingOpportunity(final String pillarDeveloperName) {
    final Program program = new Program(
      Name         = 'Test Program ' + Math.abs(Crypto.getRandomInteger()),
      RecordTypeId = Schema.SObjectType.Program.getRecordTypeInfosByDeveloperName()
        .get(pillarDeveloperName)
        .getRecordTypeId()
    );
    insert program;
    final FundingOpportunity fundingOpportunity = new FundingOpportunity(
      Name      = 'Test FO',
      Status    = 'Draft',
      ProgramId = program.Id
    );
    insert fundingOpportunity;
    return fundingOpportunity.Id;
  }

  private static void useScienceInEnglishConfig() {
    FormLanguageService.configsOverride = new List<ConfigPillarFormLanguage__mdt>{
      new ConfigPillarFormLanguage__mdt(Pillar__c = 'Science', Language__c = 'EN')
    };
  }

  @isTest
  static void getFormLanguage_givenSciencePillarAndFrenchUser_returnsEnglish() {
    System.runAs(getUser(FRENCH_USER_LAST_NAME)) {
      useScienceInEnglishConfig();
      final Id fundingOpportunityId = createFundingOpportunity('Science');

      Assert.areEqual(
        FormLanguageService.LANGUAGE_ENGLISH,
        FormLanguageService.getFormLanguage(fundingOpportunityId),
        'A Science form is always in English'
      );
    }
  }

  @isTest
  static void getFormLanguage_givenNaturePillarAndFrenchUser_returnsFrench() {
    System.runAs(getUser(FRENCH_USER_LAST_NAME)) {
      useScienceInEnglishConfig();
      final Id fundingOpportunityId = createFundingOpportunity('Nature');

      Assert.areEqual(
        FormLanguageService.LANGUAGE_FRENCH,
        FormLanguageService.getFormLanguage(fundingOpportunityId),
        'A pillar without configuration follows the language of the user'
      );
    }
  }

  @isTest
  static void getFormLanguage_givenNaturePillarAndEnglishUser_returnsEnglish() {
    System.runAs(getUser(ENGLISH_USER_LAST_NAME)) {
      useScienceInEnglishConfig();
      final Id fundingOpportunityId = createFundingOpportunity('Nature');

      Assert.areEqual(
        FormLanguageService.LANGUAGE_ENGLISH,
        FormLanguageService.getFormLanguage(fundingOpportunityId),
        'A pillar without configuration follows the language of the user'
      );
    }
  }

  @isTest
  static void getFormLanguage_givenConfigWithoutLanguage_returnsUserLanguage() {
    System.runAs(getUser(FRENCH_USER_LAST_NAME)) {
      FormLanguageService.configsOverride = new List<ConfigPillarFormLanguage__mdt>{
        new ConfigPillarFormLanguage__mdt(Pillar__c = 'Science', Language__c = null)
      };
      final Id fundingOpportunityId = createFundingOpportunity('Science');

      Assert.areEqual(
        FormLanguageService.LANGUAGE_FRENCH,
        FormLanguageService.getFormLanguage(fundingOpportunityId),
        'A configuration without language is ignored'
      );
    }
  }

  @isTest
  static void getFormLanguage_givenNullFundingOpportunity_returnsUserLanguage() {
    System.runAs(getUser(FRENCH_USER_LAST_NAME)) {
      useScienceInEnglishConfig();

      Assert.areEqual(
        FormLanguageService.LANGUAGE_FRENCH,
        FormLanguageService.getFormLanguage(null),
        'Without a Funding Opportunity, the form follows the language of the user'
      );
    }
  }

  @isTest
  static void getFormLanguage_givenOrgConfiguration_readsTheCustomMetadata() {
    System.runAs(getUser(ENGLISH_USER_LAST_NAME)) {
      final Id fundingOpportunityId = createFundingOpportunity('Nature');

      Assert.areEqual(
        FormLanguageService.LANGUAGE_ENGLISH,
        FormLanguageService.getFormLanguage(fundingOpportunityId),
        'The Custom Metadata of the org is read when no configuration is set by the test'
      );
    }
  }

  @isTest
  static void isTranslationExpected_givenSciencePillar_returnsFalse() {
    System.runAs(getUser(ENGLISH_USER_LAST_NAME)) {
      Assert.isFalse(
        FormLanguageService.isTranslationExpected(createFundingOpportunity('Science')),
        'A Science program stays in English'
      );
    }
  }

  @isTest
  static void isTranslationExpected_givenOtherPillar_returnsTrue() {
    System.runAs(getUser(ENGLISH_USER_LAST_NAME)) {
      Assert.isTrue(
        FormLanguageService.isTranslationExpected(createFundingOpportunity('Nature')),
        'Every pillar but Science is translated into French'
      );
    }
  }

  private static Map<String, Object> parseError(final AuraHandledException error) {
    return (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
  }

  @isTest
  static void buildError_givenCodeParamsAndDetail_serializesThem() {
    System.runAs(getUser(ENGLISH_USER_LAST_NAME)) {
      final Map<String, Object> error = parseError(
        FormLanguageService.buildError(FormLanguageService.ERROR_TECHNICAL, new List<String>{ 'a', 'b' }, 'Detail')
      );

      Assert.areEqual(FormLanguageService.ERROR_TECHNICAL, error.get('code'), 'Code');
      Assert.areEqual(new List<Object>{ 'a', 'b' }, (List<Object>) error.get('params'), 'Parameters');
      Assert.areEqual('Detail', error.get('detail'), 'Detail');
    }
  }

  @isTest
  static void buildError_givenNullParams_serializesAnEmptyList() {
    System.runAs(getUser(ENGLISH_USER_LAST_NAME)) {
      final Map<String, Object> error = parseError(
        FormLanguageService.buildError(FormLanguageService.ERROR_USER_NOT_LINKED, null, null)
      );

      Assert.areEqual(0, ((List<Object>) error.get('params')).size(), 'No parameters');
      Assert.isNull(error.get('detail'), 'No detail');
    }
  }
}