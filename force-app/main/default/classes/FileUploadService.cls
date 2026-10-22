/**
 * @description       : Names, links and deletes the files uploaded for the form questions.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 09-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   LAN    Name uploaded files after the form field label with sequential suffixes
 * 1.1   05-10-2026   LAN    Add renameUploadedFiles to name files sent with the standard file upload
 * 1.2   05-10-2026   LAN    Add linkFilesToRecord to attach the uploaded files to the Application Form on save
 * 1.3   05-10-2026   LAN    Remove the custom upload (uploadFile): the standard file upload is used
 * 1.4   08-10-2026   LAN    Keep the special characters of the label in the file title
 * 1.5   08-10-2026   LAN    Return the errors as codes translated by the form (FormErrorService)
 * 1.6   09-10-2026   LAN    buildError and the error codes now come from FormLanguageService
 **/
public with sharing class FileUploadService {
  public static final Integer MAX_TITLE_LENGTH = 200;
  public static final String FALLBACK_TITLE = 'Document';

  private static final String CONTROL_CHARACTERS_PATTERN = '\\p{Cntrl}';
  private static final String SPACES_PATTERN = '\\s+';
  private static final String TRAILING_DOTS_PATTERN = '[.\\s]+$';
  private static final String NON_ALPHANUMERIC_PATTERN = '[^a-zA-Z0-9]';

  public class UploadedFileWrapper {
    @AuraEnabled
    public String documentId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String fileExtension;
    @AuraEnabled
    public String name;
  }

  public static void deleteUploadedFile(final Id contentDocumentId) {
    if (contentDocumentId == null) {
      fail('A document Id is required.');
    }
    Database.delete(new ContentDocument(Id = contentDocumentId), AccessLevel.USER_MODE);
  }

  // Names documents uploaded with the standard file upload, which keeps the original file name:
  // each one is named after the form field label with sequential suffixes.
  // existingTitles are the titles already used by the other files of the same field.
  public static List<UploadedFileWrapper> renameUploadedFiles(
    final List<Id> contentDocumentIds,
    final String fieldLabel,
    final List<String> existingTitles
  ) {
    if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
      fail('A document Id is required.');
    }

    final Map<Id, ContentDocument> contentDocumentsById = new Map<Id, ContentDocument>(
      [
        SELECT
          Id,
          Title,
          FileExtension
        FROM
          ContentDocument
        WHERE
          Id IN :contentDocumentIds
        WITH
          USER_MODE
      ]
    );
    final Set<String> takenTitles = new Set<String>();
    if (existingTitles != null) {
      takenTitles.addAll(existingTitles);
    }

    final List<ContentDocument> contentDocumentsToUpdate = new List<ContentDocument>();
    final List<UploadedFileWrapper> results = new List<UploadedFileWrapper>();
    for (Id contentDocumentId : contentDocumentIds) {
      final ContentDocument contentDocument = contentDocumentsById.get(contentDocumentId);
      if (contentDocument == null) {
        continue;
      }
      final String title = buildUniqueTitle(resolveBaseName(fieldLabel, contentDocument.Title), takenTitles);
      takenTitles.add(title);
      final String fileExtension = String.isBlank(contentDocument.FileExtension) ? '' : contentDocument.FileExtension;

      contentDocumentsToUpdate.add(new ContentDocument(Id = contentDocument.Id, Title = title));
      final UploadedFileWrapper result = new UploadedFileWrapper();
      result.documentId = contentDocument.Id;
      result.title = title;
      result.fileExtension = fileExtension;
      result.name = String.isBlank(fileExtension) ? title : title + '.' + fileExtension;
      results.add(result);
    }
    if (!contentDocumentsToUpdate.isEmpty()) {
      Database.update(contentDocumentsToUpdate, AccessLevel.USER_MODE);
    }
    return results;
  }


  // Links documents uploaded by the user (attached to nothing) to a record, e.g. the Application
  // Form when the candidate saves it. The documents already linked to the record are skipped.
  public static void linkFilesToRecord(final Id recordId, final List<Id> contentDocumentIds) {
    if (recordId == null) {
      fail('A record Id is required.');
    }
    if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
      return;
    }

    final Set<Id> alreadyLinkedDocumentIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT
        ContentDocumentId
      FROM
        ContentDocumentLink
      WHERE
        LinkedEntityId = :recordId
        AND ContentDocumentId IN :contentDocumentIds
      WITH
        USER_MODE
    ]) {
      alreadyLinkedDocumentIds.add(link.ContentDocumentId);
    }

    final List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
    for (Id contentDocumentId : new Set<Id>(contentDocumentIds)) {
      if (!alreadyLinkedDocumentIds.contains(contentDocumentId)) {
        linksToInsert.add(
          new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = recordId,
            ShareType = 'V',
            Visibility = 'AllUsers'
          )
        );
      }
    }
    if (!linksToInsert.isEmpty()) {
      Database.insert(linksToInsert, AccessLevel.USER_MODE);
    }
  }

  // ---- Naming (public static so they can be unit tested) ----

  // Base title: the sanitized field label, else the sanitized file name, else a fallback.
  public static String resolveBaseName(final String fieldLabel, final String fileName) {
    final String labelBaseName = sanitizeLabel(fieldLabel);
    if (String.isNotBlank(labelBaseName)) {
      return labelBaseName;
    }
    final String fileBaseName = sanitizeLabel(getFileBaseName(fileName));
    return String.isNotBlank(fileBaseName) ? fileBaseName : FALLBACK_TITLE;
  }

  // Keeps the label as written, special characters included (/ : ? * " < > |, accents, parentheses...):
  // only control characters (tabs, line breaks) become a space, then spaces are collapsed and trimmed.
  public static String sanitizeLabel(final String label) {
    if (String.isBlank(label)) {
      return '';
    }
    return label
      .replaceAll(CONTROL_CHARACTERS_PATTERN, ' ')
      .replaceAll(SPACES_PATTERN, ' ')
      .trim()
      .replaceAll(TRAILING_DOTS_PATTERN, '');
  }

  public static String getFileExtension(final String fileName) {
    if (String.isBlank(fileName)) {
      return '';
    }
    final Integer dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == fileName.length() - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).replaceAll(NON_ALPHANUMERIC_PATTERN, '');
  }

  public static String getFileBaseName(final String fileName) {
    if (String.isBlank(fileName)) {
      return '';
    }
    final Integer dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  // First free title: "Base", then "Base (1)", "Base (2)"... Case-insensitive, fills the lowest free
  // number. The base is truncated so the whole title fits MAX_TITLE_LENGTH.
  public static String buildUniqueTitle(final String baseName, final Set<String> existingTitles) {
    final Set<String> lowerCaseTitles = new Set<String>();
    for (String existingTitle : existingTitles) {
      lowerCaseTitles.add(existingTitle.toLowerCase());
    }

    Integer index = 0;
    String candidate = buildTitle(baseName, index);
    while (lowerCaseTitles.contains(candidate.toLowerCase())) {
      index++;
      candidate = buildTitle(baseName, index);
    }
    return candidate;
  }

  private static String buildTitle(final String baseName, final Integer index) {
    final String suffix = index == 0 ? '' : ' (' + index + ')';
    final Integer maxBaseLength = MAX_TITLE_LENGTH - suffix.length();
    final String truncatedBaseName = baseName.length() > maxBaseLength
      ? baseName.substring(0, maxBaseLength).trim()
      : baseName;
    return truncatedBaseName + suffix;
  }

  // A missing Id is a technical error for the candidate: the form shows it translated, the detail is logged.
  private static void fail(final String message) {
    System.debug(LoggingLevel.ERROR, message);
    throw FormLanguageService.buildError(FormLanguageService.ERROR_TECHNICAL, new List<String>(), message);
  }
}