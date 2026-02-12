# AI Development Context - TouchNet UPay Integration

**Project:** Summit Events App - TouchNet UPay Payment Gateway  
**Version:** 1.0  
**Released:** February 2026  
**License:** BSD 3-Clause  
**Copyright:** 2026 Thaddaeus Dahlberg

## Project Overview

Payment processing integration between Summit Events App (Salesforce) and TouchNet UPay gateway. Enables secure credit card payments for event registrations with full audit trail and fee tracking.

## Technology Stack

### Salesforce
- **Platform:** Salesforce (API 65.0)
- **Languages:** Apex, Visualforce, JavaScript
- **Framework:** Lightning Design System (SLDS)
- **Build Tool:** CumulusCI (Python-based Salesforce DevOps)
- **Package Type:** Unmanaged

### External Services
- **Payment Gateway:** TouchNet UPay
- **Proxy Infrastructure:** AWS Lambda (Node.js) + Network Load Balancer
- **Security:** AES256 encryption, MD5 validation hashing

## Architecture

### Payment Flow
```
User (Browser) 
  → Salesforce Visualforce Page (auto-submit)
  → TouchNet UPay Gateway (payment entry)
  → AWS Proxy Server (static IPs)
  → Salesforce REST API (payment creation)
  → Callback Page (confirmation)
```

### Key Design Patterns
- **Auto-Submit Forms:** No intermediate confirmation pages
- **Encrypted Tokens:** SEA_SECURE passthrough parameter
- **Proxy Pattern:** AWS Lambda bridges static IP requirement
- **Without Sharing:** Guest user DML via inner class
- **Retry Logic:** Callback page retries payment query

## Codebase Structure

```
force-app/main/default/
├── classes/
│   ├── UPayHelper.cls                  (321 lines) - Core utilities
│   ├── UPayPaymentController.cls       (290 lines) - Payment page
│   ├── UPayPaymentRest.cls            (241 lines) - REST endpoint
│   ├── UPayCallbackController.cls     (215 lines) - Callback page
│   └── UPayHelper_TEST.cls            (181 lines) - Tests
├── objects/
│   └── TouchNet_UPay_Site__mdt/              - Custom metadata
│       └── fields/ (5 fields)
└── pages/
    ├── UPayPayment.page                (140 lines) - Auto-submit form
    └── UPayCallback.page               (146 lines) - Success/error page

unpackaged/
└── src/
    └── touchNet-Salesforce-NodeJS-Proxy.js   - AWS Lambda proxy

docs/
├── SETUP_GUIDE.md                            - Installation guide
├── PROXY_SETUP.md                            - AWS deployment
├── TECHNICAL_OVERVIEW.md                     - Architecture details
├── SECURITY.md                               - Security specs
├── PAYMENT_FLOW.md                           - Flow diagrams
└── FIELD_SETUP.md                            - Manual field creation
```

## Core Components

### UPayHelper.cls
**Purpose:** Utility class for encryption, configuration, and cookie management

**Key Methods:**
- `encryptData()` / `decryptData()` - AES256 encryption with managed IV
- `createSecurityToken()` - Generates SEA_SECURE token
- `validateSecurityToken()` - Decrypts and validates token
- `buildValidationKeyHash()` - MD5 hash for TouchNet validation
- `getUPaySiteConfig()` - Retrieves Custom Metadata configuration
- `getSummitEventsInfo()` - Parses encrypted registration cookie

**Security Token Structure:**
```apex
public class SecurityToken {
    public String registrationId;
    public String eventId;
    public String instanceId;
    public Decimal amount;
    public Long timestamp;
}
```

### UPayPaymentController.cls
**Purpose:** Controller for payment initiation page

**Responsibilities:**
- Query registration data (event, instance, fees)
- Calculate total payment amount
- Build TouchNet POST parameters
- Generate SEA_SECURE encrypted token
- Auto-submit form via JavaScript

**Site Selection Priority:**
1. `UPay_Site__c` field on Event record (if exists)
2. URL parameter `?site=<name>`
3. Default: "Event_Registration"

**POST Parameters Built:**
- `UPAY_SITE_ID` - TouchNet site identifier
- `AMT` - Payment amount
- `SEA_SECURE` - Encrypted security token
- `VALIDATION_KEY` - MD5 hash
- `POST_LINK` - Proxy server URL (for REST callback)
- `SUCCESS_LINK`, `CANCEL_LINK`, `ERROR_LINK` - Callback URLs with regId

### UPayPaymentRest.cls
**Purpose:** REST API endpoint for TouchNet callbacks

**Endpoint:** `@RestResource(urlMapping='/upaypaymentreceive/*')`

**Flow:**
1. Receive POST from TouchNet (via proxy)
2. Extract and validate SEA_SECURE token
3. Check for duplicate payment (by transaction ID)
4. Create `Summit_Events_Payment__c` record
5. Link all fees to payment (set `Summit_Events_Payment__c` lookup)
6. Update registration status to "Registered"
7. Return `HTTP_OK` or `HTTP_ERROR`

**Permission Model:**
```apex
public with sharing class UPayPaymentRest {
    // Main logic here
    
    private without sharing class PaymentCRUD {
        // All DML operations here (guest user support)
        public void updateFeesWithPayment() {
            // Query and update fees with elevated permissions
        }
    }
}
```

### UPayCallbackController.cls
**Purpose:** Controller for post-payment callback page

**Features:**
- Handles success/cancel/error states
- Multi-source registration ID (URL param → Cookie)
- Payment verification with retry logic (3 attempts)
- Auto-redirect to confirmation (3-second timer)

**Callback Types:**
- **Success:** Verify payment exists, show transaction ID, redirect
- **Cancel:** Show cancellation message, provide retry link
- **Error:** Show error details, provide support info

## Custom Metadata

### TouchNet_UPay_Site__mdt
**Purpose:** Multi-site payment gateway configuration

**Fields:**
- `UPay_Site_Id__c` (Text) - TouchNet site identifier
- `Gateway_URL__c` (URL) - TouchNet gateway endpoint
- `Validation_Key__c` (Encrypted Text) - MD5 validation key
- `Named_Credential__c` (Text) - Optional named credential name
- `Active__c` (Checkbox) - Enable/disable flag

**Example Record:**
```
Label: Event Registration
DeveloperName: Event_Registration
UPay_Site_Id__c: YOURSCHOOL_EVENTS
Gateway_URL__c: https://secure.touchnet.net:8443/CXXXXX_upay/web/index.jsp
Validation_Key__c: ********
Active__c: true
```

## Security Implementation

### SEA_SECURE Token
**Purpose:** Prevent payment fraud and tampering

**Contents:**
- Registration ID
- Event ID
- Instance ID
- Payment amount
- Timestamp (for expiration check)

**Encryption:** AES256 with Salesforce Crypto class

**Validation:**
- Token must decrypt successfully
- Timestamp must be within 24 hours
- Registration ID must exist
- Amount must match payment

**TouchNet Configuration:**
- Add `SEA_SECURE` as custom parameter
- Set as "passthrough variable"
- Include in POST callback

### Permission Model
- REST endpoint: `with sharing` (safe for guest user calls)
- DML operations: `without sharing` inner class (PaymentCRUD)
- Reason: Guest users can't normally create/update SEA records
- Solution: Isolated DML in secure inner class with validation

### Validation Key
**Purpose:** MD5 hash for TouchNet request validation

**Algorithm:**
```apex
String hashInput = validationKey + transactionId + amount;
String hash = EncodingUtil.convertToHex(
    Crypto.generateDigest('MD5', Blob.valueOf(hashInput))
);
```

## Deployment

### CumulusCI Commands
```powershell
# Full deployment
cci flow run dev_org --org dev

# Incremental deployment
cci task run deploy --path force-app/main/default/classes --org dev
cci task run deploy --path force-app/main/default/pages --org dev

# Run tests
cci task run run_tests --org dev

# Check coverage
cci task run run_tests --org dev --test_name_match UPayHelper_TEST
```

### Manual Steps Required
1. **Create UPay_Site__c field** - Can't deploy to managed package object
2. **Deploy AWS proxy** - Lambda + NLB with static IPs
3. **Configure TouchNet** - Add SEA_SECURE parameter, set POST_LINK
4. **Create Custom Metadata records** - Per TouchNet site

## Testing

### Apex Tests
**UPayHelper_TEST.cls**
- Tests all encryption/decryption methods
- Tests token creation and validation
- Tests expired token rejection
- Tests configuration retrieval
- **Coverage:** 75%+

### Manual Testing
1. Create test event with fees
2. Complete registration
3. Navigate to payment page (should auto-submit)
4. Complete payment on TouchNet test gateway
5. Verify payment record created
6. Verify fees linked to payment
7. Verify registration status = "Registered"
8. Verify callback page shows success
9. Verify auto-redirect to confirmation

## Common Issues & Solutions

### Issue: TouchNet Can't Reach Salesforce
**Cause:** Static IP requirement  
**Solution:** Deploy AWS proxy server with static Elastic IPs

### Issue: Payment Not Created
**Cause:** SEA_SECURE not configured or invalid  
**Solution:** Add SEA_SECURE as passthrough parameter in TouchNet admin

### Issue: Guest User Permission Errors
**Cause:** Guest users can't create/update records  
**Solution:** All DML in PaymentCRUD `without sharing` class

### Issue: Fees Not Linked to Payment
**Cause:** Fee query/update must use elevated permissions  
**Solution:** Fee operations in PaymentCRUD inner class

## Development Environment

### Tools Required
- **Salesforce CLI** (`sf`) - For deployments and queries
- **CumulusCI** - For workflow automation
- **Python 3.13** - For CumulusCI
- **Node.js** - For Lambda proxy development
- **PowerShell** - Windows command shell
- **IntelliJ IDEA** + Illuminated Cloud - IDE

### Project Configuration
- **cumulusci.yml** - Project and org configuration
- **sfdx-project.json** - SFDX project settings
- **package.json** - Node.js dependencies (Jest for LWC testing)

### Scratch Org Settings
- Edition: Developer
- Features: Communities, Sites
- Duration: 7 days
- Config: `config/project-scratch-def.json`

## Key Design Decisions

### Auto-Submit Payment Page
**Decision:** Automatically submit form to TouchNet without user interaction  
**Rationale:** Streamlines UX, reduces confusion, matches user expectation  
**Implementation:** JavaScript builds and submits form on page load

### Proxy Server for Static IPs
**Decision:** Deploy AWS Lambda + NLB instead of alternatives  
**Rationale:** TouchNet requires static IPs; Salesforce doesn't provide them  
**Alternative Considered:** API Gateway (no static IPs), Global Accelerator (expensive)

### SEA_SECURE vs URL Parameters
**Decision:** Use encrypted passthrough parameter instead of URL params  
**Rationale:** More secure, prevents tampering, validates payment legitimacy  
**Alternative:** Query parameters (less secure, can be manipulated)

### Without Sharing for DML
**Decision:** Use `without sharing` inner class for payment/fee operations  
**Rationale:** Guest users need to create records; isolated class maintains security  
**Alternative:** User context (would fail for guest users)

### Per-Event Site Selection
**Decision:** Optional UPay_Site__c field on Event object  
**Rationale:** Flexibility for different event types using different TouchNet sites  
**Fallback:** URL parameter and default value for backwards compatibility

## Important Notes

### Managed Package Object
- `summit__Summit_Events__c` is from Summit Events App (managed package)
- Cannot deploy fields to managed objects via metadata
- `UPay_Site__c` field must be created manually in Setup
- Dynamic field access used: `eventPage.get('UPay_Site__c')`

### TouchNet Configuration
- **Critical:** `SEA_SECURE` must be configured as custom parameter
- Must be set as "passthrough variable"
- Must be included in POST callback
- Without it, all payments will fail validation

### Proxy Server Requirement
- **Not optional** - TouchNet requires static IPs
- Salesforce outbound IPs are dynamic
- Proxy provides static IPs via AWS Elastic IPs
- Cost: ~$20-40/month

## Support Resources

### Documentation
- All docs in `/docs` folder
- Code comments throughout Apex classes
- README.md for quick start
- RELEASE_NOTES.md for version details

### Debugging
- Enable Debug Logs in Salesforce
- Filter by `UPayPaymentRest` for REST API issues
- Filter by `UPayCallback` for callback issues
- Check AWS CloudWatch logs for proxy issues

### External References
- TouchNet UPay documentation (from TouchNet support)
- Summit Events App documentation
- Salesforce Apex Developer Guide
- AWS Lambda documentation

---

**This context should provide everything needed to understand, maintain, and extend the TouchNet UPay integration.**

