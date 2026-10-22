@IsTest(SeeAllData = true)
public with sharing class LightningLoginFormControllerTest {

 @IsTest
 static void LightningLoginFormControllerInstantiation() {
  LightningLoginFormController controller = new LightningLoginFormController();
  Assert.areNotEqual(controller, null);
 }

 @IsTest
 static void testIsUsernamePasswordEnabled() {
  Assert.areEqual(true, LightningLoginFormController.getIsUsernamePasswordEnabled());
 }

 @IsTest
 static void testIsSelfRegistrationEnabled() {
  Assert.areEqual(false, LightningLoginFormController.getIsSelfRegistrationEnabled());
 }

 @IsTest
 static void testGetSelfRegistrationURL() {
  Assert.areEqual(null, LightningLoginFormController.getSelfRegistrationUrl());
 }

 @IsTest
 static void testAuthConfig() {
  Auth.AuthConfiguration authConfig = LightningLoginFormController.getAuthConfig();
  Assert.areNotEqual(null, authConfig);
 }

 @IsTest
 static void testGetForgotPasswordUrl() {
  final String forgotPasswordUrl = LightningLoginFormController.getForgotPasswordUrl();
  Assert.areEqual(LightningLoginFormController.getAuthConfig().getForgotPasswordUrl(), forgotPasswordUrl);
 }

 @IsTest
 static void testLoginNeverThrowsToTheCaller() {
  final String result = LightningLoginFormController.login('unknown.user@axa-test.com', 'wrongPassword1', '/');
  Assert.isTrue(result == null || String.isNotBlank(result), 'login returns null or an error message');
 }

 @IsTest
 static void testSetExperienceIdWithNullReturnsNull() {
  Assert.isNull(LightningLoginFormController.setExperienceId(null));
 }

 @IsTest
 static void testSetExperienceIdWithValueNeverThrowsToTheCaller() {
  final String result = LightningLoginFormController.setExperienceId('axa');
  Assert.isTrue(result == null || String.isNotBlank(result), 'setExperienceId returns null or an error message');
 }
}