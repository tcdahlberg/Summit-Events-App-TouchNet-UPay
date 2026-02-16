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

        // Create fee to match payment
        summit__Summit_Events_Fee__c fee = new summit__Summit_Events_Fee__c(
            summit__Event_Registration__c = reg.Id,
            summit__Event_Fee__c = 100.00,
            summit__Event_Fee_Type__c = 'Event Fee'
        );
        insert fee;

        // Create payment record that matches fee total
        summit__Summit_Events_Payment__c payment = new summit__Summit_Events_Payment__c(
            summit__Event_Registration__c = reg.Id,
            summit__TouchnetReceiptNumber__c = 'CALLBACK123',
            summit__Payment_Amount__c = 100.00,
            summit__Payment_Status__c = 'Received'
        );
        insert payment;

        // Link fee to payment
        fee.summit__Summit_Events_Payment__c = payment.Id;
        update fee;

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', reg.Id);
        pageRef.getParameters().put('UPAY_SITE_ID', '6');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('SummitEventsConfirmation'), 'Should redirect to confirmation page');
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
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('SummitEventsSubmit'), 'Should redirect to submit page with error');
        System.assert(result.getUrl().contains('error='), 'Should have error parameter');
    }

    @IsTest
    static void testSuccessCallback_AmountMismatch() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        // Create fee for $100
        summit__Summit_Events_Fee__c fee = new summit__Summit_Events_Fee__c(
            summit__Event_Registration__c = reg.Id,
            summit__Event_Fee__c = 100.00,
            summit__Event_Fee_Type__c = 'Event Fee'
        );
        insert fee;

        // Create payment record with wrong amount
        summit__Summit_Events_Payment__c payment = new summit__Summit_Events_Payment__c(
            summit__Event_Registration__c = reg.Id,
            summit__TouchnetReceiptNumber__c = 'MISMATCH123',
            summit__Payment_Amount__c = 50.00, // Wrong amount!
            summit__Payment_Status__c = 'Received'
        );
        insert payment;

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', reg.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('SummitEventsSubmit'), 'Should redirect to submit page with error');
        System.assert(result.getUrl().contains('error='), 'Should have error parameter');
        System.assert(result.getUrl().contains('mismatch'), 'Error should mention amount mismatch');
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
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('SummitEventsSubmit'), 'Should redirect to submit page');
        System.assert(result.getUrl().contains('error='), 'Should have error parameter');
        System.assert(result.getUrl().contains('cancel'), 'Error should mention cancellation');
    }

    @IsTest
    static void testErrorCallback() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'error');
        pageRef.getParameters().put('regId', reg.Id);
        pageRef.getParameters().put('error_msg', 'Test error message');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('SummitEventsSubmit'), 'Should redirect to submit page');
        System.assert(result.getUrl().contains('error='), 'Should have error parameter');
    }

    @IsTest
    static void testCallback_NoRegistrationId() {
        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('error='), 'Should have error parameter');
        System.assert(result.getUrl().contains('not+found') || result.getUrl().contains('context'), 'Error should mention context not found');
    }

    @IsTest
    static void testCallback_InvalidRegistrationId() {
        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', 'a350m0000000000AAA'); // Invalid ID
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('error='), 'Should have error parameter');
    }

    @IsTest
    static void testCallback_WithCookie() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];
        summit__Summit_Events__c evt = [SELECT Id FROM summit__Summit_Events__c LIMIT 1];

        // Create fee
        summit__Summit_Events_Fee__c fee = new summit__Summit_Events_Fee__c(
            summit__Event_Registration__c = reg.Id,
            summit__Event_Fee__c = 50.00,
            summit__Event_Fee_Type__c = 'Event Fee'
        );
        insert fee;

        // Create payment
        summit__Summit_Events_Payment__c payment = new summit__Summit_Events_Payment__c(
            summit__Event_Registration__c = reg.Id,
            summit__TouchnetReceiptNumber__c = 'COOKIE_TEST_123',
            summit__Payment_Amount__c = 50.00,
            summit__Payment_Status__c = 'Received'
        );
        insert payment;

        // Link fee to payment
        fee.summit__Summit_Events_Payment__c = payment.Id;
        update fee;

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', reg.Id);
        Test.setCurrentPage(pageRef);

        // Set cookie
        UPayHelper.SummitEventsInfo eventInfo = new UPayHelper.SummitEventsInfo();
        eventInfo.registrationId = reg.Id;
        eventInfo.eventId = evt.Id;
        String cookieValue = JSON.serialize(eventInfo);
        Cookie seaCookie = new Cookie('SummitEvents', cookieValue, null, -1, false);
        pageRef.getCookies().put('SummitEvents', seaCookie);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('SummitEventsConfirmation'), 'Should redirect to confirmation when payment verified');
    }

    @IsTest
    static void testCallback_MissingType() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        PageReference pageRef = Page.UPayCallback;
        // No type parameter
        pageRef.getParameters().put('regId', reg.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('error='), 'Should have error for missing type');
    }

    @IsTest
    static void testCallback_MultipleFees() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        // Create multiple fees
        List<summit__Summit_Events_Fee__c> fees = new List<summit__Summit_Events_Fee__c>{
            new summit__Summit_Events_Fee__c(
                summit__Event_Registration__c = reg.Id,
                summit__Event_Fee__c = 50.00,
                summit__Event_Fee_Type__c = 'Registration Fee'
            ),
            new summit__Summit_Events_Fee__c(
                summit__Event_Registration__c = reg.Id,
                summit__Event_Fee__c = 25.00,
                summit__Event_Fee_Type__c = 'Processing Fee'
            )
        };
        insert fees;

        // Create payment record that matches total
        summit__Summit_Events_Payment__c payment = new summit__Summit_Events_Payment__c(
            summit__Event_Registration__c = reg.Id,
            summit__TouchnetReceiptNumber__c = 'MULTI_FEE_123',
            summit__Payment_Amount__c = 75.00, // Sum of fees
            summit__Payment_Status__c = 'Received'
        );
        insert payment;

        PageReference pageRef = Page.UPayCallback;
        pageRef.getParameters().put('type', 'success');
        pageRef.getParameters().put('regId', reg.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayCallbackController controller = new UPayCallbackController();
        PageReference result = controller.autoRedirect();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return redirect');
        System.assert(result.getUrl().contains('SummitEventsConfirmation'), 'Should redirect to confirmation when total matches');
    }
}

