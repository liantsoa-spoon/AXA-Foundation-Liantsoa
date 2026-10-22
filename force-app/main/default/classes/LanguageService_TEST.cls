/**
 * @description       : Test class for LanguageService.
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
private class LanguageService_TEST {

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

  private static String getCurrentUserLanguage() {
    return [
      SELECT
        LanguageLocaleKey
      FROM
        User
      WHERE
        Id = :UserInfo.getUserId()
    ].LanguageLocaleKey;
  }

  @isTest
  static void updateCurrentUserLanguage_givenFrench_updatesTheUser() {
    System.runAs(getTestUser()) {
      Test.startTest();
      LanguageService.updateCurrentUserLanguage(LanguageService.LANGUAGE_FRENCH);
      Test.stopTest();

      System.assertEquals(LanguageService.LANGUAGE_FRENCH, getCurrentUserLanguage(), 'Language');
    }
  }

  @isTest
  static void updateCurrentUserLanguage_givenEnglish_updatesTheUser() {
    System.runAs(getTestUser()) {
      LanguageService.updateCurrentUserLanguage(LanguageService.LANGUAGE_FRENCH);

      Test.startTest();
      LanguageService.updateCurrentUserLanguage(LanguageService.LANGUAGE_ENGLISH);
      Test.stopTest();

      System.assertEquals(LanguageService.LANGUAGE_ENGLISH, getCurrentUserLanguage(), 'Language');
    }
  }

  @isTest
  static void updateCurrentUserLanguage_givenCurrentLanguage_keepsTheLanguage() {
    System.runAs(getTestUser()) {
      final String currentLanguage = LanguageService.LANGUAGE_ENGLISH;
      LanguageService.updateCurrentUserLanguage(currentLanguage);

      Test.startTest();
      LanguageService.updateCurrentUserLanguage(currentLanguage);
      Test.stopTest();

      System.assertEquals(currentLanguage, getCurrentUserLanguage(), 'Language');
    }
  }

  @isTest
  static void updateCurrentUserLanguage_givenUnsupportedLanguage_throwsAndKeepsTheLanguage() {
    System.runAs(getTestUser()) {
      final String initialLanguage = getCurrentUserLanguage();
      Boolean hasThrown = false;

      Test.startTest();
      try {
        LanguageService.updateCurrentUserLanguage('de');
      } catch (LanguageService.LanguageServiceException e) {
        hasThrown = true;
      }
      Test.stopTest();

      System.assert(hasThrown, 'An unsupported language must be rejected');
      System.assertEquals(initialLanguage, getCurrentUserLanguage(), 'Language');
    }
  }

  @isTest
  static void updateCurrentUserLanguage_givenBlankOrNullOrWrongCase_throws() {
    System.runAs(getTestUser()) {
      final List<String> invalidLanguages = new List<String>{ null, '', ' ', 'FR' };
      Integer rejectedCount = 0;

      Test.startTest();
      for (String invalidLanguage : invalidLanguages) {
        try {
          LanguageService.updateCurrentUserLanguage(invalidLanguage);
        } catch (LanguageService.LanguageServiceException e) {
          rejectedCount++;
        }
      }
      Test.stopTest();

      System.assertEquals(invalidLanguages.size(), rejectedCount, 'Every invalid value must be rejected');
    }
  }
}