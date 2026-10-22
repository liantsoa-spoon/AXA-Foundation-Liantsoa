@IsTest(SeeAllData = true)
public with sharing class LightningForgotPasswordControllerTest {

 /* Verifies that ForgotPasswordController handles invalid usernames appropriately */
 @IsTest
 static void testLightningForgotPasswordControllerInvalidUserName() {
  Assert.areEqual(LightningForgotPasswordController.forgotPassword('fakeUser', 'http://a.com'), Label.Site.invalid_email);
  Assert.areEqual(LightningForgotPasswordController.forgotPassword(null, 'http://a.com'), Label.Site.invalid_email);
  Assert.areEqual(LightningForgotPasswordController.forgotPassword('a', '/home/home.jsp'), Label.Site.invalid_email);
 }

 /* Verifies that null checkEmailRef url throws proper exception. */
 @IsTest
 static void testLightningForgotPasswordControllerWithNullCheckEmailRef() {
  Assert.areEqual(LightningForgotPasswordController.forgotPassword('a', null), 'Argument 1 cannot be null');
  Assert.areEqual(LightningForgotPasswordController.forgotPassword('a@salesforce.com', null), 'Argument 1 cannot be null');
 }

 /* Verifies that LightningForgotPasswordController object is instantiated correctly. */
 @IsTest
 static void LightningForgotPasswordControllerInstantiation() {
  LightningForgotPasswordController controller = new LightningForgotPasswordController();
  Assert.areNotEqual(controller, null);
 }

 @IsTest
 static void testSetExperienceIdWithNullReturnsNull() {
  Assert.isNull(LightningForgotPasswordController.setExperienceId(null));
 }

 @IsTest
 static void testSetExperienceIdWithValueNeverThrowsToTheCaller() {
  final String result = LightningForgotPasswordController.setExperienceId('axa');
  Assert.isTrue(result == null || String.isNotBlank(result), 'setExperienceId returns null or an error message');
 }
}