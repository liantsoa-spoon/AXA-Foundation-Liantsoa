/**
 * @description       : Updates the language of the current portal user.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 08-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   07-10-2026   LAN      Initial version
 * 1.1   08-10-2026   LAN      Hold the User language values here instead of PicklistValues
 **/
public with sharing class LanguageService {
  public static final String LANGUAGE_ENGLISH = 'en_US';
  public static final String LANGUAGE_FRENCH = 'fr';

  public class LanguageServiceException extends Exception {
  }

  private static final Set<String> SUPPORTED_LANGUAGES = new Set<String>{ LANGUAGE_ENGLISH, LANGUAGE_FRENCH };

  public static void updateCurrentUserLanguage(String languageCode) {
    if (!SUPPORTED_LANGUAGES.contains(languageCode)) {
      throw new LanguageServiceException('Unsupported language: ' + languageCode);
    }

    update new User(
      Id                = UserInfo.getUserId(),
      LanguageLocaleKey = languageCode
    );
  }
}