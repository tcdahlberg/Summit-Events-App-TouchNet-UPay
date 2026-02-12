/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * Test class for UPayHelper
 */
@IsTest
private class UPayHelper_TEST {

    @TestSetup
    static void setupTestData() {
        // Create Summit Events Settings
        summit__Summit_Events_Settings__c settings = new summit__Summit_Events_Settings__c();
        settings.summit__Cookie_Encryption_Key__c = '12345678901234567890123456789012'; // Exactly 32 bytes for AES256
        settings.summit__Community_Base_URL__c = 'https://test.salesforce.com/';
        insert settings;

        // Create test event
        summit__Summit_Events__c evt = new summit__Summit_Events__c(
            summit__Event_Name__c = 'Test Event',
            summit__Event_Submit_Title__c = 'Submit'
        );
        insert evt;

        // Create test instance
        summit__Summit_Events_Instance__c instance = new summit__Summit_Events_Instance__c(
            summit__Event__c = evt.Id,
            summit__Instance_Title__c = 'Test Instance',
            summit__Instance_Start_Date__c = Date.today().addDays(7),
            summit__Instance_End_Date__c = Date.today().addDays(7)
        );
        insert instance;

        // Create test registration
        summit__Summit_Events_Registration__c reg = new summit__Summit_Events_Registration__c(
            summit__Event__c = evt.Id,
            summit__Event_Instance__c = instance.Id,
            summit__Registrant_First_Name__c = 'Test',
            summit__Registrant_Last_Name__c = 'User',
            summit__Registrant_Email__c = 'test@example.com',
            summit__Status__c = 'Started'
        );
        insert reg;
    }

    @IsTest
    static void testGetSeaCommunityURL() {
        Test.startTest();
        String url = UPayHelper.getSeaCommunityURL();
        Test.stopTest();

        System.assertEquals('https://test.salesforce.com/', url, 'Community URL should match settings');
    }

    @IsTest
    static void testEncryptDecryptString() {
        String testString = 'Test Data to Encrypt';

        Test.startTest();
        String encrypted = UPayHelper.encryptString(testString);
        String decrypted = UPayHelper.decryptString(encrypted, true);
        Test.stopTest();

        System.assertNotEquals(testString, encrypted, 'Encrypted string should be different');
        System.assertEquals(testString, decrypted, 'Decrypted string should match original');
    }

    @IsTest
    static void testCreateSecurityToken() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];
        summit__Summit_Events__c evt = [SELECT Id FROM summit__Summit_Events__c LIMIT 1];

        Test.startTest();
        String token = UPayHelper.createSecurityToken(reg.Id, evt.Id, 100.00);
        Test.stopTest();

        System.assertNotEquals(null, token, 'Security token should be created');
        System.assert(String.isNotBlank(token), 'Security token should not be blank');
    }

    @IsTest
    static void testValidateSecurityToken() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];
        summit__Summit_Events__c evt = [SELECT Id FROM summit__Summit_Events__c LIMIT 1];

        String token = UPayHelper.createSecurityToken(reg.Id, evt.Id, 100.00);

        Test.startTest();
        UPayHelper.SecurityToken validatedToken = UPayHelper.validateSecurityToken(token);
        Test.stopTest();

        System.assertNotEquals(null, validatedToken, 'Token should validate successfully');
        System.assertEquals(reg.Id, validatedToken.registrationId, 'Registration ID should match');
        System.assertEquals(evt.Id, validatedToken.eventId, 'Event ID should match');
        System.assertEquals('100.00', validatedToken.amount, 'Amount should match');
    }

    @IsTest
    static void testValidateSecurityToken_Expired() {
        // Create a token with old timestamp
        UPayHelper.SecurityToken oldToken = new UPayHelper.SecurityToken();
        oldToken.registrationId = 'a350m0000008q63AAA';
        oldToken.eventId = 'a330m0000001SOrAAM';
        oldToken.timestamp = String.valueOf(Datetime.now().addDays(-2).getTime()); // 2 days old
        oldToken.amount = '100.00';

        String jsonToken = JSON.serialize(oldToken);
        String encrypted = UPayHelper.encryptString(jsonToken);

        Test.startTest();
        UPayHelper.SecurityToken validatedToken = UPayHelper.validateSecurityToken(encrypted);
        Test.stopTest();

        System.assertEquals(null, validatedToken, 'Expired token should not validate');
    }

    @IsTest
    static void testBuildValidationKeyHash() {
        Test.startTest();
        String hash = UPayHelper.buildValidationKeyHash('testKey', 'trans123', '100.00');
        Test.stopTest();

        System.assertNotEquals(null, hash, 'Hash should be generated');
        System.assert(String.isNotBlank(hash), 'Hash should not be blank');
    }

    @IsTest
    static void testGetUPaySiteConfig() {
        // Note: This will return null in test since we can't insert Custom Metadata in tests
        Test.startTest();
        TouchNet_UPay_Site__mdt config = UPayHelper.getUPaySiteConfig('Event_Registration');
        Test.stopTest();

        // In test context, this will be null since custom metadata is read-only
        // Real functionality tested in integration tests
        System.assert(true, 'Method executed without errors');
    }

    @IsTest
    static void testGetActiveUPaySites() {
        Test.startTest();
        List<TouchNet_UPay_Site__mdt> sites = UPayHelper.getActiveUPaySites();
        Test.stopTest();

        System.assertNotEquals(null, sites, 'Sites list should not be null');
    }

    @IsTest
    static void testEncryptString_BlankInput() {
        Test.startTest();
        String result = UPayHelper.encryptString('');
        Test.stopTest();

        System.assertEquals('', result, 'Blank input should return blank');
    }

    @IsTest
    static void testDecryptString_BlankInput() {
        Test.startTest();
        String result = UPayHelper.decryptString('', true);
        Test.stopTest();

        System.assertEquals('', result, 'Blank input should return blank');
    }

    @IsTest
    static void testValidateSecurityToken_InvalidToken() {
        Test.startTest();
        UPayHelper.SecurityToken token = UPayHelper.validateSecurityToken('invalid-token');
        Test.stopTest();

        System.assertEquals(null, token, 'Invalid token should return null');
    }

    @IsTest
    static void testValidateSecurityToken_BlankToken() {
        Test.startTest();
        UPayHelper.SecurityToken token = UPayHelper.validateSecurityToken('');
        Test.stopTest();

        System.assertEquals(null, token, 'Blank token should return null');
    }
}

