/**
 * @description       : Exposes the language switch of the current portal user to Lightning web components.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 07-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   07-10-2026   LAN      Initial version
 **/
public with sharing class LanguageController {

  @AuraEnabled
  public static void updateLanguage(String languageCode) {
    try {
      LanguageService.updateCurrentUserLanguage(languageCode);
    } catch (Exception e) {
      final AuraHandledException auraException = new AuraHandledException(e.getMessage());
      auraException.setMessage(e.getMessage());
      throw auraException;
    }
  }
}