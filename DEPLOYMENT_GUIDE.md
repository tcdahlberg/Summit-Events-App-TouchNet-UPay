# Deployment Guide for Production

## Prerequisites

Before deploying to production, ensure you have:

1. ✅ Salesforce Production org access
2. ✅ Summit Events App installed in production
3. ✅ CumulusCI configured locally
4. ✅ Salesforce CLI (sf) installed
5. ✅ AWS account for proxy server deployment

## Step 1: Deploy Code to Production

### Option A: Using CumulusCI (Recommended)

```powershell
# Authenticate to production org
cci org connect prod

# Deploy metadata
cci task run deploy --org prod --path force-app/main/default

# Run all tests
cci task run run_tests --org prod

# Verify deployment
cci org info prod
```

### Option B: Using Salesforce CLI

```powershell
# Authenticate to production org
sf org login web --alias prod --instance-url https://login.salesforce.com

# Deploy metadata
sf project deploy start --source-dir force-app/main/default --target-org prod

# Run tests
sf apex run test --target-org prod --code-coverage --wait 10

# Check deployment status
sf org display --target-org prod
```

### Option C: Using Change Set

1. Create outbound change set in sandbox:
   - All UPay Apex classes (8 files)
   - All UPay Visualforce pages (2 files)
   - TouchNet_UPay_Site__mdt custom metadata type
   - TouchNetUpay permission set

2. Upload change set to production

3. In production, deploy change set and run all tests

## Step 2: Configure Summit Events Settings

1. **Navigate to**: Setup → Custom Settings → Summit Events Settings

2. **Click**: Manage → Edit (for your user or organization-wide)

3. **Configure**:
   - **Cookie Encryption Key**: Enter a random 32+ character string
     - Example: `7Ks9mP2nQ4vB6xL8yT1wR3eF5gH0jC2u`
     - **IMPORTANT**: Save this key securely - you cannot recover it later
   - **Community Base URL**: Enter your Visualforce Site URL with trailing slash
     - Format: `https://yourcompany.my.site.com/events/`
     - **Note**: Do NOT include `/s/` (that's for Experience Cloud, not Visualforce Sites)

4. **Save**

## Step 3: Create UPay Site Field (Manual)

Since Summit Events is a managed package, you must create this field manually:

1. **Navigate to**: Setup → Object Manager → Summit Events → Fields & Relationships

2. **Click**: New

3. **Select**: Picklist

4. **Configure**:
   - **Field Label**: UPay Site
   - **Field Name**: UPay_Site (auto-filled)
   - **Values**: Enter your site names (one per line):
     ```
     Event_Registration
     Application_Fee
     Enrollment_Deposit
     ```
   - **Default Value**: Event_Registration
   - **Restricted**: Checked (recommended)

5. **Next** → **Next** → **Save & New** or **Save**

6. **Add to Page Layouts**: Add the field to your Summit Events page layouts

**Detailed instructions**: [FIELD_SETUP.md](docs/FIELD_SETUP.md)

## Step 4: Configure TouchNet UPay Sites

1. **Navigate to**: Setup → Custom Metadata Types → TouchNet UPay Site → Manage Records

2. **Click**: New

3. **Configure first site** (repeat for each TouchNet site you use):
   - **Label**: Event Registration Fee
   - **TouchNet UPay Site Name**: Event_Registration (must match picklist value)
   - **UPay Site ID**: YOURSCHOOL_EVENTS (from TouchNet)
   - **Gateway URL**: https://secure.touchnet.net:8443/CXXXXX_upay/web/index.jsp (from TouchNet)
   - **Validation Key**: your-secret-key (from TouchNet)
   - **Active**: Checked

4. **Save**

## Step 5: Deploy AWS Proxy Server

**⚠️ CRITICAL**: This must be completed before testing payments.

Follow the complete guide: **[PROXY_SETUP.md](docs/PROXY_SETUP.md)**

**Quick summary**:
1. Create AWS Lambda function with Node.js proxy code
2. Create Network Load Balancer with static Elastic IPs
3. Configure SSL certificate
4. Test proxy server
5. Provide static IPs to TouchNet for whitelisting

**POST_LINK URL format**:
```
https://your-proxy-domain.com/services/apexrest/upaypaymentreceive
```

## Step 6: Configure TouchNet Gateway

**In your TouchNet UPay Admin Portal**:

### 6.1: Add SEA_SECURE Custom Parameter

1. Navigate to: Settings → Sites → [Your Site] → Form Configuration
2. Add Custom Parameter:
   - **Name**: `SEA_SECURE`
   - **Type**: Passthrough Variable
   - **Include in POST Callback**: ✅ **CHECKED** (critical!)
   - **Required**: Yes
   - **Display to User**: No

### 6.2: Configure POST_LINK

1. Navigate to: Settings → Sites → [Your Site] → URLs
2. Set POST Callback URL:
   ```
   https://your-proxy-domain.com/services/apexrest/upaypaymentreceive
   ```
   **⚠️ IMPORTANT**: Use your **proxy server URL**, NOT direct Salesforce URL

### 6.3: Whitelist Static IPs

1. Provide your AWS proxy server static IPs to TouchNet
2. Wait for TouchNet to confirm whitelisting (may take 1-3 business days)

## Step 7: Enable Visualforce Pages on Site

1. **Navigate to**: Setup → Sites → [Your Site Name]

2. **Click**: Edit or Manage

3. **Under Site Visualforce Pages**:
   - Move `UPayCallback` from Available to Enabled
   - Move `UPayPayment` from Available to Enabled

4. **Save**

5. **Navigate to**: Public Access Settings (under Site detail)

6. **Enabled Visualforce Page Access**:
   - Check: UPayCallback
   - Check: UPayPayment

7. **Enabled Apex Class Access**:
   - Check: UPayCallbackController
   - Check: UPayHelper
   - Check: UPayPaymentController
   - Check: UPayPaymentRest

8. **Save**

## Step 8: Assign Guest User Permissions

1. **Navigate to**: Setup → Permission Sets

2. **Find**: TouchNetUpay

3. **Click**: Manage Assignments

4. **Add Assignments**: Select your Site Guest User profile

5. **Done**

## Step 9: Test End-to-End Payment

### 9.1: Create Test Event

1. Create a test Summit Events event
2. Add an event instance
3. Set the **UPay Site** field to: Event_Registration
4. Add registration fees

### 9.2: Start Test Registration

1. Navigate to your Summit Events site
2. Start registration for the test event
3. Complete registration through to payment

### 9.3: Test Payment Page

Expected behavior:
- Payment page loads with summary of fees
- Form auto-submits to TouchNet (you don't see the form for long)
- TouchNet payment page appears

### 9.4: Complete Test Payment

Use TouchNet test card:
- **Card Number**: (provided by TouchNet)
- **Expiration**: Any future date
- **CVV**: Any 3 digits

### 9.5: Verify Callback

Expected behavior:
- After payment, redirected back to Salesforce
- UPayCallback page loads and immediately redirects
- Lands on Summit Events Confirmation page

### 9.6: Verify Data

1. **Payment Record**:
   - Navigate to: Summit Events → Payments
   - Verify payment record exists with correct amount
   - Check transaction ID matches TouchNet

2. **Fee Linkage**:
   - Open payment record
   - Verify **Related Fees** shows linked fees

3. **Registration Status**:
   - Open registration record
   - Verify **Status** = "Registered"

### 9.7: Test Error Scenarios

1. **Cancel Payment**: Click cancel in TouchNet → should redirect to Submit page
2. **Invalid Token**: Wait 25+ hours, try payment → should show error
3. **Duplicate Payment**: Use same transaction ID twice → second should be idempotent

## Step 10: Monitor Initial Transactions

### Enable Debug Logs

1. **Navigate to**: Setup → Debug Logs
2. **Click**: New
3. **Select**: Your Site Guest User
4. **Set**: All levels to FINEST
5. **Expiration**: 1 day

### Watch for Issues

Monitor debug logs for:
- `ERROR:` prefix indicates failures
- `Invalid security token` - check encryption key matches
- `Payment record not found` - check proxy server connectivity
- `HTTP_ERROR` - check TouchNet POST_LINK configuration

### Key Metrics

Track these metrics for first 50 transactions:
- Success rate (should be > 95%)
- Average processing time
- Error types and frequencies
- User abandonment at TouchNet

## Rollback Plan

If issues occur in production:

### Option 1: Disable Feature
1. Deactivate all TouchNet_UPay_Site__mdt records
2. Payment pages will show configuration error
3. Users cannot attempt payments

### Option 2: Full Removal
```powershell
# Create destructive changes XML
sf project generate manifest --from-org prod --output-dir destructive

# Remove UPay components
sf project deploy start --metadata-dir destructive --target-org prod
```

### Option 3: Revert to Previous Version
1. Deploy previous version from source control
2. Or restore from change set backup

## Post-Deployment Verification

✅ **Checklist**:
- [ ] All tests pass in production (76/76)
- [ ] Code coverage > 75% (should be ~86%)
- [ ] Summit Events Settings configured
- [ ] UPay_Site__c field created
- [ ] TouchNet_UPay_Site__mdt records created
- [ ] AWS proxy server deployed and tested
- [ ] TouchNet whitelisted static IPs
- [ ] TouchNet SEA_SECURE parameter configured
- [ ] Visualforce pages enabled on site
- [ ] Guest user permissions assigned
- [ ] Test payment completed successfully
- [ ] Payment record created and linked
- [ ] Registration status updated
- [ ] Callback redirects working
- [ ] Debug logs clean (no errors)

## Support

**Documentation**:
- Setup Guide: [SETUP_GUIDE.md](docs/SETUP_GUIDE.md)
- Proxy Setup: [PROXY_SETUP.md](docs/PROXY_SETUP.md)
- Technical Overview: [TECHNICAL_OVERVIEW.md](docs/TECHNICAL_OVERVIEW.md)
- Troubleshooting: See SETUP_GUIDE.md

**Issues**:
- Check debug logs first
- Review troubleshooting section in SETUP_GUIDE.md
- Contact TouchNet for gateway-specific issues
- Review code in GitHub repository

---

**Version**: 1.0.0  
**Last Updated**: February 16, 2026

