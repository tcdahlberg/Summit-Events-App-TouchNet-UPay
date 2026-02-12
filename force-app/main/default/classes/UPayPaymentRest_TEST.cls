/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * Test class for UPayPaymentRest
 */
@IsTest
private class UPayPaymentRest_TEST {

    @TestSetup
    static void setupTestData() {
        // Create Summit Events Settings
        summit__Summit_Events_Settings__c settings = new summit__Summit_Events_Settings__c();
        settings.summit__Cookie_Encryption_Key__c = '12345678901234567890123456789012'; // Exactly 32 bytes for AES256
        settings.summit__Community_Base_URL__c = 'https://test.salesforce.com/';
        insert settings;

        // Create test event
        summit__Summit_Events__c evt = new summit__Summit_Events__c(
            summit__Event_Name__c = 'REST Test Event',
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
            summit__Registrant_First_Name__c = 'Jane',
            summit__Registrant_Last_Name__c = 'Smith',
            summit__Registrant_Email__c = 'jane.smith@test.com',
            summit__Status__c = 'Started'
        );
        insert reg;

        // Create test fees
        summit__Summit_Events_Fee__c fee = new summit__Summit_Events_Fee__c(
            summit__Event_Registration__c = reg.Id,
            summit__Event_Fee__c = 100.00,
            summit__Event_Fee_Type__c = 'Event Fee'
        );
        insert fee;
    }

    @IsTest
    static void testProcessPayment_Success() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];
        summit__Summit_Events__c evt = [SELECT Id FROM summit__Summit_Events__c LIMIT 1];
        summit__Summit_Events_Instance__c instance = [SELECT Id FROM summit__Summit_Events_Instance__c LIMIT 1];

        // Create security token
        String seaSecureToken = UPayHelper.createSecurityToken(reg.Id, evt.Id, 100.00);

        // Build request body (form-urlencoded format)
        String requestBody = 'pmt_status=success' +
            '&tpg_trans_id=TEST123456' +
            '&pmt_amt=100.00' +
            '&pmt_date=02/12/2026' +
            '&SEA_SECURE=' + EncodingUtil.urlEncode(seaSecureToken, 'UTF-8') +
            '&card_type=Visa' +
            '&name_on_acct=Jane Smith' +
            '&acct_addr1=123 Main St' +
            '&acct_city=Minneapolis' +
            '&acct_state=MN' +
            '&acct_zip=55401' +
            '&acct_country=US' +
            '&sys_tracking_id=TRACK123';

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/upaypaymentreceive';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = UPayPaymentRest.receivePayment();
        Test.stopTest();

        System.assertEquals('HTTP_OK', result, 'Should return HTTP_OK');

        // Verify payment was created
        List<summit__Summit_Events_Payment__c> payments = [
            SELECT Id, summit__Payment_Amount__c, summit__TouchnetReceiptNumber__c,
                   summit__Event_Registration__c
            FROM summit__Summit_Events_Payment__c
            WHERE summit__Event_Registration__c = :reg.Id
        ];
        System.assertEquals(1, payments.size(), 'Payment should be created');
        System.assertEquals(100.00, payments[0].summit__Payment_Amount__c, 'Amount should match');
        System.assertEquals('TEST123456', payments[0].summit__TouchnetReceiptNumber__c, 'Transaction ID should match');

        // Verify fees were linked
        List<summit__Summit_Events_Fee__c> fees = [
            SELECT Id, summit__Summit_Events_Payment__c
            FROM summit__Summit_Events_Fee__c
            WHERE summit__Event_Registration__c = :reg.Id
        ];
        System.assertEquals(1, fees.size(), 'Fee should exist');
        System.assertEquals(payments[0].Id, fees[0].summit__Summit_Events_Payment__c, 'Fee should be linked to payment');

        // Verify registration status updated
        summit__Summit_Events_Registration__c updatedReg = [
            SELECT Id, summit__Status__c
            FROM summit__Summit_Events_Registration__c
            WHERE Id = :reg.Id
        ];
        System.assertEquals('Registered', updatedReg.summit__Status__c, 'Status should be Registered');
    }

    @IsTest
    static void testProcessPayment_MissingToken() {
        // Build request without SEA_SECURE token
        String requestBody = 'pmt_status=success' +
            '&tpg_trans_id=TEST123456' +
            '&pmt_amt=100.00';

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/upaypaymentreceive';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = UPayPaymentRest.receivePayment();
        Test.stopTest();

        System.assertEquals('HTTP_ERROR', result, 'Should return HTTP_ERROR for missing token');
    }

    @IsTest
    static void testProcessPayment_InvalidToken() {
        // Build request with invalid token
        String requestBody = 'pmt_status=success' +
            '&tpg_trans_id=TEST123456' +
            '&pmt_amt=100.00' +
            '&SEA_SECURE=invalid-token-data';

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/upaypaymentreceive';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = UPayPaymentRest.receivePayment();
        Test.stopTest();

        System.assertEquals('HTTP_ERROR', result, 'Should return HTTP_ERROR for invalid token');
    }

    @IsTest
    static void testProcessPayment_DuplicatePayment() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];
        summit__Summit_Events__c evt = [SELECT Id FROM summit__Summit_Events__c LIMIT 1];

        // Create existing payment
        summit__Summit_Events_Payment__c existingPayment = new summit__Summit_Events_Payment__c(
            summit__Event_Registration__c = reg.Id,
            summit__TouchnetReceiptNumber__c = 'DUPLICATE123',
            summit__Payment_Amount__c = 100.00,
            summit__Payment_Status__c = 'Received'
        );
        insert existingPayment;

        // Create security token
        String seaSecureToken = UPayHelper.createSecurityToken(reg.Id, evt.Id, 100.00);

        // Build request with same transaction ID
        String requestBody = 'pmt_status=success' +
            '&tpg_trans_id=DUPLICATE123' +
            '&pmt_amt=100.00' +
            '&pmt_date=02/12/2026' +
            '&SEA_SECURE=' + EncodingUtil.urlEncode(seaSecureToken, 'UTF-8');

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/upaypaymentreceive';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = UPayPaymentRest.receivePayment();
        Test.stopTest();

        System.assertEquals('HTTP_OK', result, 'Should return HTTP_OK for duplicate (idempotent)');

        // Verify only one payment exists
        List<summit__Summit_Events_Payment__c> payments = [
            SELECT Id
            FROM summit__Summit_Events_Payment__c
            WHERE summit__TouchnetReceiptNumber__c = 'DUPLICATE123'
        ];
        System.assertEquals(1, payments.size(), 'Should only have one payment record');
    }

    @IsTest
    static void testProcessPayment_EmptyRequestBody() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/upaypaymentreceive';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('');
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = UPayPaymentRest.receivePayment();
        Test.stopTest();

        System.assertEquals('HTTP_ERROR', result, 'Should return HTTP_ERROR for empty body');
    }

    @IsTest
    static void testProcessPayment_WithAllFields() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];
        summit__Summit_Events__c evt = [SELECT Id FROM summit__Summit_Events__c LIMIT 1];

        // Create security token
        String seaSecureToken = UPayHelper.createSecurityToken(reg.Id, evt.Id, 150.50);

        // Build comprehensive request
        String requestBody = 'pmt_status=success' +
            '&tpg_trans_id=FULL_TEST_123' +
            '&pmt_amt=150.50' +
            '&pmt_date=02/12/2026' +
            '&SEA_SECURE=' + EncodingUtil.urlEncode(seaSecureToken, 'UTF-8') +
            '&card_type=MasterCard' +
            '&name_on_acct=Jane M. Smith' +
            '&acct_addr1=456 Oak Avenue' +
            '&acct_addr2=Apt 7B' +
            '&acct_city=St. Paul' +
            '&acct_state=MN' +
            '&acct_zip=55102' +
            '&acct_country=US' +
            '&acct_phone_day=555-123-4567' +
            '&sys_tracking_id=TRACKING_XYZ';

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/upaypaymentreceive';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = UPayPaymentRest.receivePayment();
        Test.stopTest();

        System.assertEquals('HTTP_OK', result, 'Should return HTTP_OK');

        // Verify all fields saved correctly
        summit__Summit_Events_Payment__c payment = [
            SELECT Id, summit__TouchnetReceiptNumber__c, summit__Payment_Amount__c,
                   summit__Card_Type__c, summit__Name_On_Account__c,
                   summit__Address_1__c, summit__Address_2__c, summit__City__c,
                   summit__State__c, summit__Zip__c, summit__Phone__c
            FROM summit__Summit_Events_Payment__c
            WHERE summit__Event_Registration__c = :reg.Id
            LIMIT 1
        ];

        System.assertEquals('FULL_TEST_123', payment.summit__TouchnetReceiptNumber__c);
        System.assertEquals(150.50, payment.summit__Payment_Amount__c);
        System.assertEquals('MasterCard', payment.summit__Card_Type__c);
        System.assertEquals('Jane M. Smith', payment.summit__Name_On_Account__c);
        System.assertEquals('456 Oak Avenue', payment.summit__Address_1__c);
        System.assertEquals('Apt 7B', payment.summit__Address_2__c);
        System.assertEquals('St. Paul', payment.summit__City__c);
        System.assertEquals('MN', payment.summit__State__c);
        System.assertEquals('55102', payment.summit__Zip__c);
        System.assertEquals('555-123-4567', payment.summit__Phone__c);
    }
}

