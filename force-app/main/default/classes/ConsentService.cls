/**
 * @description       : Resolves the active consent documents and records the consents given on the portal.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 20-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   20-10-2026   LAN      Initial version
 **/
// Without sharing: a guest or portal user cannot read the authorization forms nor create the consents.
public without sharing class ConsentService {
  public class ConsentException extends Exception {}

  public class ConsentDocument {
    @AuraEnabled public Id formTextId;
    @AuraEnabled public String url;

    public ConsentDocument(Id formTextId, String url) {
      this.formTextId = formTextId;
      this.url = url;
    }
  }

  public static final String DATA_ACCEPTANCE_FORM_NAME      = 'Data Acceptance';
  public static final String TERMS_AND_CONDITIONS_FORM_NAME = 'Terms and Conditions';
  public static final String IMAGE_RIGHTS_FORM_NAME         = 'Image Rights';

  private static final String CONSENT_STATUS_SIGNED            = 'Signed';
  private static final String CONSENT_CAPTURED_SOURCE_TYPE_WEB = 'Web';
  private static final String ENGLISH_LANGUAGE_CODE            = 'en';

  // The language is a lang code such as fr or en-US. Falls back to a text in the same language, then to the
  // form's default text; null when the form has no active revision.
  public static ConsentDocument getActiveDocument(String formName, String language) {
    final AuthorizationFormText formText = selectFormText(findActiveRevisionTexts(formName), language);
    return formText == null ? null : new ConsentDocument(formText.Id, formText.FullAuthorizationFormUrl);
  }

  // Accepting the text of one language accepts the whole revision: every language version of it is returned,
  // or the English ones only when the form is in English only (Science pillar).
  public static List<AuthorizationFormText> requireActiveTexts(
    String formName,
    Id acceptedFormTextId,
    Boolean isEnglishOnly
  ) {
    final List<AuthorizationFormText> activeRevisionTexts = findActiveRevisionTexts(formName);
    final List<AuthorizationFormText> consentedTexts = new List<AuthorizationFormText>();
    Boolean isAcceptedTextActive = false;
    for (AuthorizationFormText formText : activeRevisionTexts) {
      if (formText.Id == acceptedFormTextId) {
        isAcceptedTextActive = true;
      }
      if (isEnglishOnly != true || toLanguageCode(formText.Locale) == ENGLISH_LANGUAGE_CODE) {
        consentedTexts.add(formText);
      }
    }
    if (!isAcceptedTextActive || consentedTexts.isEmpty()) {
      throw new ConsentException(formName);
    }
    return consentedTexts;
  }

  public static void insertConsents(
    Id consentGiverId,
    List<AuthorizationFormText> formTexts,
    Id relatedRecordId,
    String source
  ) {
    final Datetime consentCapturedDateTime = System.now();
    final List<AuthorizationFormConsent> consents = new List<AuthorizationFormConsent>();
    for (AuthorizationFormText formText : formTexts) {
      consents.add(
        new AuthorizationFormConsent(
          Name                      = formText.Name,
          ConsentGiverId            = consentGiverId,
          AuthorizationFormTextId   = formText.Id,
          RelatedRecordId           = relatedRecordId,
          Status                    = CONSENT_STATUS_SIGNED,
          ConsentCapturedSourceType = CONSENT_CAPTURED_SOURCE_TYPE_WEB,
          ConsentCapturedSource     = source,
          ConsentCapturedDateTime   = consentCapturedDateTime
        )
      );
    }
    Database.insert(consents, true, AccessLevel.SYSTEM_MODE);
  }

  // Only the texts of the highest active revision: an older revision still in force is ignored.
  private static List<AuthorizationFormText> findActiveRevisionTexts(String formName) {
    final List<AuthorizationFormText> activeRevisionTexts = new List<AuthorizationFormText>();
    for (AuthorizationFormText formText : [
      SELECT
        Id,
        Name,
        Locale,
        FullAuthorizationFormUrl,
        AuthorizationFormId,
        AuthorizationForm.DefaultAuthFormTextId
      FROM
        AuthorizationFormText
      WHERE
        AuthorizationForm.Name = :formName
        AND (AuthorizationForm.EffectiveFromDate = null OR AuthorizationForm.EffectiveFromDate <= TODAY)
        AND (AuthorizationForm.EffectiveToDate = null OR AuthorizationForm.EffectiveToDate >= TODAY)
      WITH
        SYSTEM_MODE
      ORDER BY
        AuthorizationForm.RevisionNumber DESC NULLS LAST,
        Name ASC
    ]) {
      if (
        !activeRevisionTexts.isEmpty() &&
        formText.AuthorizationFormId != activeRevisionTexts[0].AuthorizationFormId
      ) {
        break;
      }
      activeRevisionTexts.add(formText);
    }
    return activeRevisionTexts;
  }

  private static AuthorizationFormText selectFormText(List<AuthorizationFormText> formTexts, String language) {
    final String locale = String.isBlank(language) ? '' : language.trim().replace('-', '_');
    final String languageCode = toLanguageCode(locale);
    AuthorizationFormText sameLanguageText;
    AuthorizationFormText defaultText;
    for (AuthorizationFormText formText : formTexts) {
      if (String.isNotBlank(locale) && formText.Locale == locale) {
        return formText;
      }
      if (
        sameLanguageText == null &&
        String.isNotBlank(languageCode) &&
        toLanguageCode(formText.Locale) == languageCode
      ) {
        sameLanguageText = formText;
      }
      if (formText.Id == formText.AuthorizationForm.DefaultAuthFormTextId) {
        defaultText = formText;
      }
    }
    return sameLanguageText != null ? sameLanguageText : defaultText;
  }

  private static String toLanguageCode(String locale) {
    return locale == null ? null : locale.substringBefore('_').toLowerCase();
  }
}
