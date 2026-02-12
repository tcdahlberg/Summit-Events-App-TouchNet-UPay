# TouchNet UPay Security Implementation

## Overview

This integration implements multiple layers of security to protect payment transactions and prevent fraud.

## SEA_SECURE Passthrough Token

### Purpose

The `SEA_SECURE` parameter is a **custom passthrough variable** that ensures payment callbacks are legitimate and haven't been tampered with.

### Configuration in TouchNet Gateway

**Required Setup in TouchNet UPay Admin Portal:**

1. Navigate to **Form Configuration** → **Custom Parameters**
2. Add new parameter:
   - **Parameter Name:** `SEA_SECURE`
   - **Type:** Passthrough Variable
   - **Include in POST Callback:** ✅ **REQUIRED**
   - **Required Field:** Yes (recommended)
   - **Display to User:** No

This tells TouchNet to:
- Accept the `SEA_SECURE` parameter when the payment form is submitted
- Store it during payment processing
- Include it in the POST callback to our REST API

### Implementation Flow

#### Step 1: Token Creation (Payment Page)

When the user is ready to pay, `UPayPaymentController` creates an encrypted security token:

```apex
// Build token with payment context
UPayHelper.SecurityToken token = UPayHelper.createSecurityToken(
    registrationId,      // 'a350m0000008q63AAA'
    eventId,             // 'a330m0000001SOrAAM'
    instanceId,          // 'a320m000000A5fOAAS'
    amount               // 150.00
);

// Add to payment form parameters
paymentParams.put('SEA_SECURE', token.encryptedToken);
```

**Token Contents (before encryption):**
```json
{
    "registrationId": "a350m0000008q63AAA",
    "eventId": "a330m0000001SOrAAM",
    "instanceId": "a320m000000A5fOAAS",
    "amount": "150.00",
    "timestamp": "2026-02-10T14:30:00.000Z"
}
```

**Encryption Method:**
- **Algorithm:** AES256 with Managed IV
- **Key Source:** Summit Events Settings `summit__Cookie_Encryption_Key__c`
- **Encoding:** Base64 → URL-encoded for safe transmission

#### Step 2: TouchNet Processing

1. User submits payment form → redirects to TouchNet
2. TouchNet receives all POST parameters including `SEA_SECURE`
3. User enters credit card information
4. TouchNet processes payment
5. TouchNet calls REST API at `POST_LINK` with payment results
6. **TouchNet includes `SEA_SECURE` unchanged in the callback** ⭐

#### Step 3: Token Validation (REST API Callback)

When TouchNet posts payment results to `/services/apexrest/upaypaymentreceive`:

```apex
// Extract SEA_SECURE from callback
String securityToken = getParameter('SEA_SECURE');

// Decrypt and validate
UPayHelper.SecurityToken token = UPayHelper.validateSecurityToken(securityToken);

if (token == null) {
    System.debug('ERROR: Invalid security token');
    return 'HTTP_ERROR';  // Reject payment
}

// Validate token hasn't expired (24 hours)
if (token.timestamp.addHours(24) < Datetime.now()) {
    System.debug('ERROR: Security token expired');
    return 'HTTP_ERROR';
}

// Token is valid - proceed with payment creation
createPaymentRecord(token);
```

### Security Benefits

| Threat | Protection |
|--------|------------|
| **Payment Fraud** | Token validates payment is for the correct registration ID and amount |
| **Man-in-the-Middle** | Encrypted payload cannot be read or modified without encryption key |
| **Replay Attacks** | 24-hour expiration prevents reusing old tokens |
| **Amount Tampering** | Token contains expected amount; REST API validates it matches `pmt_amt` |
| **Session Hijacking** | Token tied to specific registration and event instance |
| **Duplicate Payments** | REST API checks for existing payment with same `tpg_trans_id` |

### Token Validation Logic

```apex
public class SecurityToken {
    public String registrationId { get; set; }
    public String eventId { get; set; }
    public String instanceId { get; set; }
    public Decimal amount { get; set; }
    public Datetime timestamp { get; set; }
    public String encryptedToken { get; set; }
}

public static SecurityToken validateSecurityToken(String encryptedToken) {
    if (String.isBlank(encryptedToken)) {
        return null;
    }
    
    try {
        // Decrypt the token
        String decrypted = decryptString(encryptedToken, true);
        
        if (String.isBlank(decrypted)) {
            return null;
        }
        
        // Parse JSON
        SecurityToken token = (SecurityToken) JSON.deserialize(
            decrypted, 
            SecurityToken.class
        );
        
        // Validate expiration (24 hours)
        if (token.timestamp.addHours(24) < Datetime.now()) {
            System.debug('Security token expired: ' + token.timestamp);
            return null;
        }
        
        // Validate required fields
        if (String.isBlank(token.registrationId) || 
            String.isBlank(token.eventId) || 
            token.amount == null) {
            System.debug('Security token missing required fields');
            return null;
        }
        
        token.encryptedToken = encryptedToken;
        return token;
        
    } catch (Exception e) {
        System.debug('Error validating security token: ' + e.getMessage());
        return null;
    }
}
```

## Additional Security Measures

### 1. TouchNet Validation Key Hash

Standard TouchNet security using MD5 hash:

```apex
String valCode = validationKey + externalTransId + amount;
Blob hash = Crypto.generateDigest('MD5', Blob.valueOf(valCode));
String validationHash = EncodingUtil.base64Encode(hash);
```

TouchNet validates this hash on their end to ensure the request came from an authorized source.

### 2. Duplicate Payment Prevention

```apex
List<summit__Summit_Events_Payment__c> existingPayments = [
    SELECT Id
    FROM summit__Summit_Events_Payment__c
    WHERE summit__TouchnetReceiptNumber__c = :transactionId
    LIMIT 1
];

if (!existingPayments.isEmpty()) {
    System.debug('Payment already exists for transaction: ' + transactionId);
    return true; // Return success (don't create duplicate)
}
```

### 3. REST API Isolation

The REST endpoint uses a `without sharing` inner class for DML operations:

```apex
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
}
```

This ensures:
- Guest users can create payment records via REST API
- Main class `with sharing` prevents unauthorized data access
- DML isolated to specific operations with proper error handling

### 4. Registration Cookie Encryption

User's registration context is stored in an encrypted cookie:

```apex
String cookieValue = JSON.serialize(new SummitEventsInfo {
    audience = 'High School Senior',
    instanceId = 'a320m000000A5fOAAS',
    eventId = 'a330m0000001SOrAAM',
    registrationId = 'a350m0000008q63AAA',
    dt = String.valueOf(Datetime.now())
});

Blob encrypted = Crypto.encryptWithManagedIV(
    'AES256',
    Blob.valueOf(encryptionKey),
    Blob.valueOf(cookieValue)
);

String encodedCipherText = EncodingUtil.base64Encode(encrypted);
```

## Encryption Details

### AES256 with Managed IV

**Key Source:**
```apex
summit__Summit_Events_Settings__c settings = 
    summit__Summit_Events_Settings__c.getOrgDefaults();
String encryptionKey = settings.summit__Cookie_Encryption_Key__c;
```

**Requirements:**
- Key must be at least 32 characters (256 bits)
- Same key used for cookies and security tokens
- Key stored securely in Summit Events Settings (Protected Custom Setting)

### Encryption Method

```apex
public static String encryptString(String plainText) {
    if (String.isBlank(plainText)) {
        return '';
    }
    
    String key = getEncryptionKey();
    if (String.isBlank(key)) {
        return '';
    }
    
    try {
        Blob data = Blob.valueOf(plainText);
        Blob encrypted = Crypto.encryptWithManagedIV(
            'AES256',
            Blob.valueOf(key),
            data
        );
        String encoded = EncodingUtil.base64Encode(encrypted);
        return EncodingUtil.urlEncode(encoded, 'UTF-8');
    } catch (Exception e) {
        System.debug('Encryption error: ' + e.getMessage());
        return '';
    }
}
```

### Decryption Method

```apex
public static String decryptString(String encryptedText, Boolean urlDecode) {
    if (String.isBlank(encryptedText)) {
        return '';
    }
    
    String key = getEncryptionKey();
    if (String.isBlank(key)) {
        return '';
    }
    
    try {
        if (urlDecode) {
            encryptedText = EncodingUtil.urlDecode(encryptedText, 'UTF-8');
        }
        
        Blob decrypted = Crypto.decryptWithManagedIV(
            'AES256',
            Blob.valueOf(key),
            EncodingUtil.base64Decode(encryptedText)
        );
        
        return decrypted.toString();
    } catch (Exception e) {
        System.debug('Decryption error: ' + e.getMessage());
        return '';
    }
}
```

## Security Best Practices

### Configuration Checklist

- [ ] **Encryption Key:** 32+ character random string in Summit Events Settings
- [ ] **TouchNet Admin:** Configure `SEA_SECURE` as passthrough parameter
- [ ] **TouchNet Admin:** Enable POST callback to REST API
- [ ] **Named Credentials:** Use for TouchNet API credentials (optional but recommended)
- [ ] **Guest User:** Minimum permissions (only Create on Payment object)
- [ ] **Debug Logs:** Disable or minimize in production
- [ ] **HTTPS Only:** Ensure all URLs use HTTPS
- [ ] **IP Restrictions:** Consider IP whitelisting for TouchNet callbacks (organization-level)

### Testing Security

```apex
// Test expired token
SecurityToken oldToken = createSecurityToken('regId', 'eventId', 'instId', 100);
Test.setCreatedDate(oldToken.timestamp, Datetime.now().addDays(-2));
SecurityToken validated = validateSecurityToken(oldToken.encryptedToken);
System.assertEquals(null, validated, 'Expired token should be rejected');

// Test tampered token
String tampered = oldToken.encryptedToken.substring(0, 50) + 'XXXXX';
validated = validateSecurityToken(tampered);
System.assertEquals(null, validated, 'Tampered token should be rejected');

// Test valid token
SecurityToken newToken = createSecurityToken('regId', 'eventId', 'instId', 100);
validated = validateSecurityToken(newToken.encryptedToken);
System.assertNotEquals(null, validated, 'Valid token should pass');
```

## Troubleshooting

### Common Security Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Invalid security token" | SEA_SECURE not configured in TouchNet | Add custom parameter in TouchNet admin |
| "Invalid security token" | Encryption key mismatch | Verify same key in Summit Events Settings |
| "Security token expired" | Token > 24 hours old | User must restart payment process |
| "HTTP_ERROR" returned | Token validation failed | Check debug logs for specific error |
| Payment created twice | Duplicate check not working | Check `tpg_trans_id` is unique in callback |

### Debug Logging

Enable detailed logging in REST API:

```apex
System.debug('=== UPAY CALLBACK RECEIVED ===');
System.debug('Payment Status: ' + getParameter('pmt_status'));
System.debug('Transaction ID: ' + getParameter('tpg_trans_id'));
System.debug('Amount: ' + getParameter('pmt_amt'));
System.debug('SEA_SECURE Token: ' + getParameter('SEA_SECURE'));

SecurityToken token = validateSecurityToken(getParameter('SEA_SECURE'));
if (token != null) {
    System.debug('Token Valid - Registration: ' + token.registrationId);
    System.debug('Token Amount: ' + token.amount);
    System.debug('Token Timestamp: ' + token.timestamp);
} else {
    System.debug('ERROR: Token validation failed');
}
```

---

**Last Updated:** February 11, 2026  
**Version:** 1.0  
**Security Review:** Required before production deployment

