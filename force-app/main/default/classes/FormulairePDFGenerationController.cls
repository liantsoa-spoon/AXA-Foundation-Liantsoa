public with sharing class FormulairePDFGenerationController {

    // Object API name -> lookup field on that object pointing to ApplicationForm.
    private static final Map<String, String> CHILD_LOOKUP_TO_APPLICATION_FORM = new Map<String, String>{
        'Benefit' => 'Project__c'
    };

    public class SectionData {
        @AuraEnabled public String sectionName;
        @AuraEnabled public List<QuestionData> question = new List<QuestionData>();
    }

    public class QuestionData {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class FormMetadata {
        @AuraEnabled public String fundingOpportunityName;
        @AuraEnabled public String candidateName;
        @AuraEnabled public List<SectionData> sections;
    }

    @AuraEnabled
    public static FormMetadata getMergedFormJson(Id applicationFormId, Boolean eoiOnly) {
        return buildMergedSections(applicationFormId, eoiOnly);
    }

    @AuraEnabled
    public static Id generatePdf(Id applicationFormId, Id templateContentVersionId, Boolean eoiOnly) {
        FormMetadata formData = buildMergedSections(applicationFormId, eoiOnly);

        Map<String, Object> tokenData = new Map<String, Object>{
            'sections' => formData.sections,
            'fundingOpportunityName' => formData.fundingOpportunityName,
            'candidateName' => formData.candidateName,
            'IF_isEoi' => eoiOnly
        };
        String tokenJson = JSON.serialize(tokenData);
        String fileNamePrefix = eoiOnly ? 'TokenData_EOI_' : 'TokenData_Application_';
        Id jsonFileId = uploadJsonFile(tokenJson, fileNamePrefix + applicationFormId);

        DocumentGenerationProcess documentGeneration = new DocumentGenerationProcess();
        documentGeneration.Type = 'GenerateAndConvert';
        documentGeneration.RequestText = JSON.serialize(new Map<String, Object>{
            'keepIntermediate' => false,
            'title' => eoiOnly ? 'EOI Form' : 'Application Form',
            'templateContentVersionId' => templateContentVersionId
        });
        documentGeneration.ReferenceObject = applicationFormId;
        documentGeneration.TokenDataContentDocumentId = jsonFileId;
        documentGeneration.DocGenApiVersionType = 'Advanced';
        insert documentGeneration;

        return documentGeneration.Id;
    }


    private static List<AssessmentQuestionAssignment> getFormStructure(Id fundingOpportunityId, Boolean eoiOnly) {
        String query = 'SELECT AssessmentQuestionSetId, AssessmentQuestionSet.Name, AssessmentQuestionSet.Sequence__c, ' +
            'AssessmentQuestionId, AssessmentQuestion.Sequence__c, AssessmentQuestion.ObjectAPIName__c, ' +
            'AssessmentQuestion.FieldAPIName__c, AssessmentQuestion.ActiveVersionId, ' +
            'AssessmentQuestion.ActiveVersion.QuestionText, ' +
            'AssessmentQuestion.ActiveVersion.QuestionTextFR__c, ' +
            'AssessmentQuestion.ActiveVersion.ResponseValues, ' +
            'AssessmentQuestion.ActiveVersion.ResponseValuesFR__c, ' +
            'AssessmentQuestion.ActiveVersion.DataType ' +
            'FROM AssessmentQuestionAssignment ' +
            'WHERE FundingOpportunity__c = :fundingOpportunityId' +
            (eoiOnly ? ' AND EOI__c = true' : ' AND EOI__c = false') +
            ' WITH USER_MODE ' +
            'ORDER BY AssessmentQuestionSet.Sequence__c, AssessmentQuestion.Sequence__c';

        return (List<AssessmentQuestionAssignment>) Database.query(query);
    }

    // ---- Result 1: mapped questions, one query per distinct object ----

    private static Map<String, Map<String, Object>> getMappedValues(Id applicationFormId,
            List<AssessmentQuestionAssignment> assignments) {
        Map<String, Set<String>> fieldsByObject = new Map<String, Set<String>>();
        for (AssessmentQuestionAssignment a : assignments) {
            String objName = a.AssessmentQuestion.ObjectAPIName__c;
            String fieldName = a.AssessmentQuestion.FieldAPIName__c;
            if (String.isNotBlank(objName) && String.isNotBlank(fieldName)) {
                validateApiName(objName);
                validateApiName(fieldName);
                if (!fieldsByObject.containsKey(objName)) {
                    fieldsByObject.put(objName, new Set<String>());
                }
                fieldsByObject.get(objName).add(fieldName);
            }
        }
        System.debug('fieldsByObject' + fieldsByObject);

        Map<String, Id> targetRecordIdByObject = getTargetRecordIds(applicationFormId, fieldsByObject.keySet());

        Map<String, Map<String, Object>> mappedValues = new Map<String, Map<String, Object>>();
        for (String objName : fieldsByObject.keySet()) {
            Id targetRecordId = targetRecordIdByObject.get(objName);
            Map<String, Object> fieldValues = new Map<String, Object>();

            if (targetRecordId != null) {
                String query = 'SELECT ' + String.join(new List<String>(fieldsByObject.get(objName)), ', ') +
                    ' FROM ' + objName + ' WHERE Id = :targetRecordId WITH USER_MODE';
                List<SObject> results = Database.query(query);
                if (!results.isEmpty()) {
                    for (String f : fieldsByObject.get(objName)) {
                        fieldValues.put(f, results[0].get(f));
                    }
                }
            }
            mappedValues.put(objName, fieldValues);
        }

        return mappedValues;
    }

    private static Map<String, Id> getTargetRecordIds(Id applicationFormId, Set<String> objectNames) {
        Map<String, Id> targetRecordIdByObject = new Map<String, Id>();
        if (objectNames.contains('ApplicationForm')) {
            targetRecordIdByObject.put('ApplicationForm', applicationFormId);
        }

        // Objects that hold the lookup to ApplicationForm (child -> parent); most recent record wins.
        for (String objName : CHILD_LOOKUP_TO_APPLICATION_FORM.keySet()) {
            if (!objectNames.contains(objName)) {
                continue;
            }
            String childQuery = 'SELECT Id FROM ' + objName + ' WHERE ' + CHILD_LOOKUP_TO_APPLICATION_FORM.get(objName) +
                ' = :applicationFormId WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1';
            List<SObject> children = Database.query(childQuery);
            if (!children.isEmpty()) {
                targetRecordIdByObject.put(objName, children[0].Id);
            }
        }

        // Objects referenced by a lookup on ApplicationForm (<Object>Id, e.g. ContactId).
        Set<String> lookupFieldNames = new Set<String>();
        for (String objName : objectNames) {
            if (objName != 'ApplicationForm' && !CHILD_LOOKUP_TO_APPLICATION_FORM.containsKey(objName)) {
                lookupFieldNames.add(objName + 'Id');
            }
        }
        if (lookupFieldNames.isEmpty()) {
            return targetRecordIdByObject;
        }

        String query = 'SELECT ' + String.join(new List<String>(lookupFieldNames), ', ') +
            ' FROM ApplicationForm WHERE Id = :applicationFormId WITH USER_MODE';
        SObject appForm = Database.query(query)[0];

        for (String objName : objectNames) {
            if (objName == 'ApplicationForm' || CHILD_LOOKUP_TO_APPLICATION_FORM.containsKey(objName)) {
                continue;
            }
            String lookupField = objName + 'Id';
            Object lookupValue = appForm.get(lookupField);
            if (lookupValue != null) {
                targetRecordIdByObject.put(objName, (Id) lookupValue);
            }
        }
        return targetRecordIdByObject;
    }

    // ---- Result 2: stored answers for questions with no field mapping ----

    private static Map<Id, AssessmentQuestionResponse> getResponseValues(Id applicationFormId) {
        Map<Id, AssessmentQuestionResponse> responseByQuestionVersionId = new Map<Id, AssessmentQuestionResponse>();

        for (AssessmentQuestionResponse r : [
            SELECT AssessmentQuestionId, ResponseText, ResponseValue, ChoiceValue, DateValue,
                   DateTimeValue, IntegerResponseValue, DecimalResponseValue, IsTrueOrFalseValue
            FROM AssessmentQuestionResponse
            WHERE ProjetRattache__c = :applicationFormId
            WITH USER_MODE
        ]) {
            responseByQuestionVersionId.put(r.AssessmentQuestionId, r);
        }

        return responseByQuestionVersionId;
    }

    // ---- Step 3: single pass over the ordered assignments, resolving each value ----

    private static List<SectionData> mergeIntoSections(List<AssessmentQuestionAssignment> assignments,
            Map<String, Map<String, Object>> mappedValues, Map<Id, AssessmentQuestionResponse> responseValues,
            String language) {
        Map<Id, SectionData> sectionById = new Map<Id, SectionData>();
        List<SectionData> orderedSections = new List<SectionData>();

        for (AssessmentQuestionAssignment a : assignments) {
            Id setId = a.AssessmentQuestionSetId;
            if (!sectionById.containsKey(setId)) {
                SectionData sd = new SectionData();
                sd.sectionName = a.AssessmentQuestionSet.Name;
                sectionById.put(setId, sd);
                orderedSections.add(sd);
            }

            QuestionData qd = new QuestionData();
            String frText = a.AssessmentQuestion.ActiveVersion.QuestionTextFR__c;
            qd.label = (language == 'FR' && String.isNotBlank(frText))
                ? frText
                : a.AssessmentQuestion.ActiveVersion.QuestionText;

            String objName = a.AssessmentQuestion.ObjectAPIName__c;
            String fieldName = a.AssessmentQuestion.FieldAPIName__c;

            if (String.isNotBlank(objName) && String.isNotBlank(fieldName)) {
                Object rawValue = mappedValues.containsKey(objName) ? mappedValues.get(objName).get(fieldName) : null;
                qd.value = rawValue == null ? '' : translateChoiceValue(String.valueOf(rawValue), a, language);
            } else {
                AssessmentQuestionResponse resp = responseValues.get(a.AssessmentQuestion.ActiveVersionId);
                qd.value = resp == null ? '' : extractResponseValue(resp);

                if(resp == null){
                    if(a.AssessmentQuestion.ActiveVersion.DataType == 'File'){
                        qd.value = 'Not Uploaded';
                    }
                    else{
                        qd.value = '';
                    }
                }
                else{
                    if(a.AssessmentQuestion.ActiveVersion.DataType == 'File'){
                        qd.value = 'Uploaded';
                    }
                    else if(a.AssessmentQuestion.ActiveVersion.DataType == 'Checkbox'){
                        qd.value = 'Yes';
                    }
                    else{
                         qd.value = translateChoiceValue(extractResponseValue(resp), a, language);
                    }
                    
                }
            }

            sectionById.get(setId).question.add(qd);
        }
        

        return orderedSections;
    }

    private static FormMetadata buildMergedSections(Id applicationFormId, Boolean eoiOnly) {
        ApplicationForm appForm = [
            SELECT Id, ProgrammeRattache__c, ProgrammeRattache__r.Name, Contact.Name,
                   ProgrammeRattache__r.Program.RecordType.DeveloperName
            FROM ApplicationForm
            WHERE Id = :applicationFormId
            WITH USER_MODE
        ];
        Id fundingOpportunityId = appForm.ProgrammeRattache__c;

        List<AssessmentQuestionAssignment> assignments = getFormStructure(fundingOpportunityId, eoiOnly);
        Map<String, Map<String, Object>> mappedValues = getMappedValues(applicationFormId, assignments);
        Map<Id, AssessmentQuestionResponse> responseValues = getResponseValues(applicationFormId);

        FormMetadata result = new FormMetadata();
        result.fundingOpportunityName = appForm.ProgrammeRattache__r?.Name;
        result.candidateName = appForm.Contact?.Name;
        String language = resolveLanguage(appForm.ProgrammeRattache__r?.Program?.RecordType?.DeveloperName);
        result.sections = mergeIntoSections(assignments, mappedValues, responseValues, language);
        return result;
    }

    // Config_Pillar_Form_Language__mdt forces a language for a pillar (e.g. Science -> EN); otherwise use the user's language.
    private static String resolveLanguage(String pillarDeveloperName) {
        if (String.isNotBlank(pillarDeveloperName)) {
            for (ConfigPillarFormLanguage__mdt cfg : [
                SELECT Language__c
                FROM ConfigPillarFormLanguage__mdt
                WHERE Pillar__c = :pillarDeveloperName
                LIMIT 1
            ]) {
                return cfg.Language__c.toUpperCase();
            }
        }
        String userLanguage = UserInfo.getLanguage().toUpperCase();
        return userLanguage.startsWith('FR') ? 'FR' : 'EN';
    }

    // Stored answers are the EN values; ResponseValuesFR__c lists the FR labels in the same order as ResponseValues.
    private static String translateChoiceValue(String value, AssessmentQuestionAssignment a, String language) {
        if (language != 'FR' || String.isBlank(value)) {
            return value;
        }
        String enRaw = a.AssessmentQuestion.ActiveVersion.ResponseValues;
        String frRaw = a.AssessmentQuestion.ActiveVersion.ResponseValuesFR__c;
        if (String.isBlank(enRaw) || String.isBlank(frRaw)) {
            return value;
        }
        List<String> enValues = enRaw.split('\\r?\\n');
        List<String> frValues = frRaw.split('\\r?\\n');
        if (enValues.size() != frValues.size()) {
            return value;
        }

        Map<String, String> frByEn = new Map<String, String>();
        for (Integer i = 0; i < enValues.size(); i++) {
            frByEn.put(enValues[i].trim(), frValues[i].trim());
        }

        // Multiselect answers are ';' separated; a single answer is just one token.
        List<String> translated = new List<String>();
        for (String token : value.split(';')) {
            String key = token.trim();
            translated.add(frByEn.containsKey(key) && String.isNotBlank(frByEn.get(key)) ? frByEn.get(key) : key);
        }
        return String.join(translated, '; ');
    }

    private static String extractResponseValue(AssessmentQuestionResponse r) {
        if (String.isNotBlank(r.ResponseText)) {
            return r.ResponseText;
        }
        if (String.isNotBlank(r.ChoiceValue)) {
            return r.ChoiceValue;
        }
        if (r.DateValue != null) {
            return String.valueOf(r.DateValue);
        }
        if (r.DateTimeValue != null) {
            return String.valueOf(r.DateTimeValue);
        }
        if (r.IntegerResponseValue != null) {
            return String.valueOf(r.IntegerResponseValue);
        }
        if (r.DecimalResponseValue != null) {
            return String.valueOf(r.DecimalResponseValue);
        }
        if (r.IsTrueOrFalseValue != null) {
            return r.IsTrueOrFalseValue ? 'Yes' : 'No';
        }
        return String.isNotBlank(r.ResponseValue) ? r.ResponseValue : '';
    }

    private static Id uploadJsonFile(String jsonBody, String fileName) {
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName + '.json';
        cv.VersionData = Blob.valueOf(jsonBody);
        insert cv;

        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH USER_MODE].ContentDocumentId;
    }

    private static void validateApiName(String apiName) {
        if (String.isBlank(apiName) || !Pattern.matches('^[A-Za-z0-9_]+$', apiName)) {
            AuraHandledException ex = new AuraHandledException('Invalid API name: ' + apiName);
            ex.setMessage('Invalid API name: ' + apiName);
            throw ex;
        }
    }
}