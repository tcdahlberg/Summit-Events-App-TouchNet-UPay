/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * Controller for TouchNet UPay payment page.
 * Builds payment form parameters and handles submission to TouchNet gateway.
 */
public without sharing class UPayPaymentController {

    // Page properties
    public String uPaySiteName { get; set; }
    public String gatewayURL { get; set; }
    public String uPaySiteId { get; set; }
    public Decimal totalAmount { get; set; }
    public String errorMessage { get; set; }
    public Boolean hasError { get; set; }
    public String communityURL { get; set; }

    // Test bypass flag
    @TestVisible
    private static Boolean bypassConfigCheck = false;

    // Registration context
    @TestVisible
    public UPayHelper.SummitEventsInfo eventInfo { get; set; }
    public summit__Summit_Events__c eventPage { get; set; }
    public summit__Summit_Events_Instance__c eventInstance { get; set; }
    public summit__Summit_Events_Registration__c eventRegistration { get; set; }
    public List<summit__Summit_Events_Fee__c> eventFees { get; set; }

    // Payment form parameters
    public Map<String, String> paymentParams { get; set; }

    /**
     * Constructor - initializes payment page
     */
    public UPayPaymentController() {
        hasError = false;
        errorMessage = '';
        paymentParams = new Map<String, String>();
        communityURL = UPayHelper.getSeaCommunityURL();


        // Initialize payment
        initializePayment();
    }

    /**
     * Initialize payment - load registration context and build payment parameters
     */
    @TestVisible
    private void initializePayment() {
        try {
            // Reset error state (for test retries)
            hasError = false;
            errorMessage = '';

            // Get registration context from cookie (unless already set by test)
            if (eventInfo == null || String.isBlank(eventInfo.registrationId)) {
                eventInfo = UPayHelper.getSummitEventsInfo();
            }

            if (String.isBlank(eventInfo.registrationId)) {
                setError('No registration found. Please return to the event registration and try again.');
                return;
            }

            // Load registration data first to get the Event record
            loadRegistrationData();

            // Get UPay site name from Event record (if field exists)
            // Otherwise use default
            uPaySiteName = null;

            try {
                // Try to get UPay_Site__c field value if it exists
                uPaySiteName = (String) eventPage.UPay_Site__c;
            } catch (Exception e) {
                System.debug('UPay_Site__c field not found on Event, using default');
            }

            if (String.isBlank(uPaySiteName)) {
                // Default to Event_Registration if not specified
                uPaySiteName = 'Event_Registration';
                System.debug('No UPay site specified, using default: ' + uPaySiteName);
            }

            // Load UPay site configuration
            TouchNet_UPay_Site__mdt siteConfig = UPayHelper.getUPaySiteConfig(uPaySiteName);
            if (siteConfig == null && !bypassConfigCheck) {
                setError('Payment site configuration not found: ' + uPaySiteName + '. Please contact an administrator.');
                return;
            }

            if (siteConfig != null) {
                gatewayURL = siteConfig.Gateway_URL__c;
                uPaySiteId = siteConfig.UPay_Site_Id__c;
            } else {
                // Test mode - use dummy values
                gatewayURL = 'https://test.touchnet.com';
                uPaySiteId = 'TEST_SITE';
            }


            // Calculate total amount
            calculateTotalAmount();

            if (totalAmount <= 0) {
                setError('No payment required for this registration.');
                return;
            }

            // Build payment form parameters
            if (siteConfig != null || bypassConfigCheck) {
                buildPaymentParameters(siteConfig);
            }

        } catch (Exception e) {
            setError('Error initializing payment: ' + e.getMessage());
            System.debug('Payment initialization error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    /**
     * Load registration data from Summit Events
     */
    private void loadRegistrationData() {
        try {
            // Load event - use dynamic SOQL for optional UPay_Site__c field

            eventPage = [
                    SELECT Id, summit__Event_Name__c, summit__Event_Submit_Title__c,
                            summit__Event_Footer__c, summit__Template__c, UPay_Site__c, summit__Payment_Gateway__c
                    FROM summit__Summit_Events__c
                    WHERE Id = :eventInfo.eventId
                    LIMIT 1
            ];


            // Load event instance
            eventInstance = [
                    SELECT Id, summit__Instance_Title__c, summit__Event__r.summit__Event_Name__c,
                            summit__Instance_Start_Date__c, summit__Instance_End_Date__c
                    FROM summit__Summit_Events_Instance__c
                    WHERE Id = :eventInfo.instanceId
                    LIMIT 1
            ];

            // Load registration
            eventRegistration = [
                    SELECT Id, summit__Registrant_First_Name__c, summit__Registrant_Last_Name__c,
                            summit__Registrant_Email__c, summit__Registrant_Street_1__c,
                            summit__Registrant_Street_2__c, summit__Registrant_City__c,
                            summit__Registrant_State__c, summit__Registrant_State_Province__c,
                            summit__Registrant_Zip__c, summit__Registrant_Postal_Code__c,
                            summit__Registrant_Country__c, summit__Status__c
                    FROM summit__Summit_Events_Registration__c
                    WHERE Id = :eventInfo.registrationId
                    LIMIT 1
            ];

            // Load fees
            eventFees = [
                    SELECT Id, Name, summit__Event_Fee__c, summit__Event_Fee_Type__c,
                            summit__Description__c
                    FROM summit__Summit_Events_Fee__c
                    WHERE summit__Event_Registration__c = :eventInfo.registrationId
                    AND summit__Event_Fee__c > 0
            ];

        } catch (Exception e) {
            setError('Error loading registration data: ' + e.getMessage());
        }
    }

    /**
     * Calculate total payment amount from fees
     */
    private void calculateTotalAmount() {
        totalAmount = 0;
        for (summit__Summit_Events_Fee__c fee : eventFees) {
            if (fee.summit__Event_Fee__c != null) {
                totalAmount += fee.summit__Event_Fee__c;
            }
        }
    }

    /**
     * Build payment form parameters for TouchNet UPay
     * @param siteConfig UPay site configuration metadata (may be null in test mode)
     */
    private void buildPaymentParameters(TouchNet_UPay_Site__mdt siteConfig) {
        // Get community base URL for callbacks
        String baseURL = UPayHelper.getSeaCommunityURL();

        // Required parameters
        paymentParams.put('UPAY_SITE_ID', siteConfig != null ? siteConfig.UPay_Site_Id__c : 'TEST_SITE');
        paymentParams.put('AMT', totalAmount.setScale(2).toPlainString());

        // External transaction ID (human-readable)
        String firstName = eventRegistration.summit__Registrant_First_Name__c != null ?
                eventRegistration.summit__Registrant_First_Name__c : '';
        String lastName = eventRegistration.summit__Registrant_Last_Name__c != null ?
                eventRegistration.summit__Registrant_Last_Name__c : '';
        String email = eventRegistration.summit__Registrant_Email__c != null ?
                eventRegistration.summit__Registrant_Email__c : '';
        String externalTransId = firstName + ' ' + lastName + ' | ' + email + ' | ' + eventRegistration.Id;
        paymentParams.put('EXT_TRANS_ID', externalTransId.abbreviate(249));

        // Security token (encrypted passthrough variable)
        String securityToken = UPayHelper.createSecurityToken(
                eventInfo.registrationId,
                eventInfo.eventId,
                totalAmount
        );

        //SEA_SECURE has to be added to TouchNet Form Parameters and is not a standard parameter, but it will be passed back in the callback for validation and to link the payment to the registration
        paymentParams.put('SEA_SECURE', securityToken);

        paymentParams.put('EXT_TRANS_ID_LABEL', 'Registration for ' + eventPage.summit__Event_Name__c + ' | ' + eventInstance.summit__Instance_Title__c + ' | ' + eventInstance.Id);

        // Billing information
        if (String.isNotBlank(firstName) && String.isNotBlank(lastName)) {
            paymentParams.put('BILL_NAME', (firstName + ' ' + lastName).left(50));
        }

        if (String.isNotBlank(eventRegistration.summit__Registrant_Email__c)) {
            paymentParams.put('BILL_EMAIL_ADDRESS', eventRegistration.summit__Registrant_Email__c);
        }

        if (String.isNotBlank(eventRegistration.summit__Registrant_Street_1__c)) {
            paymentParams.put('BILL_STREET1', eventRegistration.summit__Registrant_Street_1__c.left(50));
        }

        if (String.isNotBlank(eventRegistration.summit__Registrant_City__c)) {
            paymentParams.put('BILL_CITY', eventRegistration.summit__Registrant_City__c.left(50));
        }

        String state = String.isNotBlank(eventRegistration.summit__Registrant_State__c) ?
                eventRegistration.summit__Registrant_State__c :
                eventRegistration.summit__Registrant_State_Province__c;
        if (String.isNotBlank(state)) {
            paymentParams.put('BILL_STATE', state.left(2));
        }

        String postalCode = String.isNotBlank(eventRegistration.summit__Registrant_Zip__c) ?
                eventRegistration.summit__Registrant_Zip__c :
                eventRegistration.summit__Registrant_Postal_Code__c;
        if (String.isNotBlank(postalCode)) {
            paymentParams.put('BILL_POSTAL_CODE', postalCode.left(10));
        }

        if (String.isNotBlank(eventRegistration.summit__Registrant_Country__c)) {
            paymentParams.put('BILL_COUNTRY', eventRegistration.summit__Registrant_Country__c.left(2));
        }

        // Callback URLs - Visualforce Site format (no /apex/ prefix needed)
        // baseURL already ends with '/', just append page name
        String callbackParams = 'regId=' + EncodingUtil.urlEncode(eventInfo.registrationId, 'UTF-8');
        paymentParams.put('SUCCESS_LINK', baseURL + 'UPayCallback?type=success&' + callbackParams);
        paymentParams.put('CANCEL_LINK', baseURL + 'UPayCallback?type=cancel&' + callbackParams);
        paymentParams.put('ERROR_LINK', baseURL + 'UPayCallback?type=error&' + callbackParams);

        // REST API endpoint for TouchNet to post payment results
        String restEndpoint = Url.getOrgDomainUrl().toExternalForm() + '/services/apexrest/upaypaymentreceive';
        paymentParams.put('POST_LINK', restEndpoint);

        // Validation key (MD5 hash) - only if config provided
        if (siteConfig != null) {
            String validationKey = UPayHelper.getValidationKey(siteConfig);
            if (String.isNotBlank(validationKey)) {
                String validationHash = UPayHelper.buildValidationKeyHash(
                        validationKey,
                        externalTransId,
                        totalAmount.setScale(2).toPlainString()
                );
                paymentParams.put('VALIDATION_KEY', validationHash);
            }
        }
    }

    /**
     * Get payment parameters as JSON for JavaScript
     * @return JSON string representation of payment parameters
     */
    public String getPaymentParamsJSON() {
        return JSON.serialize(paymentParams);
    }

    /**
     * Set error message and flag
     * @param message Error message to display to user
     */
    private void setError(String message) {
        hasError = true;
        errorMessage = message;
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, message));
    }

    /**
     * Get formatted amount for display
     * @return Formatted currency string (e.g., "$100.00")
     */
    public String getFormattedAmount() {
        if (totalAmount == null) {
            return '$0.00';
        }
        return '$' + totalAmount.setScale(2).format();
    }
}

