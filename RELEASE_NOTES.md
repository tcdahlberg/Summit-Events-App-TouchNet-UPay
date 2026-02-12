# Release Notes - Version 1.0

**Release Date:** February 2026  
**Salesforce API Version:** 65.0  
**Package Type:** Unmanaged

## Overview

First production release of the TouchNet UPay payment integration for Summit Events App. This package enables secure credit card payment processing through TouchNet's UPay gateway with full support for Summit Events registration workflows.

## What's Included

### Apex Classes (5)

**UPayHelper.cls**
- Core utility class for encryption, configuration, and cookie management
- AES256 encryption/decryption for security tokens
- MD5 validation key hashing for TouchNet communication
- Summit Events registration context management
- Custom Metadata configuration retrieval
- **Lines of Code:** 321
- **Test Coverage:** UPayHelper_TEST.cls

**UPayPaymentController.cls**
- Visualforce controller for payment initiation page
- Registration data queries and fee calculation
- SEA_SECURE token generation
- TouchNet POST parameter building
- Automatic site selection (field → URL → default)
- **Lines of Code:** 290
- **Key Feature:** Auto-submit payment form

**UPayPaymentRest.cls**
- REST API endpoint for TouchNet payment callbacks
- SEA_SECURE token validation and decryption
- Payment record creation
- Fee linking (populates `Summit_Events_Payment__c` lookup)
- Registration status updates
- Duplicate payment prevention
- **Lines of Code:** 241
- **Endpoint:** `/services/apexrest/upaypaymentreceive`

**UPayCallbackController.cls**
- Visualforce controller for post-payment callback pages
- Success/cancel/error state handling
- Payment record verification with retry logic
- Auto-redirect to Summit Events confirmation
- Multi-source registration ID retrieval
- **Lines of Code:** 215
- **Key Feature:** Graceful fallback for missing transaction data

**UPayHelper_TEST.cls**
- Comprehensive test coverage for UPayHelper
- Encryption/decryption tests
- Token validation tests
- Configuration retrieval tests
- **Lines of Code:** 181
- **Code Coverage:** 75%+

### Visualforce Pages (2)

**UPayPayment.page**
- Auto-submit payment form with SLDS styling
- JavaScript-driven form generation
- No user interaction required
- Loading spinner during redirect
- Error display for configuration issues
- **Lines:** 140

**UPayCallback.page**
- SLDS-styled callback handler
- Success/cancel/error states
- Transaction ID display
- Auto-redirect timer (3 seconds)
- Manual fallback links
- **Lines:** 146

### Custom Metadata Type

**TouchNet_UPay_Site__mdt**
- Multi-site payment configuration
- Support for multiple TouchNet gateways
- Named Credential integration option

**Fields:**
- `Active__c` - Enable/disable flag
- `Gateway_URL__c` - TouchNet endpoint URL
- `Named_Credential__c` - Optional named credential reference
- `UPay_Site_Id__c` - TouchNet site identifier
- `Validation_Key__c` - MD5 validation key

### REST Endpoint

**URL:** `/services/apexrest/upaypaymentreceive`  
**Method:** POST  
**Authentication:** Site Guest User  
**Sharing:** Without sharing (elevated permissions)

## Key Features

### Security

**SEA_SECURE Encrypted Token**
- Custom passthrough parameter for TouchNet
- AES256 encryption with managed IV
- Contains: registration ID, event ID, instance ID, amount, timestamp
- 24-hour expiration to prevent replay attacks
- Validated on REST callback before payment creation

**Permission Model**
- REST endpoint supports guest user access
- All DML operations use `without sharing` inner class
- Secure cookie management for registration context

**Validation**
- MD5 validation key hashing for TouchNet communication
- Duplicate payment prevention via transaction ID check
- Token expiration enforcement
- Amount and registration validation

### User Experience

**Seamless Payment Flow**
- No intermediate confirmation pages
- Auto-submit directly to TouchNet
- Callback page auto-redirects to confirmation
- Clear error messages for issues

**Mobile Responsive**
- SLDS styling throughout
- Works on all devices
- Optimized for mobile payments

### Multi-Site Support

**Per-Event Configuration**
- Optional `UPay_Site__c` picklist field on Summit Events
- Select different TouchNet sites for different event types
- Examples: Event Registration, Application Fees, Deposits

**Flexible Site Selection**
- Priority: Event field → URL parameter → Default value
- Backwards compatible with URL-based selection
- Defaults to "Event_Registration" if not specified

### Complete Audit Trail

**Payment Records**
- Full TouchNet transaction data captured
- Billing information stored
- Card type tracking
- Gateway session identifiers

**Fee Linkage**
- All fees automatically linked to payment via `Summit_Events_Payment__c` lookup
- Enables accurate financial reporting
- Supports Summit Events reconciliation workflows

**Registration Updates**
- Status automatically set to "Registered" upon successful payment
- Timestamps preserved
- Audit trail maintained

## Technical Requirements

### Salesforce

**Minimum Requirements:**
- Salesforce org (any edition with Apex and Visualforce)
- Summit Events App installed
- Experience Cloud site (for guest user payments)
- Summit Events Settings with encryption key configured

**Recommended:**
- Developer or higher edition
- Named Credentials for validation key storage
- Dedicated Experience Cloud site for events

### TouchNet

**Account Requirements:**
- Active TouchNet UPay account
- Gateway URL and Site ID provided
- Validation key generated
- Admin access to configure custom parameters

**Gateway Configuration:**
- `SEA_SECURE` custom parameter (passthrough variable)
- POST_LINK configured to proxy server
- Static IP whitelist (proxy server IPs)

### AWS (Proxy Server)

**Required Components:**
- AWS Lambda function (Node.js runtime)
- Network Load Balancer
- 2+ Elastic IP addresses
- SSL/TLS certificate
- VPC with public subnets

**Estimated Cost:** $20-40/month

## Installation Guide

### Step 1: Deploy Salesforce Components

```powershell
# Clone repository
git clone https://github.com/CSUEB-SE-2024/summit-events-app-touchnet-upay.git
cd summit-events-app-touchnet-upay

# Deploy with CumulusCI
cci flow run dev_org --org dev

# Or deploy components individually
cci task run deploy --path force-app/main/default/classes --org dev
cci task run deploy --path force-app/main/default/objects --org dev
cci task run deploy --path force-app/main/default/pages --org dev
```

### Step 2: Create UPay Site Field

Create `UPay_Site__c` picklist field on Summit Events object:
- Field Type: Picklist (Restricted)
- Values: Event_Registration (default), others as needed
- See [FIELD_SETUP.md](FIELD_SETUP.md) for detailed instructions

### Step 3: Deploy AWS Proxy Server

Deploy Lambda function and Network Load Balancer:
- See [PROXY_SETUP.md](PROXY_SETUP.md) for complete guide
- NodeJS proxy code included in `unpackaged/src/`
- Allocate 2+ Elastic IPs for high availability

### Step 4: Configure Custom Metadata

Create TouchNet UPay Site record:
- Setup → Custom Metadata Types → TouchNet UPay Site → New
- Label: Event Registration
- UPay Site ID: [Your TouchNet Site ID]
- Gateway URL: [TouchNet Gateway URL]
- Validation Key: [Your Validation Key]
- Active: ✓

### Step 5: Configure TouchNet Gateway

In TouchNet UPay Admin Portal:
1. Add custom parameter `SEA_SECURE` (must be passthrough)
2. Set POST_LINK to: `https://your-proxy.com/services/apexrest/upaypaymentreceive`
3. Provide static IPs to TouchNet for whitelisting

### Step 6: Test

1. Create test event in Summit Events
2. Add test fees to event
3. Complete registration
4. Process test payment
5. Verify payment record created
6. Verify fees linked to payment
7. Verify registration status updated

## Upgrade Path

This is the initial release. No upgrade needed.

## Known Limitations

### Static IP Requirement

**Issue:** TouchNet requires static IP addresses for REST callbacks  
**Impact:** Cannot call Salesforce REST endpoint directly  
**Mitigation:** AWS proxy server provides static IPs

### Managed Package Field

**Issue:** Cannot deploy field to `summit__Summit_Events__c` (managed object)  
**Impact:** `UPay_Site__c` field must be created manually  
**Mitigation:** Detailed instructions provided in FIELD_SETUP.md

### Guest User Permissions

**Issue:** Guest users have limited object access  
**Impact:** Must use `without sharing` for DML operations  
**Mitigation:** PaymentCRUD inner class provides secure elevated permissions

### Callback Timing

**Issue:** TouchNet may redirect user before POST completes  
**Impact:** Payment record may not exist when callback page loads  
**Mitigation:** Retry logic with 3 attempts built into callback controller

## Configuration Best Practices

### Security
1. Use Named Credentials for validation keys in production
2. Set encryption key to 32+ characters
3. Rotate encryption keys annually
4. Monitor failed payment attempts

### Performance
1. Keep payment page minimal (auto-submit design)
2. Use SOQL queries efficiently
3. Monitor CloudWatch logs for proxy latency

### Maintenance
1. Test after Salesforce releases
2. Update proxy server Node.js runtime periodically
3. Monitor AWS costs
4. Review TouchNet IP whitelist quarterly

## Support & Documentation

### Documentation
- [SETUP_GUIDE.md](SETUP_GUIDE.md) - Complete setup instructions
- [PROXY_SETUP.md](PROXY_SETUP.md) - AWS proxy deployment guide
- [TECHNICAL_OVERVIEW.md](TECHNICAL_OVERVIEW.md) - Architecture details
- [SECURITY.md](SECURITY.md) - Security implementation
- [PAYMENT_FLOW.md](PAYMENT_FLOW.md) - Visual flow diagrams
- [FIELD_SETUP.md](FIELD_SETUP.md) - Manual field creation

### Troubleshooting
- Check Salesforce debug logs (filter by `UPayPaymentRest` or `UPayCallback`)
- Check AWS CloudWatch logs for proxy issues
- Verify TouchNet configuration (SEA_SECURE parameter, POST_LINK)
- Confirm static IPs whitelisted by TouchNet

### Getting Help
- Review documentation in `/docs` folder
- Check TouchNet support for gateway issues
- Examine code in `/force-app/main/default`
- Reference unpackaged examples in `/unpackaged`

## Contributors

**Thaddaeus Dahlberg**
- Lead Developer
- Summit Events App Integration Specialist

## Acknowledgments

- Summit Events App community
- TouchNet for UPay gateway integration support
- AWS for reliable proxy infrastructure

---

**For Next Release:** Future enhancements may include Lightning Web Components, additional payment gateways, and enhanced reporting features.

