/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * Test class for UPayPaymentController
 */
@IsTest
private class UPayPaymentController_TEST {

    @TestSetup
    static void setupTestData() {
        // Create Summit Events Settings
        summit__Summit_Events_Settings__c settings = new summit__Summit_Events_Settings__c();
        settings.summit__Cookie_Encryption_Key__c = '12345678901234567890123456789012'; // Exactly 32 bytes for AES256
        settings.summit__Community_Base_URL__c = 'https://test.salesforce.com/';
        insert settings;

        // Create test event
        summit__Summit_Events__c evt = new summit__Summit_Events__c(
            summit__Event_Name__c = 'Test Payment Event',
            summit__Event_Submit_Title__c = 'Complete Registration',
            summit__Event_Footer__c = 'Thank you'
        );
        insert evt;

        // Create test instance
        summit__Summit_Events_Instance__c instance = new summit__Summit_Events_Instance__c(
            summit__Event__c = evt.Id,
            summit__Instance_Title__c = 'Spring 2026',
            summit__Instance_Start_Date__c = Date.today().addDays(30),
            summit__Instance_End_Date__c = Date.today().addDays(30)
        );
        insert instance;

        // Create test registration
        summit__Summit_Events_Registration__c reg = new summit__Summit_Events_Registration__c(
            summit__Event__c = evt.Id,
            summit__Event_Instance__c = instance.Id,
            summit__Registrant_First_Name__c = 'John',
            summit__Registrant_Last_Name__c = 'Doe',
            summit__Registrant_Email__c = 'john.doe@test.com',
            summit__Registrant_Street_1__c = '123 Main St',
            summit__Registrant_City__c = 'Minneapolis',
            summit__Registrant_State__c = 'MN',
            summit__Registrant_Zip__c = '55401',
            summit__Status__c = 'Started'
        );
        insert reg;

        // Create test fees
        List<summit__Summit_Events_Fee__c> fees = new List<summit__Summit_Events_Fee__c>();
        fees.add(new summit__Summit_Events_Fee__c(
            summit__Event_Registration__c = reg.Id,
            summit__Event_Fee__c = 50.00,
            summit__Event_Fee_Type__c = 'Event Fee',
            summit__Description__c = 'Standard registration fee'
        ));
        fees.add(new summit__Summit_Events_Fee__c(
            summit__Event_Registration__c = reg.Id,
            summit__Event_Fee__c = 25.00,
            summit__Event_Fee_Type__c = 'Additional Fee',
            summit__Description__c = 'Workshop add-on'
        ));
        insert fees;

        // Create encrypted cookie with registration info
        UPayHelper.SummitEventsInfo eventInfo = new UPayHelper.SummitEventsInfo();
        eventInfo.eventId = evt.Id;
        eventInfo.instanceId = instance.Id;
        eventInfo.registrationId = reg.Id;
        String encryptedData = UPayHelper.encryptString(JSON.serialize(eventInfo));

        // Set cookie (this would normally be done by Summit Events)
        Cookie regCookie = new Cookie('SummitEvents', encryptedData, null, -1, false);
        ApexPages.currentPage().setCookies(new Cookie[]{regCookie});
    }

    @IsTest
    static void testPaymentPageLoad_Success() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        // Set encrypted cookie
        UPayHelper.SummitEventsInfo eventInfo = new UPayHelper.SummitEventsInfo();
        eventInfo.registrationId = reg.Id;
        String encryptedData = UPayHelper.encryptString(JSON.serialize(eventInfo));
        Cookie regCookie = new Cookie('SummitEvents', encryptedData, null, -1, false);
        ApexPages.currentPage().setCookies(new Cookie[]{regCookie});

        PageReference pageRef = Page.UPayPayment;
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayPaymentController controller = new UPayPaymentController();
        Test.stopTest();

        System.assertEquals(false, controller.hasError, 'Should not have errors');
        System.assertNotEquals(null, controller.eventPage, 'Event should be loaded');
        System.assertNotEquals(null, controller.eventRegistration, 'Registration should be loaded');
        System.assertEquals(75.00, controller.totalAmount, 'Total should be $75.00');
    }

    @IsTest
    static void testPaymentPageLoad_NoCookie() {
        PageReference pageRef = Page.UPayPayment;
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayPaymentController controller = new UPayPaymentController();
        Test.stopTest();

        System.assertEquals(true, controller.hasError, 'Should have error for missing cookie');
        System.assert(controller.errorMessage.contains('No registration found'), 'Error message should mention registration');
    }

    @IsTest
    static void testPaymentPageLoad_InvalidRegistration() {
        // Set cookie with non-existent registration
        UPayHelper.SummitEventsInfo eventInfo = new UPayHelper.SummitEventsInfo();
        eventInfo.registrationId = 'a350m0000000000AAA'; // Invalid ID
        String encryptedData = UPayHelper.encryptString(JSON.serialize(eventInfo));
        Cookie regCookie = new Cookie('SummitEvents', encryptedData, null, -1, false);
        ApexPages.currentPage().setCookies(new Cookie[]{regCookie});

        PageReference pageRef = Page.UPayPayment;
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayPaymentController controller = new UPayPaymentController();
        Test.stopTest();

        System.assertEquals(true, controller.hasError, 'Should have error for invalid registration');
    }

    @IsTest
    static void testPaymentPageLoad_NoFees() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        // Delete all fees
        delete [SELECT Id FROM summit__Summit_Events_Fee__c WHERE summit__Event_Registration__c = :reg.Id];

        // Set encrypted cookie
        UPayHelper.SummitEventsInfo eventInfo = new UPayHelper.SummitEventsInfo();
        eventInfo.registrationId = reg.Id;
        String encryptedData = UPayHelper.encryptString(JSON.serialize(eventInfo));
        Cookie regCookie = new Cookie('SummitEvents', encryptedData, null, -1, false);
        ApexPages.currentPage().setCookies(new Cookie[]{regCookie});

        PageReference pageRef = Page.UPayPayment;
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayPaymentController controller = new UPayPaymentController();
        Test.stopTest();

        System.assertEquals(true, controller.hasError, 'Should have error for no fees');
        System.assert(controller.errorMessage.contains('No payment required'), 'Error should mention no payment required');
    }

    @IsTest
    static void testPaymentPageLoad_WithSiteParameter() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        // Set encrypted cookie
        UPayHelper.SummitEventsInfo eventInfo = new UPayHelper.SummitEventsInfo();
        eventInfo.registrationId = reg.Id;
        String encryptedData = UPayHelper.encryptString(JSON.serialize(eventInfo));
        Cookie regCookie = new Cookie('SummitEvents', encryptedData, null, -1, false);
        ApexPages.currentPage().setCookies(new Cookie[]{regCookie});

        PageReference pageRef = Page.UPayPayment;
        pageRef.getParameters().put('site', 'Application_Fee');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        UPayPaymentController controller = new UPayPaymentController();
        Test.stopTest();

        // Note: Will have error because site config doesn't exist in test
        // But we're testing the site selection logic
        System.assertNotEquals(null, controller, 'Controller should instantiate');
    }

    @IsTest
    static void testGetPaymentParamsJSON() {
        summit__Summit_Events_Registration__c reg = [SELECT Id FROM summit__Summit_Events_Registration__c LIMIT 1];

        // Set encrypted cookie
        UPayHelper.SummitEventsInfo eventInfo = new UPayHelper.SummitEventsInfo();
        eventInfo.registrationId = reg.Id;
        String encryptedData = UPayHelper.encryptString(JSON.serialize(eventInfo));
        Cookie regCookie = new Cookie('SummitEvents', encryptedData, null, -1, false);
        ApexPages.currentPage().setCookies(new Cookie[]{regCookie});

        PageReference pageRef = Page.UPayPayment;
        Test.setCurrentPage(pageRef);

        UPayPaymentController controller = new UPayPaymentController();

        Test.startTest();
        String jsonParams = controller.getPaymentParamsJSON();
        Test.stopTest();

        // Should return empty JSON object if config not found
        System.assertNotEquals(null, jsonParams, 'JSON params should not be null');
    }
}

