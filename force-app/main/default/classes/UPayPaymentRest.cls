/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * REST API endpoint for TouchNet UPay payment callbacks.
 * TouchNet posts payment results to this endpoint after payment processing.
 */
@RestResource(urlMapping='/upaypaymentreceive/*')
global with sharing class UPayPaymentRest {

    private static Map<String, String> parameters { get; set; }

    /**
     * Handle POST from TouchNet UPay after payment processing
     * @return HTTP_OK on success, HTTP_ERROR on failure
     */
    @HttpPost
    global static String receivePayment() {
        RestRequest req = RestContext.request;

        if (req.requestBody.size() > 0) {
            // Parse form-urlencoded data from TouchNet
            String contentBody = req.requestBody.toString();
            parameters = parseFormData(contentBody);

            // Debug logging (remove in production)
            System.debug('UPay callback received: ' + JSON.serializePretty(parameters));

            // Validate payment status
            if (parameters.containsKey('pmt_status')) {
                String paymentStatus = parameters.get('pmt_status');

                if (String.isNotBlank(paymentStatus) && paymentStatus.equalsIgnoreCase('success')) {

                    //SEA_SECURE has to be added to TouchNet Form Parameters and is not a standard parameter, but it will be passed back in the callback for validation and to link the payment to the registration
                    String securityToken = getParameter('SEA_SECURE');
                    UPayHelper.SecurityToken token = UPayHelper.validateSecurityToken(securityToken);

                    if (token == null) {
                        System.debug('ERROR: Invalid security token in payment callback');
                        return 'HTTP_ERROR';
                    }

                    // Create payment record
                    if (createPaymentRecord(token)) {
                        return 'HTTP_OK';
                    } else {
                        System.debug('ERROR: Failed to create payment record');
                        return 'HTTP_ERROR';
                    }
                }
            }
        }

        System.debug('ERROR: Invalid payment callback - missing or invalid data');
        return 'HTTP_ERROR';
    }

    /**
     * Create Summit Events Payment record from TouchNet callback data
     * @param token Validated security token
     * @return true if payment created successfully
     */
    private static Boolean createPaymentRecord(UPayHelper.SecurityToken token) {
        try {
            // Check for duplicate payment
            String transactionId = getParameter('tpg_trans_id');

            List<summit__Summit_Events_Payment__c> existingPayments = [
                SELECT Id
                FROM summit__Summit_Events_Payment__c
                WHERE summit__TouchnetReceiptNumber__c = :transactionId
                LIMIT 1
            ];

            if (!existingPayments.isEmpty()) {
                System.debug('Payment already exists for transaction: ' + transactionId);
                return true; // Already exists, return success
            }

            // Create new payment record
            summit__Summit_Events_Payment__c payment = new summit__Summit_Events_Payment__c();

            // Registration reference
            payment.summit__Event_Registration__c = token.registrationId;

            // Payment details from TouchNet
            payment.summit__TouchnetReceiptNumber__c = transactionId;
            payment.summit__Payment_Amount__c = getDecimalParameter('pmt_amt');
            payment.summit__Payment_Received_Date__c = getDateParameter('pmt_date');
            payment.summit__Payment_Method__c = 'Credit Card';
            payment.summit__Method_of_Payment__c = 'Credit Card';
            payment.summit__Payment_Status__c = 'Received';

            // Card type
            payment.summit__Card_Type__c = getParameter('card_type');

            // Billing information
            payment.summit__Name_On_Account__c = getParameter('name_on_acct');
            if (String.isBlank(payment.summit__Name_On_Account__c)) {
                payment.summit__Name_On_Account__c = getParameter('BILL_NAME');
            }

            payment.summit__Email_Address__c = getParameter('acct_email_address');
            if (String.isBlank(payment.summit__Email_Address__c)) {
                payment.summit__Email_Address__c = getParameter('BILL_EMAIL_ADDRESS');
            }

            payment.summit__Address_1__c = getParameter('acct_addr1');
            if (String.isBlank(payment.summit__Address_1__c)) {
                payment.summit__Address_1__c = getParameter('acct_addr');
            }
            payment.summit__Address_2__c = getParameter('acct_addr2');
            payment.summit__City__c = getParameter('acct_city');
            payment.summit__State__c = getParameter('acct_state');
            payment.summit__Zip__c = getParameter('acct_zip');
            payment.summit__Country__c = getParameter('acct_country');
            payment.summit__Phone__c = getParameter('acct_phone_day');

            // Gateway tracking
            payment.summit__Gateway_Session_Identifier__c = getParameter('sys_tracking_id');

            // Insert payment
            PaymentCRUD crud = new PaymentCRUD();
            if (crud.savePayment(payment)) {

                // Update fees with payment ID
                updateFeesWithPayment(token.registrationId, payment.Id);

                // Update registration status
                updateRegistrationStatus(token.registrationId);

                System.debug('Payment record created successfully: ' + payment.Id);
                return true;
            }

        } catch (Exception e) {
            System.debug('ERROR creating payment record: ' + e.getMessage());
            System.debug(e.getStackTraceString());
        }

        return false;
    }

    /**
     * Update registration status after successful payment
     * @param registrationId Registration record ID
     */
    private static void updateRegistrationStatus(String registrationId) {
        try {
            summit__Summit_Events_Registration__c reg = new summit__Summit_Events_Registration__c(
                Id = registrationId,
                summit__Status__c = 'Registered'
            );

            PaymentCRUD crud = new PaymentCRUD();
            crud.updateRegistration(reg);

        } catch (Exception e) {
            System.debug('ERROR updating registration status: ' + e.getMessage());
            // Don't fail the whole process if status update fails
        }
    }

    /**
     * Update all fees for a registration with payment ID
     * @param registrationId Registration record ID
     * @param paymentId Payment record ID
     */
    private static void updateFeesWithPayment(String registrationId, String paymentId) {
        try {
            PaymentCRUD crud = new PaymentCRUD();
            crud.updateFeesWithPayment(registrationId, paymentId);
        } catch (Exception e) {
            System.debug('ERROR updating fees with payment: ' + e.getMessage());
            // Don't fail the whole process if fee update fails
        }
    }

    /**
     * Get parameter value from request
     * @param key Parameter name
     * @return Parameter value or empty string
     */
    private static String getParameter(String key) {
        if (parameters.containsKey(key) && String.isNotBlank(parameters.get(key))) {
            return parameters.get(key);
        }
        return '';
    }

    /**
     * Get decimal parameter value
     * @param key Parameter name
     * @return Decimal value or 0.0
     */
    private static Decimal getDecimalParameter(String key) {
        String value = getParameter(key);
        if (String.isNotBlank(value)) {
            try {
                return Decimal.valueOf(value);
            } catch (Exception e) {
                System.debug('ERROR parsing decimal for key ' + key + ': ' + value);
            }
        }
        return 0.0;
    }

    /**
     * Get date parameter value
     * @param key Parameter name
     * @return Date value or null
     */
    private static Date getDateParameter(String key) {
        String value = getParameter(key);
        if (String.isNotBlank(value)) {
            try {
                return Date.parse(value);
            } catch (Exception e) {
                System.debug('ERROR parsing date for key ' + key + ': ' + value);
            }
        }
        return null;
    }

    /**
     * Inner class with 'without sharing' for DML operations
     * Allows REST API to create records regardless of user permissions
     */
    private without sharing class PaymentCRUD {

        public Boolean savePayment(summit__Summit_Events_Payment__c payment) {
            try {
                insert payment;
                return true;
            } catch (Exception e) {
                System.debug('ERROR in savePayment: ' + e.getMessage());
                return false;
            }
        }

        public Boolean updateRegistration(summit__Summit_Events_Registration__c reg) {
            try {
                update reg;
                return true;
            } catch (Exception e) {
                System.debug('ERROR in updateRegistration: ' + e.getMessage());
                return false;
            }
        }

        public void updateFeesWithPayment(String registrationId, String paymentId) {
            try {
                // Query all fees for the registration (with 'without sharing' permissions)
                List<summit__Summit_Events_Fee__c> fees = [
                    SELECT Id
                    FROM summit__Summit_Events_Fee__c
                    WHERE summit__Event_Registration__c = :registrationId
                    AND summit__Event_Fee__c > 0
                ];

                if (!fees.isEmpty()) {
                    // Update all fees with payment ID
                    for (summit__Summit_Events_Fee__c fee : fees) {
                        fee.summit__Summit_Events_Payment__c = paymentId;
                    }

                    update fees;
                    System.debug('Updated ' + fees.size() + ' fee(s) with payment ID: ' + paymentId);
                } else {
                    System.debug('No fees found for registration: ' + registrationId);
                }

            } catch (Exception e) {
                System.debug('ERROR in updateFeesWithPayment: ' + e.getMessage());
                throw e; // Re-throw to be caught by caller
            }
        }
    }

    /**
     * Parse form-urlencoded data into a map
     * @param formData URL-encoded form data string
     * @return Map of parameter names to values
     */
    private static Map<String, String> parseFormData(String formData) {
        Map<String, String> result = new Map<String, String>();

        if (String.isBlank(formData)) {
            return result;
        }

        // Split by & to get key=value pairs
        String[] pairs = formData.split('&');
        for (String pair : pairs) {
            // Split each pair by = to get key and value
            Integer equalsIndex = pair.indexOf('=');
            if (equalsIndex > 0) {
                String key = pair.substring(0, equalsIndex);
                String value = pair.substring(equalsIndex + 1);

                // URL decode the value
                value = EncodingUtil.urlDecode(value, 'UTF-8');

                result.put(key, value);
            }
        }

        return result;
    }
}
