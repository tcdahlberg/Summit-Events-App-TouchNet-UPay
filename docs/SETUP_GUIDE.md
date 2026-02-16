# TouchNet UPay Setup Guide

## Quick Start (5 Minutes)

### Prerequisites
- ⚠️ **AWS Proxy Server deployed** - See [PROXY_SETUP.md](PROXY_SETUP.md) - **REQUIRED FIRST**
- Summit Events App (SEA) installed in your org
- TouchNet UPay site credentials (from TouchNet)
- TouchNet has whitelisted your proxy server's static IPs
- Summit Events Settings configured with encryption key

### Step 0: Deploy Proxy Server (REQUIRED FIRST) ⚠️

**Before configuring Salesforce, you MUST deploy the proxy server.**

TouchNet requires static IP addresses to communicate with your REST endpoint. Salesforce does not provide static IPs, so you need a proxy server.

**Complete setup instructions:** [PROXY_SETUP.md](PROXY_SETUP.md)

**Quick checklist:**
- [ ] AWS Lambda function deployed with NodeJS proxy code
- [ ] Network Load Balancer created with static Elastic IPs
- [ ] SSL certificate configured
- [ ] Proxy tested successfully
- [ ] Static IPs provided to TouchNet for whitelisting
- [ ] TouchNet confirms IPs are whitelisted

**POST_LINK URL format:**
```
https://your-proxy-domain.com/services/apexrest/upaypaymentreceive
```

⚠️ **Do NOT proceed until proxy is deployed and TouchNet has confirmed IP whitelist.**

### Step 0a: Create UPay Site Field on Summit Events (RECOMMENDED)

**⭐ This allows you to configure which UPay site to use per event, instead of hardcoding it.**

Since Summit Events is a managed package, you must create this field manually:

1. **Setup → Object Manager → Summit Events → Fields & Relationships → New**
2. **Field Type:** Picklist (Restricted)
3. **Field Label:** `UPay Site`
4. **Picklist Values:** Add `Event_Registration` as the default
5. **Add to Page Layouts**

**See [FIELD_SETUP.md](FIELD_SETUP.md) for detailed step-by-step instructions.**

**Without this field:** The payment page will fall back to:
- URL parameter `?site=Event_Registration` (backwards compatible)
- Default: `Event_Registration`

### Step 1: Create UPay Site Configuration

1. **Navigate to Custom Metadata Types**
   ```
   Setup → Custom Metadata Types → TouchNet UPay Site → Manage Records → New
   ```

2. **Fill in the details:**
   - **Label:** `Event Registration Fee` (or your preferred name)
   - **TouchNet UPay Site Name:** `Event_Registration`
   - **UPay Site ID:** `YOURSCHOOL_EVENTS` (provided by TouchNet)
   - **Gateway URL:** `https://secure.touchnet.net:8443/CXXXXX_upay/web/index.jsp`
   - **Validation Key:** `your-secret-key` (provided by TouchNet)
   - **Active:** ☑ Checked

   **Note:** Callback URLs (Success, Cancel, Error) are hardcoded in the payment controller to use the `UPayCallback` page and don't need to be configured in Custom Metadata.

3. **Save** the record

### Step 2: Test the Payment Page

1. **Open the payment page:**
   ```
   https://YOUR_DOMAIN/apex/UPayPayment?site=Event_Registration
   ```

2. **Expected behavior:**
   - If no registration cookie exists, you'll see an error message
   - This is normal - the page needs to be called from within an SEA registration

### Step 3: Integrate with Summit Events

**Option A: Link from SEA**
Add a link in your Summit Events template after registration:

```html
<a href="/apex/UPayPayment?site=Event_Registration" class="slds-button slds-button_brand">
    Proceed to Payment
</a>
```

**Option B: Redirect from SEA**
Configure SEA to automatically redirect to payment after registration.

### Step 4: Configure Guest User Permissions (if using Experience Cloud)

1. **Navigate to Permission Sets**
   ```
   Setup → Users → Permission Sets → Summit_Events_Registrant_Custom
   ```

2. **Add Visualforce Page Access:**
   - UPayPayment
   - UPayCallback

3. **Add Object Permissions:**
   - summit__Summit_Events_Payment__c (Read, Create)

## Advanced Setup: Named Credentials (Recommended for Production)

### Why Named Credentials?
- More secure - secrets not visible in metadata
- Salesforce-managed encryption
- Better for enterprise deployments

### Setup Process

1. **Create Named Credential**
   ```
   Setup → Named Credentials → New Legacy
   ```

2. **Configuration:**
   - **Label:** `TouchNet UPay - Event Registration`
   - **Name:** `TouchNet_UPay_EventReg`
   - **URL:** `https://secure.touchnet.net`
   - **Identity Type:** Named Principal
   - **Authentication Protocol:** Password Authentication
   - **Username:** `YOURSCHOOL_EVENTS` (your UPay Site ID)
   - **Password:** `your-secret-validation-key`

3. **Update Custom Metadata Record:**
   - **Named Credential:** `TouchNet_UPay_EventReg`
   - **Validation Key:** [leave blank - will use Named Credential instead]

4. **Test:** Payment page should still work, now using Named Credential

## Testing Checklist

- [ ] Payment page loads without errors (when called with valid registration)
- [ ] Fees display correctly
- [ ] "Proceed to Payment" button submits to TouchNet
- [ ] TouchNet test transaction completes
- [ ] Success callback creates payment record
- [ ] Cancel callback shows cancellation message
- [ ] Error callback shows error message
- [ ] Payment record appears in Summit Events

## Troubleshooting

### Error: "No registration found"
**Cause:** Payment page called without valid registration cookie  
**Solution:** Must be called from within an active SEA registration

### Error: "Payment site configuration not found"
**Cause:** Custom Metadata record doesn't exist or is inactive  
**Solution:** Create/activate TouchNet_UPay_Site__mdt record

### Error: "Encryption key not configured"
**Cause:** Summit Events Settings missing encryption key  
**Solution:** Configure summit__Cookie_Encryption_Key__c in Summit Events Settings

### Payment doesn't create in SEA
**Cause:** REST endpoint not being called or failing  
**Solution:**
1. Check TouchNet configuration - verify POST URL is correct
2. Check Salesforce debug logs for REST API errors
3. Verify guest user or Named Principal has REST API access
4. Check that security token is valid and not expired
5. Look for duplicate payment prevention logic

### "Payment is being processed" message persists
**Cause:** REST endpoint created payment but callback page can't find it  
**Solution:**
1. Verify payment record exists with matching transaction ID
2. Check that registration ID matches between cookie and payment
3. Review debug logs for query errors

### REST API returns HTTP_ERROR
**Cause:** Various - check debug logs  
**Common causes:**
- Invalid security token
- Expired token (> 24 hours old)
- Duplicate payment attempt
- Missing required fields from TouchNet POST
- DML errors (permissions, validation rules)

**Solution:** Check Salesforce debug logs filtered by `UPayPaymentRest`

### Validation key error from TouchNet
**Cause:** Incorrect validation key or MD5 hash  
**Solution:** Verify validation key matches TouchNet configuration

## Multiple UPay Sites

You can configure different UPay sites for different purposes:

### Example Configurations

**1. Event Registration Fees**
- **Developer Name:** `Event_Registration`
- **UPay Site ID:** `SCHOOL_EVENTS`
- **Usage:** General event registrations

**2. Application Fees**
- **Developer Name:** `Application_Fee`
- **UPay Site ID:** `SCHOOL_APPFEE`
- **Usage:** Application payments

**3. Deposit Payments**
- **Developer Name:** `Enrollment_Deposit`
- **UPay Site ID:** `SCHOOL_DEPOSIT`
- **Usage:** Enrollment deposits

### Specify Site in URL
```
/apex/UPayPayment?site=Event_Registration
/apex/UPayPayment?site=Application_Fee
/apex/UPayPayment?site=Enrollment_Deposit
```

## Security Best Practices

1. **Use Named Credentials in Production**
   - Keeps validation keys secure
   - Prevents accidental exposure in metadata

2. **Monitor Token Expiration**
   - Tokens expire after 24 hours
   - Users must complete payment within this window

3. **Review Payment Records Regularly**
   - Check for duplicate payments
   - Verify amounts match expected fees

4. **Protect Custom Metadata**
   - Use Protected Custom Metadata in managed package
   - Limit access to validation keys

5. **Configure SEA_SECURE Passthrough (REQUIRED)**
   - See TouchNet Gateway Configuration section below

## TouchNet Gateway Configuration (REQUIRED)

### ⚠️ Critical: SEA_SECURE Custom Parameter

You **must** configure a custom passthrough parameter in your TouchNet UPay Admin Portal:

#### Steps to Configure in TouchNet

1. **Log into TouchNet UPay Admin Portal**

2. **Navigate to your UPay Site Configuration**
   - Usually: Settings → Sites → [Your Site] → Form Configuration

3. **Add Custom Parameter:**
   - **Parameter Name:** `SEA_SECURE`
   - **Type:** Passthrough Variable (or Custom Field)
   - **Include in POST Callback:** ✅ **CRITICAL - Must be checked**
   - **Required:** Yes (recommended)
   - **Display to User:** No
   - **Description:** "Salesforce security token for payment validation"

4. **Save Configuration**

5. **Test:** Submit a test payment and verify `SEA_SECURE` appears in the POST callback to your REST API

#### Why This Is Required

The `SEA_SECURE` parameter contains an encrypted security token that:
- Validates the payment is for the correct registration
- Prevents fraud and tampering
- Ensures payment amount matches original request
- Protects against replay attacks

**Without this configuration, all payment callbacks will fail with HTTP_ERROR.**

#### Verification

After configuring, check Salesforce debug logs for a successful payment:
```
UPay callback received: {
    "pmt_status": "success",
    "SEA_SECURE": "[encrypted-token-here]",  ← Should appear in callback
    ...
}
```

If `SEA_SECURE` is missing from the callback, the REST endpoint will reject the payment.

### Other TouchNet Settings

In addition to `SEA_SECURE`, configure these standard settings in your TouchNet UPay Admin Portal:

1. **POST Callback URL (POST_LINK)** ⚠️ **IMPORTANT**
   ```
   https://your-proxy-domain.com/services/apexrest/upaypaymentreceive
   ```
   
   **CRITICAL:** You MUST use your **proxy server URL**, NOT the direct Salesforce REST URL.
   
   - ✅ Correct: `https://touchnet-proxy.yourschool.edu/services/apexrest/upaypaymentreceive`
   - ❌ Wrong: `https://yourorg.my.salesforce.com/services/apexrest/upaypaymentreceive`
   
   **Why:** TouchNet requires static IPs. Your proxy has static IPs; Salesforce does not.
   
   **See:** [PROXY_SETUP.md](PROXY_SETUP.md) for complete proxy deployment instructions.

**Note:** Success, Cancel, and Error redirect URLs are automatically sent by Salesforce in the payment form submission and don't need to be configured in TouchNet. They are hardcoded to:
- Success: `https://YOUR_VISUALFORCE_SITE/UPayCallback?type=success&regId=...`
- Cancel: `https://YOUR_VISUALFORCE_SITE/UPayCallback?type=cancel&regId=...`
- Error: `https://YOUR_VISUALFORCE_SITE/UPayCallback?type=error&regId=...`

---

## Troubleshooting

### Issue: Redirected to Login Page After Payment

**Symptoms:**
- Payment completes successfully in TouchNet
- Redirected to Salesforce login page instead of confirmation
- URL shows login page with callback URL in startURL parameter

**Root Cause:**
The Community Base URL in Summit Events Settings is incorrect or the UPayCallback page is not enabled on your Visualforce Site.

**Fix:**
1. **Verify Community Base URL in Summit Events Settings:**
   - Go to **Setup → Custom Settings → Summit Events Settings**
   - Click **Manage** next to your user/profile
   - Update **Community Base URL** to match your Visualforce Site URL:
     - ✅ Correct: `https://yoursite.my.site.com/` (Visualforce Site format)
     - ❌ Wrong: `https://yoursite.my.site.com/s/` (Experience Cloud format - not used by SEA)
   
2. **Verify UPayCallback page is enabled on your Visualforce Site:**
   - Go to **Setup → Sites → [Your Site Name]**
   - Click **Edit** or **Manage** your site
   - Under **Site Visualforce Pages**, ensure `UPayCallback` is in the **Enabled** list
   - If not, add it from the Available list
   - Save

3. **Verify Public Access Settings:**
   - Go to **Setup → Sites → [Your Site Name] → Public Access Settings**
   - Under **Enabled Visualforce Page Access**, verify `UPayCallback` is checked
   - Under **Enabled Apex Class Access**, verify these are checked:
     - `UPayCallbackController`
     - `UPayHelper`
   - Save and test again

**Why This Happens:**
Guest users on Visualforce Sites need the callback page to be explicitly enabled in the site's allowed pages list.

### Issue: Payment Record Not Found After Callback

**Symptoms:**
- Callback page shows "Payment record not found"
- Payment was successful in TouchNet

**Possible Causes:**
1. **Proxy server not configured** - TouchNet POST_LINK can't reach your REST endpoint
2. **IP whitelist issue** - TouchNet blocked the proxy IPs
3. **REST endpoint error** - Check Debug Logs for errors in `UPayPaymentRest`

**Fix:**
1. Check proxy server logs for incoming requests from TouchNet
2. Verify TouchNet has whitelisted your static IPs
3. Check Salesforce Debug Logs for REST endpoint errors
4. Test the proxy server manually (see PROXY_SETUP.md)

### Issue: "Payment site configuration not found"

**Symptoms:**
- Payment page shows configuration error
- Custom Metadata Type record doesn't exist

**Fix:**
1. Go to **Setup → Custom Metadata Types → TouchNet UPay Site → Manage Records**
2. Create a new record with Developer Name matching your event's `UPay_Site__c` field value
3. Fill in all required fields (see Step 1 above)
4. Mark as **Active**


## Support

For issues or questions:
1. Check troubleshooting section above
2. Review `docs/IMPLEMENTATION_SUMMARY.md`
3. Review `docs/AI-TOOLS-CONFIG.md`
4. Contact your TouchNet representative for gateway-specific issues

---

**Next:** See IMPLEMENTATION_SUMMARY.md for complete technical details

