/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * Test class for UPayCallbackController
 */
@IsTest
private class UPayCallbackController_TEST {

    @TestSetup
    static void setupTestData() {
        // Create Summit Events Settings
        summit__Summit_Events_Settings__c settings = new summit__Summit_Events_Settings__c();
        settings.summit__Cookie_Encryption_Key__c = '12345678901234567890123456789012'; // Exactly 32 bytes for AES256
        settings.summit__Community_Base_URL__c = 'https://test.salesforce.com/';
        insert settings;

        // Create test event
        summit__Summit_Events__c evt = new summit__Summit_Events__c(
            summit__Event_Name__c = 'Callback Test Event',
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
            summit__Registrant_Last_Name__c = 'Callback',
            summit__Registrant_Email__c = 'callback@test.com',
            summit__Status__c = 'Started'
        );
        insert reg;
    }

    @IsTest
    static void testSuccessCallback_WithPayment() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        // Create payment record
        summit__Summit_Events_Payment__c payment = new summit__Summit_Events_Payment__c(
            summit__Event_Registration__c = reg.Id,
            summit__TouchnetReceiptNumber__c = 'CALLBACK123',
            summit__Payment_Amount__c = 100.00,
            summit__Payment_Status__c = 'Received'
        );
        insert payment;

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', reg.Id);
        pageRef.getParameters().put('tpg_trans_id', 'CALLBACK123');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals('success', controller.callbackType, 'Callback type should be success');
        System.assertEquals(false, controller.hasError, 'Should not have error');
        System.assertEquals(true, controller.paymentCreated, 'Payment should be found');
        System.assertNotEquals(null, controller.message, 'Success message should be set');
        System.assertNotEquals(null, controller.redirectURL, 'Redirect URL should be set');
    }

    @IsTest
    static void testSuccessCallback_PaymentNotFound() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', reg.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals('success', controller.callbackType, 'Callback type should be success');
        // Payment not found scenario - should show error or processing message
        System.assertNotEquals(null, controller.message, 'Message should be set');
    }

    @IsTest
    static void testCancelCallback() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'cancel');
        pageRef.getParameters().put('regId', reg.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals('cancel', controller.callbackType, 'Callback type should be cancel');
        System.assertNotEquals(null, controller.message, 'Cancel message should be set');
        System.assertNotEquals(null, controller.redirectURL, 'Redirect URL should be set');
    }

    @IsTest
    static void testErrorCallback() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'error');
        pageRef.getParameters().put('regId', reg.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals('error', controller.callbackType, 'Callback type should be error');
        System.assertNotEquals(null, controller.message, 'Error message should be set');
        System.assertNotEquals(null, controller.redirectURL, 'Redirect URL should be set');
    }

    @IsTest
    static void testCallback_NoRegistrationId() {
        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals(true, controller.hasError, 'Should have error for missing registration');
        System.assert(controller.message.contains('not found'), 'Error message should mention not found');
    }

    @IsTest
    static void testCallback_InvalidRegistrationId() {
        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', 'a350m0000000000AAA'); // Invalid ID
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals(true, controller.hasError, 'Should have error for invalid registration');
    }

    @IsTest
    static void testCallback_WithCookie() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];
        summit__Summit_Events__c evt = [SELECT Id FROM summit__Summit_Events__c LIMIT 1];
        summit__Summit_Events_Instance__c instance = [SELECT Id FROM summit__Summit_Events_Instance__c LIMIT 1];

        // Set encrypted cookie
        UPayHelper.SummitEventsInfo eventInfo = new UPayHelper.SummitEventsInfo();
        eventInfo.eventId = evt.Id;
        eventInfo.instanceId = instance.Id;
        eventInfo.registrationId = reg.Id;
        String encryptedData = UPayHelper.encryptString(JSON.serialize(eventInfo));
        Cookie regCookie = new Cookie('SummitEvents', encryptedData, null, -1, false);
        ApexPages.currentPage().setCookies(new Cookie[]{regCookie});

        // Create payment
        summit__Summit_Events_Payment__c payment = new summit__Summit_Events_Payment__c(
            summit__Event_Registration__c = reg.Id,
            summit__TouchnetReceiptNumber__c = 'COOKIE_TEST_123',
            summit__Payment_Amount__c = 50.00,
            summit__Payment_Status__c = 'Received'
        );
        insert payment;

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        // No regId parameter - should fall back to cookie
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals('success', controller.callbackType, 'Should process success callback');
        System.assertEquals(false, controller.hasError, 'Should not have error when using cookie');
    }


    @IsTest
    static void testCallback_DefaultType() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        PageReference pageRef = Page.UPayCallback;
        // No type parameter
        pageRef.getParameters().put('regId', reg.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals('success', controller.callbackType, 'Should default to success');
    }

    @IsTest
    static void testCallback_WithTransactionId() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        // Create payment
        summit__Summit_Events_Payment__c payment = new summit__Summit_Events_Payment__c(
            summit__Event_Registration__c = reg.Id,
            summit__TouchnetReceiptNumber__c = 'TRANS_ID_TEST',
            summit__Payment_Amount__c = 75.00,
            summit__Payment_Status__c = 'Received'
        );
        insert payment;

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', reg.Id);
        pageRef.getParameters().put('tpg_trans_id', 'TRANS_ID_TEST');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        Test.stopTest();

        System.assertEquals('TRANS_ID_TEST', controller.transactionId, 'Transaction ID should be captured');
        System.assertEquals(true, controller.paymentCreated, 'Payment should be found by transaction ID');
    }
}

