/**
 * @description       : Test class for LanguageController.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 08-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   07-10-2026   LAN      Initial version
 * 1.1   07-10-2026   LAN      Run every test as the AXA admin user created in the testSetup
 * 1.2   08-10-2026   LAN      Use the language values of LanguageService instead of PicklistValues
 **/
@isTest
private class LanguageController_TEST {

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
    insert new User(
      Alias             = 'axaadmin',
      Email             = 'axaadmin@testorg.com',
      EmailEncodingKey  = 'UTF-8',
      LastName          = 'AXAAdminUser',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey      = 'en_US',
      ProfileId         = adminProfile.Id,
      TimeZoneSidKey    = 'America/Los_Angeles',
      Username          = 'axaadmin' + DateTime.now().getTime() + '@testorg.com'
    );
  }

  private static User getTestUser() {
    return [
      SELECT
        Id
      FROM
        User
      WHERE
        LastName = 'AXAAdminUser'
      LIMIT
        1
    ];
  }

  @isTest
  static void updateLanguage_givenFrench_updatesTheUser() {
    System.runAs(getTestUser()) {
      Test.startTest();
      LanguageController.updateLanguage(LanguageService.LANGUAGE_FRENCH);
      Test.stopTest();

      final String language = [
        SELECT
          LanguageLocaleKey
        FROM
          User
        WHERE
          Id = :UserInfo.getUserId()
      ].LanguageLocaleKey;
      System.assertEquals(LanguageService.LANGUAGE_FRENCH, language, 'Language');
    }
  }

  @isTest
  static void updateLanguage_givenUnsupportedLanguage_throwsAnAuraHandledException() {
    System.runAs(getTestUser()) {
      String message;

      Test.startTest();
      try {
        LanguageController.updateLanguage('de');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      Test.stopTest();

      System.assertEquals('Unsupported language: de', message, 'Message');
    }
  }
}