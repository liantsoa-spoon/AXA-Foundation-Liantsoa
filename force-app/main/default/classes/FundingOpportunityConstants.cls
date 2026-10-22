/**
 * @description       : Provides record type references and picklist API values for FundingOpportunity.
 * @author            : Kevin RAMAROZATOVO
 * @last modified on  : 13-10-2026
 * @last modified by  : Kevin RAMAROZATOVO
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   08-10-2026   KRA      Initial version
 **/
public inherited sharing class FundingOpportunityConstants {
  public static final RecordTypes RecordTypes = new RecordTypes();

  public static final GeographicScope GeographicScope = new GeographicScope();
  public static final Status Status = new Status();
  public static final Theme Theme = new Theme();

  @TestVisible
  private FundingOpportunityConstants() {}

  public class RecordTypes {
    public final RecordTypeProvider.RecordTypeReference CALL_FOR_PROJECTS =
      new RecordTypeProvider.RecordTypeReference(FundingOpportunity.SObjectType, 'CallForProjects');
    public final RecordTypeProvider.RecordTypeReference DIRECT_MANAGEMENT =
      new RecordTypeProvider.RecordTypeReference(FundingOpportunity.SObjectType, 'DirectManagement');
  }

  public class GeographicScope {
    public final String FRANCE = 'France';
  }

  public class Status {
    public final String DRAFT = 'Draft';
  }

  public class Theme {
    public final String GLOBAL_CHAIRS = 'Global Chairs';
  }
}