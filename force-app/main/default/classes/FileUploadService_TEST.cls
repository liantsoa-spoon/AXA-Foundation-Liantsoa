/**
 * @description       : Test class for FileUploadService.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 08-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   01-10-2026   LAN      Initial version
 * 1.1   05-10-2026   LAN      Run every test as the AXA admin user created in the testSetup
 * 1.2   05-10-2026   LAN      Test renameUploadedFiles
 * 1.3   05-10-2026   LAN      Test linkFilesToRecord
 * 1.4   05-10-2026   LAN      Remove the tests of the custom upload (uploadFile)
 * 1.5   08-10-2026   LAN      Test that the special characters of the label are kept
 **/
@IsTest
private class FileUploadService_TEST {

  @testSetup
  static void setupTestData() {
    // Create user with Standard Profile
    Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    User testUser = new User(
      Alias = 'axaadmin',
      Email = 'axaadmin@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AXAAdminUser',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'axaadmin' + DateTime.now().getTime() + '@testorg.com'
    );
    insert testUser;

    // Query both Permission Sets (by API Name or Label)
    List<PermissionSet> psList = [
      SELECT Id 
      FROM PermissionSet 
      WHERE Name IN ('AXA_Foundation_Admin', 'Grantmaking_Manager') 
      OR Label IN ('AXA Foundation Admin', 'Grantmaking Manager')
    ];

    // Assign permission sets to the test user
    List<PermissionSetAssignment> psaList = new List<PermissionSetAssignment>();
    for (PermissionSet ps : psList) {
      psaList.add(new PermissionSetAssignment(
        AssigneeId = testUser.Id,
        PermissionSetId = ps.Id
      ));
    }
    insert psaList;
  }

  private static User getTestUser() {
    return [SELECT Id FROM User WHERE LastName = 'AXAAdminUser' LIMIT 1];
  }

  private static Id createApplicationForm() {
    final Program program = new Program(Name = 'Test Program ' + Math.abs(Crypto.getRandomInteger()));
    insert program;
    final FundingOpportunity fundingOpportunity = new FundingOpportunity(
      Name = 'Test FO',
      Status = 'Draft',
      ProgramId = program.Id
    );
    insert fundingOpportunity;
    final ApplicationForm applicationForm = new ApplicationForm(
      ReferenceRecordId = fundingOpportunity.Id,
      UsageType = 'Grantmaking'
    );
    insert applicationForm;
    return applicationForm.Id;
  }

  @IsTest
  static void deleteUploadedFile_givenExistingDocument_deletesIt() {
    System.runAs(getTestUser()) {
      final Id applicationFormId = createApplicationForm();
      final Id documentId = createContentDocument('CV');

      Test.startTest();
      FileUploadService.deleteUploadedFile(documentId);
      Test.stopTest();

      Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :documentId]);
    }
  }

  @IsTest
  static void deleteUploadedFile_givenNullId_throwsAuraHandledException() {
    System.runAs(getTestUser()) {
      try {
        FileUploadService.deleteUploadedFile(null);
        Assert.fail('Expected an AuraHandledException when the document Id is missing');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('document Id is required'), e.getMessage());
      }
    }
  }

  @IsTest
  static void buildUniqueTitle_givenNoExistingTitle_returnsBaseName() {
    System.runAs(getTestUser()) {
      Assert.areEqual('Bank details', FileUploadService.buildUniqueTitle('Bank details', new Set<String>()));
    }
  }

  @IsTest
  static void buildUniqueTitle_givenBaseTaken_returnsFirstSuffix() {
    System.runAs(getTestUser()) {
      final Set<String> titles = new Set<String>{ 'Bank details' };
      Assert.areEqual('Bank details (1)', FileUploadService.buildUniqueTitle('Bank details', titles));
    }
  }

  @IsTest
  static void buildUniqueTitle_givenGapInNumbers_fillsLowestFreeNumber() {
    System.runAs(getTestUser()) {
      final Set<String> titles = new Set<String>{ 'Bank details', 'Bank details (2)' };
      Assert.areEqual('Bank details (1)', FileUploadService.buildUniqueTitle('Bank details', titles));
    }
  }

  @IsTest
  static void buildUniqueTitle_givenDifferentCase_treatsTitleAsTaken() {
    System.runAs(getTestUser()) {
      final Set<String> titles = new Set<String>{ 'BANK DETAILS' };
      Assert.areEqual('Bank details (1)', FileUploadService.buildUniqueTitle('Bank details', titles));
    }
  }

  @IsTest
  static void buildUniqueTitle_givenLabelOfExactMaxLength_keepsFullBaseWithoutSuffix() {
    System.runAs(getTestUser()) {
      final String label = 'a'.repeat(FileUploadService.MAX_TITLE_LENGTH);
      final String title = FileUploadService.buildUniqueTitle(label, new Set<String>());
      Assert.areEqual(FileUploadService.MAX_TITLE_LENGTH, title.length());
      Assert.areEqual(label, title);
    }
  }

  @IsTest
  static void buildUniqueTitle_givenLabelOverMaxLength_truncatesBaseAndKeepsSuffix() {
    System.runAs(getTestUser()) {
      final String label = 'a'.repeat(300);
      final String first = FileUploadService.buildUniqueTitle(label, new Set<String>());
      final String second = FileUploadService.buildUniqueTitle(label, new Set<String>{ first });

      Assert.areEqual(200, first.length());
      Assert.areEqual(200, second.length());
      Assert.isTrue(second.endsWith(' (1)'), 'The suffix must never be truncated');
      Assert.areNotEqual(first, second);
    }
  }

  @IsTest
  static void sanitizeLabel_givenParenthesesAndDash_keepsThem() {
    System.runAs(getTestUser()) {
      Assert.areEqual(
        'Bank Details (Primary Account)',
        FileUploadService.sanitizeLabel('Bank Details (Primary Account)')
      );
      Assert.areEqual(
        'Bank Details - Primary Account',
        FileUploadService.sanitizeLabel('Bank Details - Primary Account')
      );
    }
  }

  @IsTest
  static void sanitizeLabel_givenSpecialCharacters_keepsThem() {
    System.runAs(getTestUser()) {
      Assert.areEqual('Budget / Plan: 2026', FileUploadService.sanitizeLabel('Budget / Plan: 2026'));
      Assert.areEqual('Statuts ? <*> "|\\', FileUploadService.sanitizeLabel('Statuts ? <*> "|\\'));
      Assert.areEqual('Rapport d\'activité – été', FileUploadService.sanitizeLabel('Rapport d\'activité – été'));
    }
  }

  @IsTest
  static void sanitizeLabel_givenBlankOrOnlyControlCharacters_returnsEmpty() {
    System.runAs(getTestUser()) {
      Assert.areEqual('', FileUploadService.sanitizeLabel(null));
      Assert.areEqual('', FileUploadService.sanitizeLabel('  '));
      Assert.areEqual('', FileUploadService.sanitizeLabel('\t\n'));
    }
  }

  @IsTest
  static void sanitizeLabel_givenControlCharacters_replacesThemWithSingleSpace() {
    System.runAs(getTestUser()) {
      Assert.areEqual('Budget Plan', FileUploadService.sanitizeLabel('Budget\t\nPlan'));
    }
  }

  @IsTest
  static void getFileExtension_givenVariousNames_returnsExtensionOrEmpty() {
    System.runAs(getTestUser()) {
      Assert.areEqual('pdf', FileUploadService.getFileExtension('document.pdf'));
      Assert.areEqual('gz', FileUploadService.getFileExtension('archive.tar.gz'));
      Assert.areEqual('', FileUploadService.getFileExtension('README'));
      Assert.areEqual('', FileUploadService.getFileExtension('.gitignore'));
      Assert.areEqual('', FileUploadService.getFileExtension('file.'));
      Assert.areEqual('', FileUploadService.getFileExtension(null));
    }
  }

  @IsTest
  static void resolveBaseName_givenBlankLabel_usesFileNameThenFallback() {
    System.runAs(getTestUser()) {
      Assert.areEqual('contrat', FileUploadService.resolveBaseName(null, 'contrat.docx'));
      Assert.areEqual(FileUploadService.FALLBACK_TITLE, FileUploadService.resolveBaseName('', ''));
    }
  }

  private static Id createContentDocument(final String title) {
    final ContentVersion version = new ContentVersion(
      Title = title,
      PathOnClient = title + '.pdf',
      VersionData = Blob.valueOf('body')
    );
    insert version;
    return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
  }

  @IsTest
  static void renameUploadedFiles_givenFilesOfAField_namesThemAfterTheLabelWithSuffixes() {
    System.runAs(getTestUser()) {
      final Id firstDocumentId = createContentDocument('scan1');
      final Id secondDocumentId = createContentDocument('scan2');

      Test.startTest();
      final List<FileUploadService.UploadedFileWrapper> results = FileUploadService.renameUploadedFiles(
        new List<Id>{ firstDocumentId, secondDocumentId },
        'Bank details',
        new List<String>()
      );
      Test.stopTest();

      Assert.areEqual(2, results.size());
      Assert.areEqual('Bank details.pdf', results[0].name);
      Assert.areEqual('Bank details (1).pdf', results[1].name);
      Assert.areEqual('Bank details', [SELECT Title FROM ContentDocument WHERE Id = :firstDocumentId].Title);
      Assert.areEqual('Bank details (1)', [SELECT Title FROM ContentDocument WHERE Id = :secondDocumentId].Title);
    }
  }

  @IsTest
  static void renameUploadedFiles_givenExistingTitles_continuesTheNumbering() {
    System.runAs(getTestUser()) {
      final Id documentId = createContentDocument('scan');

      Test.startTest();
      final List<FileUploadService.UploadedFileWrapper> results = FileUploadService.renameUploadedFiles(
        new List<Id>{ documentId },
        'Bank details',
        new List<String>{ 'Bank details', 'Bank details (1)' }
      );
      Test.stopTest();

      Assert.areEqual('Bank details (2).pdf', results[0].name);
    }
  }

  @IsTest
  static void renameUploadedFiles_givenBlankLabel_keepsTheFileName() {
    System.runAs(getTestUser()) {
      final Id documentId = createContentDocument('scan');

      Test.startTest();
      final List<FileUploadService.UploadedFileWrapper> results = FileUploadService.renameUploadedFiles(
        new List<Id>{ documentId },
        null,
        null
      );
      Test.stopTest();

      Assert.areEqual('scan.pdf', results[0].name);
    }
  }

  @IsTest
  static void renameUploadedFiles_givenNoDocument_throwsAuraHandledException() {
    System.runAs(getTestUser()) {
      try {
        FileUploadService.renameUploadedFiles(new List<Id>(), 'Bank details', null);
        Assert.fail('Expected an AuraHandledException when no document Id is given');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('document Id is required'), e.getMessage());
      }
    }
  }

  @IsTest
  static void renameUploadedFiles_givenDeletedDocument_skipsIt() {
    System.runAs(getTestUser()) {
      final Id documentId = createContentDocument('scan');
      FileUploadService.deleteUploadedFile(documentId);

      final List<FileUploadService.UploadedFileWrapper> results = FileUploadService.renameUploadedFiles(
        new List<Id>{ documentId },
        'Bank details',
        null
      );

      Assert.areEqual(0, results.size());
    }
  }

  @IsTest
  static void linkFilesToRecord_givenUploadedFiles_linksThemToTheRecordOnlyOnce() {
    System.runAs(getTestUser()) {
      final Id applicationFormId = createApplicationForm();
      final Id firstDocumentId = createContentDocument('scan1');
      final Id secondDocumentId = createContentDocument('scan2');
      final List<Id> documentIds = new List<Id>{ firstDocumentId, secondDocumentId, firstDocumentId };

      Test.startTest();
      FileUploadService.linkFilesToRecord(applicationFormId, documentIds);
      FileUploadService.linkFilesToRecord(applicationFormId, documentIds);
      Test.stopTest();

      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :applicationFormId AND ContentDocumentId IN :documentIds
        ],
        'Each document must be linked to the record exactly once'
      );
    }
  }

  @IsTest
  static void linkFilesToRecord_givenNoRecord_throwsAuraHandledException() {
    System.runAs(getTestUser()) {
      try {
        FileUploadService.linkFilesToRecord(null, new List<Id>{ createContentDocument('scan') });
        Assert.fail('Expected an AuraHandledException when the record Id is missing');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('record Id is required'), e.getMessage());
      }
    }
  }

  @IsTest
  static void linkFilesToRecord_givenNoDocuments_doesNothing() {
    System.runAs(getTestUser()) {
      final Id applicationFormId = createApplicationForm();

      FileUploadService.linkFilesToRecord(applicationFormId, null);
      FileUploadService.linkFilesToRecord(applicationFormId, new List<Id>());

      Assert.areEqual(
        0,
        [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :applicationFormId],
        'No link must be created without documents'
      );
    }
  }
}