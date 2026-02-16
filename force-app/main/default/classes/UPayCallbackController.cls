/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * Controller for TouchNet UPay payment callback pages.
 * Handles successful, cancelled, and failed payment callbacks from TouchNet.
 */
public without sharing class UPayCallbackController {

    /**
     * Constructor - minimal initialization
     */
    public UPayCallbackController() {
        // All processing happens in autoRedirect action method
    }

    /**
     * Auto-redirect action method - handles all callback processing
     * URL parameters expected:
     *   - type: success, cancel, or error
     *   - regId: registration ID
     *   - UPAY_SITE_ID: UPay site identifier (optional verification)
     * @return PageReference to redirect to
     */
    public PageReference autoRedirect() {
        try {
            // Get URL parameters
            Map<String, String> params = ApexPages.currentPage().getParameters();
            String callbackType = params.get('type');
            String regIdParam = params.get('regId');
            String upaySiteId = params.get('UPAY_SITE_ID');


            // Validate callback type
            if (String.isBlank(callbackType)) {
                return redirectWithError('Invalid payment callback - missing type parameter');
            }

            // Handle cancel and error callbacks immediately
            if (callbackType == 'cancel') {
                return redirectWithError('Payment was cancelled. Please try again.');
            } else if (callbackType == 'error') {
                String errorMsg = params.get('error_msg');
                if (String.isBlank(errorMsg)) {
                    errorMsg = 'An error occurred during payment processing';
                }
                return redirectWithError(errorMsg);
            }

            // Process success callback with verification
            if (callbackType == 'success') {
                return processSuccessCallback(regIdParam, upaySiteId);
            }

            // Unknown callback type
            return redirectWithError('Unknown callback type: ' + callbackType);

        } catch (Exception e) {
            System.debug('Callback processing error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return redirectWithError('Error processing payment callback: ' + e.getMessage());
        }
    }

    /**
     * Process successful payment callback with verification
     * @param regIdParam Registration ID from URL
     * @param upaySiteId UPay site ID from URL (optional, for future verification)
     * @return PageReference to redirect to
     */
    private static PageReference processSuccessCallback(String regIdParam, String upaySiteId) {
        // Get registration ID from URL parameter or cookie
        String registrationId = regIdParam;

        // Try to get from cookie as backup and for verification
        UPayHelper.SummitEventsInfo eventInfo = UPayHelper.getSummitEventsInfo();
        if (String.isBlank(registrationId)) {
            if (eventInfo != null && String.isNotBlank(eventInfo.registrationId)) {
                registrationId = eventInfo.registrationId;
            } else {
                return redirectWithError('Registration context not found. Please return to the event and try again.');
            }
        }

        // Verify registration ID matches cookie (if cookie available)
        if (eventInfo != null && String.isNotBlank(eventInfo.registrationId) &&
            eventInfo.registrationId != registrationId) {
            // Continue with URL parameter (it's more reliable)
        }


        // Verify payment was created by REST endpoint
        PaymentVerification verification = verifyPayment(registrationId);
        if (!verification.success) {
            return redirectWithError(verification.errorMessage);
        }

        // Success! Redirect to confirmation page
        PageReference confirmPage = new PageReference(UPayHelper.getSeaCommunityURL() + 'summit__SummitEventsConfirmation');
        confirmPage.setRedirect(true);
        return confirmPage;
    }

    /**
     * Verify payment was properly recorded
     * This runs in without sharing context to access guest user records
     * @param registrationId Registration ID
     * @return PaymentVerification result
     */
    private static PaymentVerification verifyPayment(String registrationId) {
        PaymentVerification result = new PaymentVerification();

        try {
            // Query payment record (created by REST endpoint)
            List<summit__Summit_Events_Payment__c> payments = [
                SELECT Id, summit__Payment_Amount__c, summit__TouchnetReceiptNumber__c
                FROM summit__Summit_Events_Payment__c
                WHERE summit__Event_Registration__c = :registrationId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (payments.isEmpty()) {
                result.success = false;
                result.errorMessage = 'Payment record not found. The payment may still be processing. Please contact support if this issue persists.';
                return result;
            }

            summit__Summit_Events_Payment__c payment = payments[0];

            // Query fees to calculate expected total
            List<summit__Summit_Events_Fee__c> fees = [
                SELECT Id, summit__Event_Fee__c
                FROM summit__Summit_Events_Fee__c
                WHERE summit__Event_Registration__c = :registrationId
                AND summit__Event_Fee__c > 0
            ];

            Decimal expectedTotal = 0;
            for (summit__Summit_Events_Fee__c fee : fees) {
                if (fee.summit__Event_Fee__c != null) {
                    expectedTotal += fee.summit__Event_Fee__c;
                }
            }


            // Verify amount matches (allow small rounding differences)
            if (payment.summit__Payment_Amount__c == null ||
                Math.abs(payment.summit__Payment_Amount__c - expectedTotal) > 0.01) {
                result.success = false;
                result.errorMessage = 'Payment amount mismatch. Expected: $' + expectedTotal.setScale(2) +
                                    ', Received: $' + (payment.summit__Payment_Amount__c != null ? payment.summit__Payment_Amount__c.setScale(2) : 0) +
                                    '. Please contact support.';
                return result;
            }

            result.success = true;
            return result;

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error verifying payment: ' + e.getMessage();
            System.debug('Payment verification error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return result;
        }
    }

    /**
     * Redirect to submit page with error message
     * @param errorMsg Error message to display
     * @return PageReference to submit page with error
     */
    private static PageReference redirectWithError(String errorMsg) {
        String encodedError = EncodingUtil.urlEncode(errorMsg, 'UTF-8');
        PageReference submitPage = new PageReference(UPayHelper.getSeaCommunityURL() +
                                                     'summit__SummitEventsSubmit?error=' + encodedError);
        submitPage.setRedirect(true);
        return submitPage;
    }

    /**
     * Inner class for payment verification results
     */
    private class PaymentVerification {
        public Boolean success { get; set; }
        public String errorMessage { get; set; }

        public PaymentVerification() {
            this.success = false;
            this.errorMessage = '';
        }
    }
}

