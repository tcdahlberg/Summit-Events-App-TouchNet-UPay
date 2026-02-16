/**
 * Copyright 2026 Thaddaeus Dahlberg. All rights reserved.
 * Use of this source code is governed by a BSD Revised license.
 *
 * TouchNet UPay Helper class for Summit Events App integration.
 * Handles encryption, cookie management, and UPay site configuration.
 */
public without sharing class UPayHelper {

    /**
     * Wrapper class for Summit Events registration context
     */
    public class SummitEventsInfo {
        public String audience { get; set; }
        public String instanceId { get; set; }
        public String eventId { get; set; }
        public String registrationId { get; set; }
        public String dt { get; set; }
    }

    /**
     * Wrapper class for security token data
     */
    public class SecurityToken {
        public String registrationId { get; set; }
        public String eventId { get; set; }
        public String timestamp { get; set; }
        public String amount { get; set; }
    }

    /**
     * Get the Community Base URL from Summit Events Settings
     * @return Base URL with trailing slash
     */
    public static String getSeaCommunityURL() {
        summit__Summit_Events_Settings__c seaSettings = summit__Summit_Events_Settings__c.getInstance(UserInfo.getUserId());
        String communityBaseURL = seaSettings.summit__Community_Base_URL__c;
        if (String.isNotBlank(communityBaseURL) && !communityBaseURL.endsWith('/')) {
            communityBaseURL += '/';
        }
        return communityBaseURL;
    }

    /**
     * Retrieve UPay site configuration by developer name
     * @param siteName Developer name of the UPay site configuration
     * @return UPay site configuration or null if not found
     */
    public static TouchNet_UPay_Site__mdt getUPaySiteConfig(String siteName) {
        List<TouchNet_UPay_Site__mdt> sites = [
            SELECT UPay_Site_Id__c, Gateway_URL__c, Validation_Key__c, Named_Credential__c,
                   Active__c, DeveloperName, Label
            FROM TouchNet_UPay_Site__mdt
            WHERE DeveloperName = :siteName AND Active__c = true
            LIMIT 1
        ];
        return sites.isEmpty() ? null : sites[0];
    }

    /**
     * Get all active UPay site configurations
     * @return List of active UPay site configurations
     */
    public static List<TouchNet_UPay_Site__mdt> getActiveUPaySites() {
        return [
            SELECT UPay_Site_Id__c, Gateway_URL__c, Validation_Key__c, Named_Credential__c,
                   Active__c, DeveloperName, Label
            FROM TouchNet_UPay_Site__mdt
            WHERE Active__c = true
            ORDER BY Label
        ];
    }

    /**
     * Get validation key from site config (supports both direct field and Named Credential)
     * @param siteConfig UPay site configuration record
     * @return Validation key or empty string if not found
     */
    public static String getValidationKey(TouchNet_UPay_Site__mdt siteConfig) {
        if (siteConfig == null) {
            return '';
        }

        // First try Named Credential (preferred method)
        if (String.isNotBlank(siteConfig.Named_Credential__c)) {
            // Note: In Visualforce, use {!$Credential.NamedCredentialName.Password}
            // In Apex, we return the Named Credential name for VF to resolve
            return siteConfig.Named_Credential__c;
        }

        // Fallback to Validation_Key__c field
        if (String.isNotBlank(siteConfig.Validation_Key__c)) {
            return siteConfig.Validation_Key__c;
        }

        return '';
    }

    /**
     * Retrieve Summit Events registration information from encrypted cookie
     * @return SummitEventsInfo object with registration context
     */
    public static SummitEventsInfo getSummitEventsInfo() {
        SummitEventsInfo eventInformation = new SummitEventsInfo();
        String jsonInput = getSeaCookie(true);

        if (String.isNotBlank(jsonInput)) {
            try {
                eventInformation = (SummitEventsInfo) JSON.deserialize(jsonInput, SummitEventsInfo.class);
            } catch (Exception e) {
                System.debug('Error deserializing Summit Events cookie: ' + e.getMessage());
            }
        }
        return eventInformation;
    }

    /**
     * Retrieve Summit Events registration information from encrypted string
     * @param eventInfo Encrypted event information string
     * @return SummitEventsInfo object with registration context
     */
    public static SummitEventsInfo getSummitEventsInfo(String eventInfo) {
        SummitEventsInfo eventInformation = new SummitEventsInfo();
        String jsonInput = decryptString(eventInfo, false);

        if (String.isNotBlank(jsonInput)) {
            try {
                eventInformation = (SummitEventsInfo) JSON.deserialize(jsonInput, SummitEventsInfo.class);
            } catch (Exception e) {
                System.debug('Error deserializing encrypted event info: ' + e.getMessage());
            }
        }
        return eventInformation;
    }

    /**
     * Get the Summit Events cookie value
     * @param decrypt If true, decrypt the cookie value
     * @return Cookie value (decrypted if decrypt=true)
     */
    public static String getSeaCookie(Boolean decrypt) {
        Cookie encodedCipherText = ApexPages.currentPage().getCookies().get('SummitEvents');
        if (encodedCipherText != null) {
            if (decrypt) {
                return decryptString(encodedCipherText.getValue(), true);
            } else {
                return encodedCipherText.getValue();
            }
        }
        return '';
    }

    /**
     * Create encrypted security token for passthrough validation
     * @param registrationId Registration ID
     * @param eventId Event ID
     * @param amount Payment amount
     * @return Encrypted security token
     */
    public static String createSecurityToken(String registrationId, String eventId, Decimal amount) {
        SecurityToken token = new SecurityToken();
        token.registrationId = registrationId;
        token.eventId = eventId;
        token.timestamp = String.valueOf(Datetime.now().getTime());
        token.amount = String.valueOf(amount);

        String jsonToken = JSON.serialize(token);
        return encryptString(jsonToken);
    }

    /**
     * Validate and decrypt security token from payment callback
     * @param encryptedToken Encrypted security token from TouchNet
     * @return SecurityToken object or null if invalid
     */
    public static SecurityToken validateSecurityToken(String encryptedToken) {
        if (String.isBlank(encryptedToken)) {
            return null;
        }

        String decrypted = decryptString(encryptedToken, true);
        if (String.isBlank(decrypted)) {
            return null;
        }

        try {
            SecurityToken token = (SecurityToken) JSON.deserialize(decrypted, SecurityToken.class);

            // Validate timestamp is within acceptable range (e.g., 24 hours)
            Long tokenTime = Long.valueOf(token.timestamp);
            Long currentTime = Datetime.now().getTime();
            Long timeDiff = currentTime - tokenTime;
            Long maxAge = 24 * 60 * 60 * 1000; // 24 hours in milliseconds

            if (timeDiff > maxAge || timeDiff < 0) {
                return null;
            }

            //Check if registrationId and eventId are present in salesforce and match the token values
            if (String.isBlank(token.registrationId) || String.isBlank(token.eventId)) {
                return null;
            } else {
                //Make sure the registration exists
                List<summit__Summit_Events_Registration__c> registrations = [
                    SELECT Id
                    FROM summit__Summit_Events_Registration__c
                    WHERE Id = :token.registrationId AND summit__Event__c = :token.eventId
                    LIMIT 1
                ];
                if (registrations.isEmpty()) {
                    return null;
                }
            }

            return token;
        } catch (Exception e) {
            System.debug('Error validating security token: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Encrypt a string using the Summit Events encryption key
     * @param plainText String to encrypt
     * @return Base64-encoded encrypted string
     */
    public static String encryptString(String plainText) {
        if (String.isBlank(plainText)) {
            return '';
        }

        String key = getEncryptionKey();
        if (String.isBlank(key)) {
            throw new UPayException('Encryption key not configured in Summit Events Settings');
        }

        try {
            Blob data = Blob.valueOf(plainText);
            Blob encrypted = Crypto.encryptWithManagedIV('AES256', Blob.valueOf(key), data);
            String encodedCipherText = EncodingUtil.base64Encode(encrypted);
            return EncodingUtil.urlEncode(encodedCipherText, 'UTF-8');
        } catch (Exception e) {
            System.debug('Error encrypting string: ' + e.getMessage());
            throw new UPayException('Encryption failed: ' + e.getMessage());
        }
    }

    /**
     * Decrypt a string using the Summit Events encryption key
     * @param encryptedString Encrypted string to decrypt
     * @param urlDecode If true, URL decode before decrypting
     * @return Decrypted string
     */
    public static String decryptString(String encryptedString, Boolean urlDecode) {
        if (String.isBlank(encryptedString)) {
            return '';
        }

        String key = getEncryptionKey();
        if (String.isBlank(key)) {
            return '';
        }

        try {
            if (urlDecode) {
                encryptedString = EncodingUtil.urlDecode(encryptedString, 'UTF-8');
            }

            Blob decrypted = Crypto.decryptWithManagedIV(
                'AES256',
                Blob.valueOf(key),
                EncodingUtil.base64Decode(encryptedString)
            );
            return decrypted.toString();
        } catch (Exception e) {
            System.debug('Error decrypting string: ' + e.getMessage());
            return '';
        }
    }

    /**
     * Get encryption key from Summit Events Settings
     * @return Encryption key
     */
    private static String getEncryptionKey() {
        summit__Summit_Events_Settings__c seaSettings = summit__Summit_Events_Settings__c.getOrgDefaults();
        return seaSettings.summit__Cookie_Encryption_Key__c;
    }

    /**
     * Build TouchNet validation key hash
     * @param validationKey Base validation key from config
     * @param externalTransId External transaction ID
     * @param amount Payment amount
     * @return MD5-hashed, Base64-encoded validation key
     */
    public static String buildValidationKeyHash(String validationKey, String externalTransId, String amount) {
        if (String.isBlank(validationKey)) {
            return '';
        }

        // TouchNet validation: key + externalTransId + amount, MD5 hashed, Base64 encoded
        String valCode = validationKey + externalTransId + amount;
        Blob requestBlob = Blob.valueOf(valCode);
        Blob hash = Crypto.generateDigest('MD5', requestBlob);
        return EncodingUtil.base64Encode(hash);
    }

    /**
     * Custom exception class for UPay errors
     */
    public class UPayException extends Exception {}
}

