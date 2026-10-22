/**
 * Handler class for ContentVersionTrigger.
 * Automatically formats uploaded file titles to PascalCase based on context.
 */
public with sharing class ContentVersionTriggerHandler {

    /**
     * Executes before ContentVersion records are inserted into Salesforce.
     */
    public static void handleBeforeInsert(List<ContentVersion> newVersions) {
        for (ContentVersion cv : newVersions) {
            if (String.isNotBlank(cv.Title)) {
                // Convert existing Title to PascalCase
                cv.Title = toPascalCase(cv.Title);
                
                // Keep file extension intact on PathOnClient
                if (String.isNotBlank(cv.PathOnClient)) {
                    String ext = getFileExtension(cv.PathOnClient);
                    cv.PathOnClient = cv.Title + ext;
                }
            }
        }
    }

    /**
     * Helper method to convert any string into PascalCase format.
     * Example: "Add CV" -> "AddCv"
     */
    public static String toPascalCase(String input) {
        if (String.isBlank(input)) {
            return 'UploadedFile';
        }
        
        // Remove special characters and split by space
        String cleanInput = input.replaceAll('[^a-zA-Z0-9\\s]', '');
        List<String> words = cleanInput.split('\\s+');
        String pascalResult = '';

        for (String word : words) {
            if (String.isNotBlank(word)) {
                pascalResult += word.substring(0, 1).toUpperCase() + word.substring(1).toLowerCase();
            }
        }

        return String.isNotBlank(pascalResult) ? pascalResult : 'UploadedFile';
    }

    /**
     * Extracts the file extension (including dot) from a file path.
     */
    private static String getFileExtension(String path) {
        if (String.isBlank(path) || !path.contains('.')) {
            return '';
        }
        return path.substring(path.lastIndexOf('.'));
    }
}