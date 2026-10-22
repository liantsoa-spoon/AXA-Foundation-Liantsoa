public with sharing class DecisionComitePathController {

    @AuraEnabled
    public static String getCurrentStatus(Id recordId, String fieldApiName) {
        validateFieldName(fieldApiName);

        String query = 'SELECT ' + fieldApiName + ' FROM ApplicationForm WHERE Id = :recordId WITH USER_MODE';
        List<ApplicationForm> results = Database.query(query);
        if (results.isEmpty()) {
            return null;
        }

        Object value = results[0].get(fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    @AuraEnabled
    public static void updateStatus(Id recordId, String fieldApiName, String newValue) {
        validateFieldName(fieldApiName);

        ApplicationForm record = new ApplicationForm(Id = recordId);
        record.put(fieldApiName, newValue);

        Database.SaveResult result = Database.update(record, AccessLevel.USER_MODE);
        if (!result.isSuccess()) {
            AuraHandledException ex = new AuraHandledException(result.getErrors()[0].getMessage());
            ex.setMessage(result.getErrors()[0].getMessage());
            throw ex;
        }
    }

    private static void validateFieldName(String fieldApiName) {
        if (String.isBlank(fieldApiName) || !Pattern.matches('^[A-Za-z0-9_]+$', fieldApiName)) {
            AuraHandledException ex = new AuraHandledException('Invalid field name: ' + fieldApiName);
            ex.setMessage('Invalid field name: ' + fieldApiName);
            throw ex;
        }
    }
}