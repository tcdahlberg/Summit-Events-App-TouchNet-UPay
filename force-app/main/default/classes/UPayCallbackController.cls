/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * Controller for TouchNet UPay payment callback pages.
 * Handles successful, cancelled, and failed payment callbacks from TouchNet.
 */
public without sharing class UPayCallbackController {

    // Page properties
    public String callbackType { get; set; } // 'success', 'cancel', or 'error'
    public String message { get; set; }
    public String redirectURL { get; set; }
    public Boolean hasError { get; set; }
    public Boolean paymentCreated { get; set; }
    public String communityURL { get; set; }

    // Payment details from TouchNet
    public String transactionId { get; set; }
    public String transactionStatus { get; set; }
    public String transactionAmount { get; set; }
    public String securityToken { get; set; }

    // Registration context
    public UPayHelper.SummitEventsInfo eventInfo { get; set; }
    public summit__Summit_Events_Registration__c registration { get; set; }

    /**
     * Constructor
     */
    public UPayCallbackController() {
        hasError = false;
        paymentCreated = false;
        communityURL = UPayHelper.getSeaCommunityURL();

        // Get callback type from URL parameter
        callbackType = ApexPages.currentPage().getParameters().get('type');
        if (String.isBlank(callbackType)) {
            callbackType = 'success'; // Default
        }

        // Process callback
        processCallback();
    }

    /**
     * Process payment callback from TouchNet
     */
    private void processCallback() {
        try {
            // Get parameters from URL (regId is passed in callback URL)
            Map<String, String> params = ApexPages.currentPage().getParameters();
            String regIdParam = params.get('regId');

            // TouchNet may append additional parameters, check for those too
            transactionId = params.get('tpg_trans_id');
            transactionStatus = params.get('result');
            transactionAmount = params.get('amt');
            securityToken = params.get('SEA_SECURE');

            // Get registration ID from URL parameter or cookie
            String registrationId = String.isNotBlank(regIdParam) ? regIdParam : null;

            // Also try to get from cookie as backup
            if (String.isBlank(registrationId)) {
                eventInfo = UPayHelper.getSummitEventsInfo();
                registrationId = eventInfo.registrationId;
            } else {
                // Create eventInfo from URL parameter
                eventInfo = new UPayHelper.SummitEventsInfo();
                eventInfo.registrationId = registrationId;
            }

            if (String.isBlank(registrationId)) {
                setError('Registration context not found. Please return to the event and try again.');
                return;
            }

            // Load registration
            List<summit__Summit_Events_Registration__c> regs = [
                SELECT Id, summit__Event__c, summit__Event_Instance__c, summit__Status__c,
                       summit__Registrant_First_Name__c, summit__Registrant_Last_Name__c
                FROM summit__Summit_Events_Registration__c
                WHERE Id = :registrationId
                LIMIT 1
            ];

            if (regs.isEmpty()) {
                setError('Registration not found.');
                return;
            }

            registration = regs[0];

            // Ensure eventInfo is fully populated with registration context
            if (eventInfo == null) {
                eventInfo = new UPayHelper.SummitEventsInfo();
            }
            eventInfo.registrationId = registration.Id;
            eventInfo.eventId = registration.summit__Event__c;
            eventInfo.instanceId = registration.summit__Event_Instance__c;

            // Set redirect URL to Summit Events confirmation page
            redirectURL = UPayHelper.getSeaCommunityURL() + 'summit__SummitEventsConfirmation';

            // Handle callback based on type
            if (callbackType == 'success') {
                handleSuccessCallback();
            } else if (callbackType == 'cancel') {
                handleCancelCallback();
            } else if (callbackType == 'error') {
                handleErrorCallback();
            }

        } catch (Exception e) {
            setError('Error processing payment callback: ' + e.getMessage());
            System.debug('Callback processing error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    /**
     * Handle successful payment callback
     * NOTE: Payment record is created by REST API (UPayPaymentRest)
     * This page just verifies payment exists and redirects to confirmation
     */
    private void handleSuccessCallback() {
        try {
            // Check if payment record exists (created by REST endpoint)
            // Try to find by transaction ID first (if TouchNet passed it)
            List<summit__Summit_Events_Payment__c> existingPayments = new List<summit__Summit_Events_Payment__c>();

            if (String.isNotBlank(transactionId)) {
                existingPayments = [
                    SELECT Id, summit__Payment_Amount__c, summit__TouchnetReceiptNumber__c
                    FROM summit__Summit_Events_Payment__c
                    WHERE summit__TouchnetReceiptNumber__c = :transactionId
                    AND summit__Event_Registration__c = :eventInfo.registrationId
                    LIMIT 1
                ];
            }

            // If not found by transaction ID, get most recent payment for registration
            if (existingPayments.isEmpty()) {
                existingPayments = [
                    SELECT Id, summit__Payment_Amount__c, summit__TouchnetReceiptNumber__c
                    FROM summit__Summit_Events_Payment__c
                    WHERE summit__Event_Registration__c = :eventInfo.registrationId
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
            }

            if (!existingPayments.isEmpty()) {
                // Payment exists - success!
                paymentCreated = true;
                summit__Summit_Events_Payment__c payment = existingPayments[0];

                // Update transaction ID if we found it
                if (String.isBlank(transactionId) && String.isNotBlank(payment.summit__TouchnetReceiptNumber__c)) {
                    transactionId = payment.summit__TouchnetReceiptNumber__c;
                }

                message = 'Your payment has been successfully processed.';
                if (String.isNotBlank(transactionId)) {
                    message += ' Transaction ID: ' + transactionId;
                }
            } else {
                // Payment doesn't exist yet - REST endpoint may not have been called
                // This could happen if TouchNet redirected before calling REST API
                System.debug('Warning: Payment record not found for registration ' + eventInfo.registrationId);

                // Wait a moment and check again (REST call should be very fast)
                Integer retries = 0;
                while (retries < 3 && existingPayments.isEmpty()) {
                    retries++;

                    existingPayments = [
                        SELECT Id, summit__Payment_Amount__c, summit__TouchnetReceiptNumber__c
                        FROM summit__Summit_Events_Payment__c
                        WHERE summit__Event_Registration__c = :eventInfo.registrationId
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];
                }

                if (existingPayments.isEmpty()) {
                    String errorMsg = 'Payment is being processed. If this message persists, please contact support.';
                    if (String.isNotBlank(transactionId)) {
                        errorMsg += ' Transaction ID: ' + transactionId;
                    }
                    setError(errorMsg);
                    return;
                } else {
                    paymentCreated = true;
                    message = 'Your payment has been successfully processed. Transaction ID: ' + transactionId;
                }
            }

        } catch (Exception e) {
            setError('Error verifying payment: ' + e.getMessage());
            System.debug('Payment verification error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    /**
     * Handle cancelled payment callback
     */
    private void handleCancelCallback() {
        message = 'Your payment was cancelled. You can try again by returning to the event registration.';
        redirectURL = UPayHelper.getSeaCommunityURL() + 'summit__SummitEventsSubmit?error=' +
                     EncodingUtil.urlEncode('Payment was cancelled', 'UTF-8');
    }

    /**
     * Handle error payment callback
     */
    private void handleErrorCallback() {
        String errorMsg = ApexPages.currentPage().getParameters().get('error_msg');
        if (String.isBlank(errorMsg)) {
            errorMsg = 'An error occurred during payment processing';
        }

        setError(errorMsg + '. Please try again or contact support.');
        redirectURL = UPayHelper.getSeaCommunityURL() + 'summit__SummitEventsSubmit?error=' +
                     EncodingUtil.urlEncode(errorMsg, 'UTF-8');
    }


    /**
     * Set error message and flag
     * @param errorMsg Error message to display
     */
    private void setError(String errorMsg) {
        hasError = true;
        message = errorMsg;
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, errorMsg));
    }

    /**
     * Auto-redirect action method
     * @return PageReference to redirect to if no errors, otherwise null to stay on page and show error message
     */
    public PageReference autoRedirect() {
        if (String.isNotBlank(redirectURL) && !hasError) {
            PageReference page = new PageReference(redirectURL);
            page.setRedirect(true);
            return page;
        }
        return null;
    }
}




